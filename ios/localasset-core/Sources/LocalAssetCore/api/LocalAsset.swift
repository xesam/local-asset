import Foundation

public class LocalAsset {
    public let engine: LocalAssetEngine
    private let registry: ResourceRegistry
    private let handleRegistry: HandleRegistry

    private init(engine: LocalAssetEngine, registry: ResourceRegistry, handleRegistry: HandleRegistry) {
        self.engine = engine
        self.registry = registry
        self.handleRegistry = handleRegistry
    }

    public func register(descriptor: ResourceDescriptor) throws { try registry.register(descriptor: descriptor) }
    public func unregister(id: String) { registry.remove(id: id) }
    public func registerHandle(_ handle: ResourceHandle) -> String { handleRegistry.register(handle: handle) }
    public func resolveHandle(_ resourceUri: String) throws -> ResourceHandleRecord { try handleRegistry.resolve(resourceUri: resourceUri) }
    public func removeHandle(_ resourceUri: String) { handleRegistry.remove(resourceUri: resourceUri) }
    public func cleanup() { registry.cleanup() }
    public func cleanupHandles() { handleRegistry.cleanup() }

    public class Builder {
        private var adapters: [SchemeAdapter] = []
        private var resolvers: [ResourceResolver] = []
        private var allowedFileRoots: [URL] = []
        private var allowedNamespaces: Set<String> = []
        private var allowedSchemes: Set<String> = []
        private var registry: ResourceRegistry?
        private var handleRegistry: HandleRegistry?
        private var policy: Policy?
        private var loader: ResourceLoader?
        private var observer: EngineObserver?

        public init() {}

        @discardableResult public func addAdapter(_ adapter: SchemeAdapter) -> Builder { adapters.append(adapter); return self }
        @discardableResult public func addResolver(_ resolver: ResourceResolver) -> Builder { resolvers.append(resolver); return self }

        /// Adds a directory that the default `DefaultPolicy` will accept `FilePath` resources from.
        ///
        /// The default policy is fail-closed: with no allowed roots, every `.filePath` descriptor
        /// is rejected at postCheck ("file source is outside allowed roots"). Add every root you
        /// want `FilePath` resources to live under here instead of hand-building a `DefaultPolicy`.
        /// Ignored when a custom `policy` is supplied — in that case configure allowed roots on
        /// your own `Policy`.
        @discardableResult public func addAllowedFileRoot(_ root: URL) -> Builder { allowedFileRoots.append(root); return self }
        @discardableResult public func addAllowedFileRoots(_ roots: [URL]) -> Builder { allowedFileRoots.append(contentsOf: roots); return self }

        /// Adds a namespace the default `DefaultPolicy` will accept at preCheck (design.md §5.2
        /// "namespace 白名单"). With no namespaces added, every non-blank namespace is accepted
        /// (fail-open default, preserves existing behavior). Ignored when a custom `policy` is supplied.
        @discardableResult public func addAllowedNamespace(_ namespace: String) -> Builder { allowedNamespaces.insert(namespace); return self }
        @discardableResult public func addAllowedNamespaces(_ namespaces: [String]) -> Builder { allowedNamespaces.formUnion(namespaces); return self }

        /// Adds a scheme the default `DefaultPolicy` will accept at preCheck (design.md §5.2
        /// "scheme 合法性"). With no schemes added, every non-blank scheme is accepted. Ignored
        /// when a custom `policy` is supplied.
        @discardableResult public func addAllowedScheme(_ scheme: String) -> Builder { allowedSchemes.insert(scheme); return self }
        @discardableResult public func addAllowedSchemes(_ schemes: [String]) -> Builder { allowedSchemes.formUnion(schemes); return self }

        @discardableResult public func registry(_ r: ResourceRegistry) -> Builder { registry = r; return self }
        @discardableResult public func handleRegistry(_ r: HandleRegistry) -> Builder { handleRegistry = r; return self }
        @discardableResult public func policy(_ p: Policy) -> Builder { policy = p; return self }
        @discardableResult public func loader(_ l: ResourceLoader) -> Builder { loader = l; return self }

        /// Attaches an `EngineObserver` to the default engine so each stage of the pipeline
        /// (adapter parse, policy pre/post, every resolver's decision, load, terminal outcome)
        /// fires an `EngineStageEvent` — design.md §8.
        @discardableResult public func observer(_ o: EngineObserver) -> Builder { observer = o; return self }

        public func build() -> LocalAsset {
            let reg = registry ?? InMemoryResourceRegistry()
            let handleReg = handleRegistry ?? InMemoryHandleRegistry()
            let allAdapters = adapters.isEmpty ? [DefaultLocalAssetSchemeAdapter()] : adapters
            let allResolvers = [HandleRegistryResolver(handleRegistry: handleReg)] +
                resolvers +
                [RegistryResolver(registry: reg)]
            let engine = DefaultLocalAssetEngine(
                adapters: allAdapters,
                resolverChain: ResolverChain(resolvers: allResolvers),
                policy: policy ?? DefaultPolicy(
                    allowedFileRoots: allowedFileRoots,
                    allowedSchemes: allowedSchemes,
                    allowedNamespaces: allowedNamespaces
                ),
                loader: loader ?? CompositeResourceLoader(loaders: [BytesResourceLoader(), FileResourceLoader(), StreamResourceLoader()])
            )
            return LocalAsset(engine: engine, registry: reg, handleRegistry: handleReg)
        }
    }
}
