import { describe, it, expect } from '@ohos/hypium';
import { DefaultLocalAssetEngine } from '../../main/ets/engine/DefaultLocalAssetEngine';
import { DefaultLocalAssetSchemeAdapter } from '../../main/ets/engine/DefaultLocalAssetSchemeAdapter';
import { ResolverChain } from '../../main/ets/internal/ResolverChain';
import { DefaultPolicy } from '../../main/ets/policy/DefaultPolicy';
import { CompositeResourceLoader } from '../../main/ets/loader/CompositeResourceLoader';
import { BytesResourceLoader } from '../../main/ets/loader/BytesResourceLoader';
import { FileResourceLoader } from '../../main/ets/loader/FileResourceLoader';
import { InMemoryResourceRegistry } from '../../main/ets/registry/InMemoryResourceRegistry';
import { InMemoryHandleRegistry } from '../../main/ets/registry/InMemoryHandleRegistry';
import { RegistryResolver } from '../../main/ets/resolver/RegistryResolver';
import { HandleRegistryResolver } from '../../main/ets/resolver/HandleRegistryResolver';
import { StaticMapResolver } from '../../main/ets/resolver/StaticMapResolver';
import {
  ResourceResolver,
  ResolverResult,
  resolverSkip,
  resolverHit,
  resolverFailure,
} from '../../main/ets/api/ResourceResolver';
import { Policy } from '../../main/ets/api/Policy';
import { ResourceLoader } from '../../main/ets/api/ResourceLoader';
import { AssetRequest, createAssetRequest } from '../../main/ets/model/AssetRequest';
import { ResolveContext, createResolveContext } from '../../main/ets/model/ResolveContext';
import { ResourceData } from '../../main/ets/model/ResourceData';
import {
  ResourceType,
  ResourceScope,
  ResourceDescriptor,
  bytesSource,
  filePathSource,
  createResourceDescriptor,
} from '../../main/ets/model/ResourceDescriptor';
import { createResourceHandle } from '../../main/ets/model/ResourceHandle';
import { ResourceErrorCategory } from '../../main/ets/error/ResourceErrorCategory';
import { ResourceException } from '../../main/ets/error/ResourceException';
import { EngineObserver, EngineStageEvent, EngineFailureInfo } from '../../main/ets/api/EngineObserver';

class ThrowingResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    throw new Error('resolver blew up');
  }
}

/** 抛一个自带 category + stage 的 ResourceException，用于验证引擎**不**用当前阶段覆盖它。 */
class TypedThrowingResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    throw new ResourceException(ResourceErrorCategory.LOAD_ERROR, 'typed boom', 'custom_stage');
  }
}

/** stage 为 null 的 ResourceException：category 保留，stage 由当前阶段补齐。 */
class StagelessThrowingResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    throw new ResourceException(ResourceErrorCategory.SECURITY_ERROR, 'stageless boom');
  }
}

class SkippingResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    return resolverSkip();
  }
}

/**
 * 显式返回 ResolverFailure 的 resolver：验证引擎**转发 resolver 自己的 category**，
 * 而不是把 resolve 阶段的所有失败都硬编码成 RESOLUTION_ERROR。
 */
class FailingResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    return resolverFailure(ResourceErrorCategory.SECURITY_ERROR, 'blocked by resolver');
  }
}

class FixedHitResolver implements ResourceResolver {
  private readonly descriptor: ResourceDescriptor;

  constructor(descriptor: ResourceDescriptor) {
    this.descriptor = descriptor;
  }

  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    return resolverHit(this.descriptor);
  }
}

/** 非 ResourceException 的 policy 崩溃 = policy 内部 bug，必须归到当前阶段而非被降级。 */
class CrashingPrePolicy implements Policy {
  preCheck(request: AssetRequest, context: ResolveContext): void {
    throw new Error('policy blew up');
  }

  postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext): void {
  }
}

class CrashingLoader implements ResourceLoader {
  load(descriptor: ResourceDescriptor): ResourceData {
    throw new Error('loader blew up');
  }
}

class CollectingObserver implements EngineObserver {
  readonly stages: string[] = [];
  readonly events: EngineStageEvent[] = [];

  onStage(event: EngineStageEvent): void {
    this.stages.push(event.stage);
    this.events.push(event);
  }
}

function bytesDescriptor(
  id: string,
  namespace: string,
  scope: ResourceScope | null = null,
  ttlMillis: number | null = null,
): ResourceDescriptor {
  return createResourceDescriptor({
    id: id,
    namespace: namespace,
    type: ResourceType.DYNAMIC,
    source: bytesSource(new Uint8Array([1])),
    createdAtMillis: 0,
    ttlMillis: ttlMillis,
    scope: scope,
  });
}

