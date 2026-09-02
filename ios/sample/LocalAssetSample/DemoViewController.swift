import UIKit
import WebKit
import PhotosUI
import UniformTypeIdentifiers
import LocalAssetCore
import LocalAssetWebView

/// 整个示例应用的**唯一** view controller：一块全屏 WebView。
///
/// ## 为什么只剩一个
///
/// demo 是一个完整的 web 应用，首页（`demo/pages/index.html`）也是它的一页，页间跳转由
/// HTML 里的 `<a href>` 完成。原生只负责：装载 WebView、构建引擎（见 `DemoEngine`）、
/// 实现 JSBridge —— 图片选择器这类**只有原生能做**的事。
///
/// 演示的标题、说明、分组、按钮全部在共享 HTML 里，三端加载同一份，因此三端长得一样。
///
/// ## 为什么改用 loadFileURL
///
/// 旧实现读出 HTML 文本后 `loadHTMLString(baseURL: "local-asset://pages.local/")`，
/// 让页面处于 `local-asset://` 源。这样 `<a href="static-mapping.html">` 会被解析成
/// `local-asset://pages.local/static-mapping.html` —— 落进 scheme handler，而引擎里
/// 没有任何 resolver 认这个 host，跳转必然失败。
///
/// 改用 `loadFileURL(_:allowingReadAccessTo:)` 后页面处于 `file://` 源，相对跳转按文件
/// 路径解析，与 Android / HarmonyOS 一致。`local-asset://` 子资源仍走 scheme handler，
/// 只是变成跨源请求 —— 演示页用 `<img>`/`<link>`/`<script>` 引用子资源，这些标签不经过
/// CORS 检查，故库默认不发 `Access-Control-Allow-Origin` 也不受影响。需要用 `fetch()` 读取
/// `local-asset://` 响应的集成方，给 handler 传 `allowedOrigins` 显式放行对应源即可。
///
/// **维护约束**：不要把任何演示文案搬回本文件。屏幕上该出现的字，都属于 `shared/demo/`。
class DemoViewController: UIViewController, WKScriptMessageHandler, PHPickerViewControllerDelegate {

    private let localAsset: LocalAsset
    private let webView: WKWebView

    /// 本次会话注册过的所有句柄 URI，`resetSession()` 统一清空。
    private var registeredHandleUris: [String] = []

    init() {
        let asset = DemoEngine.make()
        self.localAsset = asset

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            LocalAssetSchemeHandler(engine: asset.engine, contextFactory: { _ in
                ResolveContext(engineScope: DemoEngine.engineScope)
            }),
            forURLScheme: "local-asset"
        )

