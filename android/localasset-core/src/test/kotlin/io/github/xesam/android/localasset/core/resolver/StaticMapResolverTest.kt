package io.github.xesam.android.localasset.core.resolver

import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import kotlin.test.Test
import kotlin.test.assertTrue

class StaticMapResolverTest {
    @Test
    fun resolves_by_namespace_and_path() {
        val descriptor = ResourceDescriptor(
            id = "static-index",
            namespace = "demo",
            type = ResourceType.STATIC,
            source = ResourceSource.Bytes("static".encodeToByteArray()),
            mimeType = "text/html",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )
        val resolver = StaticMapResolver(mapOf("demo:/static/index.html" to descriptor))

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "demo",
                identifier = "index.html",
                path = "/static/index.html",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit && result.descriptor == descriptor)
    }
}
