public protocol ResourceLoader {
    func load(descriptor: ResourceDescriptor) throws -> ResourceData
}
