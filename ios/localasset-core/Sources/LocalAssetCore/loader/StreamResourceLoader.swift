import Foundation

/// Pass-through loader for `ResourceSource.stream`. Honors the streaming ownership model: it does
/// NOT call the factory — it wraps the re-openable factory into `ResourceData.stream` and lets the
/// platform response layer open, consume, and close the stream. The engine and loader therefore
/// never hold an open stream.
public class StreamResourceLoader: TypedResourceLoader {
    public init() {}

    public func canLoad(source: ResourceSource) -> Bool {
        if case .stream = source { return true }
        return false
    }

    public func load(descriptor: ResourceDescriptor) throws -> ResourceData {
        guard case .stream(let open) = descriptor.source else {
            throw ResourceException(.loadError, "unsupported source type")
        }
        return .stream(open, descriptor.mimeType)
    }
}
