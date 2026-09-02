package io.github.xesam.android.localasset.core.internal

import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import kotlin.test.Test
import kotlin.test.assertTrue

class ResolverChainTest {
    @Test
    fun returns_first_hit() {
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
        val chain = ResolverChain(
            listOf(
                ResourceResolver { _, _ -> ResolverResult.Hit(descriptor) },
                ResourceResolver { _, _ ->
                    ResolverResult.Failure(ResourceErrorCategory.RESOLUTION_ERROR, "should not run")
                },
            ),
        )

        val result = chain.resolve(
            AssetRequest("local-asset", "demo", "asset-1", null, emptyMap(), null),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit)
    }
}
