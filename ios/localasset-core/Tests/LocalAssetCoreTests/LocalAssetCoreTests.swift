import Testing
import Foundation
@testable import LocalAssetCore

private struct SkipResolver: ResourceResolver {
    func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult { .skip }
}

@Suite("DefaultLocalAssetSchemeAdapter")
struct DefaultLocalAssetSchemeAdapterTests {
    let adapter = DefaultLocalAssetSchemeAdapter()

    @Test func canHandle_validScheme() {
        #expect(adapter.canHandle(url: "local-asset://image/logo"))
        #expect(!adapter.canHandle(url: "https://example.com"))
        #expect(!adapter.canHandle(url: "not a url"))
    }

    @Test func parse_basicUrl() throws {
        let req = try adapter.parse(url: "local-asset://image/logo?id=home&theme=dark")
        #expect(req.scheme == "local-asset")
        #expect(req.namespace == "image")
        #expect(req.path == "/logo")
        #expect(req.identifier == "logo")
        #expect(req.query["id"] == "home")
        #expect(req.query["theme"] == "dark")
    }

    @Test func parse_missingNamespace() {
        #expect(throws: ResourceException.self) {
            try adapter.parse(url: "local-asset:///invalid")
        }
    }

    @Test func parse_unsupportedScheme() {
        #expect(throws: ResourceException.self) {
            try adapter.parse(url: "https://example.com/path")
        }
    }
}

@Suite("DefaultLocalAssetEngine")
struct DefaultLocalAssetEngineTests {
    func makeLocalAsset() -> LocalAsset { LocalAsset.Builder().build() }

    @Test func resolve_registeredResource_success() throws {
        let asset = makeLocalAsset()
        let descriptor = ResourceDescriptor(
            id: "test-1", namespace: "test", type: .static,
            source: .bytes("hello".data(using: .utf8)!),
            mimeType: "text/plain", createdAtMillis: currentMillis(), ttlMillis: nil, scope: nil
        )
        try asset.register(descriptor: descriptor)
        let result = asset.engine.resolve(url: "local-asset://test/test-1")
        guard case .success(let d, let data) = result else {
            Issue.record("expected success, got \(result)"); return
        }
        #expect(d.id == "test-1")
        guard case .bytes(let b, _) = data else { Issue.record("expected .bytes"); return }
        #expect(b == "hello".data(using: .utf8)!)
    }

    @Test func resolve_unknownResource_failure() {
        let asset = makeLocalAsset()
        let result = asset.engine.resolve(url: "local-asset://test/missing")
        guard case .failure(let category, _, _) = result else {
            Issue.record("expected failure"); return
        }
        #expect(category == .resolutionError)
    }

    @Test func resolve_expiredResource_failure() throws {
        var time: Int64 = 1000
        let registry = InMemoryResourceRegistry(nowMillis: { time })
        let asset = LocalAsset.Builder().registry(registry).build()
        let descriptor = ResourceDescriptor(
            id: "exp-1", namespace: "test", type: .static,
            source: .bytes(Data()),
            mimeType: nil, createdAtMillis: time, ttlMillis: 500, scope: nil
        )
        try asset.register(descriptor: descriptor)
        time = 2000  // past TTL
        let result = asset.engine.resolve(url: "local-asset://test/exp-1")
        guard case .failure(let category, _, _) = result else {
            Issue.record("expected failure"); return
        }
        #expect(category == .resolutionError)
    }

    @Test func resolve_invalidUrl_parseError() {
        let asset = makeLocalAsset()
        let result = asset.engine.resolve(url: "not-a-url")
        guard case .failure(let category, _, _) = result else {
            Issue.record("expected failure"); return
        }
        #expect(category == .parseError)
    }

