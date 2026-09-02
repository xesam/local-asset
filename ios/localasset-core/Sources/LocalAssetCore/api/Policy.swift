public protocol Policy {
    func preCheck(request: AssetRequest, context: ResolveContext) throws
    func postCheck(request: AssetRequest, descriptor: ResourceDescriptor, context: ResolveContext) throws
}
