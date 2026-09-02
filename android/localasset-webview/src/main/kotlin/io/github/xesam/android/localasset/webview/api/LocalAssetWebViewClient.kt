package io.github.xesam.android.localasset.webview.api

import android.graphics.Bitmap
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.api.LocalAsset
import io.github.xesam.android.localasset.webview.interceptor.AndroidResolveContextFactory
import io.github.xesam.android.localasset.webview.interceptor.WebViewAssetInterceptor
import io.github.xesam.android.localasset.webview.response.DefaultWebViewResponseBuilder
import io.github.xesam.android.localasset.webview.response.WebViewResponseBuilder

class LocalAssetWebViewClient(
    private val delegate: WebViewClient? = null,
    private val interceptor: WebViewAssetInterceptor,
) : WebViewClient() {
    /**
     * One-stop entry point: wires up [WebViewAssetInterceptor], [AndroidResolveContextFactory],
     * and [DefaultWebViewResponseBuilder] internally so callers don't have to hand-assemble them
     * (which every one of this library's own sample activities used to do identically). Use the
     * primary constructor instead when you need a custom [WebViewResponseBuilder] or an
     * already-built [WebViewAssetInterceptor].
     */
    @JvmOverloads
    constructor(
        localAsset: LocalAsset,
        engineScope: String? = null,
        delegate: WebViewClient? = null,
        /**
         * Origins allowed to read asset responses via `fetch()`/`XHR`. Empty (default) emits no CORS
         * headers — `<img>`/`<link>`/`<script>` do not need them. Ignored when you pass your own
         * [responseBuilder]. See `CorsPolicy`.
         */
        allowedOrigins: Set<String> = emptySet(),
        responseBuilder: WebViewResponseBuilder = DefaultWebViewResponseBuilder(allowedOrigins = allowedOrigins),
        onFailure: (EngineResult.Failure) -> Unit = {},
    ) : this(
        delegate = delegate,
        interceptor = WebViewAssetInterceptor(
            engine = localAsset.engine,
            responseBuilder = responseBuilder,
            contextFactory = AndroidResolveContextFactory(engineScope),
            onFailure = onFailure,
        ),
    )
    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
        val intercepted = request?.let { interceptor.intercept(it) }
        return intercepted
            ?: delegate?.shouldInterceptRequest(view, request)
            ?: super.shouldInterceptRequest(view, request)
    }

    @Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
    override fun shouldInterceptRequest(view: WebView?, url: String?): WebResourceResponse? {
        val intercepted = url?.let { interceptor.intercept(it, null) }
        return intercepted
            ?: delegate?.shouldInterceptRequest(view, url)
            ?: super.shouldInterceptRequest(view, url)
    }

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
        delegate?.onPageStarted(view, url, favicon)
    }

    override fun onPageFinished(view: WebView?, url: String?) {
        delegate?.onPageFinished(view, url)
    }

    override fun onReceivedError(
        view: WebView?,
        request: WebResourceRequest?,
        error: WebResourceError?,
    ) {
        delegate?.onReceivedError(view, request, error)
    }
}
