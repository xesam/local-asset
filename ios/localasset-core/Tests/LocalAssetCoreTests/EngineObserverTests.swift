import Testing
import Foundation
@testable import LocalAssetCore

@Suite("EngineObserver")
struct EngineObserverTests {
    final class CapturingObserver: EngineObserver {
        var events: [EngineStageEvent] = []
        func onStage(_ event: EngineStageEvent) { events.append(event) }
    }

    func makeEngine(observer: EngineObserver) -> DefaultLocalAssetEngine {
        DefaultLocalAssetEngine(
            adapters: [DefaultLocalAssetSchemeAdapter()],
            resolverChain: ResolverChain(resolvers: [RegistryResolver(registry: InMemoryResourceRegistry())]),
            policy: DefaultPolicy(),
            loader: CompositeResourceLoader(loaders: [BytesResourceLoader(), FileResourceLoader()]),
            observer: observer
        )
    }

    @Test func success_path_emits_all_stages() throws {
        let observer = CapturingObserver()
        let registry = InMemoryResourceRegistry()
        try registry.register(descriptor: ResourceDescriptor(
            id: "logo", namespace: "image", type: .static,
            source: .bytes("hello".data(using: .utf8)!),
            mimeType: "text/plain", createdAtMillis: 0, ttlMillis: nil, scope: nil
        ))
        let engine = DefaultLocalAssetEngine(
            adapters: [DefaultLocalAssetSchemeAdapter()],
            resolverChain: ResolverChain(resolvers: [RegistryResolver(registry: registry)]),
            policy: DefaultPolicy(),
            loader: CompositeResourceLoader(loaders: [BytesResourceLoader()]),
            observer: observer
        )

        let result = engine.resolve(url: "local-asset://image/logo")

        guard case .success = result else { Issue.record("expected success, got \(result)"); return }
        let stages = observer.events.map(\.stage)
        #expect(stages == ["adapter_parse", "policy_pre", "resolve", "policy_post", "load", "complete"])
        let resolveEvent = observer.events.first { $0.stage == EngineStage.resolve }!
        #expect(resolveEvent.resolverIndex == 0)
        if case .hit = resolveEvent.resolverResult {} else { Issue.record("expected hit") }
        #expect(resolveEvent.descriptor?.id == "logo")
        #expect(observer.events.last?.stage == EngineStage.complete)
        #expect(observer.events.allSatisfy { $0.failure == nil })
    }

    @Test func precheck_failure_is_terminal() {
        final class RejectingPolicy: Policy {
            func preCheck(request: AssetRequest, context: ResolveContext) throws {
                throw ResourceException(.securityError, "blocked", stage: EngineStage.policyPre)
            }
            func postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext) throws {}
        }
        let observer = CapturingObserver()
        let engine = DefaultLocalAssetEngine(
            adapters: [DefaultLocalAssetSchemeAdapter()],
            resolverChain: ResolverChain(resolvers: []),
            policy: RejectingPolicy(),
            loader: CompositeResourceLoader(loaders: [BytesResourceLoader()]),
            observer: observer
        )

        let result = engine.resolve(url: "local-asset://demo/logo")

        guard case .failure(let category, _, let stage) = result else { Issue.record("expected failure"); return }
        #expect(category == .securityError)
        #expect(stage == EngineStage.policyPre)
        let preEvent = observer.events.last { $0.stage == EngineStage.policyPre }!
        #expect(preEvent.failure?.stage == EngineStage.policyPre)
        #expect(observer.events.noneSatisfy { $0.stage == EngineStage.resolve || $0.stage == EngineStage.complete })
    }

    @Test func not_found_emits_resolve_skip_then_failure() {
        let observer = CapturingObserver()
        _ = makeEngine(observer: observer).resolve(url: "local-asset://demo/missing")

        let resolveEvents = observer.events.filter { $0.stage == EngineStage.resolve }
        #expect(resolveEvents.count == 2)
        if case .skip = resolveEvents[0].resolverResult {} else { Issue.record("expected first skip") }
        #expect(resolveEvents[0].failure == nil)
        #expect(resolveEvents[1].failure?.reason == "resource not found")
    }

    @Test func parse_failure_emits_terminal_parse_event_with_null_request() {
        let observer = CapturingObserver()
        _ = makeEngine(observer: observer).resolve(url: "local-asset:///invalid")

        let parseEvent = observer.events.singleSatisfying { $0.stage == EngineStage.adapterParse }
        #expect(parseEvent.request == nil)
        #expect(parseEvent.failure?.stage == EngineStage.adapterParse)
        #expect(observer.events.noneSatisfy { $0.stage == EngineStage.policyPre })
    }
}

private extension Sequence {
    func noneSatisfy(_ predicate: (Element) -> Bool) -> Bool { !contains(where: predicate) }
    func singleSatisfying(_ predicate: (Element) -> Bool) -> Element {
        first(where: predicate)!
    }
}
