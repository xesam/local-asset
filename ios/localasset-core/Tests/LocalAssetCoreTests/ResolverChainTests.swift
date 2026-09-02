import Testing
import Foundation
@testable import LocalAssetCore

@Suite("ResolverChain")
struct ResolverChainTests {
    private func descriptor(id: String = "x") -> ResourceDescriptor {
        ResourceDescriptor(id: id, namespace: "ns", type: .static,
                           source: .bytes(Data()), mimeType: nil,
                           createdAtMillis: 0, ttlMillis: nil, scope: nil)
    }

    @Test func empty_chain_returns_skip() {
        let chain = ResolverChain(resolvers: [])
        let result = chain.resolve(request: AssetRequest(scheme: "local-asset", namespace: "ns",
                                                         identifier: "x", path: "/x", query: [:], fragment: nil),
                                   context: ResolveContext())
        if case .skip = result { /* ok */ } else { Issue.record("expected skip, got \(result)") }
    }

    @Test func first_hit_short_circuits_remaining_resolvers() {
        let second = ProbeResolver(result: .skip)
        let chain = ResolverChain(resolvers: [
            StubResolver(result: .hit(descriptor())),
            second,
        ])
        let req = AssetRequest(scheme: "local-asset", namespace: "ns", identifier: "x", path: "/x", query: [:], fragment: nil)
        let result = chain.resolve(request: req, context: ResolveContext())
        if case .hit = result { /* ok */ } else { Issue.record("expected hit") }
        #expect(!second.invoked)
    }

    @Test func failure_short_circuits_remaining_resolvers() {
        let second = ProbeResolver(result: .skip)
        let chain = ResolverChain(resolvers: [
            StubResolver(result: .failure(category: .resolutionError, reason: "nope")),
            second,
        ])
        let req = AssetRequest(scheme: "local-asset", namespace: "ns", identifier: "x", path: "/x", query: [:], fragment: nil)
        let result = chain.resolve(request: req, context: ResolveContext())
        if case .failure = result { /* ok */ } else { Issue.record("expected failure") }
        #expect(!second.invoked)
    }

    @Test func skip_passes_through_to_next_resolver() {
        let chain = ResolverChain(resolvers: [
            StubResolver(result: .skip),
            StubResolver(result: .skip),
            StubResolver(result: .hit(descriptor())),
        ])
        let req = AssetRequest(scheme: "local-asset", namespace: "ns", identifier: "x", path: "/x", query: [:], fragment: nil)
        let result = chain.resolve(request: req, context: ResolveContext())
        if case .hit = result { /* ok */ } else { Issue.record("expected hit after skips") }
    }
}

private struct StubResolver: ResourceResolver {
    let result: ResolverResult
    func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult { result }
}

private final class ProbeResolver: ResourceResolver {
    let result: ResolverResult
    private(set) var invoked = false
    init(result: ResolverResult) { self.result = result }
    func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult {
        invoked = true
        return result
    }
}
