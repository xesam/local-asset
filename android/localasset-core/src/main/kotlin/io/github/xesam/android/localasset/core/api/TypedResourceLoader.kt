package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource

/**
 * A [ResourceLoader] that declares which [ResourceSource] kinds it can load via [canLoad].
 *
 * [CompositeResourceLoader] dispatches by calling [canLoad] on each loader in order and using the
 * first that accepts the descriptor's source. Implement this (rather than bare [ResourceLoader])
 * when you want a custom loader to participate in source-type dispatch — e.g. a loader for a new
 * `ResourceSource` kind, or an [AsyncResourceLoader] that bridges a suspending data source.
 *
 * [load] defaults to [loadTyped]; override either — typically just [loadTyped].
 */
public interface TypedResourceLoader : ResourceLoader {
    fun canLoad(source: ResourceSource): Boolean

    fun loadTyped(descriptor: ResourceDescriptor): ResourceData

    override fun load(descriptor: ResourceDescriptor): ResourceData = loadTyped(descriptor)
}
