public class ClosureResolver: ResourceResolver {
    private let closure: (AssetRequest, ResolveContext) -> ResolverResult
    public init(_ closure: @escaping (AssetRequest, ResolveContext) -> ResolverResult) {
        self.closure = closure
    }
    public func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult {
        closure(request, context)
    }
}
