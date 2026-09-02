package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LocalAssetBuilderTest {
    @Test
    fun builder_defaults_resolve_registered_resource() {
        val localAsset = LocalAsset.Builder().build()
        localAsset.register(
            TestFixtures.resourceDescriptor(
                id = "logo",
                namespace = "image",
                bytes = "hello".encodeToByteArray(),
                mimeType = "text/plain",
            ),
        )

        val result = localAsset.engine.resolve("local-asset://image/logo")

        assertTrue(result is EngineResult.Success)
    }

    @Test
    fun builder_defaults_resolve_registered_handle() {
        val localAsset = LocalAsset.Builder().build()
        val previewUri = localAsset.registerHandle(
            TestFixtures.resourceHandle(
                bytes = "preview".encodeToByteArray(),
                fileName = "preview.png",
                mimeType = "image/png",
            ),
        )

        val result = localAsset.engine.resolve(previewUri)

        assertTrue(result is EngineResult.Success)
        assertTrue((result.data as ResourceData.Bytes).bytes.contentEquals("preview".encodeToByteArray()))
        assertEquals("image/png", result.data.mimeType)
    }

    @Test
    fun builder_with_custom_resolver_still_resolves_registered_resource() {
        val localAsset = LocalAsset.Builder()
            .addResolver { _, _ -> ResolverResult.Skip }
            .build()
        localAsset.register(
            TestFixtures.resourceDescriptor(
                id = "logo",
                namespace = "image",
                bytes = "hello".encodeToByteArray(),
                mimeType = "text/plain",
            ),
        )

        val result = localAsset.engine.resolve("local-asset://image/logo")

        assertTrue(result is EngineResult.Success)
    }

    @Test
    fun resolve_handle_returns_registered_metadata() {
        val localAsset = LocalAsset.Builder().build()
        val previewUri = localAsset.registerHandle(
            TestFixtures.resourceHandle(
                bytes = "preview".encodeToByteArray(),
                fileName = "preview.png",
                mimeType = "image/png",
                metadata = mapOf("android.content_uri" to "content://demo/image/1"),
            ),
        )

        val record = localAsset.resolveHandle(previewUri)

        assertEquals(previewUri, record.resourceUri)
        assertEquals("preview.png", record.fileName)
        assertEquals("image/png", record.mimeType)
        assertEquals("content://demo/image/1", record.metadata["android.content_uri"])
        assertEquals(7L, record.size)
    }

    @Test
    fun builder_default_policy_rejects_filepath_without_allowed_root() {
        val root = createTempDirectory(prefix = "policy-root").toFile()
        val file = java.io.File(root, "note.txt").apply { writeText("hi") }
        val localAsset = LocalAsset.Builder().build()
        localAsset.register(
            ResourceDescriptor(
                id = "note",
                namespace = "files",
                type = ResourceType.DYNAMIC,
                source = ResourceSource.FilePath(file.absolutePath),
                mimeType = "text/plain",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
        )

        val result = localAsset.engine.resolve("local-asset://files/note")

        // fail-closed by default: no allowed root configured → SECURITY_ERROR at postCheck
        assertTrue(result is EngineResult.Failure)
    }

    @Test
    fun builder_add_allowed_file_root_lets_filepath_resolve() {
        val root = createTempDirectory(prefix = "policy-root").toFile()
        val file = java.io.File(root, "note.txt").apply { writeText("hi") }
        val localAsset = LocalAsset.Builder().addAllowedFileRoot(root).build()
        localAsset.register(
            ResourceDescriptor(
                id = "note",
                namespace = "files",
                type = ResourceType.DYNAMIC,
                source = ResourceSource.FilePath(file.absolutePath),
                mimeType = "text/plain",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
        )

        val result = localAsset.engine.resolve("local-asset://files/note")

        assertTrue(result is EngineResult.Success)
        val data = (result as EngineResult.Success).data
        assertTrue(data is ResourceData.Stream, "FilePath now loads as Stream")
        val bytes = (data as ResourceData.Stream).open().use { it.readBytes() }
        assertTrue(bytes.contentEquals("hi".encodeToByteArray()))
    }

    @Test
    fun builder_add_allowed_file_root_ignored_when_custom_policy_supplied() {
        val root = createTempDirectory(prefix = "policy-root").toFile()
        val file = java.io.File(root, "note.txt").apply { writeText("hi") }
        // custom policy with empty allowed roots — Builder knob must not override it
        val localAsset = LocalAsset.Builder()
            .addAllowedFileRoot(root)
            .policy(io.github.xesam.android.localasset.core.policy.DefaultPolicy())
            .build()
        localAsset.register(
            ResourceDescriptor(
                id = "note",
                namespace = "files",
                type = ResourceType.DYNAMIC,
                source = ResourceSource.FilePath(file.absolutePath),
                mimeType = "text/plain",
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            ),
        )

        val result = localAsset.engine.resolve("local-asset://files/note")

        assertTrue(result is EngineResult.Failure)
    }

    @Test
    fun builder_defaults_resolve_stream_source_end_to_end() {
        val payload = "stream-body".encodeToByteArray()
        val localAsset = LocalAsset.Builder()
            .addResolver { _, _ ->
                ResolverResult.Hit(
                    ResourceDescriptor(
                        id = "stream-res",
                        namespace = "demo",
                        type = ResourceType.STATIC,
                        source = ResourceSource.Stream { java.io.ByteArrayInputStream(payload) },
                        mimeType = "text/plain",
                        createdAtMillis = 0L,
                        ttlMillis = null,
                        scope = null,
                    ),
                )
            }
            .build()

        val result = localAsset.engine.resolve("local-asset://demo/stream-res")

        assertTrue(result is EngineResult.Success)
        val data = (result as EngineResult.Success).data as ResourceData.Stream
        assertEquals("text/plain", data.mimeType)
        assertContentEquals(payload, data.open().use { it.readBytes() })
    }
}
