import Foundation

public class DefaultLocalAssetSchemeAdapter: SchemeAdapter {
    public init() {}

    public func canHandle(url: String) -> Bool {
        URLComponents(string: url)?.scheme == "local-asset"
    }

    public func parse(url: String) throws -> AssetRequest {
        guard let comps = URLComponents(string: url) else {
            throw ResourceException(.parseError, "invalid url")
        }
        guard comps.scheme == "local-asset" else {
            throw ResourceException(.parseError, "unsupported scheme")
        }
        guard let namespace = comps.host, !namespace.isEmpty else {
            throw ResourceException(.parseError, "missing namespace")
        }
        let rawPath = comps.path
        guard !rawPath.isEmpty else {
            throw ResourceException(.parseError, "missing path")
        }
        let path = rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)"
        let identifier = path.split(separator: "/").last.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        let query = Dictionary(
            (comps.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return AssetRequest(
            scheme: comps.scheme!,
            namespace: namespace,
            identifier: identifier,
            path: path,
            query: query,
            fragment: comps.fragment
        )
    }
}
