package io.github.xesam.android.localasset.core.model

enum class ResourceType {
    STATIC,
    DYNAMIC,
}

enum class ResourceScope {
    ENGINE,
    PAGE,
    SESSION,
}

sealed interface ResourceSource {
    /**
     * Holds the resource bytes. `value` is a `ByteArray`, whose inherited `equals`/`hashCode` are
     * identity-based — leaving the `data class` defaults in place would make two `Bytes` with
     * identical content compare unequal and hash differently, which breaks any set/map/diff usage
     * and silently mismatches in tests. We override both to be content-based.
     */
    data class Bytes(val value: ByteArray) : ResourceSource {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Bytes) return false
            return value.contentEquals(other.value)
        }

        override fun hashCode(): Int = value.contentHashCode()

        override fun toString(): String = "Bytes(value=[${value.size} bytes])"
    }

    data class FilePath(val value: String) : ResourceSource

    /**
     * A re-openable streaming source: [open] is a factory that returns a *fresh* `InputStream` on
     * every call. The descriptor (and thus the factory) is a stable, reusable value, while each
     * opened stream is one-shot — only the platform response layer calls [open] and is responsible
     * for consuming and closing the resulting stream. This lets directory-backed resolvers hand
     * off assets/bundle files without buffering the whole file into memory at resolve time.
     *
     * Plain `class` (not `data class`): a stream source's equality is identity ("same factory"),
     * not content-based — two factories are not meaningfully `==` without draining both, so we do
     * not want the value semantics `data class` would imply. `java.io.InputStream` is a Java
     * stdlib type (not Android), so this stays core-purity-safe.
     */
    class Stream(val open: () -> java.io.InputStream) : ResourceSource {
        override fun toString(): String = "Stream(open=() -> InputStream)"
    }
}

data class ResourceDescriptor(
    val id: String,
    val namespace: String,
    val type: ResourceType,
    val source: ResourceSource,
    val mimeType: String? = null,
    val createdAtMillis: Long,
    val ttlMillis: Long? = null,
    val scope: ResourceScope? = null,
)
