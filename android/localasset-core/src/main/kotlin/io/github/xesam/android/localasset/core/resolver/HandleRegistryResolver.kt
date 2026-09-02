package io.github.xesam.android.localasset.core.resolver

import io.github.xesam.android.localasset.core.api.HandleRegistry
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceType

class HandleRegistryResolver(
    private val handleRegistry: HandleRegistry,
) : ResourceResolver {
    override fun resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
        val record = handleRegistry.resolveFromRequest(request) ?: return ResolverResult.Skip
        // TTL is owned by [HandleRegistry.resolve] (relative to the handle's own creation time).
        // The descriptor's [createdAtMillis] is a placeholder (0L) for handle-backed resources, so
        // forwarding [record.ttlMillis] here would make [DefaultPolicy.postCheck]'s absolute-time
        // TTL check (`createdAtMillis + ttl <= now`) always evaluate expired — the handle registry
        // already expires handles on lookup, so we must NOT re-enforce TTL at postCheck. Pass null
        // so postCheck skips the TTL branch entirely. See design.md §3.3 / §5.2.
        return ResolverResult.Hit(
            ResourceDescriptor(
                id = record.fileName,
                namespace = request.namespace,
                type = ResourceType.DYNAMIC,
                // Forward the handle's source verbatim: a Bytes handle loads from memory, a FilePath
                // handle is read lazily by FileResourceLoader — and postCheck's shared file-root gate
                // still applies to a FilePath handle (design.md §5.4 / §5.5), so a file-backed
                // capability can only point at a path under an allowed root.
                source = record.source,
                mimeType = record.mimeType,
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
        )
    }
}
