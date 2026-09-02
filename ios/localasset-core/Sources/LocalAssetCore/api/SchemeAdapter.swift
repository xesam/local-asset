public protocol SchemeAdapter {
    func canHandle(url: String) -> Bool
    func parse(url: String) throws -> AssetRequest
}
