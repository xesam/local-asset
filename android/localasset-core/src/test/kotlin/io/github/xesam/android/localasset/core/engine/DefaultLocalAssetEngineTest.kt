package io.github.xesam.android.localasset.core.engine

import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.api.LocalAsset
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.api.TestFixtures
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.loader.BytesResourceLoader
import io.github.xesam.android.localasset.core.loader.CompositeResourceLoader
import io.github.xesam.android.localasset.core.loader.FileResourceLoader
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceHandle
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import io.github.xesam.android.localasset.core.policy.DefaultPolicy
import io.github.xesam.android.localasset.core.registry.InMemoryHandleRegistry
import io.github.xesam.android.localasset.core.registry.InMemoryResourceRegistry
import io.github.xesam.android.localasset.core.resolver.HandleRegistryResolver
import io.github.xesam.android.localasset.core.resolver.RegistryResolver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

class DefaultLocalAssetEngineTest {
    @Test
    fun resolves_registry_backed_bytes_resource() {
        val registry = InMemoryResourceRegistry()
        registry.register(
            TestFixtures.resourceDescriptor(
                id = "logo",
                namespace = "image",
                bytes = "hello".encodeToByteArray(),
                mimeType = "text/plain",
            ),
        )
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(
                listOf(RegistryResolver(registry)),
            ),
            policy = DefaultPolicy(),
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
        )

        val result = engine.resolve("local-asset://image/logo")

