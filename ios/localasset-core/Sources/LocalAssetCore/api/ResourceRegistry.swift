public protocol ResourceRegistry {
    func register(descriptor: ResourceDescriptor) throws
    func lookup(id: String) -> RegistryLookupResult
    func remove(id: String)
    func cleanup(nowMillis: Int64)
}

public extension ResourceRegistry {
    func cleanup() { cleanup(nowMillis: currentMillis()) }
}

public enum RegistryLookupResult {
    case hit(ResourceDescriptor)
    case missing
    case expired
}
