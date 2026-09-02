package io.github.xesam.android.localasset.webview.observer

import android.util.Log
import io.github.xesam.android.localasset.core.api.EngineObserver
import io.github.xesam.android.localasset.core.api.EngineStageEvent

/**
 * An [EngineObserver] that mirrors every pipeline stage to `Log.d` under tag `LocalAssetObserver`.
 *
 * This is the structured-logging counterpart to [WebViewAssetInterceptor]'s `onFailure` callback:
 * that callback only fires on terminal failures (and is the right channel for crash reporting
 * since `Log.d` is stripped from release builds), while this observer records the *full* path —
 * adapter parse, both policy checks, every resolver's skip/hit/failure, the load step, and the
 * terminal outcome — so a `adb logcat` trace during development shows the whole decision chain.
 *
 * Attach via `LocalAsset.Builder.observer(LoggingEngineObserver())`.
 */
class LoggingEngineObserver(
    private val tag: String = DEFAULT_TAG,
    private val logger: (level: Int, tag: String, message: String) -> Unit = ::defaultLog,
) : EngineObserver {

    override fun onStage(event: EngineStageEvent) {
        val parts = buildList {
            add("stage=${event.stage}")
            event.request?.let { add("ns=${it.namespace}") }
            event.resolverIndex?.let { add("resolver[$it]=${event.resolver?.javaClass?.simpleName ?: "-"}=${event.resolverResult}") }
            event.descriptor?.let { add("descriptor=${it.id}") }
            event.failure?.let { add("failure[${it.category}/${it.stage}] ${it.reason}") }
        }
        runCatching { logger(Log.DEBUG, tag, parts.joinToString(" ")) }
    }

    private companion object {
        const val DEFAULT_TAG = "LocalAssetObserver"
        private fun defaultLog(level: Int, tag: String, message: String) {
            Log.println(level, tag, message)
        }
    }
}
