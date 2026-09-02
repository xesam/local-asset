package io.github.xesam.android.localasset.core.registry

import io.github.xesam.android.localasset.core.api.TestFixtures
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceSource
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class InMemoryHandleRegistryTest {
    private fun bytesOf(source: ResourceSource): ByteArray = (source as ResourceSource.Bytes).value
    @Test
    fun registered_handle_can_be_resolved_by_generated_uri() {
        val registry = InMemoryHandleRegistry(
            host = "bridge.demo.local",
            pathPrefix = "/preview",
        )

        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "preview".encodeToByteArray(),
                fileName = "demo-image.jpg",
                mimeType = "image/jpeg",
            ),
        )

        val record = registry.resolve(resourceUri)

        assertTrue(resourceUri.startsWith("local-asset://bridge.demo.local/preview/"))
        assertEquals(resourceUri, record.resourceUri)
        assertEquals("demo-image.jpg", record.fileName)
        assertEquals("image/jpeg", record.mimeType)
        assertEquals(7L, record.size)
        assertTrue(bytesOf(record.source).contentEquals("preview".encodeToByteArray()))
    }

    @Test
    fun removed_handle_cannot_be_resolved() {
        val registry = InMemoryHandleRegistry()
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "preview".encodeToByteArray(),
                fileName = "demo-image.jpg",
                mimeType = "image/jpeg",
            ),
        )

        registry.remove(resourceUri)

        val error = assertFailsWith<ResourceException> {
            registry.resolve(resourceUri)
        }
        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, error.category)
    }

    @Test
    fun expired_handle_cannot_be_resolved() {
        var now = 0L
        val registry = InMemoryHandleRegistry(nowMillis = { now })
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "preview".encodeToByteArray(),
                fileName = "demo-image.jpg",
                mimeType = "image/jpeg",
                metadata = emptyMap(),
            ).copy(ttlMillis = 1_000L),
        )

        now = 2_000L

        val error = assertFailsWith<ResourceException> {
            registry.resolve(resourceUri)
        }
        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, error.category)
    }

    @Test
    fun concurrent_resolve_on_same_uri_does_not_throw_ConcurrentModificationException() {
        val registry = InMemoryHandleRegistry()
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "shared".encodeToByteArray(),
                fileName = "shared.txt",
                mimeType = "text/plain",
            ),
        )

        val threads = (1..20).map {
            Thread {
                val record = registry.resolve(resourceUri)
                assertTrue(bytesOf(record.source).contentEquals("shared".encodeToByteArray()))
            }
        }
        threads.forEach { it.start() }
        threads.forEach { it.join() }
    }

    @Test
    fun cleanup_removes_expired_entries() {
        var now = 0L
        val registry = InMemoryHandleRegistry(nowMillis = { now })
        val uri1 = registry.register(
            TestFixtures.resourceHandle(
                bytes = "a".encodeToByteArray(),
                fileName = "a.txt",
                mimeType = "text/plain",
            ).copy(ttlMillis = 1_000L),
        )
        val uri2 = registry.register(
            TestFixtures.resourceHandle(
                bytes = "b".encodeToByteArray(),
                fileName = "b.txt",
                mimeType = "text/plain",
            ),
        )

        now = 2_000L
        registry.cleanup(now)

        // expired entry removed
        val error = assertFailsWith<ResourceException> { registry.resolve(uri1) }
        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, error.category)
        // non-expired entry still present
        assertEquals("b.txt", registry.resolve(uri2).fileName)
    }

    @Test
    fun file_backed_handle_records_source_and_null_size() {
        // A FilePath handle exposes the path as its source and leaves size null (the file is not
        // probed at register time). The capability token still authorizes resolution; the file-root
        // gate is enforced later at postCheck, not by the registry.
        val registry = InMemoryHandleRegistry()
        val resourceUri = registry.register(
            TestFixtures.resourceFileHandle(
                filePath = "/data/app/cache/big.pdf",
                fileName = "big.pdf",
                mimeType = "application/pdf",
            ),
        )

        val record = registry.resolve(resourceUri)
        assertTrue(record.source is ResourceSource.FilePath)
        assertEquals("/data/app/cache/big.pdf", (record.source as ResourceSource.FilePath).value)
        assertEquals(null, record.size)
        assertEquals("big.pdf", record.fileName)
    }
}
