import { describe, it, expect } from '@ohos/hypium';
import { DefaultPolicy } from '../../main/ets/policy/DefaultPolicy';
import { AssetRequest, createAssetRequest } from '../../main/ets/model/AssetRequest';
import { createResolveContext } from '../../main/ets/model/ResolveContext';
import {
  ResourceType,
  ResourceScope,
  bytesSource,
  filePathSource,
  createResourceDescriptor,
  ResourceDescriptor,
  ResourceSource,
} from '../../main/ets/model/ResourceDescriptor';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import fs from '@ohos.file.fs';
import { InMemoryHandleRegistry } from '../../main/ets/registry/InMemoryHandleRegistry';
import { HandleRegistryResolver } from '../../main/ets/resolver/HandleRegistryResolver';
import { createResourceHandle } from '../../main/ets/model/ResourceHandle';

function request(namespace: string, path: string, scheme: string = 'local-asset'): AssetRequest {
  return createAssetRequest({
    scheme: scheme,
    namespace: namespace,
    identifier: 'x',
    path: path,
  });
}

function descriptorWith(
  source: ResourceSource,
  scope: ResourceScope | null,
  ttlMillis: number | null,
  namespace: string = 'demo',
): ResourceDescriptor {
  return createResourceDescriptor({
    id: 'asset-1',
    namespace: namespace,
    type: ResourceType.STATIC,
    source: source,
    createdAtMillis: 0,
    ttlMillis: ttlMillis,
    scope: scope,
  });
}

function categoryOf(fn: () => void): string | null {
  try {
    fn();
    return null;
  } catch (error) {
    return (error as ResourceException).category;
  }
}

function stageOf(fn: () => void): string | null {
  try {
    fn();
    return null;
  } catch (error) {
    return (error as ResourceException).stage;
  }
}

/**
 * design.md §5.4 的 Handle 路径回归：造一个 HandleRegistryResolver 真实产出的 descriptor。
 * 不手抄字段，而是把请求真的送进 resolver —— 手抄的副本会随生产代码漂移而失去意义。
 */
const HANDLE_HOST = 'h.local';

function handleDescriptor(): ResourceDescriptor {
  const handles = new InMemoryHandleRegistry(HANDLE_HOST, '/p', () => 0);
  const uri = handles.register(createResourceHandle({
    source: bytesSource(new Uint8Array([1, 2, 3])),
    fileName: 'a.png',
    mimeType: 'image/png',
  }));
  const resolver = new HandleRegistryResolver(handles);
  const result = resolver.resolve(
    createAssetRequest({
      scheme: 'local-asset',
      namespace: HANDLE_HOST,
      identifier: 'a.png',
      path: uri.substring(('local-asset://' + HANDLE_HOST).length),
    }),
    createResolveContext(),
  );
  if (result.kind !== 'hit') {
    throw new Error('handle resolver must hit for this fixture');
  }
  return result.descriptor;
}

