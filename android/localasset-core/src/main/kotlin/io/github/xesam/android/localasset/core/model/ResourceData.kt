package io.github.xesam.android.localasset.core.model

/**
 * The loaded resource data. Two variants:
 * - [Bytes]: the resource is materialized into memory. `ByteArray` uses content-based equality
 *   (see [ResourceSource.Bytes] for why the `data class` defaults are wrong here).
 * - [Stream]: a re-openable factory `() -> InputStream`. The factory is a stable, reusable value;
 *   each [Stream.open] call yields a fresh one-shot stream that the platform response layer
 *   consumes and closes. Equality is identity ("same factory"), since two factories are not
 *   meaningfully `==` without draining both — hence a plain `class`, not `data class`.
 *
 * [mimeType] is exposed on the sealed interface so callers that only need the type (e.g. response
 * builders) don't have to pattern-match.
 */
sealed interface ResourceData {
    val mimeType: String?

    data class Bytes(
        val bytes: ByteArray,
        override val mimeType: String?,
    ) : ResourceData {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Bytes) return false
            return bytes.contentEquals(other.bytes) && mimeType == other.mimeType
        }

        override fun hashCode(): Int = 31 * bytes.contentHashCode() + (mimeType?.hashCode() ?: 0)

        override fun toString(): String = "Bytes(bytes=[${bytes.size} bytes], mimeType=$mimeType)"
    }

    class Stream(
        val open: () -> java.io.InputStream,
        override val mimeType: String?,
    ) : ResourceData {
        override fun toString(): String = "Stream(open=() -> InputStream, mimeType=$mimeType)"
    }
}
