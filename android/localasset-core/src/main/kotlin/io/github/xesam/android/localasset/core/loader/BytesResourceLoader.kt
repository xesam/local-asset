package io.github.xesam.android.localasset.core.loader

import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.api.TypedResourceLoader
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource

class BytesResourceLoader : TypedResourceLoader {
    override fun canLoad(source: ResourceSource): Boolean = source is ResourceSource.Bytes

    override fun loadTyped(descriptor: ResourceDescriptor): ResourceData {
        val source = descriptor.source as? ResourceSource.Bytes
            ?: throw ResourceException(ResourceErrorCategory.LOAD_ERROR, "unsupported source type")
        return ResourceData.Bytes(bytes = source.value, mimeType = descriptor.mimeType)
    }
}
