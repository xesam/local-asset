package io.github.xesam.android.localasset.sample

import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import io.github.xesam.android.localasset.core.api.EngineResult
import io.github.xesam.android.localasset.core.api.LocalAsset
import io.github.xesam.android.localasset.core.error.ResourceException
import io.github.xesam.android.localasset.core.model.ResolveContext
import io.github.xesam.android.localasset.core.model.ResourceHandle
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.webview.api.LocalAssetWebViewClient
import org.json.JSONObject
import java.io.File

/**
 * 整个示例应用的**唯一** Activity：一块全屏 WebView。
 *
 * ## 为什么只剩一个
 *
 * demo 是一个完整的 web 应用，首页（`demo/pages/index.html`）也是它的一页，页间跳转由
 * HTML 里的 `<a href>` 完成。原生这一侧只负责三件事，都不是"演示内容"：
 *
 * 1. 装载 WebView 并接上 `LocalAssetWebViewClient`
 * 2. 构建引擎（见 [DemoEngine]）
 * 3. 实现 JSBridge —— 图片选择器、句柄注册这些**只有原生能做**的事
 *
 * 演示的标题、说明、分组、按钮全部在共享 HTML 里，三端加载同一份，因此三端长得一样。
 * 曾经这里有 8 个 Activity + 一个原生首页，每端各写一套 —— 那正是三端外观不一致的根因。
 *
 * **维护约束**：不要把任何演示文案搬回本文件。屏幕上该出现的字，都属于 `shared/demo/`。
 */
class DemoActivity : ComponentActivity() {
    lateinit var webView: WebView
        private set
    private lateinit var localAsset: LocalAsset

    /**
     * 本次会话注册过的所有句柄 URI。
     *
     * 合并前 handle-lifecycle 与 jsbridge-image-picker 各自维护一份，各自的 Reset 按钮
     * 只清自己那份。现在两个场景共用一个 handleRegistry，故合并成一份，`resetSession()`
     * 统一清空 —— 语义与合并前一致（都是"把本场景注册过的句柄全撤掉再刷新"）。
     */
    private val registeredHandleUris = linkedSetOf<String>()

