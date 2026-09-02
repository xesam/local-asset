package io.github.xesam.android.localasset.core.cache

import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import java.io.File

/**
 * The cache headers for a resolved resource, computed once and attached by the platform response
 * layer. [cacheControl] is `Cache-Control`, [etag] is `ETag`.
 */
data class CacheDecision(
    val cacheControl: String,
    val etag: String,
)

/**
 * Platform-agnostic cache policy so Android and iOS emit identical headers for the same descriptor
 * (design.md §7). Pure Kotlin: derives `Cache-Control` from the resource type and an `ETag` from
 * the descriptor.
 *
 * - STATIC resources are immutable bundle assets → cacheable with `max-age`. DYNAMIC resources are
 *   registry-registered and may change per resolve → `no-store`.
 * - The ETag is built from `descriptor.id` plus a cheap, content-reflecting signal so it is stable
 *   across resolves but changes when the underlying bytes change: file `lastModified` for
 *   `FilePath`, byte size for `Bytes`, and id-only (weak) for `Stream` (a factory can't be drained
 *   for a hash without defeating the point of streaming).
 *
 * Conditional GET (304) is intentionally NOT implemented: the default platform response builders
 * always return 200 with these headers, so a 304 is never produced. The `ETag` is still emitted
 * as metadata; within `max-age`, WebView serves from its cache without revalidating, which is
 * where the bandwidth saving actually comes from.
 *
 * App-update caveat: for `Stream`-backed bundle assets the ETag is id-only and does NOT change
 * across app updates, so WebView may serve a stale cached copy for up to `maxAgeSeconds` after an
 * update. Ship immutable bundles, lower `maxAgeSeconds`, or use versioned URLs if you mutate bundle
 * assets between releases.
 */
object ResourceCachePolicy {
    const val DEFAULT_MAX_AGE_SECONDS = 86400

    fun decide(
        descriptor: ResourceDescriptor,
        maxAgeSeconds: Int = DEFAULT_MAX_AGE_SECONDS,
    ): CacheDecision {
        val cacheControl = if (descriptor.type == ResourceType.STATIC) {
            "public, max-age=$maxAgeSeconds"
        } else {
            "no-store"
        }
        return CacheDecision(cacheControl = cacheControl, etag = computeEtag(descriptor))
    }

    private fun computeEtag(descriptor: ResourceDescriptor): String = when (val source = descriptor.source) {
        is ResourceSource.FilePath -> "\"${descriptor.id}-${File(source.value).lastModified()}\""
        is ResourceSource.Bytes -> "\"${descriptor.id}-${source.value.size}\""
        is ResourceSource.Stream -> "W/\"${descriptor.id}\""
    }
}
