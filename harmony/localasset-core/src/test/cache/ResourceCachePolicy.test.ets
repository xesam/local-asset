import { describe, it, expect } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import { decideCache, DEFAULT_MAX_AGE_SECONDS } from '../../main/ets/cache/ResourceCachePolicy';
import {
  ResourceType,
  bytesSource,
  filePathSource,
  createResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';

const TMP_FILE = '/tmp/localasset-cache-policy-probe.bin';

export default function resourceCachePolicyTest() {
  describe('resourceCachePolicyTest', () => {
    it('marks static bytes cacheable with a size-based etag', 0, () => {
      const descriptor = createResourceDescriptor({
        id: 'logo',
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: bytesSource(new Uint8Array(1024)),
        createdAtMillis: 0,
      });
      const decision = decideCache(descriptor);
      expect(decision.cacheControl).assertEqual('public, max-age=86400');
      expect(decision.etag).assertEqual('"logo-1024"');
    });

    it('marks dynamic resources no-store', 0, () => {
      const descriptor = createResourceDescriptor({
        id: 'thumb',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array(512)),
        createdAtMillis: 0,
      });
      const decision = decideCache(descriptor);
      expect(decision.cacheControl).assertEqual('no-store');
      expect(decision.etag).assertEqual('"thumb-512"');
    });

    it('honours a custom max age', 0, () => {
      const descriptor = createResourceDescriptor({
        id: 'logo',
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: bytesSource(new Uint8Array(1024)),
        createdAtMillis: 0,
      });
      expect(decideCache(descriptor, 60).cacheControl).assertEqual('public, max-age=60');
    });

    it('exposes the shared default max age', 0, () => {
      expect(DEFAULT_MAX_AGE_SECONDS).assertEqual(86400);
    });

    /**
     * bytes 分支的 etag 断言（上面两条）无法区分「用了字节长度」与「用了别的恰好相等的
     * 数字」，也不覆盖 filePath 分支。这一条专门钉住 filePath 分支：
     * etag 必须是 `"<id>-<文件 mtime>"`，且 mtime 必须来自**真实文件**而不是常量 0
     * —— 若实现退化成永远返回 0（或写死 id-only），这里的两条断言各自会红。
     *
     * 单位说明：`@ohos.file.fs` 的 `stat.mtime` 是**秒**（Kotlin 的 `File.lastModified()`
     * 是毫秒）。本测试从同一个 `fs.statSync` 取值比对，因此不依赖单位；跨端 etag 取值
     * 本就不要求相等（见 ResourceCachePolicy.ets 的说明）。
     */
    it('derives the filePath etag from the real file mtime', 0, () => {
      const file = fs.openSync(TMP_FILE, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, 'cache-probe');
      fs.closeSync(file);
      const mtime = fs.statSync(TMP_FILE).mtime;

      const descriptor = createResourceDescriptor({
        id: 'doc',
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: filePathSource(TMP_FILE),
        createdAtMillis: 0,
      });
      const decision = decideCache(descriptor);
      expect(decision.etag).assertEqual('"doc-' + mtime.toString() + '"');
      // 显式排除「实现直接返回 0」这一退化路径：真实文件的 mtime 不可能是 0。
      expect(mtime > 0).assertTrue();
      expect(decision.etag === '"doc-0"').assertFalse();
      fs.unlinkSync(TMP_FILE);
    });

    /** 文件不存在时不得抛错（响应头计算绝不能把请求打挂），退化成 mtime=0。 */
    it('falls back to a zero mtime when the file is missing', 0, () => {
      const descriptor = createResourceDescriptor({
        id: 'gone',
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: filePathSource('/tmp/localasset-cache-definitely-missing.bin'),
        createdAtMillis: 0,
      });
      const decision = decideCache(descriptor);
      expect(decision.etag).assertEqual('"gone-0"');
      expect(decision.cacheControl).assertEqual('public, max-age=86400');
    });
  });
}
