package io.github.xesam.android.localasset.core.internal

import io.github.xesam.android.localasset.core.api.EngineObserver
import io.github.xesam.android.localasset.core.api.EngineStageEvent
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext

class ResolverChain(
    private val resolvers: List<ResourceResolver>,
) {
    fun resolve(
        request: AssetRequest,
        context: ResolveContext,
        observer: EngineObserver? = null,
    ): ResolverResult {
        resolvers.forEachIndexed { index, resolver ->
            val result = resolver.resolve(request, context)
            observer?.onStage(
                EngineStageEvent(
                    stage = EngineObserver.STAGE_RESOLVE,
                    request = request,
                    resolverIndex = index,
                    resolver = resolver,
                    resolverResult = result,
                    descriptor = (result as? ResolverResult.Hit)?.descriptor,
                ),
            )
            when (result) {
                is ResolverResult.Hit -> return result
                is ResolverResult.Failure -> return result
                ResolverResult.Skip -> Unit
            }
        }
        return ResolverResult.Skip
    }
}
