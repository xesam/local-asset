package io.github.xesam.android.localasset.core.loader

import io.github.xesam.android.localasset.core.api.AsyncResourceLoader
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import kotlinx.coroutines.delay
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class AsyncResourceLoaderTest {
    private class SlowNetworkLoader : AsyncResourceLoader {
        override fun canLoad(source: ResourceSource): Boolean = source is ResourceSource.Bytes

        override suspend fun loadAsync(descriptor: ResourceDescriptor): ResourceData {
            delay(1) // simulate a suspending data source (network/Room/DataStore)
            val bytes = (descriptor.source as ResourceSource.Bytes).value
            return ResourceData.Bytes(bytes = bytes, mimeType = descriptor.mimeType)
        }
    }

    @Test
    fun async_loader_is_driven_through_sync_pipeline() {
        val loader = SlowNetworkLoader()
        val composite = CompositeResourceLoader(loaders = listOf(loader))
        val payload = "from-async".encodeToByteArray()
        val descriptor = ResourceDescriptor(
            id = "net-1",
            namespace = "ns",
            type = ResourceType.DYNAMIC,
            source = ResourceSource.Bytes(payload),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )

        val data = composite.load(descriptor)

        val bytes = (data as ResourceData.Bytes).bytes
        assertTrue(bytes.contentEquals(payload))
        assertTrue(data.mimeType == "text/plain")
    }

    @Test
    fun async_loader_failure_propagates_as_load_error() {
        class FailingAsyncLoader : AsyncResourceLoader {
            override fun canLoad(source: ResourceSource): Boolean = source is ResourceSource.Bytes

            override suspend fun loadAsync(descriptor: ResourceDescriptor): ResourceData {
                throw ResourceException(ResourceErrorCategory.LOAD_ERROR, "boom")
            }
        }
        val composite = CompositeResourceLoader(loaders = listOf(FailingAsyncLoader()))
        val descriptor = ResourceDescriptor(
            id = "net-2",
            namespace = "ns",
            type = ResourceType.DYNAMIC,
            source = ResourceSource.Bytes(ByteArray(0)),
            mimeType = null,
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )

        val ex = assertFailsWith<ResourceException> { composite.load(descriptor) }

        assertTrue(ex.category == ResourceErrorCategory.LOAD_ERROR)
        assertTrue(ex.message == "boom")
    }
}
