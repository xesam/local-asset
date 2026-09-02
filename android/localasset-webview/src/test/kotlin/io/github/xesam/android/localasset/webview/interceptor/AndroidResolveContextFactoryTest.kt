package io.github.xesam.android.localasset.webview.interceptor

import android.net.Uri
import android.webkit.WebResourceRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
class AndroidResolveContextFactoryTest {
    @Test
    fun injects_engine_scope_into_context() {
        val factory = AndroidResolveContextFactory("sample-engine")

        val context = factory.create()

        assertEquals("sample-engine", context.engineScope)
    }

    @Test
    fun injects_all_four_scopes_into_context() {
        val factory = AndroidResolveContextFactory(
            engineScope = "engine-1",
            callerScope = "caller-1",
            pageScope = "page-1",
            sessionScope = "session-1",
        )

        val context = factory.create()

        assertEquals("engine-1", context.engineScope)
        assertEquals("caller-1", context.callerScope)
        assertEquals("page-1", context.pageScope)
        assertEquals("session-1", context.sessionScope)
    }

    @Test
    fun publishes_request_headers_under_prefix_lowercased() {
        val factory = AndroidResolveContextFactory()

        val context = factory.create(
            fakeRequest(headers = mapOf("Origin" to "https://app.example.com", "Referer" to "https://app.example.com/p")),
        )

        assertEquals(
            "https://app.example.com",
            context.requestMetadata[ResolveContext.REQUEST_HEADER_PREFIX + "origin"],
        )
        assertEquals("https://app.example.com", context.requestHeader("Origin"))
        assertEquals("https://app.example.com", context.requestHeader("origin"))
        assertEquals("https://app.example.com/p", context.requestHeader("REFERER"))
    }

    @Test
    fun header_lookup_returns_null_when_no_request_is_available() {
        assertNull(AndroidResolveContextFactory().create().requestHeader("Origin"))
    }

    private fun fakeRequest(headers: Map<String, String>): WebResourceRequest =
        object : WebResourceRequest {
            override fun getUrl(): Uri = Uri.parse("local-asset://demo/static/app.js")
            override fun isForMainFrame(): Boolean = false
            override fun isRedirect(): Boolean = false
            override fun hasGesture(): Boolean = false
            override fun getMethod(): String = "GET"
            override fun getRequestHeaders(): Map<String, String> = headers
        }
}
