package io.github.xesam.android.localasset.core.registry

import io.github.xesam.android.localasset.core.api.RegistryLookupResult
import io.github.xesam.android.localasset.core.api.ResourceRegistry
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import java.util.concurrent.ConcurrentHashMap

class InMemoryResourceRegistry(
    private val nowMillis: () -> Long = System::currentTimeMillis,
) : ResourceRegistry {
    private val items = ConcurrentHashMap<String, ResourceDescriptor>()

    override fun register(descriptor: ResourceDescriptor) {
        if (items.putIfAbsent(descriptor.id, descriptor) != null) {
            throw ResourceException(
                category = ResourceErrorCategory.RESOLUTION_ERROR,
                message = "duplicate resource id: ${descriptor.id}",
            )
        }
    }

    override fun lookup(id: String): RegistryLookupResult {
        val descriptor = items[id] ?: return RegistryLookupResult.Missing
        val ttlMillis = descriptor.ttlMillis ?: return RegistryLookupResult.Hit(descriptor)
        return if (descriptor.createdAtMillis + ttlMillis <= nowMillis()) {
            RegistryLookupResult.Expired
        } else {
            RegistryLookupResult.Hit(descriptor)
        }
    }

    override fun remove(id: String) {
        items.remove(id)
    }

    override fun cleanup(nowMillis: Long) {
        items.entries.removeIf { (_, descriptor) ->
            descriptor.ttlMillis?.let { descriptor.createdAtMillis + it <= nowMillis } == true
        }
    }
}
