package io.github.xesam.android.localasset.sample

import io.github.xesam.android.localasset.core.api.LocalAsset
import io.github.xesam.android.localasset.core.api.ResolverResult
import io.github.xesam.android.localasset.core.api.ResourceResolver
import io.github.xesam.android.localasset.core.model.ResourceDescriptor
import io.github.xesam.android.localasset.core.model.ResourceScope
import io.github.xesam.android.localasset.core.model.ResourceSource
import io.github.xesam.android.localasset.core.model.ResourceType
import io.github.xesam.android.localasset.core.registry.InMemoryHandleRegistry
import io.github.xesam.android.localasset.webview.mapping.AssetDirectoryResolver
import io.github.xesam.android.localasset.webview.mapping.FileDirectoryResolver
import java.io.File

/**
 * 演示引擎：8 条 sample flow 共用**一个** LocalAsset 实例。
 *
 * ## 为什么必须合并
 *
 * 演示的首页与页间跳转都在 Web 侧（`shared/demo/pages/index.html` 里的 `<a href>`），
 * 原生不再感知"当前是哪个场景"，也就没有任何时机去换引擎。所以八套配置必须一次性
 * 装进同一个引擎。
 *
 * ## 合并为什么是安全的（逐条核实过，不是假设）
 *
 * - **host 互不重叠**：assets. / cdn. / chain. / resilient. / security. / errorcat.demo.local
 *   各占一个命名空间，resolver 不命中即 Skip 落到下一条，彼此不会截胡。
 * - **handleRegistry 只能有一个**（`LocalAsset.Builder.handleRegistry()` 是单值），而原先
 *   四个场景各配一个。核实结论：`InMemoryHandleRegistry` 的 host 参数**只影响 register()
 *   生成的 URI 字面量**，resolve() 按完整 URI 查表、不校验 host。而那四个场景都是
 *   先 registerHandle() 拿 URI 再用，从不硬编码 host —— 故统一成一个 registry 后行为不变。
 * - **`/engine-mismatch` 被两个场景共用**（security-models 与 error-categories）。两者对它的
 *   期望一致：都要 SECURITY_ERROR。字节内容不参与断言（postCheck 在 load 之前就拒了），
 *   故合并成一条 resolver 规则即可，不是冲突。
 * - **allowedFileRoot 需要两个**（error-categories 的 cacheDir、directory-routing 的
 *   sample-pkg）。`addAllowedFileRoot` 可多次调用，且 sample-pkg 就在 cacheDir 之下。
 *   这里仍两条都写，是为了让"哪个场景需要哪个根"在代码里保持可读，而不依赖包含关系这个巧合。
 */
object DemoEngine {
    /**
     * 统一的 engineScope。security-models / error-categories 原本用 "demo-engine"，
     * 其余用默认值 —— 统一到前者。
     *
     * security-models 演示的"作用域不匹配"靠 resolver 返回 `namespace = "other-engine"`
     * 实现，与本值取什么无关，故统一不影响该场景。
     */
    const val ENGINE_SCOPE = "demo-engine"

    private const val LOGO_ASSET = "demo/static/images/logo.svg"