    // A file-backed handle (design.md §5.4) carries a FilePath source through the capability token.
    // The token still authorizes, but postCheck's shared file-root gate must still apply — otherwise a
    // capability could point at any path on disk. These two tests pin the security-critical contract:
    // out-of-root → securityError at postCheck; in-root → passes postCheck (then fails at load because
    // the file doesn't exist, which is fine — the point is it got past policy).

    @Test func file_backed_handle_outside_allowed_root_rejected_at_postCheck() {
        let asset = LocalAsset.Builder()
            .addAllowedFileRoot(URL(fileURLWithPath: "/tmp/localasset/allowed"))
            .build()
        let uri = asset.registerHandle(
            ResourceHandle(source: .filePath("/tmp/localasset/OUTSIDE/big.pdf"),
                           fileName: "big.pdf", mimeType: "application/pdf")
        )
        let result = asset.engine.resolve(url: uri)
        guard case .failure(let category, _, _) = result else {
            Issue.record("expected failure, got \(result)"); return
        }
        #expect(category == .securityError)
    }

    @Test func file_backed_handle_inside_allowed_root_passes_postCheck() {
        let asset = LocalAsset.Builder()
            .addAllowedFileRoot(URL(fileURLWithPath: "/tmp/localasset/allowed"))
            .build()
        let uri = asset.registerHandle(
            ResourceHandle(source: .filePath("/tmp/localasset/allowed/big.pdf"),
                           fileName: "big.pdf", mimeType: "application/pdf")
        )
        let result = asset.engine.resolve(url: uri)
        // File doesn't exist on disk → loadError, but crucially NOT securityError — proving the
        // file-root gate passed for an in-root path. The contrast with the out-of-root test above
        // is the security contract: capability token can't escape the allowed root.
        guard case .failure(let category, _, _) = result else {
            Issue.record("expected failure (file absent), got \(result)"); return
        }
        #expect(category != .securityError)
    }

    @Test func resolve_registeredResource_stillResolves_withCustomResolver() throws {
        let asset = LocalAsset.Builder()
            .addResolver(SkipResolver())
            .build()
        let descriptor = ResourceDescriptor(
            id: "test-2", namespace: "test", type: .static,
            source: .bytes("hello".data(using: .utf8)!),
            mimeType: "text/plain", createdAtMillis: currentMillis(), ttlMillis: nil, scope: nil
        )
        try asset.register(descriptor: descriptor)
        let result = asset.engine.resolve(url: "local-asset://test/test-2")
        guard case .success = result else {
            Issue.record("expected success, got \(result)"); return
        }
    }

    @Test func resolve_handleRegistry_roundtrip() throws {
        let asset = makeLocalAsset()
        let bytes = "image data".data(using: .utf8)!
        let uri = asset.registerHandle(ResourceHandle(source: .bytes(bytes), fileName: "photo.jpg", mimeType: "image/jpeg"))
        let result = asset.engine.resolve(url: uri)
        guard case .success(_, let data) = result else {
            Issue.record("expected success"); return
        }
        guard case .bytes(let b, _) = data else { Issue.record("expected .bytes"); return }
        #expect(b == bytes)
        #expect(data.mimeType == "image/jpeg")
    }

    @Test func resolve_handleRegistry_roundtrip_withTtl() throws {
        // Regression for the P0 double-judgment defect: a handle registered with a TTL must still
        // resolve through the full pipeline. HandleRegistryResolver used to forward ttlMillis onto
        // a descriptor whose createdAtMillis was a 0 placeholder, so DefaultPolicy.postCheck's
        // absolute-time TTL check (`0 + ttl <= now`) expired every TTL'd handle on the spot.
        let asset = makeLocalAsset()
        let bytes = "image data".data(using: .utf8)!
        let uri = asset.registerHandle(ResourceHandle(source: .bytes(bytes), fileName: "photo.jpg", mimeType: "image/jpeg", ttlMillis: 60_000))
        let result = asset.engine.resolve(url: uri)
        guard case .success(_, let data) = result else {
            Issue.record("expected success, got \(result)"); return
        }
        guard case .bytes(let b, _) = data else { Issue.record("expected .bytes"); return }
        #expect(b == bytes)
        #expect(data.mimeType == "image/jpeg")
    }
}

