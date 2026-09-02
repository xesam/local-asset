package io.github.xesam.android.localasset.webview.mapping

import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceSource
import java.io.ByteArrayInputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AssetDirectoryResolverTest {
    private fun ctx() = ResolveContext(null, null, null, null)

    private fun req(path: String, identifier: String? = path.substringAfterLast('/')) =
        AssetRequest(
            scheme = "local-asset",
            namespace = "cdn.demo.local",
            identifier = identifier,
            path = path,
            query = emptyMap(),
            fragment = null,
        )

    /** Stub asset opener: serves an in-memory map of assetPath -> content, throws on miss. */
    private fun openAsset(files: Map<String, ByteArray>): (String) -> java.io.InputStream = { path ->
        files[path]?.let { ByteArrayInputStream(it) } ?: throw IOException("missing asset: $path")
    }

    @Test
    fun hit_returns_stream_source_with_asset_bytes() {
        val content = "body { color: red }".toByteArray(StandardCharsets.UTF_8)
        val resolver = AssetDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            assetDirectory = "demo/pkg",
            openAsset = openAsset(mapOf("demo/pkg/home.css" to content)),
        )

        val result = resolver.resolve(req("/pkg/home.css"), ctx())

        assertTrue(result is ResolverResult.Hit)
        val source = result.descriptor.source
        assertTrue(source is ResourceSource.Stream, "expected Stream source, got $source")
        val bytes = source.open().use { it.readBytes() }
        assertTrue(content.contentEquals(bytes))
    }

    @Test
    fun stream_factory_is_reopenable() {
        val content = "console.log(1)".toByteArray(StandardCharsets.UTF_8)
        var openCount = 0
        val resolver = AssetDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            assetDirectory = "demo/pkg",
            openAsset = { path ->
                openCount++
                ByteArrayInputStream(content)
            },
        )

        val result = resolver.resolve(req("/pkg/app.js"), ctx())
        assertTrue(result is ResolverResult.Hit)
        val source = result.descriptor.source as ResourceSource.Stream

        val first = source.open().use { it.readBytes() }
        val second = source.open().use { it.readBytes() }
        assertTrue(content.contentEquals(first))
        assertTrue(content.contentEquals(second))
        // one probe open + two load opens
        assertEquals(3, openCount)
    }

    @Test
    fun missing_asset_returns_skip() {
        val resolver = AssetDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            assetDirectory = "demo/pkg",
            openAsset = openAsset(emptyMap()),
        )

        val result = resolver.resolve(req("/pkg/missing.css"), ctx())

        assertTrue(result is ResolverResult.Skip)
    }

    @Test
    fun rejects_path_traversal() {
        val resolver = AssetDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            assetDirectory = "demo/pkg",
            openAsset = openAsset(mapOf("demo/pkg/home.css" to ByteArray(0))),
        )

        val result = resolver.resolve(req("/pkg/../etc/passwd", identifier = ".."), ctx())

        assertTrue(result is ResolverResult.Skip)
    }

    @Test
    fun host_mismatch_returns_skip() {
        val resolver = AssetDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            assetDirectory = "demo/pkg",
            openAsset = openAsset(mapOf("demo/pkg/home.css" to ByteArray(0))),
        )

        val other = AssetRequest(
            scheme = "local-asset",
            namespace = "other.host",
            identifier = "home.css",
            path = "/pkg/home.css",
            query = emptyMap(),
            fragment = null,
        )

        assertTrue(resolver.resolve(other, ctx()) is ResolverResult.Skip)
    }
}
