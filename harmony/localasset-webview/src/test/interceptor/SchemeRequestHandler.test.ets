import { describe, it, expect } from '@ohos/hypium';
import {
  BridgeResponse,
  buildSuccessResponse,
  buildFailureResponse,
  passThroughResponse,
  SchemeRequestHandler,
  SchemeRequestHandlerOptions,
  HarmonyResolveContextFactory,
} from '../../../Index';
import {
  LocalAsset,
  LocalAssetBuilder,
  createResourceDescriptor,
  createResourceHandle,
  createResolveContext,
  bytesSource,
  ResourceType,
  ResourceScope,
  ResourceErrorCategory,
  EngineResult,
  EngineFailureInfo,
  STAGE_ADAPTER_PARSE,
  STAGE_POLICY_POST,
  REQUEST_HEADER_PREFIX,
  requestHeader,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 本文件同时充当本模块的 **barrel 守卫**（对齐 core 的 IndexBarrel.test.ets）：
 * 上方从 `../../../Index` 具名导入的每个符号，只要 Index.ets 漏导或拼错，
 * 编译期就会在这条 import 语句上报 `has no exported member`，与它后续是否被使用无关。
 * 新增导出时请同步加进这个 import 块。
 */

/** 注册一条 4 字节 STATIC 资源的引擎（供多条用例复用）。 */
function localAssetWithRegisteredAsset(): LocalAsset {
  const localAsset = new LocalAssetBuilder().build();
  localAsset.register(createResourceDescriptor({
    id: 'asset-1',
    namespace: 'demo',
    type: ResourceType.STATIC,
    source: bytesSource(new Uint8Array([1, 2, 3, 4])),
    mimeType: 'image/png',
    createdAtMillis: 0,
  }));
  return localAsset;
}

function handlerForRegisteredAsset(): SchemeRequestHandler {
  return new SchemeRequestHandler({ engine: localAssetWithRegisteredAsset().engine });
}

/** 注册一条自定义 mimeType 的 STATIC 资源，用于编码判定用例。 */
function registerTyped(localAsset: LocalAsset, id: string, mimeType: string): void {
  localAsset.register(createResourceDescriptor({
    id: id,
    namespace: 'demo',
    type: ResourceType.STATIC,
    source: bytesSource(new Uint8Array([1])),
    mimeType: mimeType,
    createdAtMillis: 0,
  }));
}

/** 逐字节比对 body —— 只断言 length 无法区分"取到了正确的字节"与"取到了等长的别的字节"。 */
function bodyEquals(body: Uint8Array, expected: number[]): boolean {
  if (body.length !== expected.length) {
    return false;
  }
  for (let i = 0; i < expected.length; i++) {
    if (body[i] !== expected[i]) {
      return false;
    }
  }
  return true;
}

export default function schemeRequestHandlerTest() {
  describe('schemeRequestHandlerTest', () => {
    it('returns a 200 response with body for a resolved resource', 0, () => {
      const response = handlerForRegisteredAsset()
        .handle('local-asset://demo/asset-1', createResolveContext());
      expect(response.intercepted).assertTrue();
      expect(response.status).assertEqual(200);
      expect(response.statusText).assertEqual('OK');
      expect(response.mimeType).assertEqual('image/png');
      // 逐字节断言：注册的是 [1,2,3,4]，只查 length===4 的话，任何 4 字节都能满足。
      expect(bodyEquals(response.body, [1, 2, 3, 4])).assertTrue();
      expect(response.failure).assertNull();
    });

    it('omits CORS headers by default and emits exactly three headers', 0, () => {
      const response = handlerForRegisteredAsset()
        .handle('local-asset://demo/asset-1', createResolveContext());
      expect(response.headers.get('Content-Type')).assertEqual('image/png');
      // 默认 allowedOrigins 为空 → 不发任何 CORS 头（capability-URL 泄漏防护，见 core corsHeaders）。
      expect(response.headers.get('Access-Control-Allow-Origin')).assertUndefined();
      expect(response.headers.get('Access-Control-Allow-Methods')).assertUndefined();
      // STATIC -> 可缓存
      expect(response.headers.get('Cache-Control')).assertEqual('public, max-age=86400');
      // ETag 形如 "<id>-<字节数>"：既钉住 id 也钉住内容长度（core decideCache 的契约）。
      expect(response.headers.get('ETag')).assertEqual('"asset-1-4"');
      // 头集合必须**恰好**是这三条：多发一条 Kotlin/iOS 没有的头同样是跨端偏离。
      expect(response.headers.size).assertEqual(3);
    });

    it('echoes the request origin when it is in the allow-list', 0, () => {
      const handler = new SchemeRequestHandler({
        engine: localAssetWithRegisteredAsset().engine,
        allowedOrigins: new Set<string>(['https://app.example.com']),
      });
      const context = createResolveContext();
      context.requestMetadata.set('header.origin', 'https://app.example.com');
      const response = handler.handle('local-asset://demo/asset-1', context);
      expect(response.headers.get('Access-Control-Allow-Origin'))
        .assertEqual('https://app.example.com');
      expect(response.headers.get('Access-Control-Allow-Methods')).assertEqual('GET, OPTIONS');
      expect(response.headers.get('Vary')).assertEqual('Origin');
    });

    it('emits no CORS headers when the origin is outside the allow-list', 0, () => {
      const handler = new SchemeRequestHandler({
        engine: localAssetWithRegisteredAsset().engine,
        allowedOrigins: new Set<string>(['https://app.example.com']),
      });
      const context = createResolveContext();
      context.requestMetadata.set('header.origin', 'https://evil.example.com');
      const response = handler.handle('local-asset://demo/asset-1', context);
      expect(response.headers.get('Access-Control-Allow-Origin')).assertUndefined();
      expect(response.headers.get('Vary')).assertUndefined();
    });

    it('restores blanket CORS when ALLOW_ANY_ORIGIN is a member', 0, () => {
      const handler = new SchemeRequestHandler({
        engine: localAssetWithRegisteredAsset().engine,
        allowedOrigins: new Set<string>(['*']),
      });
      const response = handler.handle('local-asset://demo/asset-1', createResolveContext());
      expect(response.headers.get('Access-Control-Allow-Origin')).assertEqual('*');
      expect(response.headers.get('Access-Control-Allow-Methods')).assertEqual('GET, OPTIONS');
      // 通配不随请求 Origin 变化，故无 Vary。
      expect(response.headers.get('Vary')).assertUndefined();
    });

    it('honours a custom max age', 0, () => {
      const options: SchemeRequestHandlerOptions = {
        engine: localAssetWithRegisteredAsset().engine,
        maxAgeSeconds: 60,
      };
      const response = new SchemeRequestHandler(options)
        .handle('local-asset://demo/asset-1', createResolveContext());
      expect(response.headers.get('Cache-Control')).assertEqual('public, max-age=60');
    });

    it('marks dynamic resources no-store', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      localAsset.register(createResourceDescriptor({
        id: 'dyn-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([9])),
        mimeType: 'image/png',
        createdAtMillis: 0,
      }));
      const handler = new SchemeRequestHandler({ engine: localAsset.engine, maxAgeSeconds: 60 });
      const response = handler.handle('local-asset://demo/dyn-1', createResolveContext());
      // maxAgeSeconds 显式给了 60，若实现漏判 type 而一律走 max-age 分支，这里会是
      // 'public, max-age=60' 而非 'no-store' —— 用非默认值排除"恰好等于默认串"的巧合。
      expect(response.headers.get('Cache-Control')).assertEqual('no-store');
    });

    it('falls back to application/octet-stream when mime is unknown', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      localAsset.register(createResourceDescriptor({
        id: 'blob-1',
        namespace: 'demo',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
      }));
      const handler = new SchemeRequestHandler({ engine: localAsset.engine });
      const response = handler.handle('local-asset://demo/blob-1', createResolveContext());
      expect(response.mimeType).assertEqual('application/octet-stream');
      // 兜底值同样要出现在 Content-Type 头里，而不只是 mimeType 字段。
      expect(response.headers.get('Content-Type')).assertEqual('application/octet-stream');
      expect(response.encoding).assertNull();
    });

    /**
     * 编码判定逐条对齐 Kotlin DefaultWebViewResponseBuilder 的谓词表：
     * startsWith("text/") || contains("/json") || contains("+json")
     * || contains("/javascript") || contains("/xml") || contains("+xml")
     * 只测 text/css 与 image/png 无法区分"实现了完整谓词表"与"只写了 startsWith('text/')"，
     * 因此每个分支各给一条真实 mime。
     */
    it('sets utf-8 encoding for every textual mime branch', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      registerTyped(localAsset, 'style.css', 'text/css');
      registerTyped(localAsset, 'data.json', 'application/json');
      registerTyped(localAsset, 'feed.jsonld', 'application/ld+json');
      registerTyped(localAsset, 'app.js', 'application/javascript');
      registerTyped(localAsset, 'doc.xml', 'application/xml');
      registerTyped(localAsset, 'icon.svg', 'image/svg+xml');
      const handler = new SchemeRequestHandler({ engine: localAsset.engine });
      const context = createResolveContext();
      expect(handler.handle('local-asset://demo/style.css', context).encoding).assertEqual('utf-8');
      expect(handler.handle('local-asset://demo/data.json', context).encoding).assertEqual('utf-8');
      expect(handler.handle('local-asset://demo/feed.jsonld', context).encoding).assertEqual('utf-8');
      expect(handler.handle('local-asset://demo/app.js', context).encoding).assertEqual('utf-8');
      expect(handler.handle('local-asset://demo/doc.xml', context).encoding).assertEqual('utf-8');
      expect(handler.handle('local-asset://demo/icon.svg', context).encoding).assertEqual('utf-8');
    });

    it('leaves encoding null for binary mime types', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      registerTyped(localAsset, 'logo.png', 'image/png');
      registerTyped(localAsset, 'clip.mp4', 'video/mp4');
      registerTyped(localAsset, 'doc.pdf', 'application/pdf');
      const handler = new SchemeRequestHandler({ engine: localAsset.engine });
      const context = createResolveContext();
      expect(handler.handle('local-asset://demo/logo.png', context).encoding).assertNull();
      expect(handler.handle('local-asset://demo/clip.mp4', context).encoding).assertNull();
      expect(handler.handle('local-asset://demo/doc.pdf', context).encoding).assertNull();
    });

    /**
     * `docs/compatibility.md` §13.7 混合策略的第一条分支：请求根本没进我们的 scheme。
     * 只断言 intercepted===false 是不够的 —— "所有失败都交还内核"同样能满足它，
     * 那正是我们**不要**的 Android 式行为。故一并钉住失败三要素与空响应体，
     * 并由下方两条 404 用例从反面把该退化实现排除掉。
     */
    it('passes non-local-asset urls back to the kernel', 0, () => {
      const handler = handlerForRegisteredAsset();
      const response = handler.handle('https://example.com/logo.png', createResolveContext());
      expect(response.intercepted).assertFalse();
      expect(response.status).assertEqual(0);
      expect(response.body.length).assertEqual(0);
      expect(response.headers.size).assertEqual(0);
      expect(response.failure !== null).assertTrue();
      if (response.failure !== null) {
        expect(response.failure.category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
        expect(response.failure.stage).assertEqual(STAGE_ADAPTER_PARSE);
      }
    });

    /**
     * 判据是**引擎阶段**（adapter_parse），不是 URL 前缀。'local-asset://demo' 缺 path，
     * 同样在 adapter_parse 失败 → 也该交还内核。若实现改写成
     * `url.startsWith('local-asset://') ? 404 : passthrough`，上一条仍绿而这条会红。
     */
    it('passes a malformed local-asset url back to the kernel as well', 0, () => {
      const handler = handlerForRegisteredAsset();
      const response = handler.handle('local-asset://demo', createResolveContext());
      expect(response.intercepted).assertFalse();
      // 与上一条用例同样先钉住 failure 非空：少了这一条，一个把 failure 置 null 的实现
      // 会整体跳过 if 块里的两条断言，只靠 intercepted === false 就绿了。
      expect(response.failure !== null).assertTrue();
      if (response.failure !== null) {
        expect(response.failure.stage).assertEqual(STAGE_ADAPTER_PARSE);
        expect(response.failure.category).assertEqual(ResourceErrorCategory.PARSE_ERROR);
      }
    });

    it('returns 404 for a resource that does not resolve', 0, () => {
      const handler = handlerForRegisteredAsset();
      const response = handler.handle('local-asset://demo/missing', createResolveContext());
      expect(response.intercepted).assertTrue();
      expect(response.status).assertEqual(404);
      expect(response.statusText).assertEqual('Not Found');
      expect(response.body.length).assertEqual(0);
      expect(response.encoding).assertNull();
      expect(response.failure !== null).assertTrue();
      if (response.failure !== null) {
        expect(response.failure.category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
      }
    });

    /**
     * 第二条 404 用例走的是**另一条**代码路径（policy_post 抛错，而非 resolver skip）。
     * 只断言 category 不够：解析失败与安全拒绝在别的实现里可能被折叠成同一类，
     * 故一并断言 stage —— 两条用例的 category 与 stage 组合互不相同。
     */
    it('returns 404 for a security rejection', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      localAsset.register(createResourceDescriptor({
        id: 'scoped',
        namespace: 'engine-a',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        createdAtMillis: 0,
        scope: ResourceScope.ENGINE,
      }));
      const handler = new SchemeRequestHandler({ engine: localAsset.engine });
      const response = handler.handle(
        'local-asset://demo/scoped',
        createResolveContext({ engineScope: 'engine-b' }),
      );
      expect(response.intercepted).assertTrue();
      expect(response.status).assertEqual(404);
      expect(response.body.length).assertEqual(0);
      expect(response.failure !== null).assertTrue();
      if (response.failure !== null) {
        expect(response.failure.category).assertEqual(ResourceErrorCategory.SECURITY_ERROR);
        expect(response.failure.stage).assertEqual(STAGE_POLICY_POST);
      }
    });

    /**
     * 404 默认同样不发 CORS 头（与 iOS 的 headerFields:nil 一致）。集成方设置了 allowedOrigins 时，
     * 404 才回显对应源的头，让 H5 侧能读到这个状态码。
     */
    it('omits CORS headers on the failure path by default', 0, () => {
      const handler = handlerForRegisteredAsset();
      const response = handler.handle('local-asset://demo/missing', createResolveContext());
      expect(response.headers.get('Access-Control-Allow-Origin')).assertUndefined();
      expect(response.headers.size).assertEqual(0);
    });

    it('echoes CORS on the failure path when allowedOrigins matches', 0, () => {
      const handler = new SchemeRequestHandler({
        engine: localAssetWithRegisteredAsset().engine,
        allowedOrigins: new Set<string>(['https://app.example.com']),
      });
      const context = createResolveContext();
      context.requestMetadata.set('header.origin', 'https://app.example.com');
      const response = handler.handle('local-asset://demo/missing', context);
      expect(response.headers.get('Access-Control-Allow-Origin'))
        .assertEqual('https://app.example.com');
    });

    it('invokes onFailure for an intercepted failure', 0, () => {
      const seen: EngineFailureInfo[] = [];
      const handler = new SchemeRequestHandler({
        engine: localAssetWithRegisteredAsset().engine,
        onFailure: (failure: EngineFailureInfo) => {
          seen.push(failure);
        },
      });
      handler.handle('local-asset://demo/missing', createResolveContext());
      expect(seen.length).assertEqual(1);
      expect(seen[0].category).assertEqual(ResourceErrorCategory.RESOLUTION_ERROR);
    });

    /**
     * 交还内核这条分支同样必须回调 —— hilog 在 release 构建里常被过滤，
     * 回调是唯一可靠的观测通道。把 onFailure 放在 stage 判别**之后**（早 return）
     * 会让这条静默，而上一条用例察觉不到。
     */
    it('invokes onFailure on the pass-through path too', 0, () => {
      const seen: EngineFailureInfo[] = [];
      const handler = new SchemeRequestHandler({
        engine: localAssetWithRegisteredAsset().engine,
        onFailure: (failure: EngineFailureInfo) => {
          seen.push(failure);
        },
      });
      handler.handle('https://example.com/logo.png', createResolveContext());
      expect(seen.length).assertEqual(1);
      expect(seen[0].stage).assertEqual(STAGE_ADAPTER_PARSE);
    });

    it('does not invoke onFailure on the success path', 0, () => {
      const seen: EngineFailureInfo[] = [];
      const handler = new SchemeRequestHandler({
        engine: localAssetWithRegisteredAsset().engine,
        onFailure: (failure: EngineFailureInfo) => {
          seen.push(failure);
        },
      });
      handler.handle('local-asset://demo/asset-1', createResolveContext());
      expect(seen.length).assertEqual(0);
    });

    it('tolerates an omitted onFailure callback', 0, () => {
      const handler = handlerForRegisteredAsset();
      expect(handler.handle('local-asset://demo/missing', createResolveContext()).status)
        .assertEqual(404);
    });

    it('serves a handle capability uri end to end', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      const uri = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([5, 6, 7])),
        fileName: 'preview.png',
        mimeType: 'image/png',
      }));
      const handler = new SchemeRequestHandler({ engine: localAsset.engine });
      const response = handler.handle(uri, createResolveContext());
      expect(response.status).assertEqual(200);
      expect(response.mimeType).assertEqual('image/png');
      expect(bodyEquals(response.body, [5, 6, 7])).assertTrue();
      // Handle 走 HandleRegistryResolver，产出的 descriptor 恒为 DYNAMIC → 不得可缓存。
      expect(response.headers.get('Cache-Control')).assertEqual('no-store');
    });

    it('returns 404 after the handle is revoked', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      const uri = localAsset.registerHandle(createResourceHandle({
        source: bytesSource(new Uint8Array([5])),
        fileName: 'preview.png',
        mimeType: 'image/png',
      }));
      const handler = new SchemeRequestHandler({ engine: localAsset.engine });
      // 先证明吊销**之前**确实是 200：否则这条用例可能只是因为 URI 从来就没解析成功过而绿。
      expect(handler.handle(uri, createResolveContext()).status).assertEqual(200);
      localAsset.removeHandle(uri);
      const response = handler.handle(uri, createResolveContext());
      expect(response.intercepted).assertTrue();
      expect(response.status).assertEqual(404);
    });

    /** 三个构建函数也可脱离 SchemeRequestHandler 单独使用（ArkWeb 适配层可能直接用）。 */
    it('exposes the response builders directly', 0, () => {
      const engine = localAssetWithRegisteredAsset().engine;
      const success: EngineResult = engine.resolveUrl('local-asset://demo/asset-1');
      expect(success.kind).assertEqual('success');
      if (success.kind === 'success') {
        const built: BridgeResponse = buildSuccessResponse(success, 30);
        expect(built.status).assertEqual(200);
        expect(built.headers.get('Cache-Control')).assertEqual('public, max-age=30');
        // 省略 maxAgeSeconds 时落回 core 的 DEFAULT_MAX_AGE_SECONDS。
        expect(buildSuccessResponse(success).headers.get('Cache-Control'))
          .assertEqual('public, max-age=86400');
      }

      const failed: EngineResult = engine.resolveUrl('local-asset://demo/missing');
      expect(failed.kind).assertEqual('failure');
      if (failed.kind === 'failure') {
        const built: BridgeResponse = buildFailureResponse(failed);
        expect(built.intercepted).assertTrue();
        expect(built.status).assertEqual(404);
        expect(built.failure !== null).assertTrue();
        if (built.failure !== null) {
          expect(built.failure.reason).assertEqual('resource not found');
        }
      }

      const passed: BridgeResponse = passThroughResponse();
      expect(passed.intercepted).assertFalse();
      expect(passed.failure).assertNull();
      expect(passed.status).assertEqual(0);
    });

    it('HarmonyResolveContextFactory injects engineScope and metadata', 0, () => {
      const factory = new HarmonyResolveContextFactory('engine-a');
      const metadata = new Map<string, string>();
      metadata.set('url', 'local-asset://demo/a.png');
      metadata.set('method', 'GET');
      const context = factory.create(metadata);
      expect(context.engineScope).assertEqual('engine-a');
      expect(context.requestMetadata.get('method')).assertEqual('GET');
      expect(context.requestMetadata.get('url')).assertEqual('local-asset://demo/a.png');
      expect(context.requestMetadata.size).assertEqual(2);
      // 其余三个 scope 默认保持 null（engineScope 之外的 scope 由调用方按需构造）。
      expect(context.callerScope).assertNull();
      expect(context.pageScope).assertNull();
      expect(context.sessionScope).assertNull();
    });

    it('HarmonyResolveContextFactory injects all four scopes', 0, () => {
      const factory = new HarmonyResolveContextFactory('e', 'c', 'p', 's');
      const context = factory.create();
      expect(context.engineScope).assertEqual('e');
      expect(context.callerScope).assertEqual('c');
      expect(context.pageScope).assertEqual('p');
      expect(context.sessionScope).assertEqual('s');
    });

    it('requestHeader reads published headers case-insensitively', 0, () => {
      const factory = new HarmonyResolveContextFactory();
      const metadata = new Map<string, string>();
      metadata.set(REQUEST_HEADER_PREFIX + 'origin', 'https://app.example.com');
      const context = factory.create(metadata);
      expect(requestHeader(context, 'Origin')).assertEqual('https://app.example.com');
      expect(requestHeader(context, 'origin')).assertEqual('https://app.example.com');
      expect(requestHeader(context, 'ORIGIN')).assertEqual('https://app.example.com');
      expect(requestHeader(context, 'Referer')).assertNull();
    });

    it('HarmonyResolveContextFactory defaults engineScope to null', 0, () => {
      const context = new HarmonyResolveContextFactory().create();
      expect(context.engineScope).assertNull();
      expect(context.requestMetadata.size).assertEqual(0);
    });

    /**
     * 工厂产出的上下文必须真的被引擎用上 —— 只断言 create() 的返回值字段，
     * 无法排除"handler 忽略传入 context、自己 new 一个空的"这条退化路径。
     * 这里让一条 ENGINE scope 资源只在 scope 匹配时通过。
     */
    it('feeds the factory context into the engine scope gate', 0, () => {
      const localAsset = new LocalAssetBuilder().build();
      localAsset.register(createResourceDescriptor({
        id: 'scoped',
        namespace: 'engine-a',
        type: ResourceType.DYNAMIC,
        source: bytesSource(new Uint8Array([1])),
        mimeType: 'image/png',
        createdAtMillis: 0,
        scope: ResourceScope.ENGINE,
      }));
      const handler = new SchemeRequestHandler({ engine: localAsset.engine });
      const matching = new HarmonyResolveContextFactory('engine-a');
      const mismatched = new HarmonyResolveContextFactory('engine-b');
      expect(handler.handle('local-asset://demo/scoped', matching.create()).status)
        .assertEqual(200);
      expect(handler.handle('local-asset://demo/scoped', mismatched.create()).status)
        .assertEqual(404);
    });
  });
}
