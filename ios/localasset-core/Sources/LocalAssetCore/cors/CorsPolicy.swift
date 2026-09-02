import Foundation

/// Platform-agnostic CORS decision so Android, iOS and HarmonyOS emit identical headers for the same
/// (allow-list, request `Origin`) pair. Pinned tri-platform by
/// `docs/compatibility-fixtures/cors-headers.json`.
///
/// ## Why the default emits nothing
///
/// A `local-asset://` response is cross-origin to any `https://` (or `file://`) page, so
/// `Access-Control-Allow-Origin: *` makes the bytes readable by **every** origin loaded in that
/// WebView — including a third-party iframe or an injected script. That is fatal on the Handle path
/// specifically: its access control is a capability token carried in the URL path (design.md §5.4),
/// and URL paths leak through `document.referrer`, the `Referer` header on outbound requests, and
/// `performance.getEntriesByType('resource')`. Wildcard CORS turns any such leak directly into
/// readable bytes.
///
/// `<img>`, `<link>`, `<script>` and `<video>` do not consult CORS at all, so the default of "no CORS
/// headers" still serves the common embedding cases. Only `fetch()`/`XMLHttpRequest` need a header,
/// and those callers know their own origin — hence the opt-in allow-list.
public enum CorsPolicy {
    /// Membership value that restores blanket `Access-Control-Allow-Origin: *`.
    public static let allowAnyOrigin = "*"

    private static let allowOrigin = "Access-Control-Allow-Origin"
    private static let allowMethods = "Access-Control-Allow-Methods"
    private static let methods = "GET, OPTIONS"

    /// - Parameters:
    ///   - allowedOrigins: empty = emit no CORS headers; containing `allowAnyOrigin` = wildcard;
    ///     otherwise an exact-match allow-list of origins (`scheme://host[:port]`, no trailing slash).
    ///   - requestOrigin: the request's `Origin` header, or nil when absent (a same-origin or
    ///     non-CORS request — browsers only send it for CORS and non-GET).
    public static func headers(
        allowedOrigins: Set<String>,
        requestOrigin: String?
    ) -> [String: String] {
        if allowedOrigins.isEmpty {
            return [:]
        }
        if allowedOrigins.contains(allowAnyOrigin) {
            return [allowOrigin: allowAnyOrigin, allowMethods: methods]
        }
        if let requestOrigin, allowedOrigins.contains(requestOrigin) {
            return [
                allowOrigin: requestOrigin,
                allowMethods: methods,
                // The response varies by request Origin, so a cache keyed on URL alone would serve
                // one origin's allow-header to another.
                "Vary": "Origin",
            ]
        }
        return [:]
    }
}
