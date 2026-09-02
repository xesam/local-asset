public struct ResourceException: Error {
    public let category: ResourceErrorCategory
    public let message: String
    public let stage: String?

    public init(_ category: ResourceErrorCategory, _ message: String, stage: String? = nil) {
        self.category = category
        self.message = message
        self.stage = stage
    }
}
