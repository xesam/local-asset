package io.github.xesam.android.localasset.webview.compat

import io.github.xesam.android.localasset.core.cache.ResourceCachePolicy
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import org.json.JSONArray
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.ByteArrayInputStream
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Cross-platform parity contract for cache headers: loads the shared `cache-headers.json` fixture
 * and asserts the core [ResourceCachePolicy] reproduces its `cacheControl`/`etag` for every case.
 * Mirrors `CacheHeadersFixtureTests` on iOS so a fixture or policy change that diverges the
 * platforms breaks one side's test. Run under Robolectric so `org.json` (Android framework) is on
 * the classpath; the policy itself is pure core.
 */
@RunWith(RobolectricTestRunner::class)
class CacheHeadersFixtureTest {
    @Test
    fun cache_headers_fixture_matches_policy() {
        val repoRoot = System.getProperty("localasset.repo.root")
        val fixture = File(repoRoot, "docs/compatibility-fixtures/cache-headers.json")
        val cases = JSONArray(fixture.readText())
        for (i in 0 until cases.length()) {
            val row = cases.getJSONObject(i)
            val name = row.getString("name")
            val input = row.getJSONObject("input")
            val type = if (input.getString("type") == "static") ResourceType.STATIC else ResourceType.DYNAMIC
            val source = when (input.getString("source")) {
                "bytes" -> ResourceSource.Bytes(ByteArray(input.getInt("size")))
                "stream" -> ResourceSource.Stream { ByteArrayInputStream(ByteArray(0)) }
                else -> error("unknown source kind in fixture case $name")
            }
            val maxAge = if (input.has("maxAgeSeconds")) {
                input.getInt("maxAgeSeconds")
            } else {
                ResourceCachePolicy.DEFAULT_MAX_AGE_SECONDS
            }
            val descriptor = ResourceDescriptor(
                id = input.getString("id"),
                namespace = "fixture",
                type = type,
                source = source,
                mimeType = null,
                createdAtMillis = 0L,
                ttlMillis = null,
                scope = null,
            )
            val decision = ResourceCachePolicy.decide(descriptor, maxAge)
            val expected = row.getJSONObject("expected")
            assertEquals(expected.getString("cacheControl"), decision.cacheControl, "cacheControl for $name")
            assertEquals(expected.getString("etag"), decision.etag, "etag for $name")
        }
    }
}
