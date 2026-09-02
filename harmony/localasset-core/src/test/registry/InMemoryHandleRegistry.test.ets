import { describe, it, expect } from '@ohos/hypium';
import { InMemoryHandleRegistry } from '../../main/ets/registry/InMemoryHandleRegistry';
import { CACHE_BUST_PARAM, reconstructUriFromRequest } from '../../main/ets/api/HandleRegistry';
import { createResourceHandle, ResourceHandle, ResourceHandleRecord } from '../../main/ets/model/ResourceHandle';
import { bytesSource, BytesSource, filePathSource } from '../../main/ets/model/ResourceDescriptor';
import { createAssetRequest } from '../../main/ets/model/AssetRequest';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import { generateUuidV4 } from '../../main/ets/internal/Uuid';

const HOST = 'h.local';
const ORIGIN = 'local-asset://' + HOST;

function handle(fileName: string, ttlMillis: number | null = null): ResourceHandle {
  return createResourceHandle({
    source: bytesSource(new Uint8Array([1, 2, 3])),
    fileName: fileName,
    mimeType: 'image/png',
    ttlMillis: ttlMillis,
  });
}

/** 取 URI 中 `/<prefix>/<token>/<fileName>` 的 token 段。 */
function tokenOf(uri: string, prefix: string): string {
  const rest = uri.substring((ORIGIN + '/' + prefix + '/').length);
  return rest.substring(0, rest.indexOf('/'));
}

function resolveThrows(registry: InMemoryHandleRegistry, uri: string): boolean {
  try {
    registry.resolve(uri);
    return false;
  } catch (error) {
    return true;
  }
}

/**
 * Handle 路径是 capability 模型（design.md §5.4）：持有不透明 token 即等于授权。
 * 因此本套用例的重点不是「URI 长得对不对」，而是三条安全属性：
 *   1. token 不可退化 —— 同样的入参连续两次 register 必须产出**不同**的 URI；
 *   2. 过期/吊销后凭证真的作废，且过期条目在读时被驱逐（不是仅仅报告状态）；
 *   3. URI 反查必须逐字节一致 —— 除保留的 `_la_cb` 外，任何 query/fragment 变化都改变身份。
 *
 * 关于 (1)：ArkTS 的 util.generateRandomUUID() 在 hvigor 单测沙箱中**返回空串**（已实测），
 * 若用它做 token，所有 handle URI 会撞成 `.../p//a.png` 这一条 —— 而只断言 URI 前后缀的
 * 测试对此完全无感（前缀仍匹配、后缀仍匹配），capability 模型静默失效。
 * 故这里显式断言 token 长度与两次 register 的差异。
 */
