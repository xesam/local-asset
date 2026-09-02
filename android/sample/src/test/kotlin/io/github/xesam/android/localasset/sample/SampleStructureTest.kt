package io.github.xesam.android.localasset.sample

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

class SampleStructureTest {
    @Test
    fun sample_manifest_exists() {
        assertTrue(File("src/main/AndroidManifest.xml").exists())
    }
}
