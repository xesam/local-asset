import Foundation

public enum ResourceType {
    case `static`
    case dynamic
}

public enum ResourceScope {
    case engine
    case page
    case session
}

public enum ResourceSource {
    case bytes(Data)
    case filePath(String)
    /// A re-openable stream producer: each call returns a FRESH `InputStream` the caller owns and
    /// must close. Carrying the factory (not an open stream) keeps the descriptor a stable,
    /// reusable value: the same descriptor can be loaded repeatedly, and no one-shot resource
    /// lives in the engine/loader. The platform response layer is the sole opener/consumer/closer.
    case stream(() -> InputStream)
}

public struct ResourceDescriptor {
    public let id: String
    public let namespace: String
    public let type: ResourceType
    public let source: ResourceSource
    public let mimeType: String?
    public let createdAtMillis: Int64
    public let ttlMillis: Int64?
    public let scope: ResourceScope?

    public init(
        id: String,
        namespace: String,
        type: ResourceType,
        source: ResourceSource,
        mimeType: String?,
        createdAtMillis: Int64,
        ttlMillis: Int64?,
        scope: ResourceScope?
    ) {
        self.id = id
        self.namespace = namespace
        self.type = type
        self.source = source
        self.mimeType = mimeType
        self.createdAtMillis = createdAtMillis
        self.ttlMillis = ttlMillis
        self.scope = scope
    }
}
