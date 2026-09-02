import Testing
import Foundation
@testable import LocalAssetCore

@Suite("CompositeResourceLoader")
struct CompositeResourceLoaderTests {
    @Test func loads_bytes_source() throws {
        let loader = CompositeResourceLoader(loaders: [BytesResourceLoader(), FileResourceLoader()])
        let payload = Data("hello".utf8)
        let descriptor = ResourceDescriptor(
            id: "bytes", namespace: "demo", type: .dynamic,
            source: .bytes(payload), mimeType: "text/plain",
            createdAtMillis: 0, ttlMillis: nil, scope: nil
        )

        let data = try loader.load(descriptor: descriptor)

        guard case .bytes(let b, _) = data else { Issue.record("expected .bytes"); return }
        #expect(b == payload)
        #expect(data.mimeType == "text/plain")
    }

    @Test func loads_file_source() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("la-\(UUID().uuidString).txt")
        try Data("from-file".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let loader = CompositeResourceLoader(loaders: [BytesResourceLoader(), FileResourceLoader()])
        let descriptor = ResourceDescriptor(
            id: "file", namespace: "demo", type: .static,
            source: .filePath(tempFile.path), mimeType: "text/plain",
            createdAtMillis: 0, ttlMillis: nil, scope: nil
        )

        let data = try loader.load(descriptor: descriptor)

        guard case .stream(let open, _) = data else { Issue.record("expected .stream"); return }
        #expect(drain(open) == Data("from-file".utf8))
        #expect(data.mimeType == "text/plain")
    }

    @Test func throws_when_no_loader_matches_source_type() {
        let loader = CompositeResourceLoader(loaders: [])
        let descriptor = ResourceDescriptor(
            id: "orphan", namespace: "demo", type: .dynamic,
            source: .bytes(Data("hello".utf8)), mimeType: "text/plain",
            createdAtMillis: 0, ttlMillis: nil, scope: nil
        )

        do {
            _ = try loader.load(descriptor: descriptor)
            Issue.record("expected load to throw")
        } catch let e as ResourceException {
            if case .loadError = e.category {
                // ok
            } else {
                Issue.record("expected loadError, got \(e.category)")
            }
        } catch {
            Issue.record("expected ResourceException, got \(error)")
        }
    }

    @Test func dispatch_uses_canLoad_not_concrete_type() throws {
        // A custom TypedResourceLoader that claims .bytes via canLoad must win over a later
        // BytesResourceLoader — proving dispatch is by canLoad, not by concrete type.
        final class CustomBytesLoader: TypedResourceLoader {
            func canLoad(source: ResourceSource) -> Bool {
                if case .bytes = source { return true }
                return false
            }

            func load(descriptor: ResourceDescriptor) throws -> ResourceData {
                guard case .bytes(let data) = descriptor.source else {
                    throw ResourceException(.loadError, "unsupported source type")
                }
                return .bytes(data, "custom/\(data.count)")
            }
        }
        let loader = CompositeResourceLoader(loaders: [CustomBytesLoader(), BytesResourceLoader()])
        let descriptor = ResourceDescriptor(
            id: "x", namespace: "demo", type: .dynamic,
            source: .bytes(Data("hello".utf8)), mimeType: "text/plain",
            createdAtMillis: 0, ttlMillis: nil, scope: nil
        )

        let data = try loader.load(descriptor: descriptor)

        // The custom loader produced a distinct mimeType, proving it was selected first.
        #expect(data.mimeType == "custom/5")
    }
}
