package io.github.xesam.android.localasset.core.resolver

import io.github.xesam.android.localasset.core.api.RegistryLookupResult
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceRegistry
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext

class RegistryResolver(
    private val registry: ResourceRegistry,
) : ResourceResolver {
    override fun resolve(request: AssetRequest, context: ResolveContext): ResolverResult {
        val id = request.identifier ?: request.query["id"] ?: return ResolverResult.Skip
        return when (val result = registry.lookup(id)) {
            is RegistryLookupResult.Hit -> ResolverResult.Hit(result.descriptor)
            RegistryLookupResult.Missing -> ResolverResult.Skip
            RegistryLookupResult.Expired -> ResolverResult.Failure(
                category = ResourceErrorCategory.RESOLUTION_ERROR,
                reason = "resource expired",
            )
        }
    }
}
