import Foundation
import LocalAssetCore

/// Maps `local-asset://host/pathPrefix/**` to files in an app Bundle.
/// Analogous to Android's `AssetDirectoryResolver`.
public class BundleDirectoryResolver: ResourceResolver {
    private let host: String
    private let normalizedPathPrefix: String
    private let bundleDirectory: String
    private let bundle: Bundle

    public init(host: String, pathPrefix: String, bundleDirectory: String = "", bundle: Bundle = .main) {
        self.host = host
        self.normalizedPathPrefix = resolverNormalize(pathPrefix)
        self.bundleDirectory = bundleDirectory
        self.bundle = bundle
    }

    public func resolve(request: AssetRequest, context: ResolveContext) -> ResolverResult {
        guard request.namespace == host, let path = request.path else { return .skip }
        guard resolverMatchesPrefix(path, normalizedPathPrefix) else { return .skip }
        let relative = String(path.dropFirst(normalizedPathPrefix.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty, !relative.contains("..") else { return .skip }
        let resourcePath = bundleDirectory.isEmpty ? relative : "\(bundleDirectory)/\(relative)"
        guard let base = bundle.resourceURL else { return .skip }
        let fileURL = base.appendingPathComponent(resourcePath)
        // Probe at resolve time: the isRegularFile check confirms existence so a missing resource
        // still Skips at the RESOLVE stage (cross-platform error-stage consistency). Bundle resources
        // are immutable, so there is no TOCTOU gap between this probe and the load-time open.
        guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return .skip }
        // Stream instead of buffering: hand back a re-openable factory. The platform response layer
        // (LocalAssetSchemeHandler) opens, pumps, and closes it — bundle bytes never sit in memory.
        let openStream: () -> InputStream = {
            // isRegularFile was verified at resolve; a subsequent open failure is a rare race that
            // degrades to an empty stream rather than crashing the handler.
            InputStream(url: fileURL) ?? InputStream(data: Data())
        }
        return .hit(ResourceDescriptor(
            id: "\(host):\(path)",
            namespace: host,
            type: .static,
            source: .stream(openStream),
            mimeType: guessMimeType(relative),
            createdAtMillis: currentMillis(),
            ttlMillis: nil,
            scope: nil
        ))
    }
}
