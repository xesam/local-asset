import Foundation

public class InMemoryHandleRegistry: HandleRegistry {
    private struct StoredHandle {
        let record: ResourceHandleRecord
        let createdAtMillis: Int64
    }

    private var items: [String: StoredHandle] = [:]
    private let lock = NSLock()
    private let host: String
    private let pathPrefix: String
    private let nowMillis: () -> Int64

    public init(
        host: String = defaultHandleHost,
        pathPrefix: String = "/handles",
        nowMillis: @escaping () -> Int64 = currentMillis
    ) {
        self.host = host
        self.pathPrefix = pathPrefix
        self.nowMillis = nowMillis
    }

    public func register(handle: ResourceHandle) -> String {
        let safe = handle.fileName.replacingOccurrences(
            of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression
        )
        let uri = buildUri(token: UUID().uuidString, fileName: safe)
        let size: Int64? = {
            if case .bytes(let data) = handle.source { return Int64(data.count) }
            return nil
        }()
        let record = ResourceHandleRecord(
            resourceUri: uri,
            source: handle.source,
            fileName: handle.fileName,
            mimeType: handle.mimeType,
            size: size,
            metadata: handle.metadata,
            ttlMillis: handle.ttlMillis
        )
        lock.withLock { items[uri] = StoredHandle(record: record, createdAtMillis: nowMillis()) }
        return uri
    }

    public func resolve(resourceUri: String) throws -> ResourceHandleRecord {
        try lock.withLock {
            guard let stored = items[resourceUri] else {
                throw ResourceException(.resolutionError, "Unknown or expired resourceUri: \(resourceUri)")
            }
            if let ttl = stored.record.ttlMillis,
               nowMillis() - stored.createdAtMillis >= ttl {
                items.removeValue(forKey: resourceUri)
                throw ResourceException(.resolutionError, "Unknown or expired resourceUri: \(resourceUri)")
            }
            return stored.record
        }
    }

    public func remove(resourceUri: String) {
        lock.withLock { _ = items.removeValue(forKey: resourceUri) }
    }

    public func cleanup(nowMillis: Int64) {
        lock.withLock {
            items = items.filter { _, stored in
                stored.record.ttlMillis.map { stored.createdAtMillis + $0 > nowMillis } ?? true
            }
        }
    }

    private func buildUri(token: String, fileName: String) -> String {
        let prefix = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = prefix.isEmpty ? "handles" : prefix
        return "local-asset://\(host)/\(p)/\(token)/\(fileName)"
    }
}
