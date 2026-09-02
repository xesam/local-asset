import { webview, WebNetErrorList } from '@kit.ArkWeb';
import {
  LocalAssetEngine,
  EngineFailureInfo,
  DEFAULT_MAX_AGE_SECONDS,
  REQUEST_HEADER_PREFIX,
} from 'io.github.xesam.harmony.localasset.core';
import { SchemeRequestHandler } from '../interceptor/SchemeRequestHandler';
import { HarmonyResolveContextFactory } from '../interceptor/HarmonyResolveContextFactory';
import { BridgeResponse } from '../response/BridgeResponse';

/** scheme 字面量是跨平台契约（Android / iOS 同）——改它等于换掉整套 URL 形态。 */
export const LOCAL_ASSET_SCHEME = 'local-asset';

/**
 * 注册用的自定义 scheme 配置。
 *
 * - `isSupportCORS` / `isSupportFetch`：不开这两项，H5 侧的 `fetch()` / `XMLHttpRequest`
 *   拿不到本 scheme 的响应（只有 `<img src>` 这类直接引用能工作）。BridgeResponse 由此能按
 *   `allowedOrigins` 下发 CORS 头；默认不发，集成方按需显式放行。
 * - `isStandard`：按 RFC 1738 §3.1 走标准 URL 规范化，`local-asset://ns/id`
 *   里的 host（namespace）与 path 才会被内核正确切分 —— core 的 SchemeAdapter
 *   正是按 host=namespace、path=资源路径来解析的。
 *
 * ⚠️ `isSecure` / `isLocal` / `isDisplayIsolated` 三个开关**刻意留空**。曾试过
 * `isSecure: true`（设想：承载页 resource:// 是安全上下文，不安全的子资源会被混合内容
 * 策略静默拦掉），真机结果是页面跳转变成 "too many redirects"，比原症状更糟，已回退。
 * 这三个开关的实际行为在本仓尚无任何验证手段，改动前必须先有真机结论。
 */
export function localAssetCustomScheme(): webview.WebCustomScheme {
  return {
    schemeName: LOCAL_ASSET_SCHEME,
    isSupportCORS: true,
    isSupportFetch: true,
    isStandard: true,
  };
}

export interface LocalAssetSchemeHandlerOptions {
  engine: LocalAssetEngine;
  contextFactory?: HarmonyResolveContextFactory;
  /** STATIC 资源的 `Cache-Control: max-age`；DYNAMIC 恒为 no-store，与本值无关。 */
  maxAgeSeconds?: number;
  /**
   * 允许经 `fetch()`/`XHR` 读取资产响应的源集合。空（默认）= 不发任何 CORS 头；
   * 含 `ALLOW_ANY_ORIGIN` = 通配；否则为精确匹配列表。见 core `corsHeaders`。
   */
  allowedOrigins?: Set<string>;
  /**
   * 终态失败回调。**这是 release 构建里唯一可靠的观测通道** ——
   * `LoggingEngineObserver` 走 hilog，常被级别过滤丢弃。要把失败送到崩溃平台
   * 或埋点，用这个。语义与 Android `WebViewAssetInterceptor.onFailure`、
   * iOS `LocalAssetSchemeHandler.onFailure` 一致。
   */
  onFailure?: (failure: EngineFailureInfo) => void;
}

