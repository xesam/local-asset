import Testing
import Foundation
@testable import LocalAssetCore

@Suite("AsyncResourceLoader")
struct AsyncResourceLoaderTests {
    private final class SlowNetworkLoader: AsyncResourceLoader {
        func canLoad(source: ResourceSource) -> Bool {
            if case .bytes = source { return true }
            return false
        }

        func loadAsync(descriptor: ResourceDescriptor) async throws -> ResourceData {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms — simulate an async data source
            guard case .bytes(let data) = descriptor.source else {
                throw ResourceException(.loadError, "unsupported source type")
            }
            return .bytes(data, descriptor.mimeType)
        }
    }

    @Test func async_loader_is_driven_through_sync_pipeline() throws {
        let loader = SlowNetworkLoader()
        let composite = CompositeResourceLoader(loaders: [loader])
        let payload = Data("from-async".utf8)
        let descriptor = ResourceDescriptor(
            id: "net-1", namespace: "ns", type: .dynamic,
            source: .bytes(payload), mimeType: "text/plain",
            createdAtMillis: 0, ttlMillis: nil, scope: nil
        )

        let data = try composite.load(descriptor: descriptor)

        guard case .bytes(let b, _) = data else { Issue.record("expected .bytes"); return }
        #expect(b == payload)
        #expect(data.mimeType == "text/plain")
    }

    @Test func async_loader_failure_propagates_as_load_error() {
        final class FailingAsyncLoader: AsyncResourceLoader {
            func canLoad(source: ResourceSource) -> Bool {
                if case .bytes = source { return true }
                return false
            }

            func loadAsync(descriptor: ResourceDescriptor) async throws -> ResourceData {
                throw ResourceException(.loadError, "boom")
            }
        }
        let composite = CompositeResourceLoader(loaders: [FailingAsyncLoader()])
        let descriptor = ResourceDescriptor(
            id: "net-2", namespace: "ns", type: .dynamic,
            source: .bytes(Data()), mimeType: nil,
            createdAtMillis: 0, ttlMillis: nil, scope: nil
        )

        do {
            _ = try composite.load(descriptor: descriptor)
            Issue.record("expected load to throw")
        } catch let e as ResourceException {
            if case .loadError = e.category {
                // ok
            } else {
                Issue.record("expected loadError, got \(e.category)")
            }
            #expect(e.message == "boom")
        } catch {
            Issue.record("expected ResourceException, got \(error)")
        }
    }
}
