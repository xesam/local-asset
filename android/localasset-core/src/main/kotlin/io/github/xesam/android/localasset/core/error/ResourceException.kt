package io.github.xesam.android.localasset.core.error

class ResourceException(
    val category: ResourceErrorCategory,
    override val message: String,
    val stage: String? = null,
    causeError: Throwable? = null,
) : RuntimeException(message, causeError)
