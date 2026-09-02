import { describe, it, expect } from '@ohos/hypium';
import {
  ResourceErrorCategory,
  ResourceException,
  AssetRequest,
  AssetRequestParams,
  createAssetRequest,
  ResolveContext,
  ResolveContextParams,
  createResolveContext,
  ResourceType,
  ResourceScope,
  ResourceDescriptor,
  ResourceDescriptorParams,
  BytesSource,
  FilePathSource,
  ResourceSource,
  bytesSource,
  filePathSource,
  createResourceDescriptor,
  ResourceData,
  bytesData,
  ResourceHandle,
  ResourceHandleParams,
  ResourceHandleRecord,
  createResourceHandle,
  SchemeAdapter,
  DefaultLocalAssetSchemeAdapter,
  ResourceResolver,
  ResolverResult,
  ResolverHit,
  ResolverSkip,
  ResolverFailure,
  resolverHit,
  resolverSkip,
  resolverFailure,
  RegistryLookupResult,
  RegistryHit,
  RegistryMissing,
  RegistryExpired,
  ResourceRegistry,
  registryHit,
  registryMissing,
  registryExpired,
  InMemoryResourceRegistry,
  HandleRegistry,
  CACHE_BUST_PARAM,
  reconstructUriFromRequest,
  InMemoryHandleRegistry,
  RegistryResolver,
  HandleRegistryResolver,
  StaticMapResolver,
  Policy,
  DefaultPolicy,
  DefaultPolicyOptions,
  ResourceLoader,
  TypedResourceLoader,
  BytesResourceLoader,
  FileResourceLoader,
  CompositeResourceLoader,
  EngineObserver,
  EngineStageEvent,
  EngineFailureInfo,
  STAGE_ADAPTER_PARSE,
  STAGE_POLICY_PRE,
  STAGE_RESOLVE,
  STAGE_POLICY_POST,
  STAGE_LOAD,
  STAGE_COMPLETE,
  LocalAssetEngine,
  EngineResult,
  EngineSuccess,
  EngineFailure,
  engineSuccess,
  engineFailure,
  DefaultLocalAssetEngine,
  DefaultLocalAssetEngineOptions,
  CacheDecision,
  DEFAULT_MAX_AGE_SECONDS,
  decideCache,
  ALLOW_ANY_ORIGIN,
  corsHeaders,
  REQUEST_HEADER_PREFIX,
  requestHeader,
  LocalAsset,
  LocalAssetBuilder,
} from '../../Index';

/**
 * 冒烟测试：只验证 Index.ets 这个 barrel 把各模块的符号真的导出了。
 * 第一个真实消费者要很多个任务之后才出现，没有这个测试，漏写/拼错的 re-export
 * 只会被解析器看一眼，直到很久以后才炸。本文件是全仓唯一从 Index.ets 导入的地方，
 * 也就是这层导出面的唯一守卫 —— 新增导出时请同步把符号加进上面的 import 块。
 *
 * 按层拆成多个 it()：单个 it() 里第一条断言失败会掩盖其后所有断言，
 * 拆开后一次运行就能看出「哪几层坏了」，而不是只看到最先坏的那一层。
 *
 * 覆盖机制（已实测，勿误解）：真正兜住漏导/拼错的是**上面 import 块里的具名绑定**本身 ——
 * TS/ArkTS 在 import 语句处就报 `has no exported member`，与该名字后续是否被使用无关。
 * 实测：把 ResolverHit 只加进 import 块、全文不使用，再从 Index.ets 删掉该行 → 构建失败，
 * 错误正是指向本文件的 import 行。所以**新增导出时，加进 import 块就等于覆盖了**。
 *
 * 下面对 interface / type alias 附带的类型标注（`const x: Foo = ...`）不是覆盖的必要条件，
 * 只是防御性写法：让符号有真实使用点，避免将来引入 unused-import 规则时被误删。
 * （实测当前工具链对未使用的 import 既不报错也不告警，所以现在纯属未雨绸缪。）
 */

/** 在类型位置消费 ResourceResolver / ResolverResult，验证二者经 barrel 可用。 */
class BarrelProbeResolver implements ResourceResolver {
  resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
    return resolverSkip();
  }
}

/** 在类型位置消费 EngineObserver / EngineStageEvent，验证二者经 barrel 可用。 */
class BarrelProbeObserver implements EngineObserver {
  private readonly log: string[];

  constructor(log: string[]) {
    this.log = log;
  }

  onStage(event: EngineStageEvent): void {
    this.log.push(event.stage);
  }
}