/**
 * ArkWeb 适配层：把 `SchemeRequestHandler` 产出的 `BridgeResponse` 翻译成
 * `WebResourceHandler` 的调用序列。
 *
 * ## 这里为什么这么薄
 *
 * ArkWeb 没有 Robolectric 那样的宿主侧仿真，本文件里的每一行都**跑不进
 * `hvigorw test`，只能编译**（真实行为要靠 sample 应用真机验收）。所以"响应
 * 该长什么样"的全部决策都被推到了 `SchemeRequestHandler`（22 条单测）与
 * `BridgeResponse`，这里只剩机械翻译。
 *
 * **维护约束**：若你正准备在本文件里写一个"决定响应该是什么"的分支
 * （改状态码、挑 MIME、判 URL 前缀、按 method 过滤……），那条逻辑属于
 * `SchemeRequestHandler`，写在这里就等于把它挪出了测试覆盖范围。
 *
 * ## 用法与时序（写错顺序会静默失效，是本模块最容易踩的坑）
 *
 * 两次调用分属**两个不同时刻**，缺一不可：
 *
 * ```typescript
 * // ① 必须早于任何 Web 组件初始化：把 scheme 注册进内核。
 * //    推荐放在 UIAbility.onCreate 里 —— 它先于任何页面加载，一处覆盖全部页面。
 * export default class EntryAbility extends UIAbility {
 *   onCreate(): void {
 *     webview.WebviewController.customizeSchemes([localAssetCustomScheme()]);
 *   }
 * }
 *
 * // ② 必须晚到 controller 已与组件绑定之后：给已注册的 scheme 挂 handler。
 * build() {
 *   Web({ src: this.url, controller: this.controller })
 *     .onControllerAttached(() => { this.assetHandler.attachTo(this.controller); })
 * }
 * ```
 *
 * - `customizeSchemes` 是 **static** 方法，作用于整个 Web 内核，进程级只需一次；
 *   晚于 Web 组件初始化再调用，注册**不报错但不生效** —— 表现为请求根本不进
 *   `onRequestStart`。放在 `UIAbility.onCreate` 里最稳（sample 即如此）；
 *   拿不到 UIAbility 级钩子时（如库被嵌进他人页面），退而求其次放在承载 Web
 *   组件的自定义组件的 `aboutToAppear` 里，同样有效，只是覆盖面仅限该组件。
 * - `setWebSchemeHandler`（即 `attachTo`）是**实例**方法，早于
 *   `onControllerAttached` 调用会抛"controller 尚未与组件绑定"。
 * - 顺序颠倒（先 attach 后 customize）两边都白做：scheme 没进内核，handler 挂了个空。
 *
 * ## 已知行为：畸形 URL 会以 ERR_UNKNOWN_URL_SCHEME 收场
 *
 * 引擎在 `adapter_parse` 阶段失败时 `onRequestStart` 返回 `false`，把请求交还内核
 * —— 与 Android `shouldInterceptRequest` 返回 null 对齐（`docs/compatibility.md` §13.7 的混合策略，另见 `harmony/README.md`「失败处理」）。
 * 但我们已经把这个 scheme 注册给了内核，而内核对它**没有任何默认加载路径**，
 * 于是一条畸形的 `local-asset://`（例如缺 path 的 `local-asset://demo`）在真机上
 * 会表现为 `ERR_UNKNOWN_URL_SCHEME` 之类的内核错误，而不是一个干净的 404。
 *
 * **这是预期行为，不是 bug**：真机验收看到这个错误码时，应确认它来自畸形 URL，
 * 而不是去"修"它。要区分两类失败，看 `onFailure` 回调带的 `stage` ——
 * `adapter_parse` 即这条路径。（非 parse 阶段的失败走 404，H5 侧可读。）
 */
export class LocalAssetSchemeHandler {
  readonly raw: webview.WebSchemeHandler = new webview.WebSchemeHandler();
  private readonly requestHandler: SchemeRequestHandler;
  private readonly contextFactory: HarmonyResolveContextFactory;

  constructor(options: LocalAssetSchemeHandlerOptions) {
    this.contextFactory = options.contextFactory ?? new HarmonyResolveContextFactory();
    this.requestHandler = new SchemeRequestHandler({
      engine: options.engine,
      maxAgeSeconds: options.maxAgeSeconds ?? DEFAULT_MAX_AGE_SECONDS,
      allowedOrigins: options.allowedOrigins,
      onFailure: options.onFailure,
    });
    this.raw.onRequestStart((
      request: webview.WebSchemeHandlerRequest,
      handler: webview.WebResourceHandler,
    ): boolean => {
      return this.onRequestStart(request, handler);
    });
  }

  /** 必须在 `onControllerAttached` 之后调用 —— 见类注释的时序说明。 */
  attachTo(controller: webview.WebviewController): void {
    controller.setWebSchemeHandler(LOCAL_ASSET_SCHEME, this.raw);
  }

