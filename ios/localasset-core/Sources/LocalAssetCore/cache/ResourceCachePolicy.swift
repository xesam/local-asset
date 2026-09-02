import Foundation

/// The cache headers for a resolved resource, computed once and attached by the platform response
/// layer. `cacheControl` is `Cache-Control`, `etag` is `ETag`.
public struct CacheDecision {
    public let cacheControl: String
    public let etag: String

    public init(cacheControl: String, etag: String) {
        self.cacheControl = cacheControl
        self.etag = etag
    }
}

/// Platform-agnostic cache policy so Android and iOS emit identical headers for the same descriptor
/// (design.md §7). Pure Swift: derives `Cache-Control` from the resource type and an `ETag` from
/// the descriptor.
///
/// - STATIC resources are immutable bundle assets → cacheable with `max-age`. DYNAMIC resources
///   are registry-registered and may change per resolve → `no-store`.
/// - The ETag is built from `descriptor.id` plus a cheap, content-reflecting signal so it is stable
///   across resolves but changes when the underlying bytes change: file `lastModified` for
///   `filePath`, byte size for `bytes`, and id-only (weak) for `stream` (a factory can't be drained
///   for a hash without defeating the point of streaming).
///
/// Conditional GET (304) is intentionally NOT implemented: the default platform response builders
/// always return 200 with these headers, so a 304 is never produced. The `ETag` is still emitted
/// as metadata; within `max-age`, WebView serves from its cache without revalidating, which is where
/// the bandwidth saving actually comes from.
///
/// App-update caveat: for `stream`-backed bundle assets the ETag is id-only and does NOT change
/// across app updates, so WebView may serve a stale cached copy for up to `maxAgeSeconds` after an
/// update. Ship immutable bundles, lower `maxAgeSeconds`, or use versioned URLs if you mutate bundle
/// assets between releases.
public enum ResourceCachePolicy {
    public static let defaultMaxAgeSeconds = 86400

    public static func decide(
        descriptor: ResourceDescriptor,
        maxAgeSeconds: Int = defaultMaxAgeSeconds
    ) -> CacheDecision {
        let cacheControl: String
        if descriptor.type == .static {
            cacheControl = "public, max-age=\(maxAgeSeconds)"
        } else {
            cacheControl = "no-store"
        }
        return CacheDecision(cacheControl: cacheControl, etag: computeEtag(descriptor: descriptor))
    }

    private static func computeEtag(descriptor: ResourceDescriptor) -> String {
        switch descriptor.source {
        case .filePath(let path):
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\"\(descriptor.id)-\(Int(mtime))\""
        case .bytes(let data):
            return "\"\(descriptor.id)-\(data.count)\""
        case .stream:
            return "W/\"\(descriptor.id)\""
        }
    }
}
