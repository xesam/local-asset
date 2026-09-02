package io.github.xesam.android.localasset.core.compat

import io.github.xesam.android.localasset.core.engine.DefaultLocalAssetSchemeAdapter
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

class CompatibilityFixtureTest {
    @Test
    fun basic_routing_fixture_exists_and_matches_adapter_expectations() {
        val repoRoot = System.getProperty("localasset.repo.root")
        val fixture = File(repoRoot, "docs/compatibility-fixtures/basic-routing.json")
        val text = fixture.readText()

        assertTrue(fixture.exists())
        assertTrue(text.contains("parse-basic-local-asset-url"))
        assertTrue(text.contains("reject-invalid-local-asset-url"))

        val request = DefaultLocalAssetSchemeAdapter().parse("local-asset://image/logo?id=home&theme=dark")
        assertTrue(text.contains("\"scheme\": \"${request.scheme}\""))
        assertTrue(text.contains("\"namespace\": \"${request.namespace}\""))
        assertTrue(text.contains("\"identifier\": \"${request.identifier}\""))
    }
}
