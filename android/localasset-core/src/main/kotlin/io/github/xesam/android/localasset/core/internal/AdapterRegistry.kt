package io.github.xesam.android.localasset.core.internal

import io.github.xesam.android.localasset.core.api.SchemeAdapter
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException

class AdapterRegistry(
    private val adapters: List<SchemeAdapter>,
) {
    fun select(url: String): SchemeAdapter = adapters.firstOrNull { it.canHandle(url) }
        ?: throw ResourceException(ResourceErrorCategory.PARSE_ERROR, "no adapter can handle url")
}
