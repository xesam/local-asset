package io.github.xesam.android.localasset.webview.mapping

import android.content.Context
import io.github.xesam.android.localasset.core.model.ResourceSource
import java.io.InputStream

/**
 * Resolves `local-asset://` URLs to Android `assets/` directory files.
 *
 * Streams the asset rather than buffering it: [resolveSource] probes that the asset is openable
 * (open + immediate close, zero buffer) so a missing/unreadable asset still surfaces as a `Skip`
 * at the RESOLVE stage, then returns a [ResourceSource.Stream] factory. The factory is re-openable;
 * the platform response layer ([`DefaultWebViewResponseBuilder`]) opens it fresh per response and
 * hands the `InputStream` straight to `WebResourceResponse`, so the asset bytes are never retained
 * in memory. `BaseDirectoryResolver` already rejects `..` traversal before this method runs.
 *
 * The asset-opening concern is captured as the function type `(String) -> InputStream` so the
 * resolver is unit-testable without an Android `AssetManager`; the public [Context] constructor
 * supplies that function from `appContext.assets.open`.
 */
class AssetDirectoryResolver internal constructor(
    host: String,
    pathPrefix: String,
    private val assetDirectory: String,
    private val openAsset: (String) -> InputStream,
) : BaseDirectoryResolver(host, pathPrefix) {

    constructor(
        appContext: Context,
        host: String,
        pathPrefix: String,
        assetDirectory: String,
    ) : this(
        host = host,
        pathPrefix = pathPrefix,
        assetDirectory = assetDirectory,
        // Capture only the app-scoped AssetManager (not the whole Context) so a caller that passes
        // an Activity context can't leak it through the descriptor's factory closure. Assets read
        // identically from the application context; this just normalizes to the app-level manager.
        openAsset = appContext.applicationContext.assets.let { assets -> { path -> assets.open(path) } },
    )

    override fun resolveSource(relativePath: String): ResourceSource? {
        val assetPath = assetDirectory.trim('/').let {
            if (it.isBlank()) relativePath else "$it/$relativePath"
        }
        // Probe: confirm the asset is openable right now without buffering it. A missing or
        // unreadable asset throws from open()/use {} and returns null -> BaseDirectoryResolver
        // turns that into ResolverResult.Skip at the RESOLVE stage (preserves error semantics).
        runCatching { openAsset(assetPath).use { /* open + close, zero read */ } }
            .getOrElse { return null }
        // Re-openable factory: each call opens a fresh stream. `openAsset` captures only the
        // AssetManager (see the constructor), so the descriptor pins no Android Context.
        return ResourceSource.Stream { openAsset(assetPath) }
    }
}
