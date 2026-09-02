struct AdapterRegistry {
    private let adapters: [SchemeAdapter]

    init(adapters: [SchemeAdapter]) {
        self.adapters = adapters
    }

    func select(url: String) throws -> SchemeAdapter {
        guard let adapter = adapters.first(where: { $0.canHandle(url: url) }) else {
            throw ResourceException(.parseError, "no adapter can handle url")
        }
        return adapter
    }
}