    fun create(activity: DemoActivity): LocalAsset {
        val logo = SampleFiles.assetBytes(activity, LOGO_ASSET)

        // directory-routing 需要一个真实的沙箱目录才能演示 FilePath 链路（assets 不是文件系统路径）。
        val packageDirectory = File(activity.cacheDir, "sample-pkg").apply { deleteRecursively() }
        SampleFiles.copyAssetDirectory(activity, "demo/pkg", packageDirectory)

        // LOAD_ERROR 需要一条"在允许的根之下、但文件不存在"的路径：postCheck 的包含校验通过，
        // 随后 FileResourceLoader 才因读不到而失败 —— 这正是 LOAD_ERROR 与 SECURITY_ERROR 的分界。
        val missingFile = File(activity.cacheDir, "missing-boom-bin").absolutePath

        return LocalAsset.Builder()
            .handleRegistry(
                InMemoryHandleRegistry(host = "handles.demo.local", pathPrefix = "/handles"),
            )
            // 链首：resolver-chain 的覆盖 resolver。先加即先跑，Hit 即短路（design.md §3.4）。
            .addResolver(
                ResourceResolver { request, _ ->
                    if (request.namespace == "chain.demo.local" && request.path == "/base/banner.svg") {
                        val mode = request.query["mode"] ?: "dark"
                        ResolverResult.Hit(
                            ResourceDescriptor(
                                id = "override-banner-$mode",
                                namespace = request.namespace,
                                type = ResourceType.DYNAMIC,
                                source = ResourceSource.Bytes(overrideBanner(mode)),
                                mimeType = "image/svg+xml",
                                createdAtMillis = System.currentTimeMillis(),
                                ttlMillis = null,
                                scope = null,
                            ),
                        )
                    } else {
                        ResolverResult.Skip
                    }
                },
            )
            // security-models + error-categories：两套安全模型与错误分类共用的规则。
            .addResolver(
                ResourceResolver { request, _ ->
                    when (request.namespace to request.path) {
                        "security.demo.local" to "/engine-matched" ->
                            hit("engine-matched", "demo-engine", ResourceScope.ENGINE, ResourceSource.Bytes(logo), "image/svg+xml")
                        // namespace 刻意写成 other-engine：与上下文 engineScope 不匹配 → postCheck 拒绝。
                        "security.demo.local" to "/engine-mismatch" ->
                            hit("engine-mismatch", "other-engine", ResourceScope.ENGINE, ResourceSource.Bytes(logo), "image/svg+xml")
                        "errorcat.demo.local" to "/load-boom" ->
                            hit("load-boom", "errorcat.demo.local", null, ResourceSource.FilePath(missingFile), null)
                        else -> ResolverResult.Skip
                    }
                },
            )
            // static-mapping
            .addResolver(
                AssetDirectoryResolver(
                    appContext = activity,
                    host = "assets.demo.local",
                    pathPrefix = "/static",
                    assetDirectory = "demo/static",
                ),
            )
            // resolver-chain 的兜底目录 resolver：仅在上面那条覆盖 resolver Skip 时才到达。
            .addResolver(
                AssetDirectoryResolver(
                    appContext = activity,
                    host = "chain.demo.local",
                    pathPrefix = "/base",
                    assetDirectory = "demo/base",
                ),
            )
            // graceful-degradation
            .addResolver(
                AssetDirectoryResolver(
                    appContext = activity,
                    host = "resilient.demo.local",
                    pathPrefix = "/static",
                    assetDirectory = "demo/static",
                ),
            )
            // directory-routing
            .addResolver(
                FileDirectoryResolver(
                    host = "cdn.demo.local",
                    pathPrefix = "/pkg",
                    rootDirectory = packageDirectory,
                ),
            )
            .addAllowedFileRoot(activity.cacheDir)
            .addAllowedFileRoot(packageDirectory)
            .build()
    }

    private fun hit(
        id: String,
        namespace: String,
        scope: ResourceScope?,
        source: ResourceSource,
        mimeType: String?,
    ): ResolverResult.Hit = ResolverResult.Hit(
        ResourceDescriptor(
            id = id,
            namespace = namespace,
            type = ResourceType.DYNAMIC,
            source = source,
            mimeType = mimeType,
            createdAtMillis = System.currentTimeMillis(),
            ttlMillis = null,
            scope = scope,
        ),
    )

    private fun overrideBanner(mode: String): ByteArray {
        val (bg, fg, label) = if (mode == "light") {
            Triple("#fff7ed", "#fb923c", "Override (light)")
        } else {
            Triple("#0f172a", "#38bdf8", "Override (dark)")
        }
        return """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 120">
              <rect width="360" height="120" rx="24" fill="$bg"/>
              <text x="180" y="70" text-anchor="middle" font-size="32" fill="$fg">$label</text>
            </svg>
        """.trimIndent().toByteArray()
    }
}
