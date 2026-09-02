package io.github.xesam.android.localasset.core.loader

import io.github.xesam.android.localasset.core.api.ResourceLoader
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.api.TypedResourceLoader
import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

class CompositeResourceLoader(
    private val loaders: List<ResourceLoader>,
) : ResourceLoader {
    override fun load(descriptor: ResourceDescriptor): ResourceData {
        val typedLoaders = loaders.mapNotNull { it as? TypedResourceLoader }
        val loader = typedLoaders.firstOrNull { it.canLoad(descriptor.source) }
            ?: run {
                val nonTyped = loaders.filter { it !is TypedResourceLoader }
                val nonTypedNames = nonTyped.map { it::class.simpleName ?: it::class.toString() }
                throw ResourceException(
                    ResourceErrorCategory.LOAD_ERROR,
                    "no loader for source type ${descriptor.source::class.simpleName}" +
                        if (nonTyped.isNotEmpty()) {
                            " (${typedLoaders.size} typed loader(s) checked; " +
                                "${nonTyped.size} loader(s) do not implement TypedResourceLoader: $nonTypedNames)"
                        } else {
                            " (${typedLoaders.size} typed loader(s) checked)"
                        },
                )
            }
        return loader.loadTyped(descriptor)
    }
}
