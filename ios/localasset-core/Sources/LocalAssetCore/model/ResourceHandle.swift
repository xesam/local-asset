import Foundation

/**
 * A runtime resource pending registration as a `local-asset://handles/...` URI.
 *
 * The handle carries a `source` (either in-memory `bytes` or a `filePath` on disk) rather than
 * always buffering bytes — so a large downloaded/generated file can be exposed as a revocable,
 * expiring capability without being read into memory first. A `filePath` handle is still
 * authorized by its opaque token; the file-root gate is enforced at postCheck (shared with the
 * Registry path), so the path must live under a root declared via `addAllowedFileRoot`.
 */
public struct ResourceHandle {
    public let source: ResourceSource
    public let fileName: String
    public let mimeType: String
    public let metadata: [String: String]
    public let ttlMillis: Int64?

    public init(
        source: ResourceSource,
        fileName: String,
        mimeType: String,
        metadata: [String: String] = [:],
        ttlMillis: Int64? = nil
    ) {
        self.source = source
        self.fileName = fileName
        self.mimeType = mimeType
        self.metadata = metadata
        self.ttlMillis = ttlMillis
    }
}

public struct ResourceHandleRecord {
    public let resourceUri: String
    public let source: ResourceSource
    public let fileName: String
    public let mimeType: String
    /// `nil` for non-bytes sources (filePath/stream): the size is not known at register time and
    /// the file is not probed. For `.bytes` it is the byte count.
    public let size: Int64?
    public let metadata: [String: String]
    public let ttlMillis: Int64?

    public init(
        resourceUri: String,
        source: ResourceSource,
        fileName: String,
        mimeType: String,
        size: Int64?,
        metadata: [String: String],
        ttlMillis: Int64? = nil
    ) {
        self.resourceUri = resourceUri
        self.source = source
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.metadata = metadata
        self.ttlMillis = ttlMillis
    }
}
