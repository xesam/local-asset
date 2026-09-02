public class RegistryResolver: ResourceResolver {
    private let registry: ResourceRegistry

    public init(registry: ResourceRegistry) {
        self.registry = registry
    }

    public func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult {
        let id = request.identifier ?? request.query["id"]
        guard let id else { return .skip }
        switch registry.lookup(id: id) {
        case .hit(let d):  return .hit(d)
        case .missing:     return .skip
        case .expired:     return .failure(category: .resolutionError, reason: "resource expired")
        }
    }
}
