package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

interface Policy {
    @Throws(ResourceException::class)
    fun preCheck(request: AssetRequest, context: ResolveContext)

    @Throws(ResourceException::class)
    fun postCheck(
        request: AssetRequest,
        descriptor: ResourceDescriptor,
        context: ResolveContext,
    )
}
