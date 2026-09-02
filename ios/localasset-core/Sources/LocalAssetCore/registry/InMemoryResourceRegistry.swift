import Foundation

public class InMemoryResourceRegistry: ResourceRegistry {
    private var items: [String: ResourceDescriptor] = [:]
    private let lock = NSLock()
    private let nowMillis: () -> Int64

    public init(nowMillis: @escaping () -> Int64 = currentMillis) {
        self.nowMillis = nowMillis
    }

    public func register(descriptor: ResourceDescriptor) throws {
        try lock.withLock {
            guard items[descriptor.id] == nil else {
                throw ResourceException(.resolutionError, "duplicate resource id: \(descriptor.id)")
            }
            items[descriptor.id] = descriptor
        }
    }

    public func lookup(id: String) -> RegistryLookupResult {
        lock.withLock {
            guard let d = items[id] else { return .missing }
            guard let ttl = d.ttlMillis else { return .hit(d) }
            return d.createdAtMillis + ttl <= nowMillis() ? .expired : .hit(d)
        }
    }

    public func remove(id: String) {
        lock.withLock { _ = items.removeValue(forKey: id) }
    }

    public func cleanup(nowMillis: Int64) {
        lock.withLock {
            items = items.filter { _, d in
                d.ttlMillis.map { d.createdAtMillis + $0 > nowMillis } ?? true
            }
        }
    }
}
