package io.github.xesam.android.localasset.core.loader

import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import java.io.ByteArrayInputStream
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class StreamResourceLoaderTest {
    private fun streamDescriptor(source: ResourceSource): ResourceDescriptor = ResourceDescriptor(
        id = "s",
        namespace = "demo",
        type = ResourceType.STATIC,
        source = source,
        mimeType = "text/plain",
        createdAtMillis = 0L,
        ttlMillis = null,
        scope = null,
    )

    @Test
    fun canLoad_matches_only_stream_source() {
        val loader = StreamResourceLoader()
        assertTrue(loader.canLoad(ResourceSource.Stream { ByteArrayInputStream(ByteArray(0)) }))
        assertTrue(!loader.canLoad(ResourceSource.Bytes(ByteArray(0))))
        assertTrue(!loader.canLoad(ResourceSource.FilePath("/x")))
    }

    @Test
    fun loadTyped_wraps_factory_into_stream_data_without_opening() {
        val payload = "hello".encodeToByteArray()
        val opens = java.util.concurrent.atomic.AtomicInteger(0)
        val source = ResourceSource.Stream {
            opens.incrementAndGet()
            ByteArrayInputStream(payload)
        }
        val loader = StreamResourceLoader()

        val data = loader.loadTyped(streamDescriptor(source))

        assertTrue(data is ResourceData.Stream)
        assertEquals("text/plain", data.mimeType)
        assertEquals(0, opens.get(), "loader must NOT open the stream — it only wraps the factory")
        val first = (data as ResourceData.Stream).open().use { it.readBytes() }
        val second = (data as ResourceData.Stream).open().use { it.readBytes() }
        assertContentEquals(payload, first)
        assertContentEquals(payload, second)
        assertEquals(2, opens.get())
    }

    @Test
    fun loadTyped_throws_for_non_stream_source() {
        val loader = StreamResourceLoader()
        val error = assertFailsWith<ResourceException> {
            loader.loadTyped(streamDescriptor(ResourceSource.Bytes(ByteArray(0))))
        }
        assertEquals(ResourceErrorCategory.LOAD_ERROR, error.category)
    }
}
