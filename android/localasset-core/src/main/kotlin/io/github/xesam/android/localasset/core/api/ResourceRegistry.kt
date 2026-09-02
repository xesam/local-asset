package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

/**
 * Stores caller-supplied [ResourceDescriptor]s keyed by their own `id` and looked up by
 * [ResolverChain][io.github.xesam.android.localasset.core.internal.ResolverChain] resolvers
 * (e.g. [RegistryResolver][io.github.xesam.android.localasset.core.resolver.RegistryResolver]).
 *
 * [lookup] returns a sealed [RegistryLookupResult] rather than throwing: "missing" and "expired"
 * are expected, everyday outcomes of a resolver probing whether it should handle a request, not
 * exceptional conditions — resolvers branch on them with a plain `when`. Contrast with
 * [HandleRegistry.resolve], which throws: a Handle-Backed URI handed back to native code is
 * closer to a capability/credential, so failing to resolve it is treated as exceptional rather
 * than a normal control-flow branch.
 */
interface ResourceRegistry {
    @Throws(ResourceException::class)
    fun register(descriptor: ResourceDescriptor)

    fun lookup(id: String): RegistryLookupResult

    fun remove(id: String)

    fun cleanup(nowMillis: Long = System.currentTimeMillis())
}

sealed interface RegistryLookupResult {
    data class Hit(val descriptor: ResourceDescriptor) : RegistryLookupResult
    data object Missing : RegistryLookupResult
    data object Expired : RegistryLookupResult
}
