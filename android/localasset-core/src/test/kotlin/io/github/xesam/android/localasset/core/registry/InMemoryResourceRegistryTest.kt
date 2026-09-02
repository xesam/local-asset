package io.github.xesam.android.localasset.core.registry

import io.github.xesam.android.localasset.core.api.RegistryLookupResult
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class InMemoryResourceRegistryTest {
    @Test
    fun expired_resource_returns_expired_result() {
        val registry = InMemoryResourceRegistry(nowMillis = { 2_000L })
        registry.register(
            ResourceDescriptor(
                id = "asset-1",
                namespace = "demo",
                type = ResourceType.DYNAMIC,
                source = ResourceSource.Bytes(byteArrayOf(1)),
                mimeType = "text/plain",
                createdAtMillis = 0L,
                ttlMillis = 1_000L,
                scope = null,
            ),
        )

        assertTrue(registry.lookup("asset-1") is RegistryLookupResult.Expired)
    }

    @Test
    fun duplicate_register_throws_resolution_error() {
        val registry = InMemoryResourceRegistry()
        val descriptor = ResourceDescriptor(
            id = "asset-1",
            namespace = "demo",
            type = ResourceType.DYNAMIC,
            source = ResourceSource.Bytes(byteArrayOf(1)),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )
        registry.register(descriptor)

        val error = assertFailsWith<ResourceException> { registry.register(descriptor) }

        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, error.category)
    }
}
