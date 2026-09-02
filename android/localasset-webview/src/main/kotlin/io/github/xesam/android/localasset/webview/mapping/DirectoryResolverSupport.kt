package io.github.xesam.android.localasset.webview.mapping

import android.webkit.MimeTypeMap
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType

internal fun guessMimeType(path: String): String? {
    val extension = path.substringAfterLast('.', "").lowercase()
    return if (extension.isBlank()) null
    else runCatching { MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) }.getOrNull()
}

internal fun normalizePathPrefix(value: String): String {
    val normalized = if (value.startsWith("/")) value else "/$value"
    return normalized.removeSuffix("/")
}

internal fun matchesPrefix(path: String, prefix: String): Boolean =
    path == prefix || path.startsWith("$prefix/")

/**
 * Shared `host + pathPrefix -> relativePath` routing skeleton for directory-backed resolvers.
 * Subclasses only need to turn a validated, traversal-safe `relativePath` into a [ResourceSource].
 *
 * Public (not `internal`): [AssetDirectoryResolver] and [FileDirectoryResolver] — both public,
 * constructed directly by consumers outside this module (e.g. the sample app) — extend it, and
 * Kotlin does not allow a public class to expose an `internal` supertype.
 */
abstract class BaseDirectoryResolver(
    private val host: String,
    pathPrefix: String,
) : ResourceResolver {
    private val normalizedPathPrefix = normalizePathPrefix(pathPrefix)

    final override fun resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
        if (request.namespace != host) {
            return ResolverResult.Skip
        }
        val path = request.path ?: return ResolverResult.Skip
        if (!matchesPrefix(path, normalizedPathPrefix)) {
            return ResolverResult.Skip
        }
        val relativePath = path.removePrefix(normalizedPathPrefix)
            .trimStart('/')
            .takeIf { it.isNotBlank() && !it.contains("..") }
            ?: return ResolverResult.Skip
        val source = resolveSource(relativePath) ?: return ResolverResult.Skip
        return ResolverResult.Hit(
            ResourceDescriptor(
                id = "$host:$path",
                namespace = host,
                type = ResourceType.STATIC,
                source = source,
                mimeType = guessMimeType(relativePath),
                createdAtMillis = System.currentTimeMillis(),
                ttlMillis = null,
                scope = null,
            ),
        )
    }

    /** Returns the resource source for [relativePath], or null if it cannot be loaded. */
    protected abstract fun resolveSource(relativePath: String): ResourceSource?
}
