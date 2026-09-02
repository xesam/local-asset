public class CompositeResourceLoader: ResourceLoader {
    private let loaders: [ResourceLoader]

    public init(loaders: [ResourceLoader]) {
        self.loaders = loaders
    }

    public func load(descriptor: ResourceDescriptor) throws -> ResourceData {
        let typed = loaders.compactMap { $0 as? TypedResourceLoader }
        if let loader = typed.first(where: { $0.canLoad(source: descriptor.source) }) {
            return try loader.load(descriptor: descriptor)
        }
        let nonTypedNames = loaders
            .filter { !($0 is TypedResourceLoader) }
            .map { String(describing: type(of: $0)) }
        throw ResourceException(
            .loadError,
            "no loader for source type \(descriptor.source)" +
                (nonTypedNames.isEmpty
                    ? " (\(typed.count) typed loader(s) checked)"
                    : " (\(typed.count) typed loader(s) checked; \(nonTypedNames.count) loader(s) do not implement TypedResourceLoader: \(nonTypedNames))")
        )
    }
}
