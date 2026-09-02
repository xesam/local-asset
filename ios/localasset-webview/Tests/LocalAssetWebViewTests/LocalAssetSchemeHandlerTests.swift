import Testing
import Foundation
import WebKit
@testable import LocalAssetWebView
import LocalAssetCore

@Suite("LocalAssetSchemeHandler")
struct LocalAssetSchemeHandlerTests {
    /// Minimal WKURLSchemeTask double capturing the response/data/finish/fail calls the handler
    /// makes. WKURLSchemeTask is an Objective-C protocol; a Swift NSObject subclass can conform.
    private final class FakeSchemeTask: NSObject, WKURLSchemeTask {
        let request: URLRequest
        var receivedResponse: URLResponse?
        var receivedData = Data()
        var didFinishCalled = false
        var didFailError: Error?

        init(url: URL?, headers: [String: String] = [:]) {
            // URLRequest has no nil-URL initializer; build from a placeholder then assign the
            // optional url (URLRequest.url is settable), so a nil url round-trips into the task.
            var req = URLRequest(url: URL(string: "http://placeholder")!)
            req.url = url
            for (name, value) in headers { req.setValue(value, forHTTPHeaderField: name) }
            self.request = req
        }

        func didReceive(_ response: URLResponse) { receivedResponse = response }
        func didReceive(_ data: Data) { receivedData += data }
        func didFinish() { didFinishCalled = true }
        func didFailWithError(_ error: Error) { didFailError = error }
    }

    /// Stub engine returning a canned result regardless of input, so the handler's response
    /// wiring can be tested in isolation from the real pipeline.
    private struct StubEngine: LocalAssetEngine {
        let result: EngineResult
        func resolve(url: String, context: ResolveContext) -> EngineResult { result }
        func resolve(request: AssetRequest, context: ResolveContext) -> EngineResult { result }
    }

    /// Shared success result for the CORS test cases — the engine/bytes setup is identical across
    /// the four cases; only `allowedOrigins` and the request's `Origin` vary. Mirrors the Android
    /// `jsonSuccess()` helper in `DefaultWebViewResponseBuilderTest.kt`.
    private static func textSuccessEngine() -> StubEngine {
        let bytes = "hello".data(using: .utf8)!
        return StubEngine(result: .success(
            descriptor: ResourceDescriptor(id: "x", namespace: "ns", type: .dynamic,
                                           source: .bytes(bytes), mimeType: "text/plain",
                                           createdAtMillis: 0, ttlMillis: nil, scope: nil),
            data: .bytes(bytes, "text/plain")
        ))
    }

    private static func corsTask(origin: String? = nil) -> FakeSchemeTask {
        var headers: [String: String] = [:]
        if let origin { headers["Origin"] = origin }
        return FakeSchemeTask(
            url: URL(string: "local-asset://ns/handles/t/a.txt"),
            headers: headers
        )
    }