@Suite("InMemoryResourceRegistry")
struct InMemoryResourceRegistryTests {
    @Test func register_and_lookup() throws {
        let reg = InMemoryResourceRegistry()
        let d = ResourceDescriptor(id: "a", namespace: "ns", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: nil)
        try reg.register(descriptor: d)
        if case .hit(let found) = reg.lookup(id: "a") {
            #expect(found.id == "a")
        } else { Issue.record("expected hit") }
    }

    @Test func duplicate_register_throws() throws {
        let reg = InMemoryResourceRegistry()
        let d = ResourceDescriptor(id: "dup", namespace: "ns", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: nil)
        try reg.register(descriptor: d)
        #expect(throws: (any Error).self) { try reg.register(descriptor: d) }
    }

    @Test func remove_makes_missing() throws {
        let reg = InMemoryResourceRegistry()
        let d = ResourceDescriptor(id: "r", namespace: "ns", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: nil)
        try reg.register(descriptor: d)
        reg.remove(id: "r")
        guard case .missing = reg.lookup(id: "r") else { Issue.record("expected missing"); return }
    }
}

@Suite("DefaultPolicy")
struct DefaultPolicyTests {
    @Test func preCheck_emptyNamespace_throws() {
        let policy = DefaultPolicy()
        let req = AssetRequest(scheme: "local-asset", namespace: "", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.preCheck(request: req, context: ResolveContext())
        }
    }

    @Test func preCheck_emptyScheme_throws() {
        let policy = DefaultPolicy()
        let req = AssetRequest(scheme: "", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.preCheck(request: req, context: ResolveContext())
        }
    }

    @Test func preCheck_schemeNotInAllowList_throws() {
        let policy = DefaultPolicy(allowedSchemes: ["local-asset"])
        let req = AssetRequest(scheme: "https", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.preCheck(request: req, context: ResolveContext())
        }
    }

