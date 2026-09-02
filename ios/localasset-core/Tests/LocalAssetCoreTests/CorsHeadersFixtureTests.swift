import Testing
import Foundation
@testable import LocalAssetCore

/// Cross-platform parity contract for CORS headers: loads the shared `cors-headers.json` fixture
/// and asserts the core `CorsPolicy` reproduces the exact header map for every case. Mirrors
/// `CorsHeadersFixtureTest` (Android) and `CorsHeadersFixture.test.ets` (HarmonyOS) so a policy
/// change on one platform breaks the others' tests.
@Suite("CorsHeadersFixture")
struct CorsHeadersFixtureTests {
    @Test func cors_headers_fixture_matches_policy() throws {
        let cases = try FixtureLoader.load("cors-headers.json")
        for row in cases {
            let name = row["name"] as? String ?? "?"
            let input = try #require(row["input"] as? [String: Any])
            let originsArray = try #require(input["allowedOrigins"] as? [Any])
            let allowedOrigins = Set(originsArray.compactMap { $0 as? String })
            let requestOrigin = input["requestOrigin"] as? String

            let actual = CorsPolicy.headers(
                allowedOrigins: allowedOrigins,
                requestOrigin: requestOrigin
            )

            let expected = try #require(row["expected"] as? [String: Any])
            let expectedMap = expected.compactMapValues { $0 as? String }
            #expect(actual == expectedMap, "headers for \(name)")
        }
    }
}