export default function inMemoryHandleRegistryTest() {
  describe('inMemoryHandleRegistryTest', () => {
    // ---------- UUID：token 熵 ----------

    it('generates distinct 36-char uuids', 0, () => {
      const a = generateUuidV4();
      const b = generateUuidV4();
      expect(a.length).assertEqual(36);
      expect(b.length).assertEqual(36);
      expect(a === b).assertFalse();
    });

    it('generates uuids in v4 shape', 0, () => {
      const uuid = generateUuidV4();
      expect(uuid.charAt(8)).assertEqual('-');
      expect(uuid.charAt(13)).assertEqual('-');
      expect(uuid.charAt(18)).assertEqual('-');
      expect(uuid.charAt(23)).assertEqual('-');
      expect(uuid.charAt(14)).assertEqual('4');
      expect('89ab'.indexOf(uuid.charAt(19)) >= 0).assertTrue();
      expect(/^[0-9a-f-]{36}$/.test(uuid)).assertTrue();
    });

    it('generates 200 distinct uuids', 0, () => {
      // 低熵/常量退化在只比两个样本时可能侥幸通过；批量去重才真正兜住。
      const seen = new Set<string>();
      for (let i = 0; i < 200; i++) {
        seen.add(generateUuidV4());
      }
      expect(seen.size).assertEqual(200);
    });

    // ---------- register：URI 形态 ----------

    it('registers a handle and returns a capability uri', 0, () => {
      const registry = new InMemoryHandleRegistry('handles.demo.local', '/preview', () => 0);
      const uri = registry.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1, 2, 3])),
        fileName: 'photo.png',
        mimeType: 'image/png',
      }));
      expect(uri.startsWith('local-asset://handles.demo.local/preview/')).assertTrue();
      expect(uri.endsWith('/photo.png')).assertTrue();
    });

    it('mints a distinct uri for identical input on every register', 0, () => {
      // 退化 token 探针：同一个 handle 对象注册两次，两条 URI 必须不同，
      // 且都能各自解析回来（handle 路径不做内容去重）。
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const same = handle('a.png');
      const first = registry.register(same);
      const second = registry.register(same);
      expect(first === second).assertFalse();
      expect(registry.resolve(first).resourceUri).assertEqual(first);
      expect(registry.resolve(second).resourceUri).assertEqual(second);
    });

    it('embeds a full-length token segment in the uri', 0, () => {
      // 空 token 会让 URI 退化成 'local-asset://h.local/p//a.png'——前后缀断言照样通过。
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const token = tokenOf(registry.register(handle('a.png')), 'p');
      expect(token.length).assertEqual(36);
    });

    it('uses the documented default host and path prefix', 0, () => {
      const registry = new InMemoryHandleRegistry();
      const uri = registry.register(handle('a.png'));
      expect(uri.startsWith('local-asset://handles.localasset.local/handles/')).assertTrue();
    });

    it('normalizes the path prefix', 0, () => {
      // Kotlin: pathPrefix.trim('/')，两端斜杠全剥；全为斜杠时回落到 'handles'。
      const trimmed = new InMemoryHandleRegistry(HOST, '//p//', () => 0);
      expect(trimmed.register(handle('a.png')).startsWith(ORIGIN + '/p/')).assertTrue();
      const empty = new InMemoryHandleRegistry(HOST, '///', () => 0);
      expect(empty.register(handle('a.png')).startsWith(ORIGIN + '/handles/')).assertTrue();
      const blank = new InMemoryHandleRegistry(HOST, '', () => 0);
      expect(blank.register(handle('a.png')).startsWith(ORIGIN + '/handles/')).assertTrue();
    });

    it('sanitizes unsafe characters in file name', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: 'my photo (1).png',
        mimeType: 'image/png',
      }));
      expect(uri.endsWith('/my_photo__1_.png')).assertTrue();
    });

    it('keeps the raw file name on the record while sanitizing only the uri', 0, () => {
      // Kotlin/iOS 均为 record.fileName = handle.fileName（原样），仅 buildUri 用 safe 版本。
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: 'my photo.png',
        mimeType: 'image/png',
      }));
      expect(uri.endsWith('/my_photo.png')).assertTrue();
      expect(registry.resolve(uri).fileName).assertEqual('my photo.png');
    });

    it('sanitizes path separators so a file name cannot forge extra segments', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: '../../etc/passwd',
        mimeType: 'text/plain',
      }));
      expect(uri.endsWith('/.._.._etc_passwd')).assertTrue();
    });

    // ---------- file-backed handles ----------

    it('file-backed handle stores filePath source and null size', 0, () => {
      // design.md §4.4：handle 现在支持 filePath 来源，避免大文件被迫全量入内存。
      // 注册时不读盘，size 留 null（对齐 Kotlin/iOS）；文件根校验由 postCheck 负责。
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(createResourceHandle({
        source: filePathSource('/data/storage/el2/base/files/big.pdf'),
        fileName: 'big.pdf',
        mimeType: 'application/pdf',
      }));
      expect(uri.endsWith('/big.pdf')).assertTrue();
      const record: ResourceHandleRecord = registry.resolve(uri);
      expect(record.source.kind).assertEqual('filePath');
      expect(record.size).assertNull();
      expect(record.fileName).assertEqual('big.pdf');
    });

    // ---------- resolve ----------

    it('resolves a registered uri back to its record', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const meta = new Map<string, string>();
      meta.set('harmony.picker_uri', 'file://media/1');
      const uri = registry.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1, 2, 3, 4])),
        fileName: 'a.png',
        mimeType: 'image/png',
        metadata: meta,
      }));
      const record: ResourceHandleRecord = registry.resolve(uri);
      expect(record.resourceUri).assertEqual(uri);
      expect(record.fileName).assertEqual('a.png');
      expect(record.mimeType).assertEqual('image/png');
      expect(record.size).assertEqual(4);
      expect(record.source.kind).assertEqual('bytes');
      expect((record.source as BytesSource).value[3]).assertEqual(4);
      expect(record.metadata.get('harmony.picker_uri')).assertEqual('file://media/1');
      expect(record.ttlMillis).assertNull();
    });

    it('throws RESOLUTION_ERROR for unknown uri', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      let caught: ResourceException | null = null;
      try {
        registry.resolve(ORIGIN + '/p/nope/a.png');
      } catch (error) {
        caught = error as ResourceException;
      }
      expect(caught !== null).assertTrue();
      expect((caught as ResourceException).category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
      expect((caught as ResourceException).message)
        .assertEqual('Unknown or expired resourceUri: ' + ORIGIN + '/p/nope/a.png');
    });

    it('throws after explicit remove (revocation)', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(handle('a.png'));
      registry.remove(uri);
      expect(resolveThrows(registry, uri)).assertTrue();
    });

    it('revokes only the named uri', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const first = registry.register(handle('a.png'));
      const second = registry.register(handle('b.png'));
      registry.remove(first);
      expect(resolveThrows(registry, first)).assertTrue();
      expect(registry.resolve(second).fileName).assertEqual('b.png');
    });

    it('remove of an unknown uri is a no-op', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      registry.remove(ORIGIN + '/p/nope/a.png');
      expect(resolveThrows(registry, ORIGIN + '/p/nope/a.png')).assertTrue();
    });

    // ---------- TTL ----------

    it('expires a handle lazily on lookup', 0, () => {
      let now = 0;
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const uri = registry.register(handle('a.png', 100));
      now = 100;
      expect(resolveThrows(registry, uri)).assertTrue();
    });

    it('still resolves one millisecond before expiry', 0, () => {
      // 判据是闭区间 now - createdAt >= ttl，与 Kotlin/iOS 一致：99 存活，100 过期。
      let now = 0;
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const uri = registry.register(handle('a.png', 100));
      now = 99;
      expect(registry.resolve(uri).fileName).assertEqual('a.png');
    });

    it('measures ttl from the handle own creation, not from registry construction', 0, () => {
      // 若实现把 createdAt 写死成 0 或用构造期快照，now=1050 这一步会误判过期。
      let now = 1000;
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const uri = registry.register(handle('a.png', 100));
      now = 1050;
      expect(registry.resolve(uri).fileName).assertEqual('a.png');
      now = 1100;
      expect(resolveThrows(registry, uri)).assertTrue();
    });

    it('evicts the expired entry on the failing lookup', 0, () => {
      // 与 ResourceRegistry.lookup 的关键不对称：handle 的 resolve 会**驱逐**过期条目。
      // 验证手法：过期读一次之后把时钟回拨——若只是「报告过期」而没删，回拨后又能解析出来。
      let now = 0;
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const uri = registry.register(handle('a.png', 100));
      now = 100;
      expect(resolveThrows(registry, uri)).assertTrue();
      now = 0;
      expect(resolveThrows(registry, uri)).assertTrue();
    });

    it('never expires a handle without ttl', 0, () => {
      let now = 0;
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const uri = registry.register(handle('a.png', null));
      now = 999999999;
      expect(registry.resolve(uri).fileName).assertEqual('a.png');
    });

    // ---------- cleanup ----------

    it('cleanup drops only expired entries', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const gone = registry.register(handle('a.png', 100));
      const kept = registry.register(handle('b.png', null));
      registry.cleanup(1000);
      expect(resolveThrows(registry, gone)).assertTrue();
      expect(registry.resolve(kept).fileName).assertEqual('b.png');
    });

    it('cleanup honours the same closed boundary as resolve', 0, () => {
      // createdAt + ttl == nowMillis 必须被清掉；差 1ms 则留下。
      let now = 0;
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const atBoundary = registry.register(handle('a.png', 1000));
      now = 1;
      const oneMsLeft = registry.register(handle('b.png', 1000));
      registry.cleanup(1000);
      expect(resolveThrows(registry, atBoundary)).assertTrue();
      now = 1;
      expect(registry.resolve(oneMsLeft).fileName).assertEqual('b.png');
    });

    // ---------- reconstructUriFromRequest / resolveFromRequest ----------

    it('resolveFromRequest reconstructs the uri and hits', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(handle('a.png'));
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: uri.substring(ORIGIN.length),
      });
      const record = registry.resolveFromRequest(request);
      expect(record !== null).assertTrue();
      expect((record as ResourceHandleRecord).resourceUri).assertEqual(uri);
    });

    it('resolveFromRequest ignores the cache-bust param', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(handle('a.png'));
      const query = new Map<string, string>();
      query.set(CACHE_BUST_PARAM, '12345');
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: uri.substring(ORIGIN.length),
        query: query,
      });
      expect(registry.resolveFromRequest(request) !== null).assertTrue();
    });

    it('resolveFromRequest keeps non-cache-bust query keys in the identity', 0, () => {
      // 注册时那条 URI 没有 query，所以任何非 _la_cb 的参数都会改变身份 → 必须 miss。
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(handle('a.png'));
      const query = new Map<string, string>();
      query.set('w', '100');
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: uri.substring(ORIGIN.length),
        query: query,
      });
      expect(registry.resolveFromRequest(request)).assertNull();
    });

    it('resolveFromRequest still misses when a cache-bust param rides along with a real one', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(handle('a.png'));
      const query = new Map<string, string>();
      query.set(CACHE_BUST_PARAM, '1');
      query.set('w', '100');
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: uri.substring(ORIGIN.length),
        query: query,
      });
      expect(registry.resolveFromRequest(request)).assertNull();
    });

    it('resolveFromRequest keeps the fragment in the identity', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = registry.register(handle('a.png'));
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: uri.substring(ORIGIN.length),
        fragment: 'top',
      });
      expect(registry.resolveFromRequest(request)).assertNull();
    });

    it('resolveFromRequest returns null for unknown uri', 0, () => {
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: '/p/unknown-token/a.png',
      });
      expect(registry.resolveFromRequest(request)).assertNull();
    });

    it('resolveFromRequest returns null for an expired handle instead of throwing', 0, () => {
      let now = 0;
      const registry = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const uri = registry.register(handle('a.png', 100));
      const request = createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: uri.substring(ORIGIN.length),
      });
      expect(registry.resolveFromRequest(request) !== null).assertTrue();
      now = 100;
      expect(registry.resolveFromRequest(request)).assertNull();
    });

    it('reconstructUriFromRequest rebuilds scheme://namespace + path', 0, () => {
      const uri = reconstructUriFromRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: '/p/tok/a.png',
      }));
      expect(uri).assertEqual(ORIGIN + '/p/tok/a.png');
    });

    it('reconstructUriFromRequest falls back to identifier when path is null', 0, () => {
      const uri = reconstructUriFromRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: null,
      }));
      expect(uri).assertEqual(ORIGIN + '/a.png');
    });

    it('reconstructUriFromRequest appends surviving query and fragment', 0, () => {
      const query = new Map<string, string>();
      query.set(CACHE_BUST_PARAM, '9');
      query.set('w', '100');
      query.set('h', '50');
      const uri = reconstructUriFromRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: HOST,
        identifier: 'a.png',
        path: '/p/tok/a.png',
        query: query,
        fragment: 'top',
      }));
      // Map 保持插入序，_la_cb 被剔除，其余按 k=v 以 '&' 连接，再接 '#fragment'。
      expect(uri).assertEqual(ORIGIN + '/p/tok/a.png?w=100&h=50#top');
    });

    it('exposes the reserved cache-bust param name as a cross-platform constant', 0, () => {
      expect(CACHE_BUST_PARAM).assertEqual('_la_cb');
    });
  });
}
