public struct ResolverChain {
    private let resolvers: [ResourceResolver]

    public init(resolvers: [ResourceResolver]) {
        self.resolvers = resolvers
    }

    public func resolve(
        request: AssetRequest,
        context: ResolveContext,
        observer: EngineObserver? = nil
    ) -> ResolverResult {
        for (index, resolver) in resolvers.enumerated() {
            let result = resolver.resolve(request: request, context: context)
            let descriptor: ResourceDescriptor? = {
                if case .hit(let d) = result { return d }
                return nil
            }()
            observer?.onStage(EngineStageEvent(
                stage: EngineStage.resolve,
                request: request,
                resolverIndex: index,
                resolver: resolver,
                resolverResult: result,
                descriptor: descriptor
            ))
            switch result {
            case .hit, .failure: return result
            case .skip: continue
            }
        }
        return .skip
    }
}
