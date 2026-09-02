package io.github.xesam.android.localasset.webview.interceptor

import android.webkit.WebResourceRequest
import io.github.xesam.android.localasset.core.model.ResolveContext

/**
 * Builds the per-request [ResolveContext] for the WebView bridge.
 *
 * All four scopes are injectable because the engine's scope model (design.md §5.3) is otherwise
 * unreachable from a WebView: a descriptor registered with `scope = PAGE` can only be resolved when
 * the context carries a matching [pageScope]. One WebView normally hosts one page and one session,
 * so these are constructor-fixed; re-create the factory (or the client) on navigation if your
 * page identity changes.
 *
 * Request headers are published into `requestMetadata` under
 * [ResolveContext.REQUEST_HEADER_PREFIX] so a custom `Policy` can gate on `Origin`/`Referer`.
 * `WebResourceRequest.requestHeaders` is unavailable on the deprecated URL-only
 * `shouldInterceptRequest` overload, which passes a null request — no header keys are published
 * then.
 */
class AndroidResolveContextFactory @JvmOverloads constructor(
    private val engineScope: String? = null,
    private val callerScope: String? = null,
    private val pageScope: String? = null,
    private val sessionScope: String? = null,
) {
    @JvmOverloads
    fun create(request: WebResourceRequest? = null): ResolveContext {
        val metadata = buildMap {
            if (request != null) {
                put("url", request.url.toString())
                put("method", request.method ?: "GET")
                put("isMainFrame", request.isForMainFrame.toString())
                request.requestHeaders?.forEach { (name, value) ->
                    put(ResolveContext.REQUEST_HEADER_PREFIX + name.lowercase(), value)
                }
            }
        }
        return ResolveContext(
            engineScope = engineScope,
            callerScope = callerScope,
            pageScope = pageScope,
            sessionScope = sessionScope,
            requestMetadata = metadata,
        )
    }
}
