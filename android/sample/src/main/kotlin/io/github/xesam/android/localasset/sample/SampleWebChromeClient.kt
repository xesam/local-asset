package io.github.xesam.android.localasset.sample

import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient

class SampleWebChromeClient : WebChromeClient() {
    override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
        val lineInfo = "${consoleMessage.sourceId()}:${consoleMessage.lineNumber()}"
        Log.d("LocalAssetSample", "[console][$lineInfo] ${consoleMessage.message()}")
        return true
    }
}
