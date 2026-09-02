package io.github.xesam.android.localasset.webview.interceptor

import android.util.Log
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import io.github.xesam.android.localasset.core.api.LocalAssetEngine
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.webview.response.WebViewResponseBuilder

class WebViewAssetInterceptor(
    private val engine: LocalAssetEngine,
    private val responseBuilder: WebViewResponseBuilder,
    private val contextFactory: AndroidResolveContextFactory,
    /**
     * Invoked for every [EngineResult.Failure], in addition to the debug-level log line. Use
     * this to feed your own crash reporting/analytics — `Log.d` output is commonly stripped or
     * filtered out of release builds and is not a reliable observability channel on its own.
     */
    private val onFailure: (EngineResult.Failure) -> Unit = {},
) {
    private companion object {
        const val TAG = "LocalAssetInterceptor"
    }

    fun intercept(url: String, request: WebResourceRequest? = null): WebResourceResponse? {
        val context = contextFactory.create(request)
        val result = engine.resolve(url, context)
        return when (result) {
            is EngineResult.Success -> responseBuilder.build(result, context.requestHeader("Origin"))
            is EngineResult.Failure -> {
                runCatching {
                    Log.d(
                        TAG,
                        "intercept failed: category=${result.category}, stage=${result.stage}, reason=${result.reason}",
                    )
                }
                onFailure(result)
                responseBuilder.buildFailure(result)
            }
        }
    }

    fun intercept(request: WebResourceRequest): WebResourceResponse? {
        return intercept(request.url.toString(), request)
    }
}