        assertTrue(result is EngineResult.Success)
        assertEquals("text/plain", result.data.mimeType)
    }

    // A file-backed handle (design.md §5.4) carries a FilePath source through the capability token.
    // The token still authorizes, but postCheck's shared file-root gate must still apply — otherwise a
    // capability could point at any path on disk. These two tests pin the security-critical contract:
    // out-of-root → SECURITY_ERROR at postCheck; in-root → passes postCheck (then fails at LOAD because
    // the file doesn't exist on disk, which is fine — the point is it got past policy).

    @Test
    fun file_backed_handle_outside_allowed_root_is_rejected_at_postCheck() {
        val handleRegistry = InMemoryHandleRegistry()
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(
                listOf(HandleRegistryResolver(handleRegistry)),
            ),
            policy = DefaultPolicy(allowedFileRoots = setOf(java.io.File("/data/app/allowed"))),
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
        )
        val uri = handleRegistry.register(
            TestFixtures.resourceFileHandle(
                filePath = "/data/app/OUTSIDE/big.pdf",
                fileName = "big.pdf",
                mimeType = "application/pdf",
            ),
        )

        val result = engine.resolve(uri)

        assertTrue(result is EngineResult.Failure)
        assertEquals(ResourceErrorCategory.SECURITY_ERROR, result.category)
    }

    @Test
    fun file_backed_handle_inside_allowed_root_passes_postCheck() {
        val handleRegistry = InMemoryHandleRegistry()
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(
                listOf(HandleRegistryResolver(handleRegistry)),
            ),
            policy = DefaultPolicy(allowedFileRoots = setOf(java.io.File("/data/app/allowed"))),
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
        )
        val uri = handleRegistry.register(
            TestFixtures.resourceFileHandle(
                filePath = "/data/app/allowed/big.pdf",
                fileName = "big.pdf",
                mimeType = "application/pdf",
            ),
        )

        val result = engine.resolve(uri)

        // File doesn't exist on disk → LOAD_ERROR, but crucially NOT SECURITY_ERROR — proving the
        // file-root gate passed for an in-root path. The contrast with the out-of-root test above
        // is the security contract: capability token can't escape the allowed root.
        assertTrue(result is EngineResult.Failure)
        assertNotEquals(ResourceErrorCategory.SECURITY_ERROR, result.category)
    }

    @Test
    fun returns_parse_error_for_invalid_url() {
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(emptyList()),
            policy = DefaultPolicy(),
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
        )

        val result = engine.resolve("local-asset:///invalid")

        assertTrue(result is EngineResult.Failure)
        assertEquals(ResourceErrorCategory.PARSE_ERROR, result.category)
        assertEquals("adapter_parse", result.stage)
    }

    @Test
    fun returns_security_error_when_policy_preCheck_rejects() {
        val rejectingPolicy = object : io.github.xesam.android.localasset.core.api.Policy {
            override fun preCheck(request: AssetRequest, context: ResolveContext) {
                throw ResourceException(ResourceErrorCategory.SECURITY_ERROR, "namespace blocked", stage = "policy_pre")
            }

            override fun postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext) {
            }
        }
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(emptyList()),
            policy = rejectingPolicy,
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
        )

        val result = engine.resolve("local-asset://image/logo")

        assertTrue(result is EngineResult.Failure)
        assertEquals(ResourceErrorCategory.SECURITY_ERROR, result.category)
        assertEquals("policy_pre", result.stage)
    }

    @Test
    fun returns_resolution_error_when_resolver_chain_skips() {
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(
                listOf(ResourceResolver { _, _ -> ResolverResult.Skip }),
            ),
            policy = DefaultPolicy(),
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
        )

        val result = engine.resolve("local-asset://image/logo")

        assertTrue(result is EngineResult.Failure)
        assertEquals(ResourceErrorCategory.RESOLUTION_ERROR, result.category)
        assertEquals("resource not found", result.reason)
        assertEquals("resolve", result.stage)
    }

    @Test
    fun returns_first_hit_from_ordered_resolver_chain() {
        val descriptorA = ResourceDescriptor(
            id = "asset-a",
            namespace = "demo",
            type = ResourceType.STATIC,
            source = ResourceSource.Bytes("a".encodeToByteArray()),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )
        val descriptorB = ResourceDescriptor(
            id = "asset-b",
            namespace = "demo",
            type = ResourceType.STATIC,
            source = ResourceSource.Bytes("b".encodeToByteArray()),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(
                listOf(
                    ResourceResolver { _, _ -> ResolverResult.Hit(descriptorA) },
                    ResourceResolver { _, _ -> ResolverResult.Hit(descriptorB) },
                ),
            ),
            policy = DefaultPolicy(),
            loader = CompositeResourceLoader(listOf(BytesResourceLoader(), FileResourceLoader())),
        )

        val result = engine.resolve("local-asset://demo/logo")

        assertTrue(result is EngineResult.Success)
        assertEquals("asset-a", result.descriptor.id)
    }

    @Test
    fun returns_load_error_when_loader_throws_unexpected_exception() {
        val brokenLoader = object : io.github.xesam.android.localasset.core.api.ResourceLoader {
            override fun load(descriptor: ResourceDescriptor): io.github.xesam.android.localasset.core.model.ResourceData {
                throw RuntimeException("disk failure")
            }
        }
        val descriptor = ResourceDescriptor(
            id = "logo",
            namespace = "demo",
            type = ResourceType.STATIC,
            source = ResourceSource.Bytes("data".encodeToByteArray()),
            mimeType = "text/plain",
            createdAtMillis = 0L,
            ttlMillis = null,
            scope = null,
        )
        val engine = DefaultLocalAssetEngine(
            adapters = listOf(DefaultLocalAssetSchemeAdapter()),
            resolverChain = io.github.xesam.android.localasset.core.internal.ResolverChain(
                listOf(ResourceResolver { _, _ -> ResolverResult.Hit(descriptor) }),
            ),
            policy = DefaultPolicy(),
            loader = brokenLoader,
        )

        val result = engine.resolve("local-asset://demo/logo")

        assertTrue(result is EngineResult.Failure)
        assertEquals(ResourceErrorCategory.LOAD_ERROR, result.category)
        assertTrue(result.reason.contains("disk failure"))
        assertEquals("load", result.stage)
    }

    @Test
    fun resolves_handle_backed_resource_that_has_ttl() {
        // Regression for the P0 double-judgment defect: a handle registered with a TTL must still
        // resolve through the full pipeline. HandleRegistryResolver used to forward ttlMillis onto
        // a descriptor whose createdAtMillis was a 0L placeholder, so DefaultPolicy.postCheck's
        // absolute-time TTL check (`0 + ttl <= now`) expired every TTL'd handle on the spot.
        val asset = LocalAsset.Builder().build()
        val bytes = "image data".encodeToByteArray()
        val uri = asset.registerHandle(
            ResourceHandle(
                source = ResourceSource.Bytes(bytes),
                fileName = "photo.jpg",
                mimeType = "image/jpeg",
                ttlMillis = 60_000L,
            ),
        )

        val result = asset.engine.resolve(uri)

        assertTrue(result is EngineResult.Success)
        assertEquals("image/jpeg", result.data.mimeType)
        assertTrue((result.data as ResourceData.Bytes).bytes.contentEquals(bytes))
    }
}
