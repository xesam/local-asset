package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.model.AssetRequest

interface SchemeAdapter {
    fun canHandle(url: String): Boolean

    fun parse(url: String): AssetRequest
}
