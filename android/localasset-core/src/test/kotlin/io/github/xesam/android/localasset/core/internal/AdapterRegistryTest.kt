package io.github.xesam.android.localasset.core.internal

import io.github.xesam.android.localasset.core.api.SchemeAdapter
import io.github.xesam.android.localasset.core.error.ResourceErrorCategory
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.AssetRequest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class AdapterRegistryTest {
    @Test
    fun selects_first_matching_adapter() {
        val adapter1 = object : SchemeAdapter {
            override fun canHandle(url: String) = url.startsWith("local-asset://app1")
            override fun parse(url: String) = AssetRequest("local-asset", "app1", "page", "/page", emptyMap(), null)
        }
        val adapter2 = object : SchemeAdapter {
            override fun canHandle(url: String) = url.startsWith("local-asset://app2")
            override fun parse(url: String) = AssetRequest("local-asset", "app2", "page", "/page", emptyMap(), null)
        }
        val registry = AdapterRegistry(listOf(adapter1, adapter2))

        val selected = registry.select("local-asset://app1/page")

        assertEquals(adapter1, selected)
    }

    @Test
    fun throws_parse_error_when_no_adapter_matches() {
        val registry = AdapterRegistry(emptyList())

        val error = assertFailsWith<ResourceException> {
            registry.select("local-asset://unknown/resource")
        }

        assertEquals(ResourceErrorCategory.PARSE_ERROR, error.category)
    }
}
