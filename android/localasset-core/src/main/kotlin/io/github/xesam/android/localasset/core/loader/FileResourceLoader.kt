package io.github.xesam.android.localasset.core.loader

import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.api.TypedResourceLoader
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import java.io.File

class FileResourceLoader : TypedResourceLoader {
    override fun canLoad(source: ResourceSource): Boolean = source is ResourceSource.FilePath

    override fun loadTyped(descriptor: ResourceDescriptor): ResourceData {
        val source = descriptor.source as? ResourceSource.FilePath
            ?: throw ResourceException(ResourceErrorCategory.LOAD_ERROR, "unsupported source type")
        val file = File(source.value)
        if (!file.exists() || !file.isFile) {
            throw ResourceException(ResourceErrorCategory.LOAD_ERROR, "file source is not readable")
        }
        // Stream the file instead of materializing it: hand back a re-openable factory whose
        // open() returns a fresh FileInputStream. The existence/isFile check above is the load-time
        // probe (FileDirectoryResolver also checks at resolve time); the platform response layer
        // opens, consumes, and closes — file bytes never sit fully in memory.
        return ResourceData.Stream(open = { file.inputStream() }, mimeType = descriptor.mimeType)
    }
}
