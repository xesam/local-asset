import Foundation

public class FileResourceLoader: TypedResourceLoader {
    public init() {}

    public func canLoad(source: ResourceSource) -> Bool {
        if case .filePath = source { return true }
        return false
    }

    public func load(descriptor: ResourceDescriptor) throws -> ResourceData {
        guard case .filePath(let path) = descriptor.source else {
            throw ResourceException(.loadError, "unsupported source type")
        }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            throw ResourceException(.loadError, "file source is not readable")
        }
        // Stream the file instead of materializing it: hand back a re-openable factory whose open()
        // returns a fresh InputStream. The fileExists/isDir check above is the load-time probe
        // (FileDirectoryResolver also checks at resolve time); the platform response layer opens,
        // consumes, and closes — file bytes never sit fully in memory.
        return .stream({ InputStream(url: url) ?? InputStream(data: Data()) }, descriptor.mimeType)
    }
}
