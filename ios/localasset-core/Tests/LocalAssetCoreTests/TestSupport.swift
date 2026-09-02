import Foundation

/// Shared test helpers for the `LocalAssetCoreTests` target.

/// Reads a re-openable stream factory to completion — the test mirror of the chunked pump in
/// `LocalAssetSchemeHandler`, so streaming sources can be asserted against expected content.
func drain(_ open: () -> InputStream) -> Data {
    let stream = open()
    stream.open()
    defer { stream.close() }
    var out = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read > 0 { out.append(buffer, count: read) } else { break }
    }
    return out
}

/// Loads the shared cross-platform fixtures under `docs/compatibility-fixtures/`. The repo root
/// is derived from this file's location, so the helper works regardless of the test working dir.
enum FixtureLoader {
    /// `<repo>/ios/localasset-core/Tests/LocalAssetCoreTests/TestSupport.swift`
    /// → walk up five components to reach the repo root that holds `docs/`.
    static var repoRoot: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // TestSupport.swift
            .deletingLastPathComponent()   // LocalAssetCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // localasset-core
            .deletingLastPathComponent()   // ios
    }

    /// Loads a fixture as a JSON array of rows (`[[String: Any]]`).
    static func load(_ name: String) throws -> [[String: Any]] {
        let url = repoRoot.appendingPathComponent("docs/compatibility-fixtures/\(name)")
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return raw as? [[String: Any]] ?? []
    }
}
