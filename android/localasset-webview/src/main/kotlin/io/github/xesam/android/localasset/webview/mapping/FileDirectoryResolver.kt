package io.github.xesam.android.localasset.webview.mapping

import io.github.xesam.android.localasset.core.model.ResourceSource
import java.io.File

class FileDirectoryResolver(
    host: String,
    pathPrefix: String,
    private val rootDirectory: File,
) : BaseDirectoryResolver(host, pathPrefix) {
    private val canonicalRoot = rootDirectory.canonicalFile

    override fun resolveSource(relativePath: String): ResourceSource? {
        val target = File(canonicalRoot, relativePath).canonicalFile
        val withinRoot = target.path == canonicalRoot.path ||
            target.path.startsWith(canonicalRoot.path + File.separator)
        if (!withinRoot || !target.isFile) {
            return null
        }
        return ResourceSource.FilePath(target.absolutePath)
    }
}
