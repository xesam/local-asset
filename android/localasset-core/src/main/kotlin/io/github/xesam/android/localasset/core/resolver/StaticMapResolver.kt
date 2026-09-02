package io.github.xesam.android.localasset.core.resolver

import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

class StaticMapResolver(
    private val mappings: Map<String, ResourceDescriptor>,
) : ResourceResolver {
    override fun resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
        val path = request.path ?: return ResolverResult.Skip
        val descriptor = mappings["${request.namespace}:$path"] ?: return ResolverResult.Skip
        return ResolverResult.Hit(descriptor)
    }
}
