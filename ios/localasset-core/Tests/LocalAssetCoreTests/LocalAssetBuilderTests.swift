import Testing
import Foundation
@testable import LocalAssetCore

@Suite("LocalAsset.Builder")
struct LocalAssetBuilderTests {
    @Test func resolve_handle_returns_registered_metadata() throws {
        let asset = LocalAsset.Builder().build()
        let previewUri = asset.registerHandle(
            ResourceHandle(source: .bytes("preview".data(using: .utf8)!),
                           fileName: "preview.png", mimeType: "image/png",
                           metadata: ["android.content_uri": "content://demo/image/1"])
        )
        let record = try asset.resolveHandle(previewUri)

        #expect(previewUri == record.resourceUri)
        #expect(record.fileName == "preview.png")
        #expect(record.mimeType == "image/png")
        #expect(record.metadata["android.content_uri"] == "content://demo/image/1")
        #expect(record.size == 7)
    }

    @Test func builder_default_policy_rejects_filepath_without_allowed_root() throws {
        let (root, file) = try makeTempFile(name: "note.txt", contents: "hi")
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = LocalAsset.Builder().build()
        try asset.register(descriptor: ResourceDescriptor(
            id: "note", namespace: "files", type: .dynamic,
            source: .filePath(file.path), mimeType: "text/plain",
            createdAtMillis: currentMillis(), ttlMillis: nil, scope: nil
        ))

        let result = asset.engine.resolve(url: "local-asset://files/note")

        // fail-closed by default: no allowed root configured → failure at postCheck
        if case .failure = result { /* ok */ } else { Issue.record("expected failure, got \(result)") }
    }

    @Test func builder_add_allowed_file_root_lets_filepath_resolve() throws {
        let (root, file) = try makeTempFile(name: "note.txt", contents: "hi")
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = LocalAsset.Builder().addAllowedFileRoot(root).build()
        try asset.register(descriptor: ResourceDescriptor(
            id: "note", namespace: "files", type: .dynamic,
            source: .filePath(file.path), mimeType: "text/plain",
            createdAtMillis: currentMillis(), ttlMillis: nil, scope: nil
        ))

        let result = asset.engine.resolve(url: "local-asset://files/note")

        guard case .success(_, let data) = result else {
            Issue.record("expected success, got \(result)"); return
        }
        guard case .stream(let open, _) = data else { Issue.record("expected .stream"); return }
        #expect(drain(open) == "hi".data(using: .utf8)!)
    }

    @Test func builder_add_allowed_file_root_ignored_when_custom_policy_supplied() throws {
        let (root, file) = try makeTempFile(name: "note.txt", contents: "hi")
        defer { try? FileManager.default.removeItem(at: root) }
        // custom policy with empty allowed roots — Builder knob must not override it
        let asset = LocalAsset.Builder()
            .addAllowedFileRoot(root)
            .policy(DefaultPolicy())
            .build()
        try asset.register(descriptor: ResourceDescriptor(
            id: "note", namespace: "files", type: .dynamic,
            source: .filePath(file.path), mimeType: "text/plain",
            createdAtMillis: currentMillis(), ttlMillis: nil, scope: nil
        ))

        let result = asset.engine.resolve(url: "local-asset://files/note")

        if case .failure = result { /* ok */ } else { Issue.record("expected failure, got \(result)") }
    }

    private func makeTempFile(name: String, contents: String) throws -> (root: URL, file: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: file)
        return (root, file)
    }
}
