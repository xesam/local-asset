package io.github.xesam.android.localasset.core.model

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ModelContractTest {
    @Test
    fun assetRequest_exposes_required_fields() {
        val request = AssetRequest(
            scheme = "local-asset",
            namespace = "image",
            identifier = "logo",
            path = "/logo",
            query = mapOf("theme" to "dark"),
            fragment = null,
            metadata = emptyMap(),
        )

        assertEquals("local-asset", request.scheme)
        assertEquals("image", request.namespace)
        assertEquals("logo", request.identifier)
        assertEquals("/logo", request.path)
        assertEquals("dark", request.query["theme"])
    }

    @Test
    fun resourceSource_bytes_equality_is_content_based() {
        val a = ResourceSource.Bytes("hello".encodeToByteArray())
        val b = ResourceSource.Bytes("hello".encodeToByteArray())
        val c = ResourceSource.Bytes("world".encodeToByteArray())

        assertTrue(a == b, "two Bytes with identical content must be equal")
        assertEquals(a.hashCode(), b.hashCode(), "equal Bytes must share a hash code")
        assertFalse(a == c, "Bytes with different content must not be equal")
        assertTrue(a != ResourceSource.FilePath("hello"), "Bytes must not equal FilePath")
    }

    @Test
    fun resourceHandle_equality_is_content_based() {
        val a = ResourceHandle(
            source = ResourceSource.Bytes("hello".encodeToByteArray()),
            fileName = "a.png",
            mimeType = "image/png",
            metadata = mapOf("k" to "v"),
            ttlMillis = 1000L,
        )
        val b = ResourceHandle(
            source = ResourceSource.Bytes("hello".encodeToByteArray()),
            fileName = "a.png",
            mimeType = "image/png",
            metadata = mapOf("k" to "v"),
            ttlMillis = 1000L,
        )
        val differentBytes = ResourceHandle(ResourceSource.Bytes("world".encodeToByteArray()), "a.png", "image/png")

        assertTrue(a == b, "two ResourceHandles with identical content must be equal")
        assertEquals(a.hashCode(), b.hashCode(), "equal ResourceHandles must share a hash code")
        assertFalse(a == differentBytes, "different bytes must not be equal")
        assertFalse(
            a == ResourceHandle(ResourceSource.Bytes("hello".encodeToByteArray()), "a.png", "image/png", mapOf("k" to "other")),
            "different metadata must not be equal",
        )
    }

    @Test
    fun resourceHandleRecord_equality_is_content_based() {
        val a = ResourceHandleRecord(
            resourceUri = "local-asset://h/handles/t/a.png",
            source = ResourceSource.Bytes("hello".encodeToByteArray()),
            fileName = "a.png",
            mimeType = "image/png",
            size = 5L,
            metadata = mapOf("k" to "v"),
            ttlMillis = 1000L,
        )
        val b = ResourceHandleRecord(
            resourceUri = "local-asset://h/handles/t/a.png",
            source = ResourceSource.Bytes("hello".encodeToByteArray()),
            fileName = "a.png",
            mimeType = "image/png",
            size = 5L,
            metadata = mapOf("k" to "v"),
            ttlMillis = 1000L,
        )
        val differentBytes = ResourceHandleRecord(
            resourceUri = "local-asset://h/handles/t/a.png",
            source = ResourceSource.Bytes("world".encodeToByteArray()),
            fileName = "a.png",
            mimeType = "image/png",
            size = 5L,
            metadata = emptyMap(),
        )

        assertTrue(a == b, "two ResourceHandleRecords with identical content must be equal")
        assertEquals(a.hashCode(), b.hashCode(), "equal ResourceHandleRecords must share a hash code")
        assertFalse(a == differentBytes, "different bytes must not be equal")
    }

    @Test
    fun resourceData_bytes_equality_is_content_based() {
        val a = ResourceData.Bytes("hello".encodeToByteArray(), "text/plain")
        val b = ResourceData.Bytes("hello".encodeToByteArray(), "text/plain")
        val c = ResourceData.Bytes("hello".encodeToByteArray(), "text/html")

        assertTrue(a == b)
        assertEquals(a.hashCode(), b.hashCode())
        assertFalse(a == c, "different mimeType must not be equal")
        assertFalse(a == ResourceData.Bytes("world".encodeToByteArray(), "text/plain"), "different bytes must not be equal")
        assertFalse(a == ResourceData.Stream({ java.io.ByteArrayInputStream(ByteArray(0)) }, "text/plain"), "Bytes must not equal Stream")
    }

    @Test
    fun resourceSource_stream_is_distinct_from_other_sources() {
        val stream = ResourceSource.Stream { java.io.ByteArrayInputStream("hello".encodeToByteArray()) }
        assertFalse(stream == ResourceSource.Bytes("hello".encodeToByteArray()), "Stream must not equal Bytes")
        assertFalse(stream == ResourceSource.FilePath("hello"), "Stream must not equal FilePath")
    }

    @Test
    fun resourceSource_stream_factory_is_reopenable() {
        val payload = "hello".encodeToByteArray()
        val source = ResourceSource.Stream { java.io.ByteArrayInputStream(payload) }

        val first = source.open().use { it.readBytes() }
        val second = source.open().use { it.readBytes() }

        assertContentEquals(payload, first, "first open must yield the payload")
        assertContentEquals(payload, second, "factory must be re-openable and yield the same payload")
    }

    @Test
    fun resourceData_stream_exposes_mime_and_factory() {
        val payload = "hi".encodeToByteArray()
        val data = ResourceData.Stream({ java.io.ByteArrayInputStream(payload) }, "text/plain")

        assertEquals("text/plain", data.mimeType)
        val bytes = (data as ResourceData.Stream).open().use { it.readBytes() }
        assertContentEquals(payload, bytes)
    }
}