    @Test func preCheck_anyNonBlankSchemeAllowed_whenAllowListEmpty() throws {
        let policy = DefaultPolicy()
        let req = AssetRequest(scheme: "custom-scheme", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        try policy.preCheck(request: req, context: ResolveContext())
    }

    @Test func preCheck_namespaceNotInAllowList_throws() {
        let policy = DefaultPolicy(allowedNamespaces: ["allowed"])
        let req = AssetRequest(scheme: "local-asset", namespace: "forbidden", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.preCheck(request: req, context: ResolveContext())
        }
    }

    @Test func preCheck_anyNonBlankNamespaceAllowed_whenAllowListEmpty() throws {
        let policy = DefaultPolicy()
        let req = AssetRequest(scheme: "local-asset", namespace: "any-ad-hoc", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        try policy.preCheck(request: req, context: ResolveContext())
    }

    @Test func preCheck_allowListDoesNotBreakHandleHost() throws {
        // Footgun regression: declaring an allowed namespace used to reject every handle URI because
        // handle URIs live under the fixed host "handles.localasset.local". The Handle path is
        // authorized by its capability token, not by namespace, so the handle host is exempt.
        let policy = DefaultPolicy(allowedNamespaces: ["foo"])
        let req = AssetRequest(scheme: "local-asset", namespace: "handles.localasset.local",
                               identifier: "abc", path: "/handles/abc/file.png", query: [:], fragment: nil)
        try policy.preCheck(request: req, context: ResolveContext())
    }

    @Test func preCheck_customHandleHostIsExempt() throws {
        let policy = DefaultPolicy(allowedNamespaces: ["foo"], handleHost: "my-handles.local")
        let req = AssetRequest(scheme: "local-asset", namespace: "my-handles.local",
                               identifier: "abc", path: "/handles/abc/file.png", query: [:], fragment: nil)
        try policy.preCheck(request: req, context: ResolveContext())
    }

    @Test func preCheck_pathTraversal_throws() {
        let policy = DefaultPolicy()
        let req = AssetRequest(scheme: "local-asset", namespace: "demo", identifier: "..",
                               path: "/pkg/../etc/passwd", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.preCheck(request: req, context: ResolveContext())
        }
    }

    @Test func preCheck_traversalOnlyOnFullSegment_allowsSubstringDots() throws {
        // A path that merely contains ".." as part of a longer segment (e.g. "my..file") is NOT
        // traversal and must still pass preCheck; only a literal ".." segment is rejected.
        let policy = DefaultPolicy()
        let req = AssetRequest(scheme: "local-asset", namespace: "demo", identifier: "my..file.js",
                               path: "/assets/my..file.js", query: [:], fragment: nil)
        try policy.preCheck(request: req, context: ResolveContext())
    }

    @Test func postCheck_ttlExpired_throws() {
        var now: Int64 = 0
        let policy = DefaultPolicy(nowMillis: { now })
        let d = ResourceDescriptor(id: "x", namespace: "ns", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: 500, scope: nil)
        let req = AssetRequest(scheme: "local-asset", namespace: "ns", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        now = 600
        #expect(throws: ResourceException.self) {
            try policy.postCheck(request: req, descriptor: d, context: ResolveContext())
        }
    }

    @Test func postCheck_engineScopeMismatch_throws() {
        let policy = DefaultPolicy()
        let d = ResourceDescriptor(id: "x", namespace: "demo", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: .engine)
        let req = AssetRequest(scheme: "local-asset", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.postCheck(request: req, descriptor: d, context: ResolveContext(engineScope: "another-engine"))
        }
    }

    @Test func postCheck_pageScopeMatch_allows() throws {
        let policy = DefaultPolicy()
        let d = ResourceDescriptor(id: "x", namespace: "demo", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: .page)
        let req = AssetRequest(scheme: "local-asset", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        try policy.postCheck(request: req, descriptor: d, context: ResolveContext(pageScope: "demo"))
    }

    @Test func postCheck_pageScopeMismatch_throws() {
        let policy = DefaultPolicy()
        let d = ResourceDescriptor(id: "x", namespace: "demo", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: .page)
        let req = AssetRequest(scheme: "local-asset", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.postCheck(request: req, descriptor: d, context: ResolveContext(pageScope: "another-page"))
        }
    }

    @Test func postCheck_sessionScopeMatch_allows() throws {
        let policy = DefaultPolicy()
        let d = ResourceDescriptor(id: "x", namespace: "demo", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: .session)
        let req = AssetRequest(scheme: "local-asset", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        try policy.postCheck(request: req, descriptor: d, context: ResolveContext(sessionScope: "demo"))
    }

    @Test func postCheck_sessionScopeMismatch_throws() {
        let policy = DefaultPolicy()
        let d = ResourceDescriptor(id: "x", namespace: "demo", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: .session)
        let req = AssetRequest(scheme: "local-asset", namespace: "demo", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.postCheck(request: req, descriptor: d, context: ResolveContext(sessionScope: "another-session"))
        }
    }

    @Test func postCheck_unsupportedSourceType_throws() throws {
        let policy = DefaultPolicy(allowedSourceTypes: [.filePath])
        let d = ResourceDescriptor(id: "x", namespace: "ns", type: .static,
                                   source: .bytes(Data()), mimeType: nil,
                                   createdAtMillis: 0, ttlMillis: nil, scope: nil)
        let req = AssetRequest(scheme: "local-asset", namespace: "ns", identifier: "x",
                               path: "/x", query: [:], fragment: nil)
        #expect(throws: ResourceException.self) {
            try policy.postCheck(request: req, descriptor: d, context: ResolveContext())
        }
    }
}
