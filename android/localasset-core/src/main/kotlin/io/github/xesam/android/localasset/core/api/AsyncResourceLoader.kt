package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import kotlinx.coroutines.runBlocking

/**
 * A [TypedResourceLoader] whose data source is intrinsically suspending — e.g. a network pre-fetch
 * cache, a Room/DataStore query, or any IO that is naturally coroutine-based.
 *
 * The engine pipeline is synchronous (WebView bridges are synchronous: Android
 * `shouldInterceptRequest` returns a `WebResourceResponse` inline; the loader runs on a background
 * thread already). This interface bridges that gap additively and non-breakingly: implement only
 * [canLoad] and [loadAsync], and the inherited [loadTyped] runs [loadAsync] under [runBlocking] so
 * the sync pipeline can drive an async source (design.md §9.3 — the documented workaround, now a
 * first-class, typed extension point instead of per-callers `runBlocking` boilerplate).
 *
 * Caveat: [runBlocking] blocks the calling (background) thread until [loadAsync] completes. Keep
 * [loadAsync] free of main-thread hops; for truly long sources, prefer a sync loader that owns its
 * own thread/executor. Do NOT call from the main thread.
 */
public interface AsyncResourceLoader : TypedResourceLoader {
    suspend fun loadAsync(descriptor: ResourceDescriptor): ResourceData

    override fun loadTyped(descriptor: ResourceDescriptor): ResourceData = runBlocking { loadAsync(descriptor) }
}
