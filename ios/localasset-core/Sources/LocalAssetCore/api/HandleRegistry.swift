public protocol HandleRegistry {
    func register(handle: ResourceHandle) -> String
    func resolve(resourceUri: String) throws -> ResourceHandleRecord
    func remove(resourceUri: String)
    func cleanup(nowMillis: Int64)
}

/// Default host (namespace) under which handle URIs are minted:
/// `local-asset://<defaultHandleHost>/handles/<token>/<file>`. The Handle path is authorized by
/// the capability token, not by the namespace, so `DefaultPolicy` exempts this namespace from its
/// namespace allow-list — otherwise declaring an allowed namespace would silently reject every
/// handle URI. A custom `HandleRegistry` minting under a different host must pass that host to
/// `DefaultPolicy(handleHost:)` so the exemption still applies.
public let defaultHandleHost = "handles.localasset.local"

public extension HandleRegistry {
    func cleanup() { cleanup(nowMillis: currentMillis()) }

    /// Reconstructs the Handle-Backed URI from `request` and looks it up via `resolve`.
    ///
    /// Contract: the reconstructed URI string MUST be byte-identical to the one returned by
    /// `register` — same scheme, host (namespace), path, query encoding, and fragment. The
    /// default implementation rebuilds the URI from `AssetRequest` fields with an unspecified
    /// `Dictionary` iteration order for the query, so a custom `HandleRegistry` that mints URIs
    /// with a different query encoding/ordering must override this to reproduce the exact string
    /// it registered, otherwise lookup silently misses (`nil` → resolver `.skip`).
    ///
    /// Reserved query param `_la_cb`: stripped before reconstruction. It exists so callers can
    /// cache-bust a handle URI (append `?_la_cb=<changing>` to defeat WKWebView's in-memory image
    /// cache, which otherwise serves a stale copy on same-URL re-fetch and skips the scheme
    /// handler entirely) without breaking lookup — the registered URI has no query, so the
    /// capability identity is the path. Non-`_la_cb` query keys remain part of the identity.
    func resolveFromRequest(_ request: AssetRequest) -> ResourceHandleRecord? {
        let path = request.path ?? "/\(request.identifier ?? "")"
        var uri = "\(request.scheme)://\(request.namespace)\(path)"
        let identityQuery = request.query.filter { $0.key != Self.cacheBustParam }
        if !identityQuery.isEmpty {
            let qs = identityQuery.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            uri += "?\(qs)"
        }
        if let fragment = request.fragment { uri += "#\(fragment)" }
        return try? resolve(resourceUri: uri)
    }

    /// Reserved cache-bust query parameter, stripped by `resolveFromRequest` so it never
    /// participates in handle identity. See `resolveFromRequest`.
    static var cacheBustParam: String { "_la_cb" }
}
