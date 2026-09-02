import Testing
import Foundation
@testable import LocalAssetCore

@Suite("HandleRegistryResolver")
struct HandleRegistryResolverTests {
    private func resolveRequest(for resourceUri: String, query: [String: String] = [:]) -> AssetRequest {
        // Rebuild an AssetRequest that resolveFromRequest can reconstruct into the original URI.
        // The default reconstruction is "<scheme>://<namespace><path>" — split the registered URI
        // at the boundary after the host so `path` carries everything resolveFromRequest needs.
        let prefix = "local-asset://handles.localasset.local"
        let path = String(resourceUri.dropFirst(prefix.count))
        return AssetRequest(
            scheme: "local-asset",
            namespace: "handles.localasset.local",
            identifier: "photo.jpg",
            path: path,
            query: query,
            fragment: nil
        )
    }

    @Test func cache_bust_param_is_stripped_so_handle_resolves() {
        // The reserved `_la_cb` cache-bust param must NOT participate in handle identity: a request
        // that differs from the registered URI only by `_la_cb=<ts>` must still resolve. Without
        // stripping, the reconstructed URI would carry `?_la_cb=...` and miss the (query-less)
        // registered key → 404 on every cache-busted re-fetch, defeating the bust.
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes("photo".data(using: .utf8)!),
                                   fileName: "photo.jpg", mimeType: "image/jpeg")
        )
        let resolver = HandleRegistryResolver(handleRegistry: registry)

        let result = resolver.resolve(
            request: resolveRequest(for: resourceUri, query: ["_la_cb": "1700000000000"]),
            context: ResolveContext()
        )

        guard case .hit(let descriptor) = result else {
            Issue.record("expected hit, got \(result)"); return
        }
        #expect(descriptor.id == "photo.jpg")
    }

    @Test func non_reserved_query_param_breaks_lookup() {
        // A query key other than `_la_cb` IS part of the identity; since the registered URI has no
        // query, any such key must miss. This guards against accidentally stripping all query.
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes("photo".data(using: .utf8)!),
                                   fileName: "photo.jpg", mimeType: "image/jpeg")
        )
        let resolver = HandleRegistryResolver(handleRegistry: registry)

        let result = resolver.resolve(
            request: resolveRequest(for: resourceUri, query: ["foo": "bar"]),
            context: ResolveContext()
        )

        if case .skip = result { /* ok */ } else { Issue.record("expected skip, got \(result)") }
    }

    @Test func returns_hit_when_handle_is_found() {
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes("photo".data(using: .utf8)!),
                                   fileName: "photo.jpg", mimeType: "image/jpeg")
        )
        let resolver = HandleRegistryResolver(handleRegistry: registry)

        let result = resolver.resolve(request: resolveRequest(for: resourceUri), context: ResolveContext())

        guard case .hit(let descriptor) = result else {
            Issue.record("expected hit, got \(result)"); return
        }
        #expect(descriptor.mimeType == "image/jpeg")
        #expect(descriptor.id == "photo.jpg")
    }

    @Test func descriptor_ttl_is_nil_even_when_handle_has_ttl() {
        // Regression: HandleRegistry owns TTL itself (relative to its own createdAt). The resolver
        // must NOT forward record.ttlMillis onto a descriptor whose createdAtMillis is a 0
        // placeholder, or DefaultPolicy.postCheck's absolute-time TTL check would always expire.
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes("photo".data(using: .utf8)!),
                                   fileName: "photo.jpg", mimeType: "image/jpeg",
                                   ttlMillis: 60_000)
        )
        let resolver = HandleRegistryResolver(handleRegistry: registry)

        let result = resolver.resolve(request: resolveRequest(for: resourceUri), context: ResolveContext())

        guard case .hit(let descriptor) = result else {
            Issue.record("expected hit, got \(result)"); return
        }
        #expect(descriptor.ttlMillis == nil)
    }

    @Test func descriptor_scope_is_nil_so_postcheck_skips_scope_gate() {
        // Handle-backed resources use a capability model: possession of the opaque token IS the
        // authority, so they must NOT pass DefaultPolicy.postCheck's namespace/scope gate (which
        // would require descriptor.namespace == the context's scope id and reject otherwise).
        // Pin scope == nil here so a future change that sets a scope can't silently start rejecting
        // every handle-backed request. See design.md §3.3 / §5.2.
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes("photo".data(using: .utf8)!),
                                   fileName: "photo.jpg", mimeType: "image/jpeg")
        )
        let resolver = HandleRegistryResolver(handleRegistry: registry)

        let result = resolver.resolve(request: resolveRequest(for: resourceUri), context: ResolveContext())

        guard case .hit(let descriptor) = result else {
            Issue.record("expected hit, got \(result)"); return
        }
        #expect(descriptor.scope == nil, "handle-backed descriptor must not carry a ResourceScope")
        if case .dynamic = descriptor.type { /* ok */ } else { Issue.record("expected dynamic type") }
    }

    @Test func file_backed_handle_produces_filePath_descriptor() {
        // A filePath handle must surface as a `.filePath` descriptor so postCheck's file-root gate
        // applies (shared with the Registry path) and FileResourceLoader loads it — the whole point
        // of file-backed handles is exposing a large on-disk file as a revocable capability without
        // buffering it into memory.
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .filePath("/tmp/localasset/big.pdf"),
                                   fileName: "big.pdf", mimeType: "application/pdf")
        )
        let resolver = HandleRegistryResolver(handleRegistry: registry)

        let result = resolver.resolve(request: resolveRequest(for: resourceUri), context: ResolveContext())

        guard case .hit(let descriptor) = result else {
            Issue.record("expected hit, got \(result)"); return
        }
        guard case .filePath(let path) = descriptor.source else {
            Issue.record("expected .filePath source, got \(descriptor.source)"); return
        }
        #expect(path == "/tmp/localasset/big.pdf")
        #expect(descriptor.scope == nil, "handle-backed descriptor must not carry a ResourceScope")
        #expect(descriptor.ttlMillis == nil)
    }

    @Test func returns_skip_when_handle_is_not_found() {
        let registry = InMemoryHandleRegistry()
        let resolver = HandleRegistryResolver(handleRegistry: registry)

        let request = AssetRequest(
            scheme: "local-asset",
            namespace: "handles.localasset.local",
            identifier: "missing",
            path: "/handles/nonexistent/missing",
            query: [:],
            fragment: nil
        )
        let result = resolver.resolve(request: request, context: ResolveContext())

        if case .skip = result { /* ok */ } else { Issue.record("expected skip, got \(result)") }
    }
}
