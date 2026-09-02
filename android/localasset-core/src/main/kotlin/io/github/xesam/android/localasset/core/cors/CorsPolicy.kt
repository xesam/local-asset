package io.github.xesam.android.localasset.core.cors

/**
 * Platform-agnostic CORS decision so Android, iOS and HarmonyOS emit identical headers for the same
 * (allow-list, request `Origin`) pair. Pinned tri-platform by
 * `docs/compatibility-fixtures/cors-headers.json`.
 *
 * ## Why the default emits nothing
 *
 * A `local-asset://` response is cross-origin to any `https://` page (and to any other custom
 * scheme), so `Access-Control-Allow-Origin: *` makes the bytes readable by **every** origin loaded
 * in that WebView — including a third-party iframe or an injected script. That is fatal on the
 * Handle path specifically: its access control is a capability token carried in the URL path
 * (design.md §5.4), and URL paths leak through `document.referrer`, the `Referer` header on
 * outbound requests, and `performance.getEntriesByType('resource')`. Wildcard CORS turns any such
 * leak directly into readable bytes.
 *
 * `<img>`, `<link>`, `<script>` and `<video>` do not consult CORS at all, so the default of "no CORS
 * headers" still serves the common embedding cases. Only `fetch()`/`XMLHttpRequest` need a header,
 * and those callers know their own origin — hence the opt-in allow-list.
 */
object CorsPolicy {
    /** Membership value that restores blanket `Access-Control-Allow-Origin: *`. */
    const val ALLOW_ANY_ORIGIN = "*"

    private const val ALLOW_ORIGIN = "Access-Control-Allow-Origin"
    private const val ALLOW_METHODS = "Access-Control-Allow-Methods"
    private const val METHODS = "GET, OPTIONS"

    /**
     * @param allowedOrigins empty = emit no CORS headers; containing [ALLOW_ANY_ORIGIN] = wildcard;
     *   otherwise an exact-match allow-list of origins (`scheme://host[:port]`, no trailing slash).
     * @param requestOrigin the request's `Origin` header, or null when absent (a same-origin or
     *   non-CORS request — browsers only send it for CORS and non-GET).
     */
    fun headers(allowedOrigins: Set<String>, requestOrigin: String?): Map<String, String> = when {
        allowedOrigins.isEmpty() -> emptyMap()
        allowedOrigins.contains(ALLOW_ANY_ORIGIN) -> mapOf(
            ALLOW_ORIGIN to ALLOW_ANY_ORIGIN,
            ALLOW_METHODS to METHODS,
        )
        requestOrigin != null && allowedOrigins.contains(requestOrigin) -> mapOf(
            ALLOW_ORIGIN to requestOrigin,
            ALLOW_METHODS to METHODS,
            // The response varies by request Origin, so a cache keyed on URL alone would serve one
            // origin's allow-header to another.
            "Vary" to "Origin",
        )
        else -> emptyMap()
    }
}
