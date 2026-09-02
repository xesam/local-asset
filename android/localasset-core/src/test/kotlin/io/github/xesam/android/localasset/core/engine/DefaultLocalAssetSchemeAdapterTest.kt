package io.github.xesam.android.localasset.core.engine

import io.github.xesam.android.localasset.core.error.ResourceException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class DefaultLocalAssetSchemeAdapterTest {
    private val adapter = DefaultLocalAssetSchemeAdapter()

    @Test
    fun parses_basic_local_asset_url() {
        val request = adapter.parse("local-asset://image/logo?id=home&theme=dark")

        assertEquals("local-asset", request.scheme)
        assertEquals("image", request.namespace)
        assertEquals("logo", request.identifier)
        assertEquals("/logo", request.path)
        assertEquals("home", request.query["id"])
        assertEquals("dark", request.query["theme"])
    }

    @Test
    fun rejects_invalid_url() {
        assertFailsWith<ResourceException> {
            adapter.parse("local-asset:///invalid")
        }
    }

    @Test
    fun decodes_percent_encoded_query_values() {
        // Regression: decode() must use the URLDecoder.decode(String, String) overload
        // (available since API 1), not the (String, Charset) overload added in API 33.
        // The project minSdk is 24, so the Charset overload throws NoSuchMethodError on
        // API 24–32 whenever a local-asset:// URL carries a query string.
        val request = adapter.parse("local-asset://cdn.demo.local/pkg/card?mode=light%20theme&name=a%2Bb")

        assertEquals("light theme", request.query["mode"])
        assertEquals("a+b", request.query["name"])
    }
}
