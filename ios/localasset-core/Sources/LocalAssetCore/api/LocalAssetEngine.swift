public protocol LocalAssetEngine {
    func resolve(url: String, context: ResolveContext) -> EngineResult
    func resolve(request: AssetRequest, context: ResolveContext) -> EngineResult
}

public extension LocalAssetEngine {
    func resolve(url: String) -> EngineResult {
        resolve(url: url, context: ResolveContext())
    }
}

public enum EngineResult {
    case success(descriptor: ResourceDescriptor, data: ResourceData)
    case failure(category: ResourceErrorCategory, reason: String, stage: String?)
}
