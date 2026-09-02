import Foundation
import WebKit
import LocalAssetCore

/// Bridges LocalAsset engine results to WKURLSchemeHandler.
/// Register with `WKWebViewConfiguration.setURLSchemeHandler(_:forURLScheme:)`.
public class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private let engine: LocalAssetEngine
    private let contextFactory: ResolveContextFactory

    /// Invoked for every engine failure, in addition to the `NSLog` line. Use this to feed your
    /// own crash reporting/analytics — `NSLog` is commonly filtered out of release builds and is
    /// not a reliable observability channel on its own. Carries the normalized `EngineFailure`
    /// (same struct the observer emits) so callers pattern-match without unpacking the result enum.
    /// Mirrors Android's `onFailure` hook.
    public var onFailure: (EngineFailure) -> Void = { _ in }

    public typealias ResolveContextFactory = (WKURLSchemeTask) -> ResolveContext

    public init(
        engine: LocalAssetEngine,
        contextFactory: @escaping ResolveContextFactory = LocalAssetSchemeHandler.defaultContextFactory,
        cacheMaxAgeSeconds: Int = ResourceCachePolicy.defaultMaxAgeSeconds,
        allowedOrigins: Set<String> = [],
        onFailure: ((EngineFailure) -> Void)? = nil
    ) {
        self.engine = engine
        self.contextFactory = contextFactory
        self.cacheMaxAgeSeconds = cacheMaxAgeSeconds
        self.allowedOrigins = allowedOrigins
        if let onFailure { self.onFailure = onFailure }
    }

    /// Default `ResolveContextFactory`: publishes `url`/`method` plus every request header under
    /// `ResolveContext.requestHeaderPrefix`, leaving all four scopes nil. Wrap it to add scopes —
    /// a descriptor registered with `scope = .page` only resolves when the context carries a
    /// matching `pageScope`:
    ///
    /// ```swift
    /// contextFactory: { task in
    ///     let base = LocalAssetSchemeHandler.defaultContextFactory(task)
    ///     return ResolveContext(pageScope: "page-1", requestMetadata: base.requestMetadata)
    /// }
    /// ```
    public static func defaultContextFactory(_ task: any WKURLSchemeTask) -> ResolveContext {
        var metadata: [String: String] = [:]
        if let url = task.request.url {
            metadata["url"] = url.absoluteString
        }
        metadata["method"] = task.request.httpMethod ?? "GET"
        for (name, value) in task.request.allHTTPHeaderFields ?? [:] {
            metadata[ResolveContext.requestHeaderPrefix + name.lowercased()] = value
        }
        return ResolveContext(requestMetadata: metadata)
    }

    /// `Cache-Control: max-age` for STATIC resources (DYNAMIC is always `no-store`). Mirrors the
    /// Android `DefaultWebViewResponseBuilder(maxAgeSeconds=...)` knob so both platforms share the
    /// same cache behavior via the core `ResourceCachePolicy`.
    private let cacheMaxAgeSeconds: Int

    /// Origins allowed to read asset responses via `fetch()`/`XHR`. Empty (default) emits no CORS
    /// headers — `<img>`/`<link>`/`<script>` do not need them. See `CorsPolicy`.
    private let allowedOrigins: Set<String>

    public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        start(urlSchemeTask)
    }

    /// Resolves a single scheme task end-to-end. Extracted from the `WKURLSchemeHandler` callback
    /// so it can be exercised without instantiating a `WKWebView` (which is unsafe in headless
    /// test environments) — the `webView` parameter of the protocol callback is otherwise unused.
    public func start(_ urlSchemeTask: any WKURLSchemeTask) {
        // Guard against a task with no URL: WKURLSchemeTask.request.url is optional, and a nil URL
        // must not crash the handler — fail the task explicitly instead of force-unwrapping.
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(
                NSError(
                    domain: "LocalAssetWebView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "scheme task has no URL"]
                )
            )
            return
        }
        let context = contextFactory(urlSchemeTask)
        let result = engine.resolve(url: url.absoluteString, context: context)

        switch result {
        case .success(let descriptor, let data):
            let mimeType = data.mimeType ?? "application/octet-stream"
            let decision = ResourceCachePolicy.decide(
                descriptor: descriptor,
                maxAgeSeconds: cacheMaxAgeSeconds
            )
            var headers: [String: String] = [
                "Content-Type": mimeType,
                "Cache-Control": decision.cacheControl,
                "ETag": decision.etag,
            ]
            // CorsPolicy returns only CORS keys (disjoint from Content-Type/Cache-Control/ETag),
            // so there is no collision to resolve — straight assignment mirrors Android's `putAll`
            // and Harmony's `forEach(set)`.
            for (name, value) in CorsPolicy.headers(
                allowedOrigins: allowedOrigins,
                requestOrigin: context.requestHeader("Origin")
            ) {
                headers[name] = value
            }
            // HTTPURLResponse.init returns nil only for an invalid status code; 200 is valid,
            // so this force-unwrap is bounded and safe. Conditional GET (304) is intentionally not
            // implemented — see ResourceCachePolicy.
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            urlSchemeTask.didReceive(response)
            switch data {
            case .bytes(let bytes, _):
                urlSchemeTask.didReceive(bytes)
                urlSchemeTask.didFinish()
            case .stream(let open, _):
                // Open the factory lazily here and pump in chunks straight into the scheme task;
                // the engine/loader never held an open stream (factory-through model). The pump is
                // synchronous, matching the existing bytes path — `stop` has no async work to cancel.
                let stream = open()
                stream.open()
                defer { stream.close() }
                if let error = stream.streamError {
                    urlSchemeTask.didFailWithError(error)
                    return
                }
                let chunkSize = 4096
                var buffer = [UInt8](repeating: 0, count: chunkSize)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: chunkSize)
                    if read > 0 {
                        urlSchemeTask.didReceive(Data(bytes: buffer, count: read))
                    } else if read == 0 {
                        break
                    } else {
                        urlSchemeTask.didFailWithError(
                            stream.streamError ?? NSError(
                                domain: "LocalAssetWebView",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "stream read failed"]
                            )
                        )
                        return
                    }
                }
                urlSchemeTask.didFinish()
            }

        case .failure(let category, let reason, let stage):
            NSLog("[LocalAsset] intercept failed: category=\(category), stage=\(stage ?? "-"), reason=\(reason)")
            onFailure(EngineFailure(category: category, reason: reason, stage: stage))
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data())
            urlSchemeTask.didFinish()
        }
    }

    /// No-op: the streaming pump in `start` runs synchronously and completes (finish/fail) before
    /// it returns, so there is no outstanding async work to cancel when WebKit calls `stop`.
    public func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
