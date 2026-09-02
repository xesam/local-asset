public struct AssetRequest {
    public let scheme: String
    public let namespace: String
    public let identifier: String?
    public let path: String?
    public let query: [String: String]
    public let fragment: String?
    public let metadata: [String: String]

    public init(
        scheme: String,
        namespace: String,
        identifier: String?,
        path: String?,
        query: [String: String],
        fragment: String?,
        metadata: [String: String] = [:]
    ) {
        self.scheme = scheme
        self.namespace = namespace
        self.identifier = identifier
        self.path = path
        self.query = query
        self.fragment = fragment
        self.metadata = metadata
    }
}
