package io.github.xesam.android.localasset.core.api

import io.github.xesam.android.localasset.core.model.ResourceData
import io.github.xesam.android.localasset.core.model.ResourceDescriptor

interface ResourceLoader {
    fun load(descriptor: ResourceDescriptor): ResourceData
}
