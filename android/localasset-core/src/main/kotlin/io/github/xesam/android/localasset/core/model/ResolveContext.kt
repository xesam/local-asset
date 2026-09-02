package io.github.xesam.android.localasset.core.model

data class ResolveContext(
    val engineScope: String? = null,
    val callerScope: String? = null,
    val pageScope: String? = null,
    val sessionScope: String? = null,
    val requestMetadata: Map<String, String> = emptyMap(),
) {
    /**
     * Reads a request header captured by the platform bridge, case-insensitively. Returns null when
     * the bridge captured no headers (native callers, or the deprecated URL-only
     * `shouldInterceptRequest` overload) — a `Policy` that gates on `Origin` must therefore decide
     * what "absent" means rather than assuming the header was empty.
     */
    fun requestHeader(name: String): String? = requestMetadata[REQUEST_HEADER_PREFIX + name.lowercase()]

    companion object {
        /**
         * Key prefix under which platform bridges publish request headers into [requestMetadata],
         * with the header name lowercased (`header.origin`, `header.referer`, ...). Shared across
         * Android/iOS/HarmonyOS so a `Policy` is portable.
         */
        const val REQUEST_HEADER_PREFIX = "header."
    }
}
