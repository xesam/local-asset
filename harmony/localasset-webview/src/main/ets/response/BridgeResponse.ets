import {
  EngineSuccess,
  EngineFailure,
  EngineFailureInfo,
  decideCache,
  CacheDecision,
  DEFAULT_MAX_AGE_SECONDS,
  corsHeaders,
} from 'io.github.xesam.harmony.localasset.core';

/**
 * 平台无关的响应结构。刻意**不引用任何 `@ohos.web.webview` 类型** ——
 * ArkWeb 没有 Robolectric 那样的宿主侧仿真，凡是碰到真实 Web 组件类型的代码
 * 只能靠真机手测。把"引擎结果 → HTTP 语义"的全部决策收进本文件与
 * SchemeRequestHandler，就等于把这部分决策全部搬进可在无设备环境下跑的单元测试；
 * `LocalAssetSchemeHandler`（ArkWeb 适配层）只剩"把 BridgeResponse 翻译成 WebResourceHandler 调用"
 * 这一层薄壳。iOS 把 `start(_:)` 从 `WKURLSchemeHandler` 回调里抽出来是同一动机
 * （LocalAssetSchemeHandler.swift:44 的注释），这里再往前推一级。
 */
export interface BridgeResponse {
  /**
   * false 表示不接管，交还 ArkWeb 内核走默认加载路径 ——
   * 对应 Android `shouldInterceptRequest` 返回 null（WebViewAssetInterceptor.kt:28）。
   */
  intercepted: boolean;
  status: number;
  statusText: string;
  mimeType: string;
  encoding: string | null;
  headers: Map<string, string>;
  body: Uint8Array;
  failure: EngineFailureInfo | null;
}

/** 与 Kotlin DefaultWebViewResponseBuilder.kt:14 / iOS LocalAssetSchemeHandler.swift:61 同一字面量。 */
const FALLBACK_MIME = 'application/octet-stream';

/**
 * 成功路径。响应头由 Content-Type / Cache-Control / ETag 加上 `corsHeaders` 给出的 CORS 头
 * （默认空集 → 不发任何 CORS 头）组成。后两条一律取 core `decideCache` 的结果，本层不重算 ——
 * 三端共享同一个策略函数正是 `docs/compatibility-fixtures/cache-headers.json` 能钉住的前提；
 * CORS 头同样三端共享 `corsHeaders`，由 `docs/compatibility-fixtures/cors-headers.json` 钉住。
 *
 * 与 Kotlin 的一处形态差异（非行为差异）：Kotlin 的 headers map 里**没有** Content-Type，
 * 因为它作为 `WebResourceResponse` 构造函数的独立参数传入（DefaultWebViewResponseBuilder.kt:43），
 * 框架自己会补上该响应头；iOS 则把它显式写进 headerFields（LocalAssetSchemeHandler.swift:67）。
 * ArkWeb 的 WebResourceResponse 同样是 setResponseMimeType / setResponseHeader 分开设置，
 * 但本结构是平台无关的中间态，把 Content-Type 明确列进 headers 才能让响应头这件事
 * 在测试里被完整断言；ArkWeb 适配层按 mimeType 字段设置 MIME，不必重复写这条头。
 *
 * 恒为 200：条件请求（304）三端一致地不实现，省流量靠的是 max-age 窗口内 WebView
 * 直接吃本地缓存、根本不发起校验（见 core ResourceCachePolicy 的说明）。
 */
export function buildSuccessResponse(
  result: EngineSuccess,
  maxAgeSeconds: number = DEFAULT_MAX_AGE_SECONDS,
  allowedOrigins: Set<string> = new Set<string>(),
  requestOrigin: string | null = null,
): BridgeResponse {
  const mimeType: string = result.data.mimeType ?? FALLBACK_MIME;
  const decision: CacheDecision = decideCache(result.descriptor, maxAgeSeconds);
  const headers = new Map<string, string>();
  headers.set('Content-Type', mimeType);
  headers.set('Cache-Control', decision.cacheControl);
  headers.set('ETag', decision.etag);
  corsHeaders(allowedOrigins, requestOrigin).forEach((value: string, name: string) => {
    headers.set(name, value);
  });
  return {
    intercepted: true,
    status: 200,
    statusText: 'OK',
    mimeType: mimeType,
    encoding: isTextualMime(mimeType) ? 'utf-8' : null,
    headers: headers,
    body: result.data.bytes,
    failure: null,
  };
}

