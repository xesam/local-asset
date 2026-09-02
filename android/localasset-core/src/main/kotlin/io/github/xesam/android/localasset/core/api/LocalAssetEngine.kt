package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

interface LocalAssetEngine {
    fun resolve(
        url: String,
        context: ResolveContext = ResolveContext(),
    ): EngineResult

    fun resolve(request: AssetRequest, context: ResolveContext = ResolveContext()): EngineResult
}

sealed interface EngineResult {
    data class Success(
        val descriptor: ResourceDescriptor,
        val data: ResourceData,
    ) : EngineResult

    data class Failure(
        val category: ResourceErrorCategory,
        val reason: String,
        val stage: String? = null,
    ) : EngineResult
}
