import Foundation

/// The kind of a [ResourceSource], for allow-listing in [DefaultPolicy].
public enum ResourceSourceKind: Sendable, Hashable {
    case bytes
    case filePath
    case stream
}

public extension ResourceSource {
    var kind: ResourceSourceKind {
        switch self {
        case .bytes: return .bytes
        case .filePath: return .filePath
        case .stream: return .stream
        }
    }
}

public class DefaultPolicy: Policy {
    private let allowedSourceTypes: Set<ResourceSourceKind>
    private let allowedFileRoots: [URL]
    /// Optional scheme allow-list (request-level). Empty (default) = unrestricted; every non-blank
    /// scheme passes. When non-empty, a request whose scheme is not in the set is rejected at
    /// preCheck. Matches design.md §5.2 "scheme 合法性".
    private let allowedSchemes: Set<String>
    /// Optional namespace allow-list (request-level). Empty (default) = unrestricted; every
    /// non-blank namespace passes (preserves the fail-open default so existing callers that rely
    /// on ad-hoc namespaces keep resolving). When non-empty, a request whose namespace is not in
    /// the set is rejected at preCheck. Matches design.md §5.2 "namespace 白名单".
    private let allowedNamespaces: Set<String>
    /// Namespace under which handle URIs are minted; always exempt from `allowedNamespaces`.
    /// Defaults to `defaultHandleHost`. Pass a custom value only when using a custom
    /// `HandleRegistry` that mints under a different host.
    private let handleHost: String
    private let nowMillis: () -> Int64

    public init(
        allowedSourceTypes: Set<ResourceSourceKind> = [.bytes, .filePath, .stream],
        allowedFileRoots: [URL] = [],
        allowedSchemes: Set<String> = [],
        allowedNamespaces: Set<String> = [],
        handleHost: String = defaultHandleHost,
        nowMillis: @escaping () -> Int64 = currentMillis
    ) {
        self.allowedSourceTypes = allowedSourceTypes
        self.allowedFileRoots = allowedFileRoots.map { $0.resolvingSymlinksInPath() }
        self.allowedSchemes = allowedSchemes
        self.allowedNamespaces = allowedNamespaces
        self.handleHost = handleHost
        self.nowMillis = nowMillis
    }

    public func preCheck(request: AssetRequest, context: ResolveContext) throws {
        guard !request.scheme.isEmpty else {
            throw ResourceException(.securityError, "scheme must not be blank", stage: "policy_pre")
        }
        if !allowedSchemes.isEmpty, !allowedSchemes.contains(request.scheme) {
            throw ResourceException(.securityError, "scheme is not allowed: \(request.scheme)", stage: "policy_pre")
        }
        guard !request.namespace.isEmpty else {
            throw ResourceException(.securityError, "namespace must not be blank", stage: "policy_pre")
        }
        if !allowedNamespaces.isEmpty, request.namespace != handleHost, !allowedNamespaces.contains(request.namespace) {
            throw ResourceException(.securityError, "namespace is not allowed: \(request.namespace)", stage: "policy_pre")
        }
        // Request-level path-traversal gate (defense in depth before any resolver sees the path).
        // A `..` segment in an `local-asset://` path is never legitimate and lets directory-scoped
        // resolvers escape their root; reject it here as a SECURITY_ERROR rather than relying on
        // each resolver's own containment check. Matches design.md §5.2 "identifier/path 格式".
        if Self.containsTraversalSegment(request.path) || Self.containsTraversalSegment(request.identifier) {
            throw ResourceException(.securityError, "path traversal is not allowed", stage: "policy_pre")
        }
    }

    private static func containsTraversalSegment(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return value.split(separator: "/").contains("..")
    }

    public func postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext) throws {
        if let ttl = descriptor.ttlMillis,
           descriptor.createdAtMillis + ttl <= nowMillis() {
            throw ResourceException(.resolutionError, "resource expired", stage: "policy_post")
        }
        if let scope = descriptor.scope {
            let expectedScopeId: String?
            switch scope {
            case .engine: expectedScopeId = context.engineScope
            case .page: expectedScopeId = context.pageScope
            case .session: expectedScopeId = context.sessionScope
            }
            guard descriptor.namespace == expectedScopeId else {
                throw ResourceException(.securityError, "\(scope) scope mismatch", stage: "policy_post")
            }
        }
        guard allowedSourceTypes.contains(descriptor.source.kind) else {
            throw ResourceException(.securityError, "source type is not allowed: \(descriptor.source.kind)", stage: "policy_post")
        }
        if case .filePath(let path) = descriptor.source {
            guard isAllowedFilePath(path) else {
                throw ResourceException(.securityError, "file source is outside allowed roots", stage: "policy_post")
            }
        }
    }

    private func isAllowedFilePath(_ path: String) -> Bool {
        guard !allowedFileRoots.isEmpty else { return false }
        let filePath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return allowedFileRoots.contains { root in
            filePath == root.path || filePath.hasPrefix(root.path + "/")
        }
    }
}
