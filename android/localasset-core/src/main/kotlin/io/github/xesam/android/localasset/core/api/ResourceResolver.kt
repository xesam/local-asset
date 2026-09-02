package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

fun interface ResourceResolver {
    fun resolve(request: AssetRequest, context: ResolveContext): ResolverResult
}

sealed interface ResolverResult {
    data class Hit(val descriptor: ResourceDescriptor) : ResolverResult
    data object Skip : ResolverResult
    data class Failure(
        val category: ResourceErrorCategory,
        val reason: String,
    ) : ResolverResult
}
