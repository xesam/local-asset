import {
  LocalAssetEngine,
  EngineResult,
  ResolveContext,
  EngineFailureInfo,
  DEFAULT_MAX_AGE_SECONDS,
  STAGE_ADAPTER_PARSE,
  requestHeader,
} from 'io.github.xesam.harmony.localasset.core';
import {
  BridgeResponse,
  buildSuccessResponse,
  buildFailureResponse,
  passThroughResponse,
} from '../response/BridgeResponse';

export interface SchemeRequestHandlerOptions {
  engine: LocalAssetEngine;
  /** STATIC 资源的 `Cache-Control: max-age`；DYNAMIC 恒为 no-store，与本值无关。 */
  maxAgeSeconds?: number;
  /**
   * 允许经 `fetch()`/`XHR` 读取资产响应的源集合。空（默认）= 不发任何 CORS 头；
   * 含 `ALLOW_ANY_ORIGIN` = 通配；否则为精确匹配列表。见 core `corsHeaders`。
   */
  allowedOrigins?: Set<string>;
  /**
   * 每个失败都会回调（含交还内核那条分支）。这是日志之外的观测通道：
   * `hilog` 在 release 构建里常被过滤，不能作为唯一的可观测手段 ——
   * 与 Android `WebViewAssetInterceptor.onFailure`（WebViewAssetInterceptor.kt:19 的注释）
   * 和 iOS `LocalAssetSchemeHandler.onFailure`（LocalAssetSchemeHandler.swift:16）同一理由。
   *
   * 携带的是三字段的 `EngineFailureInfo`（观测事件用的结构，与 observer 发出的同型），
   * 而不是带 `kind` 判别子的 `EngineFailure` 联合成员，调用方无需自己拆联合。
   */
  onFailure?: (failure: EngineFailureInfo) => void;
}

/**
 * 桥接层的纯逻辑核心：**不依赖 ArkWeb**，可直接在本地单元测试里驱动。
 *
 * 混合失败策略（`docs/compatibility.md` §13.7 与 `harmony/README.md`「失败处理」）
 * 就落在 handle() 里，两条分支不可混为一谈：
 *
 * - 引擎在 `adapter_parse` 阶段失败 = 这条 URL 根本没进我们的流水线（不是
 *   `local-asset://`，或形态畸形连 AssetRequest 都构不出来）→ 交还内核，
 *   对应 Android `shouldInterceptRequest` 返回 null。
 * - 其余任何阶段失败（resolve / policy / load）= 请求已经进了我们接管的 scheme
 *   然后失败了 → 404，让失败在 H5 侧可见，对应 iOS 的显式失败语义。
 *   这里交还内核是没有意义的：scheme 归我们管，内核对它没有任何默认加载路径。
 *
 * 判据是**引擎给出的 stage**，不是对 URL 做前缀匹配。前缀匹配会把
 * `local-asset://demo`（缺 path，同样在 adapter_parse 失败）错判成 404。
 */
export class SchemeRequestHandler {
  private readonly engine: LocalAssetEngine;
  private readonly maxAgeSeconds: number;
  private readonly allowedOrigins: Set<string>;
  private readonly onFailure: (failure: EngineFailureInfo) => void;

  constructor(options: SchemeRequestHandlerOptions) {
    this.engine = options.engine;
    this.maxAgeSeconds = options.maxAgeSeconds ?? DEFAULT_MAX_AGE_SECONDS;
    this.allowedOrigins = options.allowedOrigins ?? new Set<string>();
    this.onFailure = options.onFailure ?? ((failure: EngineFailureInfo) => {});
  }

  handle(url: string, context: ResolveContext): BridgeResponse {
    const requestOrigin = requestHeader(context, 'Origin');
    const result: EngineResult = this.engine.resolveUrl(url, context);
    if (result.kind === 'success') {
      return buildSuccessResponse(result, this.maxAgeSeconds, this.allowedOrigins, requestOrigin);
    }
    // 回调必须在分支判别**之前**：交还内核那条路径同样要可观测，
    // 把它放进 404 分支里会让"URL 不归我们管"的失败静默消失。
    const failure: EngineFailureInfo = {
      category: result.category,
      reason: result.reason,
      stage: result.stage,
    };
    this.onFailure(failure);
    if (result.stage === STAGE_ADAPTER_PARSE) {
      return passThroughResponse(failure);
    }
    return buildFailureResponse(result, this.allowedOrigins, requestOrigin);
  }
}