/**
 * 已经被我们接管的 scheme 内部失败：回 **404 + 空 body**，而不是交还内核。
 *
 * 为什么不交还：scheme 已经归我们管，内核对 `local-asset://` 没有任何默认加载路径，
 * 交还只会得到一个语义模糊的失败。显式 404 让失败在 H5 侧看得见 ——
 * **仅状态码与空 body 这一形态**对齐 iOS（LocalAssetSchemeHandler.swift:123，显式 404 + 空 Data）。
 *
 * 注意这里与 Android **有意分歧**：Kotlin `buildFailure` 返回 null（等于交还内核，
 * DefaultWebViewResponseBuilder.kt:46）。`harmony/README.md`「失败处理」记录的混合策略取两端各自的优点 ——
 * 「不是我们的 URL」用 Android 的交还语义，「是我们的 URL 但失败了」用 iOS 的显式可见语义。
 *
 * CORS 头与成功路径同源：默认（空 allow-list）不发任何 CORS 头，与 iOS 的 `headerFields: nil` 一致；
 * 集成方设置了 `allowedOrigins` 时，404 响应也会回显对应源的头，让 H5 侧能读到这个 404 状态码。
 * 旧的 harmony 独有 `Access-Control-Allow-Origin: *` 已移除——它让一个空 body 的 404 仍向任意源
 * 暴露状态码，且与「默认不发 CORS 头」的安全默认相矛盾。
 */
export function buildFailureResponse(
  result: EngineFailure,
  allowedOrigins: Set<string> = new Set<string>(),
  requestOrigin: string | null = null,
): BridgeResponse {
  const headers = new Map<string, string>();
  corsHeaders(allowedOrigins, requestOrigin).forEach((value: string, name: string) => {
    headers.set(name, value);
  });
  return {
    intercepted: true,
    status: 404,
    statusText: 'Not Found',
    mimeType: FALLBACK_MIME,
    encoding: null,
    headers: headers,
    body: new Uint8Array(0),
    failure: { category: result.category, reason: result.reason, stage: result.stage },
  };
}

/**
 * 不是我们的 scheme：交还内核（对齐 Android `shouldInterceptRequest` 返回 null）。
 *
 * `failure` 参数可省，缺省为 null。调用方（SchemeRequestHandler）会把引擎给出的
 * 失败三要素带上，供 ArkWeb 适配层与观测方追因；直接调用者若无失败上下文可不传。
 * 除 intercepted 外的字段全是"无意义"占位（status 0、空 headers、空 body），
 * 适配层看到 intercepted === false 就不应再读它们。
 */
export function passThroughResponse(failure: EngineFailureInfo | null = null): BridgeResponse {
  return {
    intercepted: false,
    status: 0,
    statusText: '',
    mimeType: '',
    encoding: null,
    headers: new Map<string, string>(),
    body: new Uint8Array(0),
    failure: failure,
  };
}

/**
 * 谓词表逐条抄自 Kotlin DefaultWebViewResponseBuilder.kt:15-27，顺序与分支一一对应。
 * Kotlin 里多出的 `mimeType == "application/json"` 一条被 `contains("/json")` 完全包含，
 * 是参考实现里的冗余分支，行为等价，故此处不重复。
 *
 * 只有文本类 MIME 才带 `utf-8` —— 给二进制响应标编码会让 WebView 按文本解码，
 * 图片/视频当场损坏。
 */
function isTextualMime(mimeType: string): boolean {
  return mimeType.startsWith('text/') ||
    mimeType.includes('/json') ||
    mimeType.includes('+json') ||
    mimeType.includes('/javascript') ||
    mimeType.includes('/xml') ||
    mimeType.includes('+xml');
}
