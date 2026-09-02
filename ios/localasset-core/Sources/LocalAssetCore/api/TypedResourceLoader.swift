import Foundation

/// A `ResourceLoader` that declares which `ResourceSource` kinds it can load via `canLoad`.
///
/// `CompositeResourceLoader` dispatches by calling `canLoad` on each loader in order and using the
/// first that accepts the descriptor's source. Implement this (rather than a bare `ResourceLoader`)
/// when you want a custom loader to participate in source-type dispatch — e.g. a loader for a new
/// `ResourceSource` kind, or an `AsyncResourceLoader` that bridges an async data source.
public protocol TypedResourceLoader: ResourceLoader {
    func canLoad(source: ResourceSource) -> Bool
}
