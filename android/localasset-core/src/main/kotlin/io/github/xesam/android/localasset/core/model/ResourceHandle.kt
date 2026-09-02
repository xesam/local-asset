package io.github.xesam.android.localasset.core.model

/**
 * Holds a runtime resource pending registration as a `local-asset://handles/...` URI.
 *
 * The handle carries a [ResourceSource] — typically [ResourceSource.Bytes] (in-memory) or
 * [ResourceSource.FilePath] (a file on disk). Bytes handles load straight from memory; file-backed
 * handles let a large runtime resource (download, generated PDF, camera capture written to cache)
 * be exposed as a revocable, expiring capability **without** materializing the whole file into
 * memory at register time — the file is read lazily by [FileResourceLoader] at resolve time, and
 * postCheck still enforces it sits under an allowed file root (design.md §5.4 / §5.5).
 *
 * `ResourceSource` is content-equal for [ResourceSource.Bytes] (overridden equals/hashCode) and
 * value-equal for [ResourceSource.FilePath], so the `data class` defaults are safe here — unlike
 * the old `bytes: ByteArray` field whose identity-based defaults forced a hand-written equals.
 */
data class ResourceHandle(
    val source: ResourceSource,
    val fileName: String,
    val mimeType: String,
    val metadata: Map<String, String> = emptyMap(),
    val ttlMillis: Long? = null,
) {
    override fun toString(): String =
        "ResourceHandle(fileName=$fileName, mimeType=$mimeType, source=$source)"
}

data class ResourceHandleRecord(
    val resourceUri: String,
    val source: ResourceSource,
    val fileName: String,
    val mimeType: String,
    /**
     * Known byte length for [ResourceSource.Bytes] handles; `null` for [ResourceSource.FilePath]
     * (the file's size is not probed at register time — the handle is a capability pointing at a
     * path, and the file may not even exist yet; it is read at resolve time). Callers that need a
     * size for a file-backed handle should stat the resolved path themselves.
     */
    val size: Long?,
    val metadata: Map<String, String>,
    val ttlMillis: Long? = null,
) {
    override fun toString(): String =
        "ResourceHandleRecord(resourceUri=$resourceUri, fileName=$fileName, mimeType=$mimeType, source=$source)"
}
