import { describe, it, expect } from '@ohos/hypium';
import { LocalAssetBuilder } from '../../main/ets/api/LocalAsset';
import { createResourceHandle } from '../../main/ets/model/ResourceHandle';
import {
  ResourceType,
  bytesSource,
  createResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';
import {
  ResourceResolver,
  ResolverResult,
  resolverHit,
} from '../../main/ets/api/ResourceResolver';
import { AssetRequest } from '../../main/ets/model/AssetRequest';
import { ResolveContext } from '../../main/ets/model/ResolveContext';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import { EngineObserver, EngineStageEvent, STAGE_COMPLETE } from '../../main/ets/api/EngineObserver';
import { Policy } from '../../main/ets/api/Policy';
import { ResourceDescriptor } from '../../main/ets/model/ResourceDescriptor';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { InMemoryResourceRegistry } from '../../main/ets/registry/InMemoryResourceRegistry';
import { InMemoryHandleRegistry } from '../../main/ets/registry/InMemoryHandleRegistry';

class AlwaysHitResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    return resolverHit(createResourceDescriptor({
      id: 'from-custom',
      namespace: request.namespace,
      type: ResourceType.DYNAMIC,
      source: bytesSource(new Uint8Array([42])),
      createdAtMillis: 0,
    }));
  }
}

/** 记录名字与顺序，用于验证 addResolver 的调用顺序被原样保留。 */
class NamedResolver implements ResourceResolver {
  private readonly name: string;
  private readonly log: string[];
  private readonly hit: boolean;

  constructor(name: string, log: string[], hit: boolean) {
    this.name = name;
    this.log = log;
    this.hit = hit;
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    this.log.push(this.name);
    if (!this.hit) {
      return { kind: 'skip' };
    }
    return resolverHit(createResourceDescriptor({
      id: this.name,
      namespace: request.namespace,
      type: ResourceType.DYNAMIC,
      source: bytesSource(new Uint8Array([1])),
      createdAtMillis: 0,
    }));
  }
}

class RejectAllPolicy implements Policy {
  preCheck(request: AssetRequest, context: ResolveContext): void {
    throw new ResourceException(ResourceErrorCategory.SECURITY_ERROR, 'custom policy rejected', 'policy_pre');
  }

  postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext): void {
  }
}

class RecordingObserver implements EngineObserver {
  readonly stages: string[] = [];

  onStage(event: EngineStageEvent): void {
    this.stages.push(event.stage);
  }
}

