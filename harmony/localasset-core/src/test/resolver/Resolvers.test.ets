import { describe, it, expect } from '@ohos/hypium';
import { RegistryResolver } from '../../main/ets/resolver/RegistryResolver';
import { HandleRegistryResolver } from '../../main/ets/resolver/HandleRegistryResolver';
import { StaticMapResolver } from '../../main/ets/resolver/StaticMapResolver';
import { InMemoryResourceRegistry } from '../../main/ets/registry/InMemoryResourceRegistry';
import { InMemoryHandleRegistry } from '../../main/ets/registry/InMemoryHandleRegistry';
import { DefaultLocalAssetSchemeAdapter } from '../../main/ets/engine/DefaultLocalAssetSchemeAdapter';
import { AssetRequest, createAssetRequest } from '../../main/ets/model/AssetRequest';
import { createResolveContext } from '../../main/ets/model/ResolveContext';
import { createResourceHandle } from '../../main/ets/model/ResourceHandle';
import {
  ResourceType,
  ResourceScope,
  bytesSource,
  filePathSource,
  createResourceDescriptor,
  ResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import { CACHE_BUST_PARAM } from '../../main/ets/api/HandleRegistry';

const HOST = 'h.local';
const ORIGIN = 'local-asset://' + HOST;

function descriptor(id: string, ttlMillis: number | null): ResourceDescriptor {
  return createResourceDescriptor({
    id: id,
    namespace: 'demo',
    type: ResourceType.DYNAMIC,
    source: bytesSource(new Uint8Array([1])),
    createdAtMillis: 0,
    ttlMillis: ttlMillis,
  });
}

/** 内容比较：BytesSource 是引用相等（见 model/ResourceDescriptor.ets 的注记），必须逐字节比。 */
function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

/**
 * 三个内置 resolver 的契约测试。
 *
 * 重点在 HandleRegistryResolver：它产出的 descriptor 必须是
 * `scope = null` / `ttlMillis = null` / `createdAtMillis = 0`。这三条不是疏漏，
 * 而是 design.md §5.4 明写的两套安全模型分野：
 *   - Handle 路径是**能力令牌模型**，持有不透明 token 即授权，不能再被 Registry 路径的
 *     namespace/scope 匹配二次门禁 → scope 必须为 null；
 *   - TTL 归 HandleRegistry.resolve() 自己惰性执行（判据 now - createdAt >= ttl）。
 *     这里的 createdAtMillis 是占位 0，若把真实 ttlMillis 透传下去，Policy.postCheck
 *     的绝对时间判据 `createdAtMillis + ttl <= now` 会把**每一条** handle 都判成过期。
 * 只断言「返回了 hit」的测试对以上退化毫无察觉，所以下面三个字段逐个钉死。
 * （与 Android HandleRegistryResolverTest 的三条回归用例同源。）
 */
export default function resolversTest() {
  describe('resolversTest', () => {
    // ---------- RegistryResolver ----------

    it('RegistryResolver hits by identifier', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(descriptor('asset-1', null));
      const resolver = new RegistryResolver(registry);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: 'asset-1',
          path: '/asset-1',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('asset-1');
      }
    });

    it('RegistryResolver falls back to query id', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(descriptor('from-query', null));
      const resolver = new RegistryResolver(registry);
      const query = new Map<string, string>();
      query.set('id', 'from-query');
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: null,
          path: '/',
          query: query,
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('from-query');
      }
    });

    it('RegistryResolver prefers identifier over query id', 0, () => {
      // 优先级来自 `identifier ?? query['id']` 的求值顺序（Kotlin/iOS 同）。
      // 只测「两条路各自能命中」无法区分谁优先——两个 id 同时可命中才钉得住。
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(descriptor('from-identifier', null));
      registry.register(descriptor('from-query', null));
      const resolver = new RegistryResolver(registry);
      const query = new Map<string, string>();
      query.set('id', 'from-query');
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: 'from-identifier',
          path: '/from-identifier',
          query: query,
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('from-identifier');
      }
    });

    it('RegistryResolver skips when missing', 0, () => {
      const resolver = new RegistryResolver(new InMemoryResourceRegistry(() => 0));
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: 'nope',
          path: '/nope',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });

    it('RegistryResolver skips when neither identifier nor query id present', 0, () => {
      // 没有 id 可查时必须 Skip（把机会让给链上后续 resolver），不能是 Failure。
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(descriptor('asset-1', null));
      const resolver = new RegistryResolver(registry);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: null,
          path: '/',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });

    it('RegistryResolver fails when expired', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 5000);
      registry.register(descriptor('asset-1', 1000));
      const resolver = new RegistryResolver(registry);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: 'asset-1',
          path: '/asset-1',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
        expect(result.reason).assertEqual('resource expired');
      }
    });

    // ---------- HandleRegistryResolver ----------

    it('HandleRegistryResolver hits and neutralizes scope and ttl', 0, () => {
      const handles = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([9, 9])),
        fileName: 'a.png',
        mimeType: 'image/png',
        ttlMillis: 60000,
      }));
      const resolver = new HandleRegistryResolver(handles);
      const path = uri.substring(ORIGIN.length);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: HOST,
          identifier: 'a.png',
          path: path,
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        // design.md §5.4：handle 路径靠 token 授权，必须绕开 postCheck 的 scope 与 TTL 门。
        expect(result.descriptor.scope).assertNull();
        expect(result.descriptor.ttlMillis).assertNull();
        expect(result.descriptor.createdAtMillis).assertEqual(0);
        expect(result.descriptor.type).assertEqual(ResourceType.DYNAMIC);
        expect(result.descriptor.mimeType).assertEqual('image/png');
        expect(result.descriptor.id).assertEqual('a.png');
        expect(result.descriptor.namespace).assertEqual(HOST);
      }
    });

    it('HandleRegistryResolver carries the handle bytes into the descriptor source', 0, () => {
      const handles = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([7, 8, 9])),
        fileName: 'a.png',
        mimeType: 'image/png',
      }));
      const resolver = new HandleRegistryResolver(handles);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: HOST,
          identifier: 'a.png',
          path: uri.substring(ORIGIN.length),
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        const source = result.descriptor.source;
        expect(source.kind).assertEqual('bytes');
        if (source.kind === 'bytes') {
          expect(bytesEqual(source.value, new Uint8Array([7, 8, 9]))).assertTrue();
        }
      }
    });

    it('HandleRegistryResolver carries a filePath handle into the descriptor source', 0, () => {
      // file-backed handle：descriptor.source 必须是 filePath，这样 postCheck 的文件根门
      // （与 Registry 路径共享）才适用，FileResourceLoader 才会加载它——这是"大文件不进内存"
      // 的关键链路。
      const handles = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = handles.register(createResourceHandle({
        source: filePathSource('/data/storage/el2/base/files/big.pdf'),
        fileName: 'big.pdf',
        mimeType: 'application/pdf',
      }));
      const resolver = new HandleRegistryResolver(handles);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: HOST,
          identifier: 'big.pdf',
          path: uri.substring(ORIGIN.length),
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.source.kind).assertEqual('filePath');
        expect(result.descriptor.scope).assertNull();
        expect(result.descriptor.ttlMillis).assertNull();
        if (result.descriptor.source.kind === 'filePath') {
          expect(result.descriptor.source.value).assertEqual('/data/storage/el2/base/files/big.pdf');
        }
      }
    });

    it('HandleRegistryResolver skips unknown uri', 0, () => {
      const resolver = new HandleRegistryResolver(new InMemoryHandleRegistry(HOST, '/p', () => 0));
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: HOST,
          identifier: 'a.png',
          path: '/p/unknown/a.png',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });

    it('HandleRegistryResolver skips an expired handle instead of failing', 0, () => {
      // resolveFromRequest 把 HandleRegistry.resolve 的抛错吞成 null，所以过期在
      // resolver 这层表现为 Skip（探测语义），而不是 RegistryResolver 那样的 Failure。
      let now = 0;
      const handles = new InMemoryHandleRegistry(HOST, '/p', () => now);
      const uri = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: 'a.png',
        mimeType: 'image/png',
        ttlMillis: 1000,
      }));
      const resolver = new HandleRegistryResolver(handles);
      now = 5000;
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: HOST,
          identifier: 'a.png',
          path: uri.substring(ORIGIN.length),
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });

    it('HandleRegistryResolver ignores the reserved cache-bust param', 0, () => {
      // `_la_cb` 不参与 handle 身份：只差这个参数的请求仍须命中，否则每次打穿缓存都 404。
      const handles = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: 'a.png',
        mimeType: 'image/png',
      }));
      const resolver = new HandleRegistryResolver(handles);
      const query = new Map<string, string>();
      query.set(CACHE_BUST_PARAM, '1700000000000');
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: HOST,
          identifier: 'a.png',
          path: uri.substring(ORIGIN.length),
          query: query,
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('a.png');
      }
    });

    it('HandleRegistryResolver misses when a non-reserved query param is present', 0, () => {
      // 反向守卫：除 `_la_cb` 外的 query key 仍是身份的一部分，不能被一并剥掉。
      const handles = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const uri = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: 'a.png',
        mimeType: 'image/png',
      }));
      const resolver = new HandleRegistryResolver(handles);
      const query = new Map<string, string>();
      query.set('foo', 'bar');
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: HOST,
          identifier: 'a.png',
          path: uri.substring(ORIGIN.length),
          query: query,
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });

    it('HandleRegistryResolver resolves a minted uri parsed by the real scheme adapter', 0, () => {
      // 端到端：register() 铸造的 URI → 真实 DefaultLocalAssetSchemeAdapter.parse() →
      // HandleRegistryResolver.resolve()。这才是生产路径。
      // 其余用例用 `uri.substring(ORIGIN.length)` 手工切 path（与 Android/iOS 参考测试同一手法），
      // 那只证明 reconstructUriFromRequest 自洽，证明不了「真解析器解出来的 AssetRequest
      // 能逐字节还原出注册串」—— 编码/解码若在任一侧偏一点点，反查只会静默 miss。
      // 文件名刻意带空格与括号，走一遍净化正则 [^A-Za-z0-9._-] → '_'：
      // 净化只作用于 URI 段，record.fileName（即 descriptor.id）保留原名。
      const handles = new InMemoryHandleRegistry(HOST, '/p', () => 0);
      const originalFileName = 'my photo (1).png';
      const uri = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([4, 5, 6])),
        fileName: originalFileName,
        mimeType: 'image/png',
      }));
      // 净化后的段：空格与括号各自变成一个 '_'
      expect(uri.endsWith('/my_photo__1_.png')).assertTrue();

      const adapter = new DefaultLocalAssetSchemeAdapter();
      const request: AssetRequest = adapter.parse(uri);
      expect(request.namespace).assertEqual(HOST);
      expect(request.identifier).assertEqual('my_photo__1_.png');

      const resolver = new HandleRegistryResolver(handles);
      const result = resolver.resolve(request, createResolveContext());
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual(originalFileName);
        expect(result.descriptor.scope).assertNull();
        expect(result.descriptor.ttlMillis).assertNull();
        const source = result.descriptor.source;
        expect(source.kind).assertEqual('bytes');
        if (source.kind === 'bytes') {
          expect(bytesEqual(source.value, new Uint8Array([4, 5, 6]))).assertTrue();
        }
      }
    });

    // ---------- StaticMapResolver ----------

    it('StaticMapResolver hits by namespace and path', 0, () => {
      const mappings = new Map<string, ResourceDescriptor>();
      mappings.set('demo:/logo.png', descriptor('logo', null));
      const resolver = new StaticMapResolver(mappings);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: 'logo.png',
          path: '/logo.png',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.id).assertEqual('logo');
      }
    });

    it('StaticMapResolver returns the mapped descriptor verbatim', 0, () => {
      // 映射里的 descriptor 原样透传：不加工 scope/ttl（与 HandleRegistryResolver 的
      // 刻意置空形成对照 —— static 映射走的是 Registry 路径的 namespace/scope 模型）。
      const mapped = createResourceDescriptor({
        id: 'logo',
        namespace: 'demo',
        type: ResourceType.STATIC,
        source: bytesSource(new Uint8Array([1])),
        mimeType: 'image/png',
        createdAtMillis: 123,
        ttlMillis: 60000,
        scope: ResourceScope.PAGE,
      });
      const mappings = new Map<string, ResourceDescriptor>();
      mappings.set('demo:/logo.png', mapped);
      const resolver = new StaticMapResolver(mappings);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: 'logo.png',
          path: '/logo.png',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('hit');
      if (result.kind === 'hit') {
        expect(result.descriptor.scope).assertEqual(ResourceScope.PAGE);
        expect(result.descriptor.ttlMillis).assertEqual(60000);
        expect(result.descriptor.createdAtMillis).assertEqual(123);
        expect(result.descriptor.type).assertEqual(ResourceType.STATIC);
      }
    });

    it('StaticMapResolver skips unmapped path', 0, () => {
      const resolver = new StaticMapResolver(new Map<string, ResourceDescriptor>());
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'demo',
          identifier: 'logo.png',
          path: '/logo.png',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });

    it('StaticMapResolver skips when the namespace differs', 0, () => {
      // key 是 `<namespace>:<path>`；只按 path 匹配会跨 namespace 走漏资源。
      const mappings = new Map<string, ResourceDescriptor>();
      mappings.set('demo:/logo.png', descriptor('logo', null));
      const resolver = new StaticMapResolver(mappings);
      const result = resolver.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'other',
          identifier: 'logo.png',
          path: '/logo.png',
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });
  });
}
