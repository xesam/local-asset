package io.github.xesam.android.localasset.webview.mapping

import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.AssetRequest
import io.github.xesam.android.localasset.core.model.ResolveContext
import java.io.File
import java.nio.file.Files
import kotlin.io.path.createTempDirectory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FileDirectoryResolverTest {
    @Test
    fun resolves_file_path_by_host_and_prefix() {
        val root = createTempDirectory("appasset-file-mapping").toFile()
        val target = File(root, "home.js").apply {
            writeText("console.log('home')")
        }
        val resolver = FileDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            rootDirectory = root,
        )

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "cdn.demo.local",
                identifier = "home.js",
                path = "/pkg/home.js",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Hit)
        assertEquals(target.canonicalPath, (result.descriptor.source as ResourceSource.FilePath).value)
    }

    @Test
    fun rejects_path_traversal_attempt() {
        val root = createTempDirectory("appasset-secure").toFile()
        File(root, "safe.js").apply { writeText("ok") }
        val resolver = FileDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            rootDirectory = root,
        )

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "cdn.demo.local",
                identifier = "..",
                path = "/pkg/../etc/passwd",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Skip)
    }

    @Test
    fun rejects_symlink_escape_to_sibling_directory_sharing_root_prefix() {
        val root = createTempDirectory("appasset-secure").toFile()
        val canonicalRoot = root.canonicalFile
        // Sibling directory whose name has canonicalRoot's path as a plain string prefix
        // (e.g. root=".../appasset-secureAB12", sibling=".../appasset-secureAB12-evil").
        // A path-containment check without a trailing separator would wrongly treat it as "inside" root.
        val sibling = File(canonicalRoot.parentFile, "${canonicalRoot.name}-evil").apply { mkdirs() }
        File(sibling, "secret.txt").writeText("top secret")
        Files.createSymbolicLink(File(canonicalRoot, "escape").toPath(), sibling.toPath())

        val resolver = FileDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            rootDirectory = root,
        )

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "cdn.demo.local",
                identifier = "secret.txt",
                path = "/pkg/escape/secret.txt",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Skip)
    }

    @Test
    fun rejects_directory_instead_of_file() {
        val root = createTempDirectory("appasset-dir").toFile()
        val subdir = File(root, "subdir").apply { mkdirs() }
        val resolver = FileDirectoryResolver(
            host = "cdn.demo.local",
            pathPrefix = "/pkg",
            rootDirectory = root,
        )

        val result = resolver.resolve(
            AssetRequest(
                scheme = "local-asset",
                namespace = "cdn.demo.local",
                identifier = "subdir",
                path = "/pkg/subdir",
                query = emptyMap(),
                fragment = null,
            ),
            ResolveContext(null, null, null, null),
        )

        assertTrue(result is ResolverResult.Skip)
    }
}
