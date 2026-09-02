package io.github.xesam.android.localasset.webview.response

import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.cors.CorsPolicy
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
class DefaultWebViewResponseBuilderTest {
    @Test
    fun success_response_builds_web_resource_response() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "asset-1",
                namespace = "demo",
                type = ResourceType.STATIC,
                source = ResourceSource.Bytes(byteArrayOf(1)),
                mimeType = "image/png",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
            data = ResourceData.Bytes(byteArrayOf(1, 2, 3), "image/png"),
        )

        val response = builder.build(result)

        assertNotNull(response)
        assertEquals("image/png", response.mimeType)
        assertEquals(200, response.statusCode)
        assertEquals("OK", response.reasonPhrase)
    }

    @Test
    fun success_response_sets_utf8_encoding_for_text_content() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "asset-1",
                namespace = "demo",
                type = ResourceType.STATIC,
                source = ResourceSource.Bytes("hello".encodeToByteArray()),
                mimeType = "text/html",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
            data = ResourceData.Bytes("hello".encodeToByteArray(), "text/html"),
        )

        val response = builder.build(result)

        assertNotNull(response)
        assertEquals("utf-8", response.encoding)
    }

    @Test
    fun success_response_sets_null_encoding_for_binary_content() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "asset-1",
                namespace = "demo",
                type = ResourceType.STATIC,
                source = ResourceSource.Bytes(byteArrayOf(1)),
                mimeType = "image/png",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
            data = ResourceData.Bytes(byteArrayOf(1, 2, 3), "image/png"),
        )

        val response = builder.build(result)

        assertNotNull(response)
        assertNull(response.encoding)
    }

    @Test
    fun success_response_omits_cors_headers_by_default() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "asset-1",
                namespace = "demo",
                type = ResourceType.STATIC,
                source = ResourceSource.Bytes(byteArrayOf(1)),
                mimeType = "application/json",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
            data = ResourceData.Bytes("{}".encodeToByteArray(), "application/json"),
        )

        val response = builder.build(result, requestOrigin = "https://app.example.com")

        assertNotNull(response)
        assertNull(response.responseHeaders["Access-Control-Allow-Origin"])
        assertNull(response.responseHeaders["Access-Control-Allow-Methods"])
        // STATIC → cacheable; ETag derived from id + byte size ("asset-1-1").
        assertEquals("public, max-age=86400", response.responseHeaders["Cache-Control"])
        assertEquals("\"asset-1-1\"", response.responseHeaders["ETag"])
    }

    @Test
    fun allow_listed_origin_is_echoed_with_vary() {
        val builder = DefaultWebViewResponseBuilder(allowedOrigins = setOf("https://app.example.com"))
        val response = builder.build(jsonSuccess(), requestOrigin = "https://app.example.com")

        assertEquals("https://app.example.com", response.responseHeaders["Access-Control-Allow-Origin"])
        assertEquals("GET, OPTIONS", response.responseHeaders["Access-Control-Allow-Methods"])
        assertEquals("Origin", response.responseHeaders["Vary"])
    }

    @Test
    fun origin_outside_allow_list_gets_no_cors_headers() {
        val builder = DefaultWebViewResponseBuilder(allowedOrigins = setOf("https://app.example.com"))
        val response = builder.build(jsonSuccess(), requestOrigin = "https://evil.example.com")

        assertNull(response.responseHeaders["Access-Control-Allow-Origin"])
    }

    @Test
    fun wildcard_membership_restores_blanket_cors() {
        val builder = DefaultWebViewResponseBuilder(allowedOrigins = setOf(CorsPolicy.ALLOW_ANY_ORIGIN))
        val response = builder.build(jsonSuccess())

        assertEquals("*", response.responseHeaders["Access-Control-Allow-Origin"])
        assertEquals("GET, OPTIONS", response.responseHeaders["Access-Control-Allow-Methods"])
    }

    private fun jsonSuccess() = EngineResult.Success(
        descriptor = ResourceDescriptor(
            id = "asset-1", namespace = "demo", type = ResourceType.STATIC,
            source = ResourceSource.Bytes(byteArrayOf(1)),
            mimeType = "application/json", createdAtMillis = 0L, ttlMillis = null, scope = null,
        ),
        data = ResourceData.Bytes("{}".encodeToByteArray(), "application/json"),
    )

    @Test
    fun dynamic_resource_uses_no_store_cache_control() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "d-1", namespace = "demo", type = ResourceType.DYNAMIC,
                source = ResourceSource.Bytes("{}".encodeToByteArray()),
                mimeType = "application/json", createdAtMillis = 0L, ttlMillis = null, scope = null,
            ),
            data = ResourceData.Bytes("{}".encodeToByteArray(), "application/json"),
        )

        val response = builder.build(result)

        assertEquals("no-store", response.responseHeaders["Cache-Control"])
        assertEquals(200, response.statusCode)
    }

    @Test
    fun max_age_is_configurable() {
        val builder = DefaultWebViewResponseBuilder(maxAgeSeconds = 60)
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "asset-1", namespace = "demo", type = ResourceType.STATIC,
                source = ResourceSource.Bytes(byteArrayOf(1)),
                mimeType = "application/json", createdAtMillis = 0L, ttlMillis = null, scope = null,
            ),
            data = ResourceData.Bytes("{}".encodeToByteArray(), "application/json"),
        )

        val response = builder.build(result)

        assertEquals("public, max-age=60", response.responseHeaders["Cache-Control"])
    }

    @Test
    fun failure_response_returns_null() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Failure(
            category = io.github.xesam.android.localasset.core.error.ResourceErrorCategory.RESOLUTION_ERROR,
            reason = "not found",
        )

        val response = builder.buildFailure(result)

        assertNull(response)
    }

    @Test
    fun sets_utf8_for_application_json() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "a", namespace = "d", type = ResourceType.STATIC,
                source = ResourceSource.Bytes("{}".encodeToByteArray()),
                mimeType = "application/json", createdAtMillis = 0L, ttlMillis = null, scope = null,
            ),
            data = ResourceData.Bytes("{}".encodeToByteArray(), "application/json"),
        )
        assertEquals("utf-8", builder.build(result).encoding)
    }

    @Test
    fun sets_utf8_for_application_javascript() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "a", namespace = "d", type = ResourceType.STATIC,
                source = ResourceSource.Bytes("x".encodeToByteArray()),
                mimeType = "application/javascript", createdAtMillis = 0L, ttlMillis = null, scope = null,
            ),
            data = ResourceData.Bytes("x".encodeToByteArray(), "application/javascript"),
        )
        assertEquals("utf-8", builder.build(result).encoding)
    }

    @Test
    fun sets_utf8_for_application_ld_json() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "a", namespace = "d", type = ResourceType.STATIC,
                source = ResourceSource.Bytes("{}".encodeToByteArray()),
                mimeType = "application/ld+json", createdAtMillis = 0L, ttlMillis = null, scope = null,
            ),
            data = ResourceData.Bytes("{}".encodeToByteArray(), "application/ld+json"),
        )
        assertEquals("utf-8", builder.build(result).encoding)
    }

    @Test
    fun sets_utf8_for_image_svg_xml() {
        val builder = DefaultWebViewResponseBuilder()
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "a", namespace = "d", type = ResourceType.STATIC,
                source = ResourceSource.Bytes("<svg/>".encodeToByteArray()),
                mimeType = "image/svg+xml", createdAtMillis = 0L, ttlMillis = null, scope = null,
            ),
            data = ResourceData.Bytes("<svg/>".encodeToByteArray(), "image/svg+xml"),
        )
        assertEquals("utf-8", builder.build(result).encoding)
    }

    @Test
    fun success_response_streams_body_without_buffering() {
        val builder = DefaultWebViewResponseBuilder()
        val payload = byteArrayOf(1, 2, 3, 4, 5)
        val result = EngineResult.Success(
            descriptor = ResourceDescriptor(
                id = "stream-1", namespace = "demo", type = ResourceType.STATIC,
                source = ResourceSource.Stream { java.io.ByteArrayInputStream(payload) },
                mimeType = "application/octet-stream", createdAtMillis = 0L, ttlMillis = null, scope = null,
            ),
            data = ResourceData.Stream({ java.io.ByteArrayInputStream(payload) }, "application/octet-stream"),
        )

        val response = builder.build(result)

        assertNotNull(response)
        assertEquals("application/octet-stream", response.mimeType)
        assertEquals(200, response.statusCode)
        // Body must flow straight from the factory into the response stream.
        assertContentEquals(payload, response.data.readBytes())
    }
}
