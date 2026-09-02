package io.github.xesam.android.localasset.webview.api

import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.github.xesam.android.localasset.core.api.LocalAsset
import io.github.xesam.android.localasset.core.api.LocalAssetEngine
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import io.github.xesam.android.localasset.webview.interceptor.AndroidResolveContextFactory
import io.github.xesam.android.localasset.webview.interceptor.WebViewAssetInterceptor
import io.github.xesam.android.localasset.webview.response.DefaultWebViewResponseBuilder
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class LocalAssetWebViewClientTest {
    @Test
    fun convenience_constructor_wires_up_interceptor_from_localAsset() {
        val localAsset = LocalAsset.Builder().build()
        localAsset.register(
            ResourceDescriptor(
                id = "logo",
                namespace = "image",
                type = ResourceType.DYNAMIC,
                source = ResourceSource.Bytes("hello".encodeToByteArray()),
                mimeType = "text/plain",
                createdAtMillis = 0L,
            ),
        )

        val client = LocalAssetWebViewClient(localAsset = localAsset)
        val response = client.shouldInterceptRequest(null, "local-asset://image/logo")

        assertNotNull(response)
    }

    @Test
    fun forwards_page_finished_to_delegate() {
        val delegate = RecordingWebViewClient()
        val client = LocalAssetWebViewClient(
            delegate = delegate,
            interceptor = testInterceptor(),
        )

        client.onPageFinished(null, "local-asset://demo/static/index.html")

        assertTrue(delegate.pageFinishedCalled)
    }

    @Test
    fun forwards_received_error_to_delegate() {
        val delegate = RecordingWebViewClient()
        val client = LocalAssetWebViewClient(
            delegate = delegate,
            interceptor = testInterceptor(),
        )

        client.onReceivedError(null, null, null)

        assertTrue(delegate.receivedErrorCalled)
    }

    private fun testInterceptor(): WebViewAssetInterceptor {
        return WebViewAssetInterceptor(
            engine = object : LocalAssetEngine {
                override fun resolve(url: String, context: ResolveContext): EngineResult {
                    return EngineResult.Failure(ResourceErrorCategory.RESOLUTION_ERROR, "miss")
                }

                override fun resolve(request: AssetRequest, context: ResolveContext): EngineResult {
                    return EngineResult.Failure(ResourceErrorCategory.RESOLUTION_ERROR, "miss")
                }
            },
            responseBuilder = DefaultWebViewResponseBuilder(),
            contextFactory = AndroidResolveContextFactory(),
        )
    }

    private class RecordingWebViewClient : WebViewClient() {
        var pageFinishedCalled = false
        var receivedErrorCalled = false

        override fun onPageFinished(view: WebView?, url: String?) {
            pageFinishedCalled = true
        }

        override fun onReceivedError(
            view: WebView?,
            request: WebResourceRequest?,
            error: WebResourceError?,
        ) {
            receivedErrorCalled = true
        }
    }
}