export default function defaultPolicyTest() {
  describe('defaultPolicyTest', () => {
    it('preCheck passes a plain request', 0, () => {
      const policy = new DefaultPolicy();
      expect(categoryOf(() => policy.preCheck(request('demo', '/a.png'), createResolveContext()))).assertNull();
    });

    it('preCheck rejects blank scheme', 0, () => {
      const policy = new DefaultPolicy();
      const req = request('demo', '/a.png', '');
      expect(categoryOf(() => policy.preCheck(req, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
      expect(stageOf(() => policy.preCheck(req, createResolveContext()))).assertEqual('policy_pre');
    });

    it('preCheck enforces scheme allow-list when configured', 0, () => {
      const policy = new DefaultPolicy({ allowedSchemes: ['other-scheme'] });
      expect(categoryOf(() => policy.preCheck(request('demo', '/a.png'), createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('preCheck rejects blank namespace', 0, () => {
      const policy = new DefaultPolicy();
      const req = request('   ', '/a.png');
      expect(categoryOf(() => policy.preCheck(req, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
      expect(stageOf(() => policy.preCheck(req, createResolveContext()))).assertEqual('policy_pre');
    });

    it('preCheck enforces namespace allow-list when configured', 0, () => {
      const policy = new DefaultPolicy({ allowedNamespaces: ['allowed'] });
      expect(categoryOf(() => policy.preCheck(request('demo', '/a.png'), createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
      expect(categoryOf(() => policy.preCheck(request('allowed', '/a.png'), createResolveContext())))
        .assertNull();
    });

    it('preCheck does not break handle host when namespace allow-list is set', 0, () => {
      // Footgun regression: 声明 namespace 白名单曾把所有 handle URI 静默拒掉，因为 handle
      // URI 固定住在 handles.localasset.local。Handle 路径靠能力令牌授权、不靠 namespace，
      // 故 handle host 永远豁免。
      const policy = new DefaultPolicy({ allowedNamespaces: ['foo'] });
      expect(categoryOf(() => policy.preCheck(request('handles.localasset.local', '/handles/t/a.png'), createResolveContext())))
        .assertNull();
    });

    it('preCheck exempts a custom handle host from the namespace allow-list', 0, () => {
      const policy = new DefaultPolicy({ allowedNamespaces: ['foo'], handleHost: 'my-handles.local' });
      expect(categoryOf(() => policy.preCheck(request('my-handles.local', '/handles/t/a.png'), createResolveContext())))
        .assertNull();
    });

    it('preCheck rejects path traversal', 0, () => {
      const policy = new DefaultPolicy();
      expect(categoryOf(() => policy.preCheck(request('demo', '/pkg/../secret'), createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('preCheck rejects traversal hidden in the identifier', 0, () => {
      // path 干净但 identifier 带 `..` 段 —— 只查 path 的实现会漏掉这一条。
      const policy = new DefaultPolicy();
      const req = createAssetRequest({
        scheme: 'local-asset',
        namespace: 'demo',
        identifier: '../secret',
        path: '/a.png',
      });
      expect(categoryOf(() => policy.preCheck(req, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('preCheck allows dots inside a segment', 0, () => {
      const policy = new DefaultPolicy();
      expect(categoryOf(() => policy.preCheck(request('demo', '/pkg/a..b.png'), createResolveContext())))
        .assertNull();
    });

    it('preCheck runs the scheme gate before the namespace gate', 0, () => {
      // 同时违反两条时，先报的必须是 scheme —— 顺序决定调用方看到哪条 message。
      const policy = new DefaultPolicy();
      const req = request('', '/a.png', '');
      let message = '';
      try {
        policy.preCheck(req, createResolveContext());
      } catch (error) {
        message = (error as ResourceException).message;
      }
      expect(message).assertEqual('scheme must not be blank');
    });

    it('postCheck rejects expired descriptor as RESOLUTION_ERROR', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 1000 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), null, 1000);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
      expect(stageOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual('policy_post');
    });

    it('postCheck accepts a descriptor one millisecond before expiry', 0, () => {
      // 与上一条配对钉死闭区间判据 `createdAt + ttl <= now`：
      // now = 999 时未过期，now = 1000（上一条）已过期。改成 `<` 会让上一条失败。
      const policy = new DefaultPolicy({ nowProvider: () => 999 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), null, 1000);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    it('postCheck passes ENGINE scope when namespace matches engineScope', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), ResourceScope.ENGINE, null, 'engine-a');
      const context = createResolveContext({ engineScope: 'engine-a' });
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, context))).assertNull();
    });

    it('postCheck rejects ENGINE scope mismatch as SECURITY_ERROR', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), ResourceScope.ENGINE, null, 'engine-a');
      const context = createResolveContext({ engineScope: 'engine-b' });
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, context)))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck rejects PAGE scope mismatch', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), ResourceScope.PAGE, null, 'page-a');
      const context = createResolveContext({ pageScope: 'page-b' });
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, context)))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck matches each scope against its own context field', 0, () => {
      // design.md §5.3：三种 scope 各查各的字段。把 SESSION 的期望值只放进 pageScope，
      // 若实现把 SESSION 错查成 pageScope 就会误放行。
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), ResourceScope.SESSION, null, 'sess-a');
      const wrongField = createResolveContext({ pageScope: 'sess-a', engineScope: 'sess-a' });
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, wrongField)))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
      const rightField = createResolveContext({ sessionScope: 'sess-a' });
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, rightField)))
        .assertNull();
    });

    it('postCheck reports the offending scope in the message', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), ResourceScope.PAGE, null, 'page-a');
      let message = '';
      try {
        policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext({ pageScope: 'page-b' }));
      } catch (error) {
        message = (error as ResourceException).message;
      }
      expect(message).assertEqual('page scope mismatch');
    });

    it('postCheck skips scope gate when scope is null', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), null, null, 'anything');
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    it('postCheck runs the TTL gate before the scope gate', 0, () => {
      // 同时过期且 scope 不匹配时，调用方必须看到 RESOLUTION_ERROR（过期），不是 SECURITY_ERROR。
      const policy = new DefaultPolicy({ nowProvider: () => 1000 });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), ResourceScope.ENGINE, 1000, 'engine-a');
      const context = createResolveContext({ engineScope: 'engine-b' });
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, context)))
        .assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
    });

    it('postCheck rejects filePath source when no roots configured (fail-closed)', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const descriptor = descriptorWith(filePathSource('/data/app/cache/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck accepts filePath under an allowed root', 0, () => {
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/cache/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    it('postCheck accepts a real on-disk file under an allowed root', 0, () => {
      // 本平台第一个走过 isAllowedFilePath 全链的真实文件用例：确保 normalizeAbsolutePath 对真实
      // 路径的规范化不误伤。符号链接逃逸不在本用例覆盖范围——平台无 readlink/realPath，词法校验
      // 不做符号链接拦截，该缺口靠调用方契约缓解（见类注释与 threat-model §4.1）。
      const root = '/tmp/__la_policy_root_' + Date.now();
      const file = root + '/note.txt';
      if (!fs.accessSync(root)) {
        fs.mkdirSync(root, true);
      }
      const f = fs.openSync(file, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(f.fd, 'hi');
      fs.closeSync(f);
      try {
        const policy = new DefaultPolicy({ nowProvider: () => 0, allowedFileRoots: [root] });
        const descriptor = descriptorWith(filePathSource(file), null, null);
        expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
          .assertNull();
      } finally {
        try { fs.unlinkSync(file); } catch (e) { /* ignore */ }
        try { fs.rmdirSync(root); } catch (e) { /* ignore */ }
      }
    });

    it('postCheck accepts a root given with a trailing separator', 0, () => {
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache/'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/cache/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    it('postCheck accepts the root path itself', 0, () => {
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/cache'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    it('postCheck rejects filePath outside allowed roots', 0, () => {
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/other/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck rejects a prefix-lookalike sibling directory', 0, () => {
      // /data/app/cache-evil 不能因为字符串前缀相同就被当成 /data/app/cache 下的文件。
      // 裸 startsWith(root) 会放行它 —— 那是一次真实的目录逃逸。
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/cache-evil/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck checks every configured root, not just the first', 0, () => {
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache', '/data/app/media'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/media/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    // ---------- filePath 规范化（fix round 1）：descriptor.source.value 从不经过 preCheck ----------

    it('postCheck rejects `..` escaping the allowed root', 0, () => {
      // 核心回归：/data/app/cache/../../../etc/passwd 字符串前缀确实是 /data/app/cache/，
      // 不规范化就会被放行给 Loader。descriptor.source.value 由 resolver 产出，
      // preCheck 的 `..` 拦截只看 request.path / request.identifier，管不到这里。
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/cache/../../../etc/passwd'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck accepts `..` that collapses back inside the root', 0, () => {
      // 防止矫枉过正：折叠后是 /data/app/cache/b.png，仍在根内，必须放行。
      // 一刀切地"含 `..` 就拒"会让这条失败 —— 规范化不等于拉黑关键字。
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/cache/sub/../b.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    it('postCheck normalizes `.` and duplicate separators', 0, () => {
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/./cache//a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertNull();
    });

    it('postCheck normalizes the configured root too, not just the path', 0, () => {
      // 两侧都要规范化：根写成 /data/app/tmp/../cache 时，等价于 /data/app/cache。
      // 只规范化 path 的实现会让这条失败。
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/tmp/../cache'],
      });
      const inside = descriptorWith(filePathSource('/data/app/cache/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), inside, createResolveContext())))
        .assertNull();
      const outside = descriptorWith(filePathSource('/data/app/tmp/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), outside, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck fails closed on a path that cannot be normalized', 0, () => {
      // 对齐 Kotlin 的 `runCatching { ... }.getOrNull() ?: return false`：
      // 规范化失败必须拒绝，绝不放行。
      //
      // 关键在第一条：它的**原始字符串**就以 `/data/app/cache/` 开头，只有规范化失败后
      // 老老实实返回 false 才会被拒。任何"规范化失败就退回原串再比"的写法都会放行它。
      // （变异测试实测：把 `?? path` 兜底加回去，只有这一条能抓住；用相对路径写的断言
      //  在两种实现下都被拒，对 fail-open 完全无感。）
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const prefixMatchingButUnnormalizable =
        descriptorWith(filePathSource('/data/app/cache/../../../../etc/passwd'), null, null);
      expect(categoryOf(() => policy.postCheck(
        request('demo', '/a.png'),
        prefixMatchingButUnnormalizable,
        createResolveContext(),
      ))).assertEqual(ResourceErrorCategory.SECURITY_ERROR);

      const relative = descriptorWith(filePathSource('data/app/cache/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), relative, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
      const escapesFsRoot = descriptorWith(filePathSource('/../../etc/passwd'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), escapesFsRoot, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck rejects rather than clamps a path escaping the filesystem root', 0, () => {
      // 刻意比 Kotlin 更严：Java 的 File("/../../etc/passwd").canonicalFile 会**钳到**
      // /etc/passwd（POSIX 语义），根配成 '/' 时因而放行；本实现返回 null 直接拒。
      // 方向是更保守（只会多拒、绝不多放），符合 fail-closed 的取向。
      // 根 '/' 只是最容易写的一种情形，**不是唯一显形的情形** —— 见下一条用例。
      const policy = new DefaultPolicy({ nowProvider: () => 0, allowedFileRoots: ['/'] });
      const normal = descriptorWith(filePathSource('/etc/passwd'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), normal, createResolveContext())))
        .assertNull();
      const escapes = descriptorWith(filePathSource('/../../etc/passwd'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), escapes, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck rejects a leading-.. path that Java would clamp back into the root', 0, () => {
      // 钉住上一条更正后的说法：钳-vs-拒 的分歧**不限于根 = '/'**。
      // 实测 JVM（java.io.File.getCanonicalFile）：
      //   /../data/app/cache/x.png    -> /data/app/cache/x.png   → 参考实现 ACCEPT
      //   /../../data/app/cache/x.png -> /data/app/cache/x.png   → 参考实现 ACCEPT
      // 前导 `..` 被钳在文件系统根上，折叠后又落回 /data/app/cache 之内。
      // 本实现返回 null → REJECT。差异真实存在于普通根之下，方向仍是我们更严。
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache'],
      });
      const clampsBackIn = descriptorWith(filePathSource('/../data/app/cache/x.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), clampsBackIn, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
      // 同一路径去掉前导 `..` 后必须放行 —— 证明拒绝的原因确实是那两个点，
      // 而不是路径本身就不在根内（否则这条断言测不出任何东西）。
      const sameWithoutDotDot = descriptorWith(filePathSource('/data/app/cache/x.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), sameWithoutDotDot, createResolveContext())))
        .assertNull();
    });

    it('postCheck drops a root that cannot be normalized instead of trusting it', 0, () => {
      // 无法规范化的根（相对路径）在构造期被丢弃。丢弃后列表为空 → fail-closed 全拒，
      // 而不是留着它去做一次形态不一致的比较。
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['relative/cache'],
      });
      const descriptor = descriptorWith(filePathSource('relative/cache/a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck still blocks the sibling directory after normalization', 0, () => {
      // 规范化不能把尾分隔符前缀检查冲掉：/data/app/cache-evil 规范化后仍是它自己，
      // 依旧不得被当成 /data/app/cache 之下。与上面 prefix-lookalike 一条互为保险。
      const policy = new DefaultPolicy({
        nowProvider: () => 0,
        allowedFileRoots: ['/data/app/cache/'],
      });
      const descriptor = descriptorWith(filePathSource('/data/app/cache-evil/./a.png'), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck rejects a source kind that is not allowed', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0, allowedSourceKinds: ['filePath'] });
      const descriptor = descriptorWith(bytesSource(new Uint8Array([1])), null, null);
      expect(categoryOf(() => policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext())))
        .assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });

    it('postCheck allows both source kinds by default', 0, () => {
      const policy = new DefaultPolicy({ nowProvider: () => 0, allowedFileRoots: ['/data/app/cache'] });
      expect(categoryOf(() => policy.postCheck(
        request('demo', '/a.png'),
        descriptorWith(bytesSource(new Uint8Array([1])), null, null),
        createResolveContext(),
      ))).assertNull();
      expect(categoryOf(() => policy.postCheck(
        request('demo', '/a.png'),
        descriptorWith(filePathSource('/data/app/cache/a.png'), null, null),
        createResolveContext(),
      ))).assertNull();
    });

    it('postCheck runs the source-kind gate before the file-root gate', 0, () => {
      // filePath 既不在白名单里、也不在任何根下时，先报的必须是来源类型。
      const policy = new DefaultPolicy({ nowProvider: () => 0, allowedSourceKinds: ['bytes'] });
      const descriptor = descriptorWith(filePathSource('/data/app/other/a.png'), null, null);
      let message = '';
      try {
        policy.postCheck(request('demo', '/a.png'), descriptor, createResolveContext());
      } catch (error) {
        message = (error as ResourceException).message;
      }
      expect(message).assertEqual('source type is not allowed: filePath');
    });

    // ---------- design.md §5.4 Handle 路径与 Registry 路径的分野 ----------

    it('a HandleRegistryResolver descriptor survives postCheck with mismatched scopes', 0, () => {
      // HandleRegistry 把 scope / ttlMillis / createdAtMillis 三个字段刻意置空/置零，理由是
      // 「否则 postCheck 会拒掉每一条 handle」。DefaultPolicy 存在之前那只是预测，
      // 这条用例把它变成事实：上下文的三个 scope 身份全都与 descriptor.namespace 不同，
      // 而且 nowProvider 返回一个真实量级的时刻（handle 的 createdAtMillis 是占位 0），
      // 依然必须放行。
      const policy = new DefaultPolicy({ nowProvider: () => 1700000000000 });
      const descriptor = handleDescriptor();
      expect(descriptor.scope).assertNull();
      expect(descriptor.ttlMillis).assertNull();
      expect(descriptor.createdAtMillis).assertEqual(0);
      const hostileContext = createResolveContext({
        engineScope: 'engine-x',
        pageScope: 'page-x',
        sessionScope: 'session-x',
      });
      expect(categoryOf(() => policy.postCheck(
        request(HANDLE_HOST, '/p/t/a.png'),
        descriptor,
        hostileContext,
      ))).assertNull();
    });

    it('restoring ttlMillis on a handle descriptor would expire every handle', 0, () => {
      // 反证 ttlMillis = null 是承重的：把真实 TTL 填回去，配上占位的 createdAtMillis = 0，
      // postCheck 的绝对时间判据 `0 + ttl <= now` 立刻把它判过期。
      const policy = new DefaultPolicy({ nowProvider: () => 1700000000000 });
      const real = handleDescriptor();
      const leaky = createResourceDescriptor({
        id: real.id,
        namespace: real.namespace,
        type: real.type,
        source: real.source,
        mimeType: real.mimeType,
        createdAtMillis: real.createdAtMillis,
        ttlMillis: 60000,
        scope: real.scope,
      });
      expect(categoryOf(() => policy.postCheck(
        request(HANDLE_HOST, '/p/t/a.png'),
        leaky,
        createResolveContext(),
      ))).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
    });

    it('restoring scope on a handle descriptor would reject every handle', 0, () => {
      // 反证 scope = null 是承重的：handle 的 namespace 是 registry host，永远不会等于
      // 引擎/页面/会话的身份令牌，一旦带上 scope 就必然 scope mismatch。
      const policy = new DefaultPolicy({ nowProvider: () => 0 });
      const real = handleDescriptor();
      const leaky = createResourceDescriptor({
        id: real.id,
        namespace: real.namespace,
        type: real.type,
        source: real.source,
        mimeType: real.mimeType,
        createdAtMillis: real.createdAtMillis,
        ttlMillis: real.ttlMillis,
        scope: ResourceScope.ENGINE,
      });
      expect(categoryOf(() => policy.postCheck(
        request(HANDLE_HOST, '/p/t/a.png'),
        leaky,
        createResolveContext({ engineScope: 'engine-x' }),
      ))).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
    });
  });
}