    @Test func success_omits_cors_headers_by_default() {
        let handler = LocalAssetSchemeHandler(engine: Self.textSuccessEngine())
        let task = Self.corsTask()

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.statusCode == 200)
        // Default empty allow-list emits no CORS headers — the capability-URL leak vectors
        // (document.referrer / Referer / performance.getEntriesByType) no longer turn into
        // readable bytes. <img>/<link>/<script> need no CORS at all.
        #expect(http?.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == nil)
        #expect(http?.value(forHTTPHeaderField: "Access-Control-Allow-Methods") == nil)
        #expect(http?.value(forHTTPHeaderField: "Content-Type") == "text/plain")
        #expect(task.receivedData == "hello".data(using: .utf8))
        #expect(task.didFinishCalled)
        #expect(task.didFailError == nil)
    }

    @Test func allow_listed_origin_is_echoed_with_vary() {
        let handler = LocalAssetSchemeHandler(
            engine: Self.textSuccessEngine(),
            allowedOrigins: ["https://app.example.com"]
        )
        let task = Self.corsTask(origin: "https://app.example.com")

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "https://app.example.com")
        #expect(http?.value(forHTTPHeaderField: "Access-Control-Allow-Methods") == "GET, OPTIONS")
        #expect(http?.value(forHTTPHeaderField: "Vary") == "Origin")
    }

    @Test func origin_outside_allow_list_gets_no_cors_headers() {
        let handler = LocalAssetSchemeHandler(
            engine: Self.textSuccessEngine(),
            allowedOrigins: ["https://app.example.com"]
        )
        let task = Self.corsTask(origin: "https://evil.example.org")

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == nil)
        #expect(http?.value(forHTTPHeaderField: "Vary") == nil)
    }

    @Test func wildcard_membership_restores_blanket_cors() {
        let handler = LocalAssetSchemeHandler(
            engine: Self.textSuccessEngine(),
            allowedOrigins: [CorsPolicy.allowAnyOrigin]
        )
        let task = Self.corsTask(origin: "https://evil.example.org")

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.value(forHTTPHeaderField: "Access-Control-Allow-Origin") == "*")
        #expect(http?.value(forHTTPHeaderField: "Access-Control-Allow-Methods") == "GET, OPTIONS")
    }

    @Test func success_streams_in_chunks_and_finishes() {
        // > 4 KB so the pump emits multiple didReceive chunks; the accumulated data must equal the
        // original payload — proving the stream path never materializes the whole file at once.
        let payload = Data(repeating: 0x41, count: 10_000)
        let engine = StubEngine(result: .success(
            descriptor: ResourceDescriptor(id: "s", namespace: "ns", type: .static,
                                           source: .stream({ InputStream(data: payload) }),
                                           mimeType: "application/octet-stream",
                                           createdAtMillis: 0, ttlMillis: nil, scope: nil),
            data: .stream({ InputStream(data: payload) }, "application/octet-stream")
        ))
        let handler = LocalAssetSchemeHandler(engine: engine)
        let task = FakeSchemeTask(url: URL(string: "local-asset://ns/handles/t/s"))

        handler.start(task)

        #expect(task.receivedData == payload)
        #expect(task.didFinishCalled)
        #expect(task.didFailError == nil)
    }

    @Test func failure_returns_404_and_invokes_onFailure() {
        let engine = StubEngine(result: .failure(category: .resolutionError, reason: "not found", stage: "resolve"))
        var captured: EngineFailure?
        let handler = LocalAssetSchemeHandler(
            engine: engine,
            onFailure: { captured = $0 }
        )
        let task = FakeSchemeTask(url: URL(string: "local-asset://ns/handles/t/missing"))

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.statusCode == 404)
        #expect(task.didFinishCalled)
        #expect(captured?.category == .resolutionError)
        #expect(captured?.reason == "not found")
        #expect(captured?.stage == "resolve")
    }

    @Test func nil_url_fails_task_instead_of_crashing() {
        // Regression: the failure branch previously force-unwrapped request.url. A task with no URL
        // must fail the scheme task explicitly rather than crash.
        let engine = StubEngine(result: .failure(category: .resolutionError, reason: "x", stage: nil))
        let handler = LocalAssetSchemeHandler(engine: engine)
        let task = FakeSchemeTask(url: nil)

        handler.start(task)

        #expect(task.didFailError != nil, "nil-URL task should be failed, not crash")
        #expect(!task.didFinishCalled, "nil-URL task must not reach didFinish")
        #expect(task.receivedResponse == nil)
    }

    @Test func static_resource_sets_cacheable_control_and_etag() {
        let bytes = "hello".data(using: .utf8)!
        let engine = StubEngine(result: .success(
            descriptor: ResourceDescriptor(id: "x", namespace: "ns", type: .static,
                                           source: .bytes(bytes), mimeType: "text/plain",
                                           createdAtMillis: 0, ttlMillis: nil, scope: nil),
            data: .bytes(bytes, "text/plain")
        ))
        let handler = LocalAssetSchemeHandler(engine: engine)
        let task = FakeSchemeTask(url: URL(string: "local-asset://ns/handles/t/a.txt"))

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.statusCode == 200)
        #expect(http?.value(forHTTPHeaderField: "Cache-Control") == "public, max-age=86400")
        // ETag from id + byte size ("x-5").
        #expect(http?.value(forHTTPHeaderField: "ETag") == "\"x-5\"")
    }

    @Test func dynamic_resource_sets_no_store() {
        let bytes = "hello".data(using: .utf8)!
        let engine = StubEngine(result: .success(
            descriptor: ResourceDescriptor(id: "d", namespace: "ns", type: .dynamic,
                                           source: .bytes(bytes), mimeType: "text/plain",
                                           createdAtMillis: 0, ttlMillis: nil, scope: nil),
            data: .bytes(bytes, "text/plain")
        ))
        let handler = LocalAssetSchemeHandler(engine: engine)
        let task = FakeSchemeTask(url: URL(string: "local-asset://ns/handles/t/a.txt"))

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    }

    @Test func max_age_is_configurable() {
        let bytes = "hello".data(using: .utf8)!
        let engine = StubEngine(result: .success(
            descriptor: ResourceDescriptor(id: "x", namespace: "ns", type: .static,
                                           source: .bytes(bytes), mimeType: "text/plain",
                                           createdAtMillis: 0, ttlMillis: nil, scope: nil),
            data: .bytes(bytes, "text/plain")
        ))
        let handler = LocalAssetSchemeHandler(engine: engine, cacheMaxAgeSeconds: 60)
        let task = FakeSchemeTask(url: URL(string: "local-asset://ns/handles/t/a.txt"))

        handler.start(task)

        let http = task.receivedResponse as? HTTPURLResponse
        #expect(http?.value(forHTTPHeaderField: "Cache-Control") == "public, max-age=60")
    }
}
