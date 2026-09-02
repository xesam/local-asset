package io.github.xesam.android.localasset.webview.response

import android.webkit.WebResourceResponse
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.cache.ResourceCachePolicy
import io.github.xesam.android.localasset.core.cors.CorsPolicy
import io.github.xesam.android.localasset.core.model.ResourceData
import java.io.ByteArrayInputStream
import java.io.InputStream

class DefaultWebViewResponseBuilder(
    private val maxAgeSeconds: Int = ResourceCachePolicy.DEFAULT_MAX_AGE_SECONDS,
    /**
     * Origins allowed to read these responses via `fetch()`/`XHR`. Empty (default) emits no CORS
     * headers at all — see [CorsPolicy] for why that is the safe default and why `<img>`/`<link>`/
     * `<script>` still work without them. Add [CorsPolicy.ALLOW_ANY_ORIGIN] to restore wildcard CORS.
     */
    private val allowedOrigins: Set<String> = emptySet(),
) : WebViewResponseBuilder {
    override fun build(result: EngineResult.Success, requestOrigin: String?): WebResourceResponse {
        val mimeType = result.data.mimeType ?: "application/octet-stream"
        val encoding = if (
            mimeType.startsWith("text/") ||
            mimeType == "application/json" ||
            mimeType.contains("/json") ||
            mimeType.contains("+json") ||
            mimeType.contains("/javascript") ||
            mimeType.contains("/xml") ||
            mimeType.contains("+xml")
        ) {
            "utf-8"
        } else {
            null
        }
        val decision = ResourceCachePolicy.decide(result.descriptor, maxAgeSeconds)
        val headers = buildMap {
            put("Cache-Control", decision.cacheControl)
            put("ETag", decision.etag)
            putAll(CorsPolicy.headers(allowedOrigins, requestOrigin))
        }
        // Always 200. Conditional GET (304) is intentionally not implemented: `WebResourceResponse`
        // rejects 3xx (`statusCode can't be in the [300, 399] range`), so a 304 can't be returned
        // here. The bandwidth win comes from `Cache-Control: max-age` — WebView serves from its
        // cache without revalidating within the window. See `ResourceCachePolicy`.
        val body: InputStream = when (val data = result.data) {
            is ResourceData.Bytes -> ByteArrayInputStream(data.bytes)
            is ResourceData.Stream -> data.open()
        }
        return WebResourceResponse(mimeType, encoding, 200, "OK", headers, body)
    }

    override fun buildFailure(result: EngineResult.Failure): WebResourceResponse? = null
}
