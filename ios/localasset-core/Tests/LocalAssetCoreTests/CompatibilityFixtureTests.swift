import Testing
import Foundation
@testable import LocalAssetCore

/// Cross-platform parity contract: the shared JSON fixtures in `docs/compatibility-fixtures/`
/// must be loadable from the iOS test target and must match what `DefaultLocalAssetSchemeAdapter`
/// actually parses. Mirrors `CompatibilityFixtureTest` on Android so a fixture change that breaks
/// one platform breaks the other.
@Suite("CompatibilityFixture")
struct CompatibilityFixtureTests {
    @Test func basic_routing_fixture_matches_adapter_parse() throws {
        let cases = try FixtureLoader.load("basic-routing.json")
        let names = cases.compactMap { $0["name"] as? String }
        #expect(names.contains("parse-basic-local-asset-url"))
        #expect(names.contains("reject-invalid-local-asset-url"))

        let adapter = DefaultLocalAssetSchemeAdapter()
        let req = try adapter.parse(url: "local-asset://image/logo?id=home&theme=dark")

        // Find the parse case and assert each parsed field matches the fixture's `expected`.
        let parseCase = cases.first { $0["name"] as? String == "parse-basic-local-asset-url" }
        let expected = try #require(parseCase?["expected"] as? [String: Any])
        #expect(expected["scheme"] as? String == req.scheme)
        #expect(expected["namespace"] as? String == req.namespace)
        #expect(expected["identifier"] as? String == req.identifier)
        let expectedQuery = expected["query"] as? [String: String] ?? [:]
        #expect(expectedQuery == req.query)
    }

    @Test func reject_invalid_url_fixture_matches_adapter_behavior() throws {
        let cases = try FixtureLoader.load("basic-routing.json")
        let rejectCase = try #require(
            cases.first { $0["name"] as? String == "reject-invalid-local-asset-url" }
        )
        let expected = try #require(rejectCase["expected"] as? [String: Any])
        #expect(expected["errorCategory"] as? String == "parse_error")
        // The adapter itself must reject the invalid URL with a parse error.
        #expect(throws: ResourceException.self) {
            _ = try DefaultLocalAssetSchemeAdapter().parse(url: "local-asset:///invalid")
        }
    }
}
