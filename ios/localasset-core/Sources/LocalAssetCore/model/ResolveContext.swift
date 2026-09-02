public struct ResolveContext {
    public let engineScope: String?
    public let callerScope: String?
    public let pageScope: String?
    public let sessionScope: String?
    public let requestMetadata: [String: String]

    public init(
        engineScope: String? = nil,
        callerScope: String? = nil,
        pageScope: String? = nil,
        sessionScope: String? = nil,
        requestMetadata: [String: String] = [:]
    ) {
        self.engineScope = engineScope
        self.callerScope = callerScope
        self.pageScope = pageScope
        self.sessionScope = sessionScope
        self.requestMetadata = requestMetadata
    }

    /// Key prefix under which platform bridges publish request headers into `requestMetadata`, with
    /// the header name lowercased (`header.origin`, `header.referer`, ...). Shared across
    /// Android/iOS/HarmonyOS so a `Policy` is portable.
    public static let requestHeaderPrefix = "header."

    /// Reads a request header captured by the platform bridge, case-insensitively. Returns nil when
    /// the bridge captured no headers (native callers) — a `Policy` that gates on `Origin` must
    /// therefore decide what "absent" means rather than assuming the header was empty.
    public func requestHeader(_ name: String) -> String? {
        requestMetadata[Self.requestHeaderPrefix + name.lowercased()]
    }
}