function probeDescriptor(): ResourceDescriptor {
  return createResourceDescriptor({
    id: 'r1',
    namespace: 'image',
    type: ResourceType.DYNAMIC,
    source: bytesSource(new Uint8Array([1])),
    createdAtMillis: 0,
  });
}

export default function indexBarrelTest() {
  describe('indexBarrelTest', () => {
    it('re-exports the error layer', 0, () => {
      expect(ResourceErrorCategory.PARSE_ERROR).assertEqual('PARSE_ERROR');
      const error = new ResourceException(ResourceErrorCategory.LOAD_ERROR, 'boom', 'loader');
      expect(error.category).assertEqual('LOAD_ERROR');
      expect(error.stage).assertEqual('loader');
    });

    it('re-exports the model layer', 0, () => {
      const requestParams: AssetRequestParams = {
        scheme: 'local-asset',
        namespace: 'image',
        identifier: 'logo',
        path: null,
      };
      const request: AssetRequest = createAssetRequest(requestParams);
      expect(request.identifier).assertEqual('logo');

      const contextParams: ResolveContextParams = {};
      const context: ResolveContext = createResolveContext(contextParams);
      expect(context.engineScope).assertNull();

      expect(ResourceType.STATIC).assertEqual('STATIC');
      expect(ResourceScope.ENGINE).assertEqual('ENGINE');
      const bytes: BytesSource = bytesSource(new Uint8Array([1]));
      const file: FilePathSource = filePathSource('/tmp/a.png');
      const source: ResourceSource = file;
      expect(bytes.kind).assertEqual('bytes');
      expect(source.kind).assertEqual('filePath');

      const descriptorParams: ResourceDescriptorParams = {
        id: 'r1',
        namespace: 'image',
        type: ResourceType.STATIC,
        source: source,
        createdAtMillis: 0,
      };
      const descriptor: ResourceDescriptor = createResourceDescriptor(descriptorParams);
      expect(descriptor.mimeType).assertNull();

      const data: ResourceData = bytesData(new Uint8Array([1]), 'image/png');
      expect(data.mimeType).assertEqual('image/png');

      const handleParams: ResourceHandleParams = {
        source: bytesSource(new Uint8Array([1])),
        fileName: 'a.png',
        mimeType: 'image/png',
      };
      const handle: ResourceHandle = createResourceHandle(handleParams);
      expect(handle.metadata.size).assertEqual(0);
      expect(handle.ttlMillis).assertNull();

      // ResourceHandleRecord 没有工厂函数（只有 HandleRegistry 产出它），
      // 这里直接构造字面量占位，仅为让该类型有使用点。
      const record: ResourceHandleRecord = {
        resourceUri: 'local-asset://handle/h1',
        source: bytesSource(new Uint8Array([1])),
        fileName: 'a.png',
        mimeType: 'image/png',
        size: 1,
        metadata: new Map<string, string>(),
        ttlMillis: null,
      };
      expect(record.size).assertEqual(1);
    });

    it('re-exports the scheme adapter layer', 0, () => {
      const adapter: SchemeAdapter = new DefaultLocalAssetSchemeAdapter();
      expect(adapter.canHandle('local-asset://image/logo')).assertTrue();
      expect(adapter.parse('local-asset://image/logo').namespace).assertEqual('image');
    });

    it('re-exports the resolver layer', 0, () => {
      const hit: ResolverHit = resolverHit(probeDescriptor());
      const skip: ResolverSkip = resolverSkip();
      const failure: ResolverFailure = resolverFailure(
        ResourceErrorCategory.RESOLUTION_ERROR,
        'nope',
      );
      expect(hit.kind).assertEqual('hit');
      expect(skip.kind).assertEqual('skip');
      expect(failure.kind).assertEqual('failure');
      expect(failure.reason).assertEqual('nope');

      const probe: ResourceResolver = new BarrelProbeResolver();
      const result: ResolverResult = probe.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'image',
          identifier: 'logo',
          path: null,
        }),
        createResolveContext(),
      );
      expect(result.kind).assertEqual('skip');
    });

    it('re-exports the registry layer', 0, () => {
      const descriptor: ResourceDescriptor = probeDescriptor();
      const hit: RegistryHit = registryHit(descriptor);
      const missing: RegistryMissing = registryMissing();
      const expired: RegistryExpired = registryExpired();
      expect(hit.kind).assertEqual('hit');
      expect(missing.kind).assertEqual('missing');
      expect(expired.kind).assertEqual('expired');

      const registry: ResourceRegistry = new InMemoryResourceRegistry(() => 0);
      registry.register(descriptor);
      const found: RegistryLookupResult = registry.lookup('r1');
      expect(found.kind).assertEqual('hit');
      registry.cleanup(0);
      registry.remove('r1');
      expect(registry.lookup('r1').kind).assertEqual('missing');
    });

    it('re-exports the handle registry layer', 0, () => {
      expect(CACHE_BUST_PARAM).assertEqual('_la_cb');

      const handles: HandleRegistry = new InMemoryHandleRegistry('h.local', '/p', () => 0);
      const uri: string = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1, 2])),
        fileName: 'a.png',
        mimeType: 'image/png',
      }));
      const record: ResourceHandleRecord = handles.resolve(uri);
      expect(record.size).assertEqual(2);

      const rebuilt: string = reconstructUriFromRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: 'h.local',
        identifier: 'a.png',
        path: uri.substring('local-asset://h.local'.length),
      }));
      expect(rebuilt).assertEqual(uri);
      expect(handles.resolveFromRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: 'h.local',
        identifier: 'a.png',
        path: uri.substring('local-asset://h.local'.length),
      })) !== null).assertTrue();

      handles.cleanup(0);
      handles.remove(uri);
      expect(handles.resolveFromRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: 'h.local',
        identifier: 'a.png',
        path: uri.substring('local-asset://h.local'.length),
      }))).assertNull();
    });

    it('re-exports the built-in resolvers', 0, () => {
      const registry: ResourceRegistry = new InMemoryResourceRegistry(() => 0);
      registry.register(probeDescriptor());
      const byRegistry: ResourceResolver = new RegistryResolver(registry);
      expect(byRegistry.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'image',
          identifier: 'r1',
          path: '/r1',
        }),
        createResolveContext(),
      ).kind).assertEqual('hit');

      const handles: HandleRegistry = new InMemoryHandleRegistry('h.local', '/p', () => 0);
      const uri: string = handles.register(createResourceHandle({
        source: bytesSource(new Uint8Array([1])),
        fileName: 'a.png',
        mimeType: 'image/png',
      }));
      const byHandle: ResourceResolver = new HandleRegistryResolver(handles);
      expect(byHandle.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'h.local',
          identifier: 'a.png',
          path: uri.substring('local-asset://h.local'.length),
        }),
        createResolveContext(),
      ).kind).assertEqual('hit');

      const mappings = new Map<string, ResourceDescriptor>();
      mappings.set('image:/r1', probeDescriptor());
      const byMap: ResourceResolver = new StaticMapResolver(mappings);
      expect(byMap.resolve(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'image',
          identifier: 'r1',
          path: '/r1',
        }),
        createResolveContext(),
      ).kind).assertEqual('hit');
    });

    it('re-exports the policy layer', 0, () => {
      const options: DefaultPolicyOptions = { nowProvider: () => 0, allowedFileRoots: ['/data/app/cache'] };
      const policy: Policy = new DefaultPolicy(options);
      policy.preCheck(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'image',
          identifier: 'r1',
          path: '/r1',
        }),
        createResolveContext(),
      );
      policy.postCheck(
        createAssetRequest({
          scheme: 'local-asset',
          namespace: 'image',
          identifier: 'r1',
          path: '/r1',
        }),
        probeDescriptor(),
        createResolveContext(),
      );
      let rejected = false;
      try {
        policy.postCheck(
          createAssetRequest({
            scheme: 'local-asset',
            namespace: 'image',
            identifier: 'r1',
            path: '/r1',
          }),
          createResourceDescriptor({
            id: 'r2',
            namespace: 'image',
            type: ResourceType.STATIC,
            source: filePathSource('/data/app/other/a.png'),
            createdAtMillis: 0,
          }),
          createResolveContext(),
        );
      } catch (error) {
        rejected = (error as ResourceException).category === ResourceErrorCategory.SECURITY_ERROR;
      }
      expect(rejected).assertTrue();
    });

    it('re-exports the loader and observer layer', 0, () => {
      const bytes: TypedResourceLoader = new BytesResourceLoader();
      const files: TypedResourceLoader = new FileResourceLoader();
      const loader: ResourceLoader = new CompositeResourceLoader([bytes, files]);
      expect(loader.load(probeDescriptor()).bytes.length).assertEqual(1);
      expect(files.canLoad(filePathSource('/tmp/a.png'))).assertTrue();

      expect(STAGE_ADAPTER_PARSE).assertEqual('adapter_parse');
      expect(STAGE_POLICY_PRE).assertEqual('policy_pre');
      expect(STAGE_RESOLVE).assertEqual('resolve');
      expect(STAGE_POLICY_POST).assertEqual('policy_post');
      expect(STAGE_LOAD).assertEqual('load');
      expect(STAGE_COMPLETE).assertEqual('complete');

      const failure: EngineFailureInfo = {
        category: ResourceErrorCategory.LOAD_ERROR,
        reason: 'boom',
        stage: STAGE_LOAD,
      };
      const event: EngineStageEvent = {
        stage: STAGE_LOAD,
        request: null,
        resolverIndex: null,
        resolverResult: null,
        descriptor: null,
        failure: failure,
      };
      const observed: string[] = [];
      const observer: EngineObserver = new BarrelProbeObserver(observed);
      observer.onStage(event);
      expect(observed.length).assertEqual(1);
      expect(observed[0]).assertEqual('load');
    });

    it('re-exports the engine layer', 0, () => {
      const success: EngineSuccess = engineSuccess(probeDescriptor(), bytesData(new Uint8Array([1]), null));
      const failed: EngineFailure = engineFailure(ResourceErrorCategory.PARSE_ERROR, 'boom', STAGE_ADAPTER_PARSE);
      expect(success.kind).assertEqual('success');
      expect(failed.kind).assertEqual('failure');

      // 此处曾有全仓唯一一处不走 barrel 的 import（`internal/ResolverChain`），
      // 因为 DefaultLocalAssetEngineOptions.resolverChain 需要一个真实实例，而 ResolverChain
      // 与 Kotlin 一样刻意留在 internal/、不经 Index.ets 导出。LocalAssetBuilder 落地后，
      // 链的组装收口进了公开入口，这里改为经 builder 拿一个可用引擎，非 barrel import 已删除。
      //
      // 遗留结论（供后续计划参考）：`DefaultLocalAssetEngineOptions` **无法只靠 barrel 构造** ——
      // 它的 resolverChain 字段引用的是未导出的内部类型。想直接 new DefaultLocalAssetEngine 的
      // 调用方必须走源路径 import，或者改用 LocalAssetBuilder。这两个符号的导出覆盖由上面
      // import 块里的具名绑定保证（见本文件顶部实测说明），不依赖此处的值使用点。
      const built: LocalAsset = new LocalAssetBuilder().build();
      built.register(probeDescriptor());
      const engine: LocalAssetEngine = built.engine;
      const hit: EngineResult = engine.resolveUrl('local-asset://image/r1');
      expect(hit.kind).assertEqual('success');
      const result: EngineResult = engine.resolveUrl('local-asset://image/missing');
      expect(result.kind).assertEqual('failure');
      const byRequest: EngineResult = engine.resolveRequest(createAssetRequest({
        scheme: 'local-asset',
        namespace: 'image',
        identifier: 'missing',
        path: '/missing',
      }));
      expect(byRequest.kind).assertEqual('failure');
    });

    it('re-exports the cache policy layer', 0, () => {
      expect(DEFAULT_MAX_AGE_SECONDS).assertEqual(86400);
      const decision: CacheDecision = decideCache(createResourceDescriptor({
        id: 'r1',
        namespace: 'image',
        type: ResourceType.STATIC,
        source: bytesSource(new Uint8Array([1, 2, 3])),
        createdAtMillis: 0,
      }));
      expect(decision.cacheControl).assertEqual('public, max-age=86400');
      expect(decision.etag).assertEqual('"r1-3"');
    });

    it('re-exports the cors policy layer', 0, () => {
      expect(ALLOW_ANY_ORIGIN).assertEqual('*');
      expect(REQUEST_HEADER_PREFIX).assertEqual('header.');
      // 默认空 allow-list → 不发任何 CORS 头。
      expect(corsHeaders(new Set<string>(), 'https://app.example.com').size).assertEqual(0);
      // 通配成员 → 通配头。
      const wild: Map<string, string> = corsHeaders(new Set<string>(['*']), null);
      expect(wild.get('Access-Control-Allow-Origin')).assertEqual('*');
      // requestHeader 大小写不敏感读取。
      const context: ResolveContext = createResolveContext({
        requestMetadata: new Map<string, string>([['header.origin', 'https://app.example.com']]),
      });
      expect(requestHeader(context, 'Origin')).assertEqual('https://app.example.com');
      expect(requestHeader(context, 'origin')).assertEqual('https://app.example.com');
    });

    it('re-exports the builder facade', 0, () => {
      const builder: LocalAssetBuilder = new LocalAssetBuilder();
      const localAsset: LocalAsset = builder.build();
      const uri: string = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([1, 2])),
        fileName: 'a.png',
        mimeType: 'image/png',
      }));
      expect(localAsset.resolveHandle(uri).size).assertEqual(2);
      localAsset.removeHandle(uri);
      localAsset.cleanup();
      localAsset.cleanupHandles();
    });
  });
}
