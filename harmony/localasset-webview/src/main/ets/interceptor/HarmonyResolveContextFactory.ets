import { ResolveContext, createResolveContext } from 'io.github.xesam.harmony.localasset.core';

/**
 * 把平台侧的请求信息组装成 core 的 `ResolveContext`，对应 Android 的
 * `AndroidResolveContextFactory` 与 iOS 的 `ResolveContextFactory` 闭包。
 *
 * 与那两端的形态差异：Android/iOS 的工厂直接吃平台请求对象
 * （`WebResourceRequest` / `WKURLSchemeTask`），本工厂只吃一个
 * `Map<string, string>` —— 因为本模块刻意不引用任何 ArkWeb 类型（见 BridgeResponse.ets）。
 * 从 `WebResourceRequest` 里摘取 url / method / header 填进这个 Map，是 ArkWeb 适配层（`LocalAssetSchemeHandler`）的事。
 *
 * 四个 scope 全部构造期可注入，缺省为 null（core 的语义）。engineScope 之所以常被固定，
 * 是因为它与"一个 WebView 实例对应一个引擎"这件事天然同构；page/session scope 则随页面生命周期变化，
 * 由调用方在构造工厂时按需传入。
 */
export class HarmonyResolveContextFactory {
  private readonly engineScope: string | null;
  private readonly callerScope: string | null;
  private readonly pageScope: string | null;
  private readonly sessionScope: string | null;

  constructor(
    engineScope: string | null = null,
    callerScope: string | null = null,
    pageScope: string | null = null,
    sessionScope: string | null = null,
  ) {
    this.engineScope = engineScope;
    this.callerScope = callerScope;
    this.pageScope = pageScope;
    this.sessionScope = sessionScope;
  }

  create(requestMetadata?: Map<string, string>): ResolveContext {
    return createResolveContext({
      engineScope: this.engineScope,
      callerScope: this.callerScope,
      pageScope: this.pageScope,
      sessionScope: this.sessionScope,
      requestMetadata: requestMetadata ?? new Map<string, string>(),
    });
  }
}
