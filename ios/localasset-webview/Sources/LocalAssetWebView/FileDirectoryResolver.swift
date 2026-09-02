import Foundation
import LocalAssetCore

/// Maps `local-asset://host/pathPrefix/**` to files in a given filesystem directory.
/// Analogous to Android's `FileDirectoryResolver`.
public class FileDirectoryResolver: ResourceResolver {
    private let host: String
    private let normalizedPathPrefix: String
    private let canonicalRoot: URL

    public init(host: String, pathPrefix: String, rootDirectory: URL) {
        self.host = host
        self.normalizedPathPrefix = resolverNormalize(pathPrefix)
        self.canonicalRoot = rootDirectory.resolvingSymlinksInPath()
    }

    public func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult {
        guard request.namespace == host, let path = request.path else { return .skip }
        guard resolverMatchesPrefix(path, normalizedPathPrefix) else { return .skip }
        let relative = String(path.dropFirst(normalizedPathPrefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty, !relative.contains("..") else { return .skip }
        let target = canonicalRoot.appendingPathComponent(relative).resolvingSymlinksInPath()
        guard target.path.hasPrefix(canonicalRoot.path + "/") || target.path == canonicalRoot.path,
              FileManager.default.fileExists(atPath: target.path) else { return .skip }
        return .hit(ResourceDescriptor(
            id: "\(host):\(path)",
            namespace: host,
            type: .static,
            source: .filePath(target.path),
            mimeType: guessMimeType(relative),
            createdAtMillis: currentMillis(),
            ttlMillis: nil,
            scope: nil
        ))
    }
}
