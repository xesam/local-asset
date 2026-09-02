package io.github.xesam.android.localasset.webview.interceptor

import io.github.xesam.android.localasset.core.api.LocalAssetEngine
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.webview.response.DefaultWebViewResponseBuilder
import kotlin.test.Test
import kotlin.test.assertEquals

class WebViewAssetInterceptorTest {
    @Test
    fun returns_null_for_failure_result() {
        val interceptor = WebViewAssetInterceptor(
            engine = object : LocalAssetEngine {
                override fun resolve(url: String, context: ResolveContext): EngineResult =
                    EngineResult.Failure(ResourceErrorCategory.RESOLUTION_ERROR, "miss")

                override fun resolve(request: AssetRequest, context: ResolveContext): EngineResult =
                    EngineResult.Failure(ResourceErrorCategory.RESOLUTION_ERROR, "miss")
            },
            responseBuilder = DefaultWebViewResponseBuilder(),
            contextFactory = AndroidResolveContextFactory(),
        )

        val response = interceptor.intercept("local-asset://demo/missing/resource")

        assertEquals(null, response)
    }

    @Test
    fun invokes_onFailure_callback_for_failure_result() {
        var observed: EngineResult.Failure? = null
        val interceptor = WebViewAssetInterceptor(
            engine = object : LocalAssetEngine {
                override fun resolve(url: String, context: ResolveContext): EngineResult =
                    EngineResult.Failure(ResourceErrorCategory.RESOLUTION_ERROR, "miss")

                override fun resolve(request: AssetRequest, context: ResolveContext): EngineResult =
                    EngineResult.Failure(ResourceErrorCategory.RESOLUTION_ERROR, "miss")
            },
            responseBuilder = DefaultWebViewResponseBuilder(),
            contextFactory = AndroidResolveContextFactory(),
            onFailure = { observed = it },
        )

        interceptor.intercept("local-asset://demo/missing/resource")

        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, observed?.category)
    }
}
