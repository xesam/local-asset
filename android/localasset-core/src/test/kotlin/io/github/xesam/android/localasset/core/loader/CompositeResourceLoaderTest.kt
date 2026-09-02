package io.github.xesam.android.localasset.core.loader

import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import java.io.ByteArrayInputStream
import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class CompositeResourceLoaderTest {
    @Test
    fun loads_bytes_source() {
        val loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader()))
        val descriptor = ResourceDescriptor(
            id = "bytes",
            namespace = "demo",
            type = ResourceType.DYNAMIC,
            source = ResourceSource.Bytes("hello".encodeToByteArray()),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )

        val data = loader.load(descriptor)

        val bytes = (data as ResourceData.Bytes).bytes
        assertContentEquals("hello".encodeToByteArray(), bytes)
        assertEquals("text/plain", data.mimeType)
    }

    @Test
    fun loads_file_source() {
        val tempFile = File.createTempFile("appasset", ".txt").apply {
            writeText("from-file")
            deleteOnExit()
        }
        val loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader()))
        val descriptor = ResourceDescriptor(
            id = "file",
            namespace = "demo",
            type = ResourceType.STATIC,
            source = ResourceSource.FilePath(tempFile.absolutePath),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )

        val data = loader.load(descriptor)

        assertTrue(data is ResourceData.Stream, "expected Stream data for FilePath source")
        val bytes = (data as ResourceData.Stream).open().use { it.readBytes() }
        assertContentEquals("from-file".encodeToByteArray(), bytes)
        assertEquals("text/plain", data.mimeType)
    }

    @Test
    fun loads_stream_source() {
        val payload = "from-stream".encodeToByteArray()
        val loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader(), StreamResourceLoader()))
        val descriptor = ResourceDescriptor(
            id = "stream",
            namespace = "demo",
            type = ResourceType.STATIC,
            source = ResourceSource.Stream { ByteArrayInputStream(payload) },
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )

        val data = loader.load(descriptor)

        val stream = data as ResourceData.Stream
        assertEquals("text/plain", stream.mimeType)
        assertContentEquals(payload, stream.open().use { it.readBytes() })
        // factory is re-openable: a second open yields the same payload
        assertContentEquals(payload, stream.open().use { it.readBytes() })
    }

    @Test
    fun throws_when_no_loader_matches_source_type() {
        val loader = CompositeResourceLoader(loaders = emptyList())
        val descriptor = ResourceDescriptor(
            id = "orphan",
            namespace = "demo",
            type = ResourceType.DYNAMIC,
            source = ResourceSource.Bytes("hello".encodeToByteArray()),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )

        val ex = assertFailsWith<ResourceException> { loader.load(descriptor) }

        assertTrue(ex.category == ResourceErrorCategory.LOAD_ERROR)
    }

    @Test
    fun throws_when_no_loader_matches_stream_source_type() {
        val loader = CompositeResourceLoader(loaders = emptyList())
        val descriptor = ResourceDescriptor(
            id = "orphan-stream",
            namespace = "demo",
            type = ResourceType.DYNAMIC,
            source = ResourceSource.Stream { ByteArrayInputStream(ByteArray(0)) },
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )

        val ex = assertFailsWith<ResourceException> { loader.load(descriptor) }

        assertTrue(ex.category == ResourceErrorCategory.LOAD_ERROR)
    }
}
