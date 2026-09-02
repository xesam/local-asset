public protocol ResourceResolver {
    func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult
}

public enum ResolverResult {
    case hit(ResourceDescriptor)
    case skip
    case failure(category: ResourceErrorCategory, reason: String)
}
