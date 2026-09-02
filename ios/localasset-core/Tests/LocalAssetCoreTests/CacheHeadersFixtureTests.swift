import Testing
import Foundation
@testable import LocalAssetCore

/// Cross-platform parity contract for cache headers: loads the shared `cache-headers.json` fixture
/// and asserts the core `ResourceCachePolicy` reproduces its `cacheControl`/`etag` for every case.
/// Mirrors `CacheHeadersFixtureTest` on Android so a fixture or policy change that diverges the
/// platforms breaks one side's test.
@Suite("CacheHeadersFixture")
struct CacheHeadersFixtureTests {
    @Test func cache_headers_fixture_matches_policy() throws {
        let cases = try FixtureLoader.load("cache-headers.json")
        for row in cases {
            let name = row["name"] as? String ?? "?"
            let input = try #require(row["input"] as? [String: Any])
            let type: ResourceType = (input["type"] as? String == "static") ? .static : .dynamic
            let source: ResourceSource
            switch input["source"] as? String {
            case "bytes":
                let size = input["size"] as? Int ?? 0
                source = .bytes(Data(count: size))
            case "stream":
                source = .stream({ InputStream(data: Data()) })
            default:
                Issue.record("unknown source kind in fixture case \(name)"); return
            }
            let id = input["id"] as? String ?? ""
            let maxAge = input["maxAgeSeconds"] as? Int ?? ResourceCachePolicy.defaultMaxAgeSeconds
            let descriptor = ResourceDescriptor(
                id: id, namespace: "fixture", type: type, source: source,
                mimeType: nil, createdAtMillis: 0, ttlMillis: nil, scope: nil
            )
            let decision = ResourceCachePolicy.decide(descriptor: descriptor, maxAgeSeconds: maxAge)
            let expected = try #require(row["expected"] as? [String: Any])
            let expectedCacheControl = expected["cacheControl"] as? String
            let expectedEtag = expected["etag"] as? String
            #expect(decision.cacheControl == expectedCacheControl, "cacheControl for \(name)")
            #expect(decision.etag == expectedEtag, "etag for \(name)")
        }
    }
}
