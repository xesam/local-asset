package io.github.xesam.android.localasset.webview.compat

import io.github.xesam.android.localasset.core.cors.CorsPolicy
import org.json.JSONArray
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Cross-platform parity contract for CORS headers: loads the shared `cors-headers.json` fixture and
 * asserts the core [CorsPolicy] reproduces the exact header map for every case. Mirrors
 * `CorsHeadersFixtureTests` (iOS) and `CorsHeadersFixture.test.ets` (HarmonyOS) so a policy change
 * on one platform breaks the others' tests.
 */
@RunWith(RobolectricTestRunner::class)
class CorsHeadersFixtureTest {
    @Test
    fun cors_headers_fixture_matches_policy() {
        val repoRoot = System.getProperty("localasset.repo.root")
        val fixture = File(repoRoot, "docs/compatibility-fixtures/cors-headers.json")
        val cases = JSONArray(fixture.readText())
        for (i in 0 until cases.length()) {
            val row = cases.getJSONObject(i)
            val name = row.getString("name")
            val input = row.getJSONObject("input")
            val origins = input.getJSONArray("allowedOrigins")
            val allowedOrigins = (0 until origins.length()).map { origins.getString(it) }.toSet()
            val requestOrigin = if (input.isNull("requestOrigin")) null else input.getString("requestOrigin")

            val actual = CorsPolicy.headers(allowedOrigins, requestOrigin)

            val expectedJson = row.getJSONObject("expected")
            val expected = expectedJson.keys().asSequence().associateWith { expectedJson.getString(it) }
            assertEquals(expected, actual, "headers for $name")
        }
    }
}
