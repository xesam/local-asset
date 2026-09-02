public class DefaultLocalAssetEngine: LocalAssetEngine {
    private let adapterRegistry: AdapterRegistry
    private let resolverChain: ResolverChain
    private let policy: Policy
    private let loader: ResourceLoader
    private let observer: EngineObserver?

    public init(
        adapters: [SchemeAdapter],
        resolverChain: ResolverChain,
        policy: Policy,
        loader: ResourceLoader,
        observer: EngineObserver? = nil
    ) {
        self.adapterRegistry = AdapterRegistry(adapters: adapters)
        self.resolverChain = resolverChain
        self.policy = policy
        self.loader = loader
        self.observer = observer
    }

    public func resolve(url: String, context: ResolveContext) -> EngineResult {
        let request: AssetRequest
        do {
            let adapter = try adapterRegistry.select(url: url)
            request = try adapter.parse(url: url)
        } catch {
            return stageFailure(error, stage: EngineStage.adapterParse, request: nil,
                defaultCategory: .parseError, defaultPrefix: "invalid url: ")
        }
        emit(EngineStage.adapterParse, request: request)
        return resolve(request: request, context: context)
    }

    public func resolve(request: AssetRequest, context: ResolveContext) -> EngineResult {
        do {
            try policy.preCheck(request: request, context: context)
        } catch {
            return stageFailure(error, stage: EngineStage.policyPre, request: request,
                defaultCategory: .securityError, defaultPrefix: "preCheck failed: ")
        }
        emit(EngineStage.policyPre, request: request)

        let resolverResult = resolverChain.resolve(request: request, context: context, observer: observer)

        switch resolverResult {
        case .skip:
            return emitFailure(
                EngineStage.resolve, request: request,
                failure: EngineFailure(category: .resolutionError, reason: "resource not found", stage: EngineStage.resolve)
            )
        case .failure(let category, let reason):
            return emitFailure(
                EngineStage.resolve, request: request,
                failure: EngineFailure(category: category, reason: reason, stage: EngineStage.resolve)
            )
        case .hit(let descriptor):
            return resolveHit(request: request, descriptor: descriptor, context: context)
        }
    }

    private func resolveHit(
        request: AssetRequest,
        descriptor: ResourceDescriptor,
        context: ResolveContext
    ) -> EngineResult {
        do {
            try policy.postCheck(request: request, descriptor: descriptor, context: context)
        } catch {
            return stageFailure(error, stage: EngineStage.policyPost, request: request, descriptor: descriptor,
                defaultCategory: .securityError, defaultPrefix: "postCheck failed: ")
        }
        emit(EngineStage.policyPost, request: request, descriptor: descriptor)

        do {
            let data = try loader.load(descriptor: descriptor)
            emit(EngineStage.load, request: request, descriptor: descriptor)
            emit(EngineStage.complete, request: request, descriptor: descriptor)
            return .success(descriptor: descriptor, data: data)
        } catch {
            return stageFailure(error, stage: EngineStage.load, request: request, descriptor: descriptor,
                defaultCategory: .loadError, defaultPrefix: "unexpected load failure: ")
        }
    }

    // MARK: - Error handling helpers

    /// Unified error handler for throwing pipeline stages: extracts `ResourceException`
    /// category/stage when present, otherwise wraps with a stage-specific fallback category and
    /// prefix; emits the failure event and returns the matching `EngineResult.failure`.
    ///
    /// Mirrors the Kotlin `stageFailure` and ArkTS `toFailure` + emit pattern, keeping error
    /// messages and stage assignments identical across platforms.
    private func stageFailure(
        _ error: Error,
        stage: String,
        request: AssetRequest?,
        descriptor: ResourceDescriptor? = nil,
        defaultCategory: ResourceErrorCategory,
        defaultPrefix: String
    ) -> EngineResult {
        let failure: EngineFailure
        if let e = error as? ResourceException {
            failure = EngineFailure(category: e.category, reason: e.message, stage: e.stage ?? stage)
        } else {
            failure = EngineFailure(category: defaultCategory, reason: "\(defaultPrefix)\(error)", stage: stage)
        }
        emit(stage, request: request, descriptor: descriptor, failure: failure)
        return .failure(category: failure.category, reason: failure.reason, stage: failure.stage)
    }

    /// Emits `failure` to the observer (if attached) and returns the matching `EngineResult.failure`
    /// — used for non-throwing failure paths (ResolverResult.Failure / Skip).
    @discardableResult
    private func emitFailure(
        _ stage: String,
        request: AssetRequest?,
        descriptor: ResourceDescriptor? = nil,
        failure: EngineFailure
    ) -> EngineResult {
        emit(stage, request: request, descriptor: descriptor, failure: failure)
        return .failure(category: failure.category, reason: failure.reason, stage: failure.stage)
    }

    private func emit(
        _ stage: String,
        request: AssetRequest?,
        descriptor: ResourceDescriptor? = nil,
        failure: EngineFailure? = nil
    ) {
        observer?.onStage(EngineStageEvent(
            stage: stage,
            request: request,
            descriptor: descriptor,
            failure: failure
        ))
    }
}