export default function localAssetBuilderTest() {
  describe('localAssetBuilderTest', () => {
    it('builds a working engine with defaults', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1, 2])),
        createdAtMillis: 0,
      }));
      const result = localAsset.engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('success');
      if (result.kind === 'success') {
        expect(result.descriptor.id).assertEqual('asset-1');
        expect(result.data.bytes.length).assertEqual(2);
      }
    });

    it('unregister makes the resource unresolvable', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      localAsset.unregister('asset-1');
      const result = localAsset.engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
      }
    });

    /**
     * 链序是安全属性，不是配置项（design.md §3.4）。
     * 自定义 resolver 对任何请求都 Hit，但 handle URI 仍必须由链首的 HandleRegistryResolver 命中。
     *
     * 断言刻意选了**两个能区分来源的字段**：
     * HandleRegistryResolver 命中 → id='a.png'、3 字节；AlwaysHitResolver 命中 → id='from-custom'、1 字节。
     * 若只断言 `kind === 'success'`，把用户 resolver 提到链首同样会成功 —— 这条测试就形同虚设。
     */
    it('places handle resolver first so handle uris win', 0, () => {
      const localAsset = new LocalAssetBuilder().addResolver(new AlwaysHitResolver()).build();
      const uri = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([9, 9, 9])),
        fileName: 'a.png',
        mimeType: 'image/png',
      }));
      const result = localAsset.engine.resolveUrl(uri);
      expect(result.kind).assertEqual('success');
      if (result.kind === 'success') {
        expect(result.descriptor.id).assertEqual('a.png');
        expect(result.data.bytes.length).assertEqual(3);
        // 逐字节核对，排除「恰好也是 3 字节的别的来源」这种巧合
        expect(result.data.bytes[0]).assertEqual(9);
      }
    });

    it('user resolvers run before the registry fallback', 0, () => {
      const localAsset = new LocalAssetBuilder().addResolver(new AlwaysHitResolver()).build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      const result = localAsset.engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('success');
      if (result.kind === 'success') {
        expect(result.descriptor.id).assertEqual('from-custom');
        expect(result.data.bytes[0]).assertEqual(42);
      }
    });

    /** addResolver 的调用顺序即链内顺序（不排序、不去重、不反转）。 */
    it('preserves addResolver call order', 0, () => {
      const log: string[] = [];
      const localAsset = new LocalAssetBuilder()
        .addResolver(new NamedResolver('first', log, false))
        .addResolver(new NamedResolver('second', log, false))
        .addResolver(new NamedResolver('third', log, true))
        .build();
      const result = localAsset.engine.resolveUrl('local-asset://demo/anything');
      expect(log.join(',')).assertEqual('first,second,third');
      expect(result.kind).assertEqual('success');
      if (result.kind === 'success') {
        expect(result.descriptor.id).assertEqual('third');
      }
    });

    it('resolveHandle round-trips a registered handle', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      const uri = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([5])),
        fileName: 'b.png',
        mimeType: 'image/png',
      }));
      expect(localAsset.resolveHandle(uri).fileName).assertEqual('b.png');
    });

    it('removeHandle revokes the capability uri', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      const uri = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([5])),
        fileName: 'b.png',
        mimeType: 'image/png',
      }));
      localAsset.removeHandle(uri);
      const result = localAsset.engine.resolveUrl(uri);
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
      }
    });

    /** 注入的 registry / handleRegistry 必须是引擎实际使用的那一个实例（而非被默认值悄悄替换）。 */
    it('uses the injected registries', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 0);
      const handleRegistry = new InMemoryHandleRegistry('h.local', '/p', () => 0);
      const localAsset = new LocalAssetBuilder()
        .setRegistry(registry)
        .setHandleRegistry(handleRegistry)
        .build();

      // 直接往注入的 registry 里写，经 engine 应能查到
      registry.register(createResourceDescriptor({
        id: 'direct',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([7])),
        createdAtMillis: 0,
      }));
      expect(localAsset.engine.resolveUrl('local-asset://demo/direct').kind).assertEqual('success');

      // 经门面注册的 handle，应出现在注入的那个 handleRegistry 里
      const uri = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([8])),
        fileName: 'c.png',
        mimeType: 'image/png',
      }));
      expect(uri.startsWith('local-asset://h.local/p/')).assertTrue();
      expect(handleRegistry.resolve(uri).fileName).assertEqual('c.png');
    });

    /** setPolicy 注入后，addAllowedXxx 配置被忽略（与 Kotlin Builder 的文档约定一致）。 */
    it('honours an injected policy', 0, () => {
      const localAsset = new LocalAssetBuilder()
        .addAllowedNamespace('demo')
        .setPolicy(new RejectAllPolicy())
        .build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      const result = localAsset.engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(result.reason).assertEqual('custom policy rejected');
      }
    });

    /** 默认 policy 的 namespace 白名单必须由 builder 传下去（否则该配置形同虚设）。 */
    it('wires allowed namespaces into the default policy', 0, () => {
      const localAsset = new LocalAssetBuilder().addAllowedNamespace('demo').build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'other',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      const rejected = localAsset.engine.resolveUrl('local-asset://other/asset-1');
      expect(rejected.kind).assertEqual('failure');
      if (rejected.kind === 'failure') {
        expect(rejected.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(rejected.reason).assertEqual('namespace is not allowed: other');
      }
    });

    /** addAllowedSchemes / addAllowedNamespaces 的批量变体与单个版本走同一条配置。 */
    it('wires bulk allowed schemes into the default policy', 0, () => {
      const localAsset = new LocalAssetBuilder().addAllowedSchemes(['other-scheme']).build();
      const rejected = localAsset.engine.resolveUrl('local-asset://demo/asset-1');
      expect(rejected.kind).assertEqual('failure');
      if (rejected.kind === 'failure') {
        expect(rejected.reason).assertEqual('scheme is not allowed: local-asset');
      }
    });

    it('attaches the observer to the built engine', 0, () => {
      const observer = new RecordingObserver();
      const localAsset = new LocalAssetBuilder().setObserver(observer).build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      localAsset.engine.resolveUrl('local-asset://demo/asset-1');
      expect(observer.stages.length > 0).assertTrue();
      expect(observer.stages.includes(STAGE_COMPLETE)).assertTrue();
    });

    /** design.md §3.1：不存在全局单例，两个实例的注册表互不可见。 */
    it('keeps separate instances isolated', 0, () => {
      const a = new LocalAssetBuilder().build();
      const b = new LocalAssetBuilder().build();
      a.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      expect(a.engine.resolveUrl('local-asset://demo/asset-1').kind).assertEqual('success');
      expect(b.engine.resolveUrl('local-asset://demo/asset-1').kind).assertEqual('failure');
    });

    /**
     * cleanup / cleanupHandles 打到的必须是门面持有的那两个 registry。
     *
     * 两半的验证手法**刻意不同**，因为两个 registry 的驱逐语义不同：
     *
     * - registry 半：`InMemoryResourceRegistry.lookup()` **不做惰性驱逐**（只报告状态），
     *   所以 now=100 时若 cleanup() 没跑，lookup 会返回 'expired' 而非 'missing'。
     *   断言 'missing' 本身就证明了条目被物理移除。
     *
     * - handle 半：`InMemoryHandleRegistry.resolve()` **自带惰性驱逐**，now=100 时
     *   无论 cleanupHandles() 跑没跑，该 URI 都解析失败 —— 因此"在 now=100 断言失败"
     *   完全不能证明 cleanupHandles() 做了事（把它改成空实现，那种断言照样绿）。
     *   改为**把时钟拨回 TTL 窗口内**（now=0）再断言 resolve 仍抛错：
     *   条目若只是被惰性拒绝、仍留在 map 里，回到窗口内就会重新解析成功；
     *   只有真的被 cleanupHandles() 物理删除，回拨后才依然失败。
     *   （已用变异验证：把 LocalAsset.cleanupHandles() 改成空实现 → 本用例变红。）
     */
    it('cleanup evicts expired registry entries and handles', 0, () => {
      let now = 0;
      const registry = new InMemoryResourceRegistry(() => now);
      const handleRegistry = new InMemoryHandleRegistry('h.local', '/p', () => now);
      const localAsset = new LocalAssetBuilder()
        .setRegistry(registry)
        .setHandleRegistry(handleRegistry)
        .build();
      localAsset.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
        ttlMillis: 10,
      }));
      const uri = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: 'c.png',
        mimeType: 'image/png',
        ttlMillis: 10,
      }));
      // 前置：TTL 窗口内两者都可用，确保后面的"失败"确实由驱逐造成而非一开始就没注册成功。
      expect(registry.lookup('asset-1').kind).assertEqual('hit');
      expect(localAsset.resolveHandle(uri).fileName).assertEqual('c.png');

      now = 100;
      localAsset.cleanup();
      localAsset.cleanupHandles();

      // registry：lookup 不惰性驱逐，'missing'（而非 'expired'）才证明 cleanup() 跑过。
      expect(registry.lookup('asset-1').kind).assertEqual('missing');

      // handle：时钟拨回窗口内。条目若还在 map 里就会重新解析成功，
      // 仍然失败才说明 cleanupHandles() 把它物理删了。
      now = 0;
      let stillGone = false;
      try {
        localAsset.resolveHandle(uri);
      } catch (error) {
        stillGone = (error as ResourceException).category === ResourceErrorCategory.RESOLUTION_ERROR;
      }
      expect(stillGone).assertTrue();
      // 同一时刻经引擎走也必须失败（证明删的是引擎实际使用的那个 handleRegistry 实例）。
      expect(localAsset.engine.resolveUrl(uri).kind).assertEqual('failure');
    });
  });
}