function engineWith(
  resolvers: ResourceResolver[],
  observer: EngineObserver | null = null,
): DefaultLocalAssetEngine {
  return new DefaultLocalAssetEngine({
    adapters: [new DefaultLocalAssetSchemeAdapter()],
    resolverChain: new ResolverChain(resolvers),
    policy: new DefaultPolicy({ nowProvider: () => 0 }),
    loader: new CompositeResourceLoader([new BytesResourceLoader()]),
    observer: observer,
  });
}

export default function defaultLocalAssetEngineTest() {
  describe('defaultLocalAssetEngineTest', () => {
    it('resolves a registered resource end to end', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1, 2, 3])),
        mimeType: 'image/png',
        createdAtMillis: 0,
      }));
      const engine = engineWith([new RegistryResolver(registry)]);
      const result = engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('success');
      if (result.kind === 'success') {
        expect(result.data.bytes.length).assertEqual(3);
        expect(result.descriptor.id).assertEqual('asset-1');
        expect(result.data.mimeType).assertEqual('image/png');
      }
    });

    // design.md §5.4 的 Handle 路径 + FilePath 来源：能力令牌不能越出允许根。
    // file-backed handle 的路径必须落在 addAllowedFileRoot 声明的根内，否则 postCheck 拒绝。
    it('maps a file-backed handle outside the allowed root to SECURITY_ERROR at policy_post', 0, () => {
      const handleRegistry = new InMemoryHandleRegistry();
      const engine = new DefaultLocalAssetEngine({
        adapters: [new DefaultLocalAssetSchemeAdapter()],
        resolverChain: new ResolverChain([new HandleRegistryResolver(handleRegistry)]),
        policy: new DefaultPolicy({ allowedFileRoots: ['/data/app/allowed'], nowProvider: () => 0 }),
        loader: new CompositeResourceLoader([new BytesResourceLoader(), new FileResourceLoader()]),
        observer: null,
      });
      const uri = handleRegistry.register(createResourceHandle({
        source: filePathSource('/data/app/OUTSIDE/big.pdf'),
        fileName: 'big.pdf',
        mimeType: 'application/pdf',
      }));
      const result = engine.resolveUrl(uri);
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(result.stage).assertEqual('policy_post');
      }
    });

    it('lets a file-backed handle inside the allowed root pass postCheck', 0, () => {
      const handleRegistry = new InMemoryHandleRegistry();
      const engine = new DefaultLocalAssetEngine({
        adapters: [new DefaultLocalAssetSchemeAdapter()],
        resolverChain: new ResolverChain([new HandleRegistryResolver(handleRegistry)]),
        policy: new DefaultPolicy({ allowedFileRoots: ['/data/app/allowed'], nowProvider: () => 0 }),
        loader: new CompositeResourceLoader([new BytesResourceLoader(), new FileResourceLoader()]),
        observer: null,
      });
      const uri = handleRegistry.register(createResourceHandle({
        source: filePathSource('/data/app/allowed/big.pdf'),
        fileName: 'big.pdf',
        mimeType: 'application/pdf',
      }));
      const result = engine.resolveUrl(uri);
      // 文件不存在 → LOAD_ERROR，但关键是不被 SECURITY_ERROR 拒——证明文件根门放行了根内路径。
      // 与上一条「根外被拒」对照，即能力令牌无法越出允许根的安全契约。
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category !== ResourceErrorCategory.SECURITY_ERROR).assertTrue();
      }
    });

    it('maps an unparseable url to PARSE_ERROR at adapter_parse', 0, () => {
      const engine = engineWith([new SkippingResolver()]);
      const result = engine.resolveUrl('local-asset:///invalid');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
        expect(result.stage).assertEqual('adapter_parse');
        // reason 来自 adapter 抛出的 ResourceException 原文，而不是引擎的 'invalid url: ' 兜底前缀 ——
        // 这条断言把「保留 ResourceException 自身信息」与「走兜底分支」区分开。
        expect(result.reason).assertEqual('missing namespace');
      }
    });

    it('maps a non-local-asset url to PARSE_ERROR', 0, () => {
      const engine = engineWith([new SkippingResolver()]);
      const result = engine.resolveUrl('https://example.com/a.png');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
        expect(result.stage).assertEqual('adapter_parse');
        // AdapterRegistry.select 的跨平台契约消息；与上一条（adapter.parse 抛出）区分来源。
        expect(result.reason).assertEqual('no adapter can handle url');
      }
    });

    it('maps an empty chain to RESOLUTION_ERROR at resolve', 0, () => {
      const engine = engineWith([new SkippingResolver()]);
      const result = engine.resolveUrl('local-asset://demo/nothing');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
        expect(result.reason).assertEqual('resource not found');
        expect(result.stage).assertEqual('resolve');
      }
    });

    it('forwards a resolver-supplied failure category instead of hardcoding RESOLUTION_ERROR', 0, () => {
      const engine = engineWith([new FailingResolver()]);
      const result = engine.resolveUrl('local-asset://demo/blocked');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        // ⚠️ 判别力在这条 category 断言上：resolver 显式返回的 Failure 与「整条链 Skip」
        // 的 stage 完全相同（都是 resolve），若引擎把 Failure 分支塌进 Skip 分支，
        // 只断言 stage 的版本会保持全绿。category 必须是 resolver 给的 SECURITY_ERROR，
        // 而**不是** Skip 分支硬编码的 RESOLUTION_ERROR —— 这正是该分支存在的理由。
        expect(result.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(result.stage).assertEqual('resolve');
        // reason 同样必须原样转发，而非被替换成 'resource not found'。
        expect(result.reason).assertEqual('blocked by resolver');
      }
    });

    it('maps a resolver crash to RESOLUTION_ERROR rather than swallowing it as skip', 0, () => {
      const engine = engineWith([new ThrowingResolver()]);
      const result = engine.resolveUrl('local-asset://demo/boom');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
        expect(result.stage).assertEqual('resolve');
        // ⚠️ 这条 reason 断言是本用例的**唯一**判别力所在，不要删。
        // 「resolver 抛异常」与「整条链 Skip」的 category + stage 完全相同
        // （都是 RESOLUTION_ERROR @ resolve），若引擎把异常吞成 Skip 这种 fail-open 变异，
        // 只断言 category/stage 的版本会保持全绿；只有 reason 前缀能把两者分开。
        expect(result.reason).assertEqual('resolver chain failed: resolver blew up');
      }
    });

    it('preserves a ResourceException category and stage thrown by a resolver', 0, () => {
      const engine = engineWith([new TypedThrowingResolver()]);
      const result = engine.resolveUrl('local-asset://demo/boom');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        // 既不是当前阶段的兜底 category（RESOLUTION_ERROR），也不是当前 stage（resolve）。
        expect(result.category).assertEqual(ResourceErrorCategory.LOAD_ERROR);
        expect(result.stage).assertEqual('custom_stage');
        expect(result.reason).assertEqual('typed boom');
      }
    });

    it('substitutes the current stage when a ResourceException carries no stage', 0, () => {
      const engine = engineWith([new StagelessThrowingResolver()]);
      const result = engine.resolveUrl('local-asset://demo/boom');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        // category 仍归异常自己（SECURITY_ERROR，非当前阶段兜底的 RESOLUTION_ERROR）；
        // 只有 stage 因为是 null 才由当前阶段补齐。
        expect(result.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(result.stage).assertEqual('resolve');
        expect(result.reason).assertEqual('stageless boom');
      }
    });

    it('maps a scope mismatch to SECURITY_ERROR at policy_post', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'engine-a',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
        scope: ResourceScope.ENGINE,
      }));
      const engine = engineWith([new RegistryResolver(registry)]);
      const result = engine.resolveUrl('local-asset://demo/asset-1', createResolveContext({ engineScope: 'engine-b' }));
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(result.stage).assertEqual('policy_post');
        expect(result.reason).assertEqual('engine scope mismatch');
      }
    });

    it('maps an expired descriptor to RESOLUTION_ERROR at policy_post, not SECURITY_ERROR', 0, () => {
      // design.md §3.5 与 DefaultPolicy 类注释：过期虽然在 policy 里检出，但归
      // RESOLUTION_ERROR。引擎绝不能因为「这是 policy 阶段」就把它改写成 SECURITY_ERROR。
      // 走 StaticMapResolver 而非 RegistryResolver：后者在 lookup 就把过期拦成
      // resolve 阶段的 Failure，根本到不了 postCheck。
      const mappings = new Map<string, ResourceDescriptor>();
      mappings.set('demo:/asset-1', bytesDescriptor('asset-1', 'demo', null, 10));
      const engine = new DefaultLocalAssetEngine({
        adapters: [new DefaultLocalAssetSchemeAdapter()],
        resolverChain: new ResolverChain([new StaticMapResolver(mappings)]),
        policy: new DefaultPolicy({ nowProvider: () => 1000 }),
        loader: new CompositeResourceLoader([new BytesResourceLoader()]),
      });
      const result = engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
        expect(result.stage).assertEqual('policy_post');
        expect(result.reason).assertEqual('resource expired');
      }
    });

    it('maps path traversal to SECURITY_ERROR at policy_pre', 0, () => {
      const engine = engineWith([new SkippingResolver()]);
      const result = engine.resolveUrl('local-asset://demo/pkg/../secret');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(result.stage).assertEqual('policy_pre');
        expect(result.reason).assertEqual('path traversal is not allowed');
      }
    });

    it('maps a preCheck crash to SECURITY_ERROR at policy_pre', 0, () => {
      const engine = new DefaultLocalAssetEngine({
        adapters: [new DefaultLocalAssetSchemeAdapter()],
        resolverChain: new ResolverChain([new SkippingResolver()]),
        policy: new CrashingPrePolicy(),
        loader: new CompositeResourceLoader([new BytesResourceLoader()]),
      });
      const result = engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(result.stage).assertEqual('policy_pre');
        expect(result.reason).assertEqual('preCheck failed: policy blew up');
      }
    });

    it('maps a loader crash to LOAD_ERROR at load', 0, () => {
      const engine = new DefaultLocalAssetEngine({
        adapters: [new DefaultLocalAssetSchemeAdapter()],
        resolverChain: new ResolverChain([new FixedHitResolver(bytesDescriptor('asset-1', 'demo'))]),
        policy: new DefaultPolicy({ nowProvider: () => 0 }),
        loader: new CrashingLoader(),
      });
      const result = engine.resolveUrl('local-asset://demo/asset-1');
      expect(result.kind).assertEqual('failure');
      if (result.kind === 'failure') {
        expect(result.category).assertEqual(ResourceErrorCategory.LOAD_ERROR);
        expect(result.stage).assertEqual('load');
        expect(result.reason).assertEqual('unexpected load failure: loader blew up');
      }
    });

    it('resolveRequest runs the pipeline without the adapter stage', 0, () => {
      const observer = new CollectingObserver();
      const engine = engineWith([new FixedHitResolver(bytesDescriptor('asset-1', 'demo'))], observer);
      const result = engine.resolveRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: 'demo',
        identifier: 'asset-1',
        path: '/asset-1',
      }));
      expect(result.kind).assertEqual('success');
      // 从 policy_pre 起步，没有 adapter_parse —— 证明 resolveUrl 的解析段没被硬编码进
      // resolveRequest（否则一个已构造好的 request 会被再解析一次）。
      expect(observer.stages[0]).assertEqual('policy_pre');
      expect(observer.stages.length).assertEqual(5);
    });

    it('emits stages in pipeline order on success', 0, () => {
      const registry = new InMemoryResourceRegistry(() => 0);
      registry.register(createResourceDescriptor({
        id: 'asset-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      const observer = new CollectingObserver();
      const engine = engineWith([new RegistryResolver(registry)], observer);
      engine.resolveUrl('local-asset://demo/asset-1');
      expect(observer.stages[0]).assertEqual('adapter_parse');
      expect(observer.stages[1]).assertEqual('policy_pre');
      expect(observer.stages[2]).assertEqual('resolve');
      expect(observer.stages[3]).assertEqual('policy_post');
      expect(observer.stages[4]).assertEqual('load');
      expect(observer.stages[5]).assertEqual('complete');
      expect(observer.stages.length).assertEqual(6);
      // resolve 那条由 ResolverChain 发出，带 resolverIndex；引擎不再补发一条。
      expect(observer.events[2].resolverIndex).assertEqual(0);
      expect(observer.events[5].failure).assertNull();
    });

    it('emits the terminating failure to the observer at the failing stage', 0, () => {
      const observer = new CollectingObserver();
      const engine = engineWith([new SkippingResolver()], observer);
      const result = engine.resolveUrl('local-asset://demo/pkg/../secret');
      expect(result.kind).assertEqual('failure');
      // 终止事件是最后一条，且必须带非空 failure —— 观测面与返回值同源。
      const last: EngineStageEvent = observer.events[observer.events.length - 1];
      expect(last.stage).assertEqual('policy_pre');
      const info: EngineFailureInfo | null = last.failure;
      expect(info !== null).assertTrue();
      if (info !== null) {
        expect(info.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(info.stage).assertEqual('policy_pre');
        expect(info.reason).assertEqual('path traversal is not allowed');
      }
      // 请求既然在 policy_pre 就被拒，链上的 SkippingResolver 一次都不该跑
      // （否则说明 preCheck 的拒绝没有真正短路流水线）。
      expect(observer.stages.length).assertEqual(2);
      expect(observer.stages[0]).assertEqual('adapter_parse');
    });
  });
}