    private val imagePicker = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) {
            dispatchJs("window.LocalAssetSampleNative.onChooseError('Image picking was cancelled')")
        } else {
            handlePickedImage(uri)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        localAsset = DemoEngine.create(this)

        WebView.setWebContentsDebuggingEnabled(true)
        webView = WebView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.allowFileAccess = true
            setBackgroundColor(Color.WHITE)
            webViewClient = LocalAssetWebViewClient(
                localAsset = localAsset,
                engineScope = DemoEngine.ENGINE_SCOPE,
            )
            webChromeClient = SampleWebChromeClient()
            // 两个桥名都要注册：多数页面调 NativeSampleBridge，唯独
            // graceful-degradation.html 调 LocalAssetSampleBridge.getRevokedHandleUri()。
            // 名字对不上时页面脚本会抛 TypeError 并整段中断 —— 表现为白页，无任何提示。
            addJavascriptInterface(SampleBridge(), "NativeSampleBridge")
            addJavascriptInterface(SampleBridge(), "LocalAssetSampleBridge")
        }
        setContentView(webView)

        // WebView 有历史就先退一页，否则才退出应用。
        //
        // 页间跳转由共享 HTML 承担，系统返回键若直接结束 Activity，从任一场景页按返回
        // 就会直接退出应用而不是回到首页 —— 与 HarmonyOS 侧行为不一致。
        //
        // 用 dispatcher 而非重写 onBackPressed()：后者已废弃，且在 Android 13+
        // 开启预测式返回后不再被调用。callback 内 disable 自己再转发，是官方推荐的
        // "本次不消费"写法 —— 直接调 finish() 会跳过其他已注册的 callback。
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) {
                    webView.goBack()
                } else {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        })

        prepareRevokedHandle()
        webView.loadUrl(INDEX_URL)
    }

    override fun onDestroy() {
        if (this::webView.isInitialized) {
            webView.destroy()
        }
        super.onDestroy()
    }

    /**
     * graceful-degradation 需要一条**已吊销**的 handle URI：注册后立刻撤销，页面再请求它
     * 就会 404，用以演示失效的 capability 在 H5 侧优雅降级。
     *
     * 必须在页面加载前备好 —— 该页在**顶层脚本**（早于 DOMContentLoaded）同步调用
     * `getRevokedHandleUri()`，那时拿不到值就只能显示空字符串。
     */
    private fun prepareRevokedHandle() {
        val uri = localAsset.registerHandle(
            ResourceHandle(source = ResourceSource.Bytes(logoBytes()), fileName = "logo.svg", mimeType = "image/svg+xml"),
        )
        localAsset.removeHandle(uri)
        revokedHandleUri = uri
    }

    private var revokedHandleUri: String = ""

    private fun logoBytes(): ByteArray = SampleFiles.assetBytes(this, "demo/static/images/logo.svg")

    private fun dispatchJs(script: String) {
        runOnUiThread { webView.evaluateJavascript(script, null) }
    }

    /**
     * 八个场景共用的桥。合并前每个 Activity 各挂一个只含自己那几个方法的桥对象；
     * 现在只有一块 WebView，故合成一个 —— 页面只调自己需要的方法，多出来的方法对它无副作用。
     */
    private inner class SampleBridge {

        // ---- 通用（替代原先的原生页头按钮）----

        /** 撤销本次会话注册的全部句柄后刷新。对应原生页头上那个 Reset / Reset Session 按钮。 */
        @JavascriptInterface
        fun resetSession() {
            runOnUiThread {
                registeredHandleUris.forEach { localAsset.removeHandle(it) }
                registeredHandleUris.clear()
                webView.reload()
            }
        }

        // ---- handle-lifecycle ----

        @JavascriptInterface
        fun registerHandle(ttlSeconds: Int) {
            runCatching {
                val uri = localAsset.registerHandle(
                    ResourceHandle(
                        source = ResourceSource.Bytes(logoBytes()),
                        fileName = "logo.svg",
                        mimeType = "image/svg+xml",
                        ttlMillis = ttlSeconds.toLong() * 1000L,
                    ),
                )
                registeredHandleUris += uri
                JSONObject().put("uri", uri).toString()
            }.onSuccess { payload ->
                dispatchJs("window.LocalAssetSampleNative.onRegister($payload)")
            }.onFailure { error ->
                dispatchJs("window.LocalAssetSampleNative.onRegister(${errorJson(error)})")
            }
        }

        @JavascriptInterface
        fun revokeHandle(uri: String) {
            localAsset.removeHandle(uri)
            dispatchJs("window.LocalAssetSampleNative.onRevoke()")
        }

        @JavascriptInterface
        fun probeResolveHandle(uri: String) {
            val payload = runCatching {
                localAsset.resolveHandle(uri)
                JSONObject().put("ok", true).toString()
            }.getOrElse { error ->
                val e = error as? ResourceException
                JSONObject()
                    .put("ok", false)
                    .put("category", e?.category?.name ?: "UNKNOWN")
                    .put("stage", e?.stage ?: JSONObject.NULL)
                    .put("message", e?.message ?: error.message ?: "unknown")
                    .toString()
            }
            dispatchJs("window.LocalAssetSampleNative.onProbe($payload)")
        }

        // ---- security-models ----

        @JavascriptInterface
        fun getHandleUri() {
            // 每次调用都新注册一条：本方法在 DOMContentLoaded 里被调用，而用户可能
            // 反复进出该页；沿用一条会话级 URI 会在 resetSession 之后失效。
            val uri = localAsset.registerHandle(
                ResourceHandle(source = ResourceSource.Bytes(logoBytes()), fileName = "logo.svg", mimeType = "image/svg+xml"),
            )
            registeredHandleUris += uri
            dispatchJs("window.LocalAssetSampleNative.onHandleUri(${JSONObject.quote(uri)})")
        }

        @JavascriptInterface
        fun probeResolve(url: String) {
            dispatchJs("window.LocalAssetSampleNative.onProbe(${resolveToJson(url)})")
        }

        // ---- error-categories ----

        @JavascriptInterface
        fun trigger(kind: String) {
            val url = when (kind) {
                "parse" -> "local-asset://"
                "resolution" -> "local-asset://nobody.demo.local/x"
                "load" -> "local-asset://errorcat.demo.local/load-boom"
                "security" -> "local-asset://security.demo.local/engine-mismatch"
                else -> return
            }
            val result = localAsset.engine.resolve(url, ResolveContext(engineScope = DemoEngine.ENGINE_SCOPE))
            val resultObj = when (result) {
                is EngineResult.Success -> JSONObject()
                    .put("category", "OK")
                    .put("stage", JSONObject.NULL)
                    .put("message", "resolved")
                is EngineResult.Failure -> JSONObject()
                    .put("category", result.category.name)
                    .put("stage", result.stage ?: JSONObject.NULL)
                    .put("message", result.reason)
            }
            val payload = JSONObject().put("kind", kind).put("result", resultObj).toString()
            dispatchJs("window.LocalAssetSampleNative.onResult($payload)")
        }

        // ---- graceful-degradation ----

        /** 同步返回 —— 该页在顶层脚本里直接取返回值，不走回调。 */
        @JavascriptInterface
        fun getRevokedHandleUri(): String = revokedHandleUri

        // ---- jsbridge-image-picker ----

        @JavascriptInterface
        fun chooseImage() {
            runOnUiThread { imagePicker.launch("image/*") }
        }

        @JavascriptInterface
        fun submitImage(previewUri: String) {
            handleSubmit(previewUri)
        }
    }

    private fun resolveToJson(url: String): String {
        val result = localAsset.engine.resolve(url, ResolveContext(engineScope = DemoEngine.ENGINE_SCOPE))
        return when (result) {
            is EngineResult.Success -> JSONObject().put("ok", true).toString()
            is EngineResult.Failure -> JSONObject()
                .put("ok", false)
                .put("category", result.category.name)
                .put("stage", result.stage ?: JSONObject.NULL)
                .put("message", result.reason)
                .toString()
        }
    }

    private fun errorJson(error: Throwable): String =
        JSONObject().put("ok", false).put("message", error.message ?: "unknown").toString()

    private fun handlePickedImage(uri: Uri) {
        Thread {
            runCatching {
                val bytes = SampleFiles.readContentBytes(this, uri)
                val mimeType = SampleFiles.queryMimeType(this, uri)
                val baseName = SampleFiles.queryDisplayName(this, uri).substringBeforeLast('.', "")
                    .ifBlank { "picked-image" }
                val fileName = SampleFiles.fileNameForMime(baseName = baseName, mimeType = mimeType)
                val previewUri = localAsset.registerHandle(
                    ResourceHandle(
                        source = ResourceSource.Bytes(bytes),
                        fileName = fileName,
                        mimeType = mimeType,
                        metadata = mapOf(ANDROID_CONTENT_URI_KEY to uri.toString()),
                    ),
                )
                registeredHandleUris += previewUri
                JSONObject()
                    .put("previewUri", previewUri)
                    .put("fileName", fileName)
                    .put("mimeType", mimeType)
            }.onSuccess { payload ->
                dispatchJs("window.LocalAssetSampleNative.onChooseSuccess($payload)")
            }.onFailure { error ->
                dispatchJs(
                    "window.LocalAssetSampleNative.onChooseError(" +
                        JSONObject.quote(error.message ?: "Unknown image error") + ")",
                )
            }
        }.start()
    }

    private fun handleSubmit(previewUri: String) {
        Thread {
            runCatching {
                val record = localAsset.resolveHandle(previewUri)
                val contentUri = requireNotNull(record.metadata[ANDROID_CONTENT_URI_KEY]) {
                    "Missing android.content_uri metadata for $previewUri"
                }
                val bytes = (record.source as? ResourceSource.Bytes)?.value
                    ?: error("preview handle for $previewUri is not a bytes handle")
                val safeName = record.fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val submittedFile = File(cacheDir, "submitted-$safeName").apply { writeBytes(bytes) }
                JSONObject()
                    .put("previewUri", record.resourceUri)
                    .put("contentUri", contentUri)
                    .put("localCachePath", submittedFile.absolutePath)
                    .put("fileName", record.fileName)
                    .put("mimeType", record.mimeType)
                    .put("size", submittedFile.length())
            }.onSuccess { payload ->
                dispatchJs("window.LocalAssetSampleNative.onSubmitSuccess($payload)")
            }.onFailure { error ->
                dispatchJs(
                    "window.LocalAssetSampleNative.onSubmitError(" +
                        JSONObject.quote(error.message ?: "Unknown submit error") + ")",
                )
            }
        }.start()
    }

    private companion object {
        const val INDEX_URL = "file:///android_asset/demo/pages/index.html"
        const val ANDROID_CONTENT_URI_KEY = "android.content_uri"
    }
}