  private onRequestStart(
    request: webview.WebSchemeHandlerRequest,
    handler: webview.WebResourceHandler,
  ): boolean {
    const url = request.getRequestUrl();
    const metadata = new Map<string, string>();
    metadata.set('url', url);
    metadata.set('method', request.getRequestMethod());
    // 发布请求头到 requestMetadata（小写键名 + `header.` 前缀），让一个自定义 Policy 能跨端
    // 读到 Origin/Referer。getHeader() 在 ArkWeb 上返回 WebHeader[]，可能为空数组（非 CORS 请求）。
    const headers = request.getHeader();
    if (headers) {
      headers.forEach((h: webview.WebHeader) => {
        metadata.set(REQUEST_HEADER_PREFIX + h.headerKey.toLowerCase(), h.headerValue);
      });
    }
    const response = this.requestHandler.handle(url, this.contextFactory.create(metadata));

    if (!response.intercepted) {
      // 交还内核走默认加载路径（对齐 Android shouldInterceptRequest 返回 null）。
      // 对已注册的 scheme 而言这条路多半以内核错误收场 —— 见类注释。
      return false;
    }
    try {
      handler.didReceiveResponse(this.toWebResponse(response));
      handler.didReceiveResponseBody(toArrayBuffer(response.body));
      handler.didFinish();
    } catch (error) {
      // 已经 didReceiveResponse 之后再抛，didFail 是收尾这次请求的唯一途径；
      // 不收尾会让 H5 侧那个请求永远挂起。
      handler.didFail(WebNetErrorList.ERR_FAILED);
    }
    // 无论成功还是 didFail，都已接管这次请求，必须返回 true。
    return true;
  }

  /**
   * `BridgeResponse` → `WebSchemeHandlerResponse` 的逐字段搬运，不做任何判断。
   * MIME 走 `setMimeType`（而不是只塞 headers），因为内核按它决定怎么解码响应体。
   * headers 里那条 `Content-Type` 是 BridgeResponse 为了让"五条头"可断言而保留的，
   * 一并 set 过去无害且与 iOS 的 headerFields 形态一致。
   *
   * ## ⚠️ 不要调 `setUrl()`
   *
   * 它不是"这条响应对应哪个 URL"，SDK 原文是 *"Set the resolved URL **after redirects**
   * or changed as a result of HSTS"* —— 即**重定向后的目标地址**。把它设成请求自身的
   * URL，等于告诉内核"这条请求重定向到它自己"，内核照做，于是无限循环，真机上报
   * `ERR_TOO_MANY_REDIRECTS`（诊断栏实测：`← local-asset://assets.demo.local/static/app.js`）。
   * 不设置即表示"没有发生重定向"，这正是本库要的语义。
   */
  private toWebResponse(response: BridgeResponse): webview.WebSchemeHandlerResponse {
    const webResponse = new webview.WebSchemeHandlerResponse();
    webResponse.setStatus(response.status);
    webResponse.setStatusText(response.statusText);
    webResponse.setMimeType(response.mimeType);
    if (response.encoding !== null) {
      webResponse.setEncoding(response.encoding);
    }
    response.headers.forEach((value: string, name: string) => {
      webResponse.setHeaderByName(name, value, true);
    });
    return webResponse;
  }
}

/**
 * `Uint8Array` → `ArrayBuffer`。逐字节拷贝而不是直接取 `bytes.buffer`：
 * 后者在视图只覆盖底层 buffer 一部分时（byteOffset 非 0 或 length 小于 buffer）
 * 会把多余字节一并送进响应体，资源当场损坏。
 *
 * 导出给 sample 复用（`SampleFiles.writeBytes` 落盘前做同一件事，同一条理由）。
 */
export function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const arrayBuffer = new ArrayBuffer(bytes.length);
  const view = new Uint8Array(arrayBuffer);
  for (let i = 0; i < bytes.length; i++) {
    view[i] = bytes[i];
  }
  return arrayBuffer;
}
