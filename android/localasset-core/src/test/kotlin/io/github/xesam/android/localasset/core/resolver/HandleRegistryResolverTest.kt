package io.github.xesam.android.localasset.core.resolver

import io.github.xesam.android.localasset.core.api.HandleRegistry
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.TestFixtures
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceScope
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import io.github.xesam.android.localasset.core.registry.InMemoryHandleRegistry
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class HandleRegistryResolverTest {
    @Test
    fun returns_hit_when_handle_is_found() {
        val registry = InMemoryHandleRegistry(
            host = "bridge.demo.local",
            pathPrefix = "/preview",
        )
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "photo".encodeToByteArray(),
                fileName = "photo.jpg",
                mimeType = "image/jpeg",
            ),
        )
        val resolver = HandleRegistryResolver(registry)

        // Extract path from generated URI for the request
        val path = resourceUri.removePrefix("local-asset://bridge.demo.local")
        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "bridge.demo.local",
                identifier = "photo.jpg",
                path = path,
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit)
        assertTrue((result as ResolverResult.Hit).descriptor.mimeType == "image/jpeg")
    }

    @Test
    fun descriptor_ttl_is_null_even_when_handle_has_ttl() {
        // Regression: HandleRegistry owns TTL itself (relative to its own createdAt). The resolver
        // must NOT forward record.ttlMillis onto a descriptor whose createdAtMillis is a 0L
        // placeholder, or DefaultPolicy.postCheck's absolute-time TTL check would always expire.
        val registry = InMemoryHandleRegistry()
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "photo".encodeToByteArray(),
                fileName = "photo.jpg",
                mimeType = "image/jpeg",
            ).copy(ttlMillis = 60_000L),
        )
        val resolver = HandleRegistryResolver(registry)
        val path = resourceUri.removePrefix("local-asset://handles.localasset.local")

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "handles.localasset.local",
                identifier = "photo.jpg",
                path = path,
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit)
        val descriptor = (result as ResolverResult.Hit).descriptor
        assertEquals(null, descriptor.ttlMillis)
    }

    @Test
    fun descriptor_scope_is_null_so_postcheck_skips_scope_gate() {
        // Handle-backed resources use a capability model: possession of the opaque token IS the
        // authority, so they must NOT pass DefaultPolicy.postCheck's namespace/scope gate (which
        // would require descriptor.namespace == the context's scope id and reject otherwise).
        // Pin scope == null here so a future change that sets a scope can't silently start rejecting
        // every handle-backed request. See design.md §3.3 / §5.2.
        val registry = InMemoryHandleRegistry()
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "photo".encodeToByteArray(),
                fileName = "photo.jpg",
                mimeType = "image/jpeg",
            ),
        )
        val resolver = HandleRegistryResolver(registry)
        val path = resourceUri.removePrefix("local-asset://handles.localasset.local")

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "handles.localasset.local",
                identifier = "photo.jpg",
                path = path,
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit)
        val descriptor = (result as ResolverResult.Hit).descriptor
        assertNull(descriptor.scope, "handle-backed descriptor must not carry a ResourceScope")
        assertEquals(ResourceType.DYNAMIC, descriptor.type)
    }

    @Test
    fun file_backed_handle_produces_filepath_descriptor_source() {
        // A FilePath handle must surface as ResourceSource.FilePath on the descriptor so that
        // FileResourceLoader (not BytesResourceLoader) reads it, and postCheck's shared file-root
        // gate applies. The capability token still authorizes; the path is not re-validated here.
        val registry = InMemoryHandleRegistry()
        val resourceUri = registry.register(
            TestFixtures.resourceFileHandle(
                filePath = "/data/app/cache/big.pdf",
                fileName = "big.pdf",
                mimeType = "application/pdf",
            ),
        )
        val resolver = HandleRegistryResolver(registry)
        val path = resourceUri.removePrefix("local-asset://handles.localasset.local")

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "handles.localasset.local",
                identifier = "big.pdf",
                path = path,
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit)
        val source = (result as ResolverResult.Hit).descriptor.source
        assertTrue(source is ResourceSource.FilePath)
        assertEquals("/data/app/cache/big.pdf", (source as ResourceSource.FilePath).value)
    }

    @Test
    fun returns_skip_when_handle_is_not_found() {
        val registry = InMemoryHandleRegistry()
        val resolver = HandleRegistryResolver(registry)

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "demo",
                identifier = "missing",
                path = "/handles/nonexistent/missing",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Skip)
    }

    @Test
    fun cache_bust_param_is_stripped_so_handle_resolves() {
        // The reserved `_la_cb` cache-bust param must NOT participate in handle identity: a
        // request that differs from the registered URI only by `_la_cb=<ts>` must still resolve.
        // Without stripping, the reconstructed URI would carry `?_la_cb=...` and miss the
        // (query-less) registered key → 404 on every cache-busted re-fetch, defeating the bust.
        val registry = InMemoryHandleRegistry(
            host = "bridge.demo.local",
            pathPrefix = "/preview",
        )
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "photo".encodeToByteArray(),
                fileName = "photo.jpg",
                mimeType = "image/jpeg",
            ),
        )
        val resolver = HandleRegistryResolver(registry)
        val path = resourceUri.removePrefix("local-asset://bridge.demo.local")

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "bridge.demo.local",
                identifier = "photo.jpg",
                path = path,
                query = mapOf("_la_cb" to "1700000000000"),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit)
        assertEquals("photo.jpg", (result as ResolverResult.Hit).descriptor.id)
    }

    @Test
    fun non_reserved_query_param_breaks_lookup() {
        // A query key other than `_la_cb` IS part of the identity; since the registered URI has no
        // query, any such key must miss. This guards against accidentally stripping all query.
        val registry = InMemoryHandleRegistry(
            host = "bridge.demo.local",
            pathPrefix = "/preview",
        )
        val resourceUri = registry.register(
            TestFixtures.resourceHandle(
                bytes = "photo".encodeToByteArray(),
                fileName = "photo.jpg",
                mimeType = "image/jpeg",
            ),
        )
        val resolver = HandleRegistryResolver(registry)
        val path = resourceUri.removePrefix("local-asset://bridge.demo.local")

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "bridge.demo.local",
                identifier = "photo.jpg",
                path = path,
                query = mapOf("foo" to "bar"),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Skip)
    }
}
