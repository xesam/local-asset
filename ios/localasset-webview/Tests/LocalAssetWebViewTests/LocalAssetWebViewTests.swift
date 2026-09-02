import Testing
import Foundation
@testable import LocalAssetWebView
import LocalAssetCore

/// Reads a re-openable stream factory to completion — the test mirror of the chunked pump in
/// LocalAssetSchemeHandler, so streaming sources can be asserted against expected content.
private func drain(_ open: () -> InputStream) -> Data {
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

// MARK: - BundleDirectoryResolver

@Suite("BundleDirectoryResolver")
struct BundleDirectoryResolverTests {
    /// Creates a temp directory tree and returns a Bundle pointing at its root.
    private func makeBundle(files: [String: String]) throws -> (Bundle, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleDirTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (relativePath, content) in files {
            let file = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        let bundle = Bundle(path: root.path)!
        return (bundle, root)
    }

    @Test func hostMismatch_returnsSkip() throws {
        let (bundle, _) = try makeBundle(files: ["demo/pkg/home.css": "body{}"])
        let resolver = BundleDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", bundleDirectory: "demo/pkg", bundle: bundle)
        let req = AssetRequest(scheme: "local-asset", namespace: "other.host", identifier: "home.css", path: "/pkg/home.css", query: [:], fragment: nil)
        guard case .skip = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected skip"); return
        }
    }

    @Test func prefixMismatch_returnsSkip() throws {
        let (bundle, _) = try makeBundle(files: ["demo/pkg/home.css": "body{}"])
        let resolver = BundleDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", bundleDirectory: "demo/pkg", bundle: bundle)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: "home.css", path: "/other/home.css", query: [:], fragment: nil)
        guard case .skip = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected skip"); return
        }
    }

    @Test func flatFile_returnsHit() throws {
        let (bundle, _) = try makeBundle(files: ["demo/pkg/home.css": "body { color: red }"])
        let resolver = BundleDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", bundleDirectory: "demo/pkg", bundle: bundle)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: "home.css", path: "/pkg/home.css", query: [:], fragment: nil)
        guard case .hit(let d) = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected hit"); return
        }
        #expect(d.mimeType == "text/css")
        if case .stream(let open) = d.source {
            #expect(String(data: drain(open), encoding: .utf8) == "body { color: red }")
        } else { Issue.record("expected stream source") }
    }

    @Test func nestedPath_returnsHit() throws {
        let (bundle, _) = try makeBundle(files: ["demo/pkg/cards/card-a.svg": "<svg/>"])
        let resolver = BundleDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", bundleDirectory: "demo/pkg", bundle: bundle)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: "card-a.svg", path: "/pkg/cards/card-a.svg", query: [:], fragment: nil)
        guard case .hit(let d) = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected hit for nested path"); return
        }
        #expect(d.mimeType == "image/svg+xml")
    }

    @Test func pathTraversal_returnsSkip() throws {
        let (bundle, _) = try makeBundle(files: ["demo/pkg/home.css": "body{}"])
        let resolver = BundleDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", bundleDirectory: "demo/pkg", bundle: bundle)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: nil, path: "/pkg/../secret", query: [:], fragment: nil)
        guard case .skip = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected skip for traversal"); return
        }
    }

    @Test func missingFile_returnsSkip() throws {
        let (bundle, _) = try makeBundle(files: [:])
        let resolver = BundleDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", bundleDirectory: "demo/pkg", bundle: bundle)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: "home.css", path: "/pkg/home.css", query: [:], fragment: nil)
        guard case .skip = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected skip"); return
        }
    }
}

// MARK: - FileDirectoryResolver

@Suite("FileDirectoryResolver")
struct FileDirectoryResolverTests {
    private func makeTempDir(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDirTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (relativePath, content) in files {
            let file = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func flatFile_returnsHit() throws {
        let root = try makeTempDir(files: ["home.css": "body{}"])
        let resolver = FileDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", rootDirectory: root)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: "home.css", path: "/pkg/home.css", query: [:], fragment: nil)
        guard case .hit(let d) = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected hit"); return
        }
        if case .filePath(let path) = d.source {
            #expect(path.hasSuffix("home.css"))
        } else { Issue.record("expected filePath source") }
    }

    @Test func nestedPath_returnsHit() throws {
        let root = try makeTempDir(files: ["cards/card-a.svg": "<svg/>"])
        let resolver = FileDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", rootDirectory: root)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: "card-a.svg", path: "/pkg/cards/card-a.svg", query: [:], fragment: nil)
        guard case .hit = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected hit"); return
        }
    }

    @Test func pathTraversal_returnsSkip() throws {
        let root = try makeTempDir(files: [:])
        // Create a file outside root
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside.txt")
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        let resolver = FileDirectoryResolver(host: "cdn.demo.local", pathPrefix: "/pkg", rootDirectory: root)
        let req = AssetRequest(scheme: "local-asset", namespace: "cdn.demo.local", identifier: nil, path: "/pkg/../outside.txt", query: [:], fragment: nil)
        guard case .skip = resolver.resolve(request: req, context: ResolveContext()) else {
            Issue.record("expected skip for traversal"); return
        }
    }
}

// MARK: - End-to-end: engine + BundleDirectoryResolver

@Suite("Engine + BundleDirectoryResolver Integration")
struct EngineIntegrationTests {
    private func makeBundle(files: [String: String]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineIntTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (relativePath, content) in files {
            let file = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        return Bundle(path: root.path)!
    }

    @Test func resolve_bundleResource_success() throws {
        let bundle = try makeBundle(files: ["demo/pkg/home.css": "body { color: red }"])
        let asset = LocalAsset.Builder()
            .addResolver(BundleDirectoryResolver(
                host: "cdn.demo.local", pathPrefix: "/pkg",
                bundleDirectory: "demo/pkg", bundle: bundle
            ))
            .build()
        let result = asset.engine.resolve(url: "local-asset://cdn.demo.local/pkg/home.css")
        guard case .success(_, let data) = result else {
            Issue.record("expected success, got \(result)"); return
        }
        #expect(data.mimeType == "text/css")
        guard case .stream(let open, _) = data else { Issue.record("expected .stream"); return }
        #expect(String(data: drain(open), encoding: .utf8) == "body { color: red }")
    }

    @Test func resolve_nestedBundleResource_success() throws {
        let bundle = try makeBundle(files: ["demo/pkg/cards/card-a.svg": "<svg/>"])
        let asset = LocalAsset.Builder()
            .addResolver(BundleDirectoryResolver(
                host: "cdn.demo.local", pathPrefix: "/pkg",
                bundleDirectory: "demo/pkg", bundle: bundle
            ))
            .build()
        let result = asset.engine.resolve(url: "local-asset://cdn.demo.local/pkg/cards/card-a.svg")
        guard case .success = result else {
            Issue.record("expected success for nested resource, got \(result)"); return
        }
    }

    @Test func resolve_missingResource_resolutionError() throws {
        let bundle = try makeBundle(files: [:])
        let asset = LocalAsset.Builder()
            .addResolver(BundleDirectoryResolver(
                host: "cdn.demo.local", pathPrefix: "/pkg",
                bundleDirectory: "demo/pkg", bundle: bundle
            ))
            .build()
        let result = asset.engine.resolve(url: "local-asset://cdn.demo.local/pkg/missing.css")
        guard case .failure(let cat, _, _) = result else {
            Issue.record("expected failure"); return
        }
        #expect(cat == .resolutionError)
    }
}
