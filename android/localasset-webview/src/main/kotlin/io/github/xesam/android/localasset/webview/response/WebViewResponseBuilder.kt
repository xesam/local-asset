package io.github.xesam.android.localasset.webview.response

import android.webkit.WebResourceResponse
import io.github.xesam.android.localasset.core.api.EngineResult

interface WebViewResponseBuilder {
    /**
     * @param requestOrigin the request's `Origin` header, or null when absent. Needed to decide the
     *   `Access-Control-Allow-Origin` value against the configured allow-list.
     */
    fun build(result: EngineResult.Success, requestOrigin: String? = null): WebResourceResponse

    fun buildFailure(result: EngineResult.Failure): WebResourceResponse?
}
