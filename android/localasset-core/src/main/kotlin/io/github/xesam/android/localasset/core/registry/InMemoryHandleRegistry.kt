package io.github.xesam.android.localasset.core.registry

import io.github.xesam.android.localasset.core.api.HandleRegistry
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResourceHandle
import io.github.xesam.android.localasset.core.model.ResourceHandleRecord
import io.github.xesam.android.localasset.core.model.ResourceSource
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class InMemoryHandleRegistry(
    private val host: String = HandleRegistry.DEFAULT_HANDLE_HOST,
    private val pathPrefix: String = "/handles",
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
) : HandleRegistry {
    private val items = ConcurrentHashMap<String, StoredHandle>()

    override fun register(handle: ResourceHandle): String {
        val safeFileName = handle.fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val resourceUri = buildUri(
            token = UUID.randomUUID().toString(),
            fileName = safeFileName,
        )
        // size is only known for Bytes handles; for FilePath it is probed at resolve time, not here.
        val size: Long? = (handle.source as? ResourceSource.Bytes)?.value?.size?.toLong()
        items[resourceUri] = StoredHandle(
            record = ResourceHandleRecord(
                resourceUri = resourceUri,
                source = handle.source,
                fileName = handle.fileName,
                mimeType = handle.mimeType,
                size = size,
                metadata = handle.metadata,
                ttlMillis = handle.ttlMillis,
            ),
            createdAtMillis = nowMillis(),
        )
        return resourceUri
    }

    override fun resolve(resourceUri: String): ResourceHandleRecord {
        return items.compute(resourceUri) { _, stored ->
            if (stored == null) return@compute null
            val ttlMillis = stored.record.ttlMillis
            if (ttlMillis != null && nowMillis() - stored.createdAtMillis >= ttlMillis) {
                null
            } else {
                stored
            }
        }?.record ?: throw ResourceException(
            category = ResourceErrorCategory.RESOLUTION_ERROR,
            message = "Unknown or expired resourceUri: $resourceUri",
        )
    }


    override fun cleanup(nowMillis: Long) {
        items.entries.removeIf { (_, stored) ->
            stored.record.ttlMillis?.let { stored.createdAtMillis + it <= nowMillis } == true
        }
    }

    override fun remove(resourceUri: String) {
        items.remove(resourceUri)
    }

    private fun buildUri(token: String, fileName: String): String {
        val normalizedPrefix = pathPrefix.trim('/').takeIf { it.isNotBlank() } ?: "handles"
        return "local-asset://$host/$normalizedPrefix/$token/$fileName"
    }

    private data class StoredHandle(
        val record: ResourceHandleRecord,
        val createdAtMillis: Long,
    )
}
