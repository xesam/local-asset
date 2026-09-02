package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResourceHandle
import io.github.xesam.android.localasset.core.model.ResourceHandleRecord

interface HandleRegistry {
    fun register(handle: ResourceHandle): String

    /**
     * Reconstructs the Handle-Backed URI from [request] and looks it up via [resolve].
     *
     * Contract: the reconstructed URI string MUST be byte-identical to the one returned by
     * [register] — same scheme, host (namespace), path, query encoding, and fragment. The default
     * implementation rebuilds the URI from [AssetRequest] fields with a fixed `k=v` join order
     * (the request's query-map iteration order), so a custom [HandleRegistry] that mints URIs
     * with a different query encoding/ordering must override this to reproduce the exact string
     * it registered, otherwise lookup silently misses (`null` → resolver `Skip`).
     *
     * Reserved query param [CACHE_BUST_PARAM]: stripped before reconstruction. It exists so
     * callers can cache-bust a handle URI (append `?_la_cb=<changing>` to defeat WebView caches
     * that serve a stale copy on same-URL re-fetch and skip the scheme handler entirely) without
     * breaking lookup — the registered URI has no query, so the capability identity is the path.
     * Non-`_la_cb` query keys remain part of the identity.
     */
    fun resolveFromRequest(request: AssetRequest): ResourceHandleRecord? {
        val path = request.path ?: "/${request.identifier.orEmpty()}"
        val uri = buildString {
            append(request.scheme)
            append("://")
            append(request.namespace)
            append(path)
            val identityQuery = request.query.filterKeys { it != CACHE_BUST_PARAM }
            if (identityQuery.isNotEmpty()) {
                append('?')
                append(identityQuery.entries.joinToString("&") { (k, v) -> "$k=$v" })
            }
            request.fragment?.let { append('#').append(it) }
        }
        return runCatching { resolve(uri) }.getOrNull()
    }

    companion object {
        /**
         * Reserved cache-bust query parameter, stripped by [resolveFromRequest] so it never
         * participates in handle identity. See [resolveFromRequest].
         */
        const val CACHE_BUST_PARAM = "_la_cb"

        /**
         * Default host (namespace) under which handle URIs are minted:
         * `local-asset://<DEFAULT_HANDLE_HOST>/handles/<token>/<file>`. The Handle path is
         * authorized by the capability token, not by the namespace, so [DefaultPolicy] exempts
         * this namespace from its namespace allow-list — otherwise declaring
         * `addAllowedNamespace("foo")` would silently reject every handle URI. A custom
         * [HandleRegistry] minting under a different host must pass that host to [DefaultPolicy]'s
         * `handleHost` so the exemption still applies.
         */
        const val DEFAULT_HANDLE_HOST = "handles.localasset.local"
    }

    /**
     * Resolves a Handle-Backed URI back to the [ResourceHandle] it was registered from.
     *
     * Throws rather than returning a sealed result (contrast with
     * [ResourceRegistry.lookup][io.github.xesam.android.localasset.core.api.ResourceRegistry.lookup]):
     * a resourceUri is typically round-tripped through a WebView/native boundary as an opaque
     * capability, so an unknown-or-expired URI here means the caller is holding an invalid
     * credential — an exceptional condition — rather than a normal "not registered yet" branch a
     * resolver probes through.
     */
    @Throws(ResourceException::class)
    fun resolve(resourceUri: String): ResourceHandleRecord

    fun remove(resourceUri: String)

    fun cleanup(nowMillis: Long = System.currentTimeMillis()) {
        // default no-op
    }
}
