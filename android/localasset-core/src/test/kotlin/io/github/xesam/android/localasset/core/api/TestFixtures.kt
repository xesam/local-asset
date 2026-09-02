package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.model.ResourceHandle
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType

object TestFixtures {
    fun resourceDescriptor(
        id: String,
        namespace: String,
        bytes: ByteArray,
        mimeType: String?,
    ): ResourceDescriptor = ResourceDescriptor(
        id = id,
        namespace = namespace,
        type = ResourceType.DYNAMIC,
        source = ResourceSource.Bytes(bytes),
        mimeType = mimeType,
        createdAtMillis = 0L,
        ttlMillis = null,
        scope = null,
    )

    fun resourceHandle(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        metadata: Map<String, String> = emptyMap(),
    ): ResourceHandle = ResourceHandle(
        source = ResourceSource.Bytes(bytes),
        fileName = fileName,
        mimeType = mimeType,
        metadata = metadata,
        ttlMillis = null,
    )

    fun resourceFileHandle(
        filePath: String,
        fileName: String,
        mimeType: String,
        metadata: Map<String, String> = emptyMap(),
    ): ResourceHandle = ResourceHandle(
        source = ResourceSource.FilePath(filePath),
        fileName = fileName,
        mimeType = mimeType,
        metadata = metadata,
        ttlMillis = null,
    )
}
