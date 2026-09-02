package io.github.xesam.android.localasset.core.model

/**
 * `identifier` and `path` are each independently nullable, but per `design.md §4.1` at least one
 * of the two must be non-null. Both stay required (no default) so every call site — including
 * custom `SchemeAdapter` implementations — has to make an explicit choice for each rather than
 * silently defaulting into an invalid combination; the validation below turns a violation into
 * an immediate, obvious failure instead of a resolver silently skipping the request later.
 */
data class AssetRequest(
    val scheme: String,
    val namespace: String,
    val identifier: String?,
    val path: String?,
    val query: Map<String, String> = emptyMap(),
    val fragment: String? = null,
    val metadata: Map<String, String> = emptyMap(),
) {
    init {
        require(identifier != null || path != null) {
            "AssetRequest requires identifier or path to be non-null"
        }
    }
}
