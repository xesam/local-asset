package io.github.xesam.android.localasset.core.engine

import io.github.xesam.android.localasset.core.api.EngineObserver
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.api.EngineStageEvent
import io.github.xesam.android.localasset.core.api.LocalAssetEngine
import io.github.xesam.android.localasset.core.api.Policy
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceLoader
import io.github.xesam.android.localasset.core.api.SchemeAdapter
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.internal.AdapterRegistry
import io.github.xesam.android.localasset.core.internal.ResolverChain
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

class DefaultLocalAssetEngine(
    adapters: List<SchemeAdapter>,
    private val resolverChain: ResolverChain,
    private val policy: Policy,
    private val loader: ResourceLoader,
    private val observer: EngineObserver? = null,
) : LocalAssetEngine {
    private val adapterRegistry = AdapterRegistry(adapters)

    override fun resolve(url: String, context: ResolveContext): EngineResult {
        val request: AssetRequest
        try {
            request = adapterRegistry.select(url).parse(url)
        } catch (e: Exception) {
            return stageFailure(e, EngineObserver.STAGE_ADAPTER_PARSE, request = null,
                defaultCategory = ResourceErrorCategory.PARSE_ERROR, defaultPrefix = "invalid url: ")
        }
        emit(EngineObserver.STAGE_ADAPTER_PARSE, request = request)
        return resolve(request, context)
    }

    override fun resolve(request: AssetRequest, context: ResolveContext): EngineResult {
        try {
            policy.preCheck(request, context)
        } catch (e: Exception) {
            return stageFailure(e, EngineObserver.STAGE_POLICY_PRE, request,
                defaultCategory = ResourceErrorCategory.SECURITY_ERROR, defaultPrefix = "preCheck failed: ")
        }
        emit(EngineObserver.STAGE_POLICY_PRE, request = request)

        val result: ResolverResult
        try {
            result = resolverChain.resolve(request, context, observer)
        } catch (e: Exception) {
            return stageFailure(e, EngineObserver.STAGE_RESOLVE, request,
                defaultCategory = ResourceErrorCategory.RESOLUTION_ERROR, defaultPrefix = "resolver chain failed: ")
        }

        return when (result) {
            is ResolverResult.Hit -> resolveHit(request, result.descriptor, context)
            is ResolverResult.Failure -> {
                val failure = EngineResult.Failure(result.category, result.reason, EngineObserver.STAGE_RESOLVE)
                emit(EngineObserver.STAGE_RESOLVE, request = request, failure = failure)
                failure
            }
            ResolverResult.Skip -> {
                val failure = EngineResult.Failure(
                    ResourceErrorCategory.RESOLUTION_ERROR,
                    "resource not found",
                    EngineObserver.STAGE_RESOLVE,
                )
                emit(EngineObserver.STAGE_RESOLVE, request = request, failure = failure)
                failure
            }
        }
    }

    private fun resolveHit(
        request: AssetRequest,
        descriptor: ResourceDescriptor,
        context: ResolveContext,
    ): EngineResult {
        try {
            policy.postCheck(request, descriptor, context)
        } catch (e: Exception) {
            return stageFailure(e, EngineObserver.STAGE_POLICY_POST, request, descriptor,
                defaultCategory = ResourceErrorCategory.SECURITY_ERROR, defaultPrefix = "postCheck failed: ")
        }
        emit(EngineObserver.STAGE_POLICY_POST, request = request, descriptor = descriptor)

        try {
            val data = loader.load(descriptor)
            emit(EngineObserver.STAGE_LOAD, request = request, descriptor = descriptor)
            emit(EngineObserver.STAGE_COMPLETE, request = request, descriptor = descriptor)
            return EngineResult.Success(descriptor, data)
        } catch (e: Exception) {
            return stageFailure(e, EngineObserver.STAGE_LOAD, request, descriptor,
                defaultCategory = ResourceErrorCategory.LOAD_ERROR, defaultPrefix = "unexpected load failure: ")
        }
    }

    /**
     * Unified error handler for all pipeline stages: extracts [ResourceException] category/stage
     * when present, otherwise wraps with a stage-specific fallback category and prefix; emits the
     * failure event and returns the [EngineResult.Failure].
     *
     * Mirrors the ArkTS `toFailure` + emit pattern and the Swift `emitFailure` pattern, keeping
     * error messages and stage assignments identical across platforms.
     */
    private fun stageFailure(
        error: Exception,
        stage: String,
        request: AssetRequest?,
        descriptor: ResourceDescriptor? = null,
        defaultCategory: ResourceErrorCategory,
        defaultPrefix: String,
    ): EngineResult.Failure {
        val failure = if (error is ResourceException) {
            EngineResult.Failure(error.category, error.message, error.stage ?: stage)
        } else {
            EngineResult.Failure(defaultCategory, "$defaultPrefix${error.message}", stage)
        }
        emit(stage, request, descriptor, failure)
        return failure
    }

    private fun emit(
        stage: String,
        request: AssetRequest?,
        descriptor: ResourceDescriptor? = null,
        failure: EngineResult.Failure? = null,
    ) {
        observer?.onStage(
            EngineStageEvent(
                stage = stage,
                request = request,
                descriptor = descriptor,
                failure = failure,
            ),
        )
    }
}
