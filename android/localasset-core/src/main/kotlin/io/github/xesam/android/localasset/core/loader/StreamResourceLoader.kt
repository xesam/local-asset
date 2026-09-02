package io.github.xesam.android.localasset.core.loader

import io.github.xesam.android.localasset.core.api.TypedResourceLoader
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource

/**
 * Pass-through loader for [ResourceSource.Stream]. Honors the streaming ownership model: it does
 * NOT call the factory — it wraps the re-openable factory into [ResourceData.Stream] and lets the
 * platform response layer open, consume, and close the stream. The engine and loader therefore
 * never hold an open stream.
 */
class StreamResourceLoader : TypedResourceLoader {
    override fun canLoad(source: ResourceSource): Boolean = source is ResourceSource.Stream

    override fun loadTyped(descriptor: ResourceDescriptor): ResourceData {
        val source = descriptor.source as? ResourceSource.Stream
            ?: throw ResourceException(ResourceErrorCategory.LOAD_ERROR, "unsupported source type")
        return ResourceData.Stream(open = source.open, mimeType = descriptor.mimeType)
    }
}
