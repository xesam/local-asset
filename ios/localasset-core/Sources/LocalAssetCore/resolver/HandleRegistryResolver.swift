public class HandleRegistryResolver: ResourceResolver {
    private let handleRegistry: HandleRegistry

    public init(handleRegistry: HandleRegistry) {
        self.handleRegistry = handleRegistry
    }

    public func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult {
        guard let record = handleRegistry.resolveFromRequest(request) else { return .skip }
        // TTL is owned by `HandleRegistry.resolve` (relative to the handle's own creation time).
        // The descriptor's `createdAtMillis` is a placeholder (0) for handle-backed resources, so
        // forwarding `record.ttlMillis` here would make `DefaultPolicy.postCheck`'s absolute-time
        // TTL check (`createdAtMillis + ttl <= now`) always evaluate expired — the handle registry
        // already expires handles on lookup, so we must NOT re-enforce TTL at postCheck. Pass nil
        // so postCheck skips the TTL branch entirely. See design.md §3.3 / §5.2.
        return .hit(ResourceDescriptor(
            id: record.fileName,
            namespace: request.namespace,
            type: .dynamic,
            source: record.source,
            mimeType: record.mimeType,
            createdAtMillis: 0,
            ttlMillis: nil,
            scope: nil
        ))
    }
}
