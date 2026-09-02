package io.github.xesam.android.localasset.core.resolver

import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import io.github.xesam.android.localasset.core.registry.InMemoryResourceRegistry
import kotlin.test.Test
import kotlin.test.assertTrue

class RegistryResolverTest {
    @Test
    fun resolves_by_query_id_when_identifier_is_missing() {
        val registry = InMemoryResourceRegistry()
        val descriptor = ResourceDescriptor(
            id = "welcome",
            namespace = "demo",
            type = ResourceType.DYNAMIC,
            source = ResourceSource.Bytes("hello".encodeToByteArray()),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )
        registry.register(descriptor)

        val resolver = RegistryResolver(registry)
        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "demo",
                identifier = null,
                path = "/runtime/content",
                query = mapOf("id" to "welcome"),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit && result.descriptor == descriptor)
    }
}
