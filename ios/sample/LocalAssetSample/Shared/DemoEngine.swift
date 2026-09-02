import Foundation
import LocalAssetCore
import LocalAssetWebView

/// 演示引擎：8 条 sample flow 共用**一个** LocalAsset 实例。
///
/// ## 为什么必须合并
///
/// 演示的首页与页间跳转都在 Web 侧（`shared/demo/pages/index.html` 里的 `<a href>`），
/// 原生不再感知"当前是哪个场景"，也就没有任何时机去换引擎。八套配置必须一次装进同一个引擎。
///
/// ## 合并为什么是安全的
///
/// - **host 互不重叠**：assets. / cdn. / chain. / resilient. / security. / errorcat.demo.local
///   各占一个命名空间，resolver 不命中即 skip 落到下一条。
/// - **handleRegistry 只能有一个**，而原先四个场景各配一个。`InMemoryHandleRegistry` 的 host
///   只影响 register() 生成的 URI 字面量，resolve() 按完整 URI 查表、不校验 host；那四个场景
///   都是先 registerHandle() 拿 URI 再用，从不硬编码 host —— 故统一后行为不变。
/// - **`/engine-mismatch` 被 security-models 与 error-categories 共用**，两者期望一致
///   （都要 SECURITY_ERROR），字节内容不参与断言，合并成一条规则即可。
///
/// 与 Android 的 `DemoEngine.kt` / HarmonyOS 的 `DemoEngine.ets` 一一对应。
enum DemoEngine {
    /// 统一的 engineScope。security-models 演示的"不匹配"靠 resolver 返回
    /// `namespace = "other-engine"` 实现，与本值取什么无关。
    static let engineScope = "demo-engine"

    /// 已吊销的 handle URI —— graceful-degradation 用。
    ///
    /// 该页在**顶层脚本**（早于 DOMContentLoaded）同步取这个值，所以必须在 WebView
    /// 建立之前就备好，且要通过 `.atDocumentStart` 的 user script 注入。
    private(set) static var revokedHandleUri: String = ""

    static func make() -> LocalAsset {
        let logo = demoLogoData()

        // LOAD_ERROR 需要一条"在允许的根之下、但文件不存在"的路径：postCheck 的包含校验通过，
        // 随后 FileResourceLoader 才因读不到而失败 —— 这正是 LOAD_ERROR 与 SECURITY_ERROR 的分界。
        let tempDir = FileManager.default.temporaryDirectory
        let missingPath = tempDir.appendingPathComponent("missing-boom-bin").path

        let asset = LocalAsset.Builder()
            .handleRegistry(InMemoryHandleRegistry(host: "handles.demo.local", pathPrefix: "/handles"))
            // 链首：resolver-chain 的覆盖 resolver。先加即先跑，hit 即短路（design.md §3.4）。
            .addResolver(ClosureResolver { request, _ in
                guard request.namespace == "chain.demo.local",
                      request.path == "/base/banner.svg" else { return .skip }
                let mode = request.query["mode"] ?? "dark"
                return .hit(ResourceDescriptor(
                    id: "override-banner-\(mode)", namespace: request.namespace, type: .dynamic,
                    source: .bytes(overrideBanner(mode: mode)), mimeType: "image/svg+xml",
                    createdAtMillis: currentMillis(), ttlMillis: nil, scope: nil))
            })
            // security-models + error-categories 共用的规则。
            .addResolver(ClosureResolver { request, _ in
                switch (request.namespace, request.path) {
                case ("security.demo.local", "/engine-matched"):
                    return .hit(ResourceDescriptor(
                        id: "engine-matched", namespace: "demo-engine", type: .dynamic,
                        source: .bytes(logo), mimeType: "image/svg+xml",
                        createdAtMillis: currentMillis(), ttlMillis: nil, scope: .engine))
                case ("security.demo.local", "/engine-mismatch"):
                    // namespace 刻意写成 other-engine：与上下文 engineScope 不匹配 → postCheck 拒绝。
                    return .hit(ResourceDescriptor(
                        id: "engine-mismatch", namespace: "other-engine", type: .dynamic,
                        source: .bytes(logo), mimeType: "image/svg+xml",
                        createdAtMillis: currentMillis(), ttlMillis: nil, scope: .engine))
                case ("errorcat.demo.local", "/load-boom"):
                    return .hit(ResourceDescriptor(
                        id: "load-boom", namespace: "errorcat.demo.local", type: .dynamic,
                        source: .filePath(missingPath), mimeType: nil,
                        createdAtMillis: currentMillis(), ttlMillis: nil, scope: nil))
                default:
                    return .skip
                }
            })
            // static-mapping
            .addResolver(BundleDirectoryResolver(
                host: "assets.demo.local", pathPrefix: "/static", bundleDirectory: "demo/static"))
            // resolver-chain 的兜底目录 resolver：仅在上面那条覆盖 resolver skip 时才到达。
            .addResolver(BundleDirectoryResolver(
                host: "chain.demo.local", pathPrefix: "/base", bundleDirectory: "demo/base"))
            // graceful-degradation
            .addResolver(BundleDirectoryResolver(
                host: "resilient.demo.local", pathPrefix: "/static", bundleDirectory: "demo/static"))
            // directory-routing
            .addResolver(BundleDirectoryResolver(
                host: "cdn.demo.local", pathPrefix: "/pkg", bundleDirectory: "demo/pkg"))
            .addAllowedFileRoot(tempDir)
            .build()

        // 注册后立刻吊销：页面请求这条 URI 会 404，用以演示失效的 capability 在 H5 侧优雅降级。
        let uri = asset.registerHandle(
            ResourceHandle(source: .bytes(logo), fileName: "logo.svg", mimeType: "image/svg+xml"))
        asset.removeHandle(uri)
        revokedHandleUri = uri

        return asset
    }

    private static func overrideBanner(mode: String) -> Data {
        let bg = mode == "light" ? "#fff7ed" : "#0f172a"
        let fg = mode == "light" ? "#fb923c" : "#38bdf8"
        let label = mode == "light" ? "Override (light)" : "Override (dark)"
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 120">
          <rect width="360" height="120" rx="24" fill="\(bg)"/>
          <text x="180" y="70" text-anchor="middle" font-size="32" fill="\(fg)">\(label)</text>
        </svg>
        """.data(using: .utf8) ?? Data()
    }
}
