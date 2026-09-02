import Testing
import Foundation
@testable import LocalAssetCore

@Suite("InMemoryHandleRegistry")
struct InMemoryHandleRegistryTests {
    @Test func registered_handle_can_be_resolved_by_generated_uri() throws {
        let registry = InMemoryHandleRegistry(host: "bridge.demo.local", pathPrefix: "/preview")
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes("preview".data(using: .utf8)!),
                           fileName: "demo-image.jpg", mimeType: "image/jpeg")
        )
        let record = try registry.resolve(resourceUri: resourceUri)

        #expect(resourceUri.hasPrefix("local-asset://bridge.demo.local/preview/"))
        #expect(resourceUri == record.resourceUri)
        #expect(record.fileName == "demo-image.jpg")
        #expect(record.mimeType == "image/jpeg")
        #expect(record.size == 7)
        guard case .bytes(let b) = record.source else {
            Issue.record("expected .bytes source"); return
        }
        #expect(b == "preview".data(using: .utf8)!)
    }

    @Test func removed_handle_cannot_be_resolved() {
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes(Data()), fileName: "demo.jpg", mimeType: "image/jpeg")
        )
        registry.remove(resourceUri: resourceUri)
        #expect(throws: ResourceException.self) { try registry.resolve(resourceUri: resourceUri) }
    }

    @Test func expired_handle_cannot_be_resolved() {
        var now: Int64 = 0
        let registry = InMemoryHandleRegistry(nowMillis: { now })
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes(Data()), fileName: "demo.jpg", mimeType: "image/jpeg", ttlMillis: 1_000)
        )
        now = 2_000
        #expect(throws: ResourceException.self) { try registry.resolve(resourceUri: resourceUri) }
    }

    @Test func concurrent_resolve_on_same_uri_does_not_crash() {
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .bytes("shared".data(using: .utf8)!), fileName: "shared.txt", mimeType: "text/plain")
        )
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            let record = try? registry.resolve(resourceUri: resourceUri)
            guard case .bytes(let b)? = record?.source else {
                Issue.record("expected .bytes source"); return
            }
            #expect(b == "shared".data(using: .utf8)!)
        }
    }

    @Test func cleanup_removes_expired_entries() throws {
        var now: Int64 = 0
        let registry = InMemoryHandleRegistry(nowMillis: { now })
        let uri1 = registry.register(
            handle: ResourceHandle(source: .bytes(Data()), fileName: "a.txt", mimeType: "text/plain", ttlMillis: 1_000)
        )
        let uri2 = registry.register(
            handle: ResourceHandle(source: .bytes(Data()), fileName: "b.txt", mimeType: "text/plain")
        )
        now = 2_000
        registry.cleanup(nowMillis: now)

        #expect(throws: ResourceException.self) { try registry.resolve(resourceUri: uri1) }
        let stillThere = try registry.resolve(resourceUri: uri2)
        #expect(stillThere.fileName == "b.txt")
    }

    @Test func file_backed_handle_records_source_and_null_size() {
        // A filePath handle exposes the path as its source and leaves size nil (the file is not
        // probed at register time). The token still authorizes; the file-root gate is enforced
        // later at postCheck, not by the registry.
        let registry = InMemoryHandleRegistry()
        let resourceUri = registry.register(
            handle: ResourceHandle(source: .filePath("/var/mobile/Containers/Data/Library/Caches/big.pdf"),
                                    fileName: "big.pdf", mimeType: "application/pdf")
        )
        let record = try? registry.resolve(resourceUri: resourceUri)

        guard case .filePath(let path)? = record?.source else {
            Issue.record("expected .filePath source"); return
        }
        #expect(path == "/var/mobile/Containers/Data/Library/Caches/big.pdf")
        #expect(record?.size == nil)
        #expect(record?.fileName == "big.pdf")
    }
}
