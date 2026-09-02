public class StaticMapResolver: ResourceResolver {
    private let mappings: [String: ResourceDescriptor]

    public init(mappings: [String: ResourceDescriptor]) {
        self.mappings = mappings
    }

    public func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult {
        guard let path = request.path else { return .skip }
        guard let descriptor = mappings["\(request.namespace):\(path)"] else { return .skip }
        return .hit(descriptor)
    }
}