        // 两个桥名都要注入：多数页面调 NativeSampleBridge，唯独 graceful-degradation.html
        // 调 LocalAssetSampleBridge.getRevokedHandleUri()，且是在**顶层脚本**里同步取返回值
        // —— 故它必须是一个直接返回字符串的函数，不能走 postMessage 异步回调。
        let escapedRevoked = DemoEngine.revokedHandleUri
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let bridgeScript = """
        (function () {
          function post(payload) {
            window.webkit.messageHandlers.localAssetBridge.postMessage(payload);
          }
          window.NativeSampleBridge = {
            resetSession: function () { post({action: "resetSession"}); },
            registerHandle: function (ttlSeconds) { post({action: "registerHandle", ttlSeconds: ttlSeconds}); },
            revokeHandle: function (uri) { post({action: "revokeHandle", uri: uri}); },
            probeResolveHandle: function (uri) { post({action: "probeResolveHandle", uri: uri}); },
            getHandleUri: function () { post({action: "getHandleUri"}); },
            probeResolve: function (url) { post({action: "probeResolve", url: url}); },
            trigger: function (kind) { post({action: "trigger", kind: kind}); },
            chooseImage: function () { post({action: "chooseImage"}); },
            submitImage: function (previewUri) { post({action: "submitImage", previewUri: previewUri}); }
          };
          window.LocalAssetSampleBridge = {
            getRevokedHandleUri: function () { return "\(escapedRevoked)"; }
          };
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        // 占位 handler：self 在 super.init 之前不可用，故先挂一个空实现，init 之后再换掉。
        config.userContentController.add(MessageRelay(), name: "localAssetBridge")

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)

        webView.configuration.userContentController.removeScriptMessageHandler(forName: "localAssetBridge")
        webView.configuration.userContentController.add(self, name: "localAssetBridge")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        loadIndex()
    }

    private func loadIndex() {
        guard let base = Bundle.main.resourceURL else { return }
        let pagesDir = base.appendingPathComponent("demo/pages")
        // allowingReadAccessTo 必须给到 demo/ 而不是 demo/pages/：页面间跳转只需要 pages/，
        // 但 WebKit 也要能读到同源之外被引用的文件。给整棵 demo/ 树最省心且仍受限于 bundle。
        webView.loadFileURL(
            pagesDir.appendingPathComponent("index.html"),
            allowingReadAccessTo: base.appendingPathComponent("demo")
        )
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "resetSession":
            registeredHandleUris.forEach { localAsset.removeHandle($0) }
            registeredHandleUris.removeAll()
            DispatchQueue.main.async { self.webView.reload() }

        case "registerHandle":
            handleRegister(ttlSeconds: body["ttlSeconds"] as? Int ?? 5)

        case "revokeHandle":
            localAsset.removeHandle(body["uri"] as? String ?? "")
            evalJS("window.LocalAssetSampleNative.onRevoke()")

        case "probeResolveHandle":
            probeHandle(uri: body["uri"] as? String ?? "")

        case "getHandleUri":
            // 每次调用都新注册一条：本方法在 DOMContentLoaded 里被调用，用户可能反复进出该页，
            // 沿用一条会话级 URI 会在 resetSession 之后失效。
            let uri = localAsset.registerHandle(
                ResourceHandle(source: .bytes(demoLogoData()), fileName: "logo.svg", mimeType: "image/svg+xml"))
            registeredHandleUris.append(uri)
            evalJS("window.LocalAssetSampleNative.onHandleUri(\(jsQuote(uri)))")

        case "probeResolve":
            probeResolve(url: body["url"] as? String ?? "")

        case "trigger":
            trigger(kind: body["kind"] as? String ?? "")

        case "chooseImage":
            presentPhotoPicker()

        case "submitImage":
            handleSubmit(previewUri: body["previewUri"] as? String ?? "")

        default:
            break
        }
    }

    // MARK: - handle-lifecycle

    private func handleRegister(ttlSeconds: Int) {
        let uri = localAsset.registerHandle(
            ResourceHandle(
                source: .bytes(demoLogoData()), fileName: "logo.svg", mimeType: "image/svg+xml",
                ttlMillis: Int64(ttlSeconds) * 1000))
        registeredHandleUris.append(uri)
        evalJS("window.LocalAssetSampleNative.onRegister({\"uri\":\(jsQuote(uri))})")
    }

    private func probeHandle(uri: String) {
        let payload: String
        do {
            _ = try localAsset.resolveHandle(uri)
            payload = "{\"ok\":true}"
        } catch let e as ResourceException {
            payload = "{\"ok\":false,\"category\":\(jsQuote(errorCategoryName(e.category))),\"stage\":\(e.stage.map { jsQuote($0) } ?? "null"),\"message\":\(jsQuote(e.message))}"
        } catch {
            payload = "{\"ok\":false,\"category\":\"UNKNOWN\",\"stage\":null,\"message\":\(jsQuote(String(describing: error)))}"
        }
        evalJS("window.LocalAssetSampleNative.onProbe(\(payload))")
    }

    // MARK: - security-models

    private func probeResolve(url: String) {
        evalJS("window.LocalAssetSampleNative.onProbe(\(resolveJson(url: url)))")
    }

    // MARK: - error-categories

    private func trigger(kind: String) {
        let url: String
        switch kind {
        case "parse": url = "local-asset://"
        case "resolution": url = "local-asset://nobody.demo.local/x"
        case "load": url = "local-asset://errorcat.demo.local/load-boom"
        case "security": url = "local-asset://security.demo.local/engine-mismatch"
        default: return
        }
        let result = localAsset.engine.resolve(
            url: url, context: ResolveContext(engineScope: DemoEngine.engineScope))
        let resultObj: String
        switch result {
        case .success:
            resultObj = "{\"category\":\"OK\",\"stage\":null,\"message\":\"resolved\"}"
        case .failure(let category, let reason, let stage):
            resultObj = "{\"category\":\(jsQuote(errorCategoryName(category))),\"stage\":\(stage.map { jsQuote($0) } ?? "null"),\"message\":\(jsQuote(reason))}"
        }
        evalJS("window.LocalAssetSampleNative.onResult({\"kind\":\(jsQuote(kind)),\"result\":\(resultObj)})")
    }

    private func resolveJson(url: String) -> String {
        let result = localAsset.engine.resolve(
            url: url, context: ResolveContext(engineScope: DemoEngine.engineScope))
        switch result {
        case .success:
            return "{\"ok\":true}"
        case .failure(let category, let reason, let stage):
            return "{\"ok\":false,\"category\":\(jsQuote(errorCategoryName(category))),\"stage\":\(stage.map { jsQuote($0) } ?? "null"),\"message\":\(jsQuote(reason))}"
        }
    }

    // MARK: - jsbridge-image-picker

    private func presentPhotoPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        DispatchQueue.main.async { self.present(picker, animated: true) }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else {
            evalJS("window.LocalAssetSampleNative.onChooseError('Image picking was cancelled')")
            return
        }
        result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            guard let self else { return }
            guard let data else {
                self.evalJS("window.LocalAssetSampleNative.onChooseError(\(jsQuote(error?.localizedDescription ?? "load failed")))")
                return
            }
            let fileName = (result.itemProvider.suggestedName ?? "photo") + ".jpg"
            let uri = self.localAsset.registerHandle(
                ResourceHandle(source: .bytes(data), fileName: fileName, mimeType: "image/jpeg"))
            self.registeredHandleUris.append(uri)
            let payload = #"{"previewUri":"\#(uri)","fileName":"\#(fileName)","mimeType":"image/jpeg"}"#
            self.evalJS("window.LocalAssetSampleNative.onChooseSuccess(\(payload))")
        }
    }

    private func handleSubmit(previewUri: String) {
        guard let record = try? localAsset.resolveHandle(previewUri) else {
            evalJS("window.LocalAssetSampleNative.onSubmitError(\(jsQuote("Could not resolve previewUri")))")
            return
        }
        // 把选中的字节落到缓存文件，让提交结果带上一条真实可寻址的路径 —— capability URI
        // 本身不是一个可用的资源地址。对应 Android 的 localCachePath（iOS 无 content uri）。
        let sanitized = record.fileName.replacingOccurrences(
            of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let cacheFile = cacheDir.appendingPathComponent("submitted-\(sanitized)")
        guard case .bytes(let bytes) = record.source else {
            evalJS("window.LocalAssetSampleNative.onSubmitError(\(jsQuote("preview handle is not bytes-backed")))")
            return
        }
        do {
            try bytes.write(to: cacheFile)
        } catch {
            evalJS("window.LocalAssetSampleNative.onSubmitError(\(jsQuote(error.localizedDescription)))")
            return
        }
        let payload = #"{"previewUri":"\#(record.resourceUri)","localCachePath":"\#(cacheFile.path)","fileName":"\#(record.fileName)","mimeType":"\#(record.mimeType)","size":\#(record.size ?? 0)}"#
        evalJS("window.LocalAssetSampleNative.onSubmitSuccess(\(payload))")
    }

    // MARK: - Helpers

    private func evalJS(_ script: String) {
        DispatchQueue.main.async { self.webView.evaluateJavaScript(script) }
    }
}

private func jsQuote(_ s: String) -> String {
    "\"\(s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
}

/// 占位 handler：`self` 在 `super.init` 之前不可用，先挂它，init 之后立刻换成 self。
private class MessageRelay: NSObject, WKScriptMessageHandler {
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {}
}
