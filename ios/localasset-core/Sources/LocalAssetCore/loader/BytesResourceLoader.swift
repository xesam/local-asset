public class BytesResourceLoader: TypedResourceLoader {
    public init() {}

    public func canLoad(source: ResourceSource) -> Bool {
        if case .bytes = source { return true }
        return false
    }

    public func load(descriptor: ResourceDescriptor) throws -> ResourceData {
        guard case .bytes(let data) = descriptor.source else {
            throw ResourceException(.loadError, "unsupported source type")
        }
        return .bytes(data, descriptor.mimeType)
    }
}
