import Foundation

/// A `TypedResourceLoader` whose data source is intrinsically async — e.g. a network pre-fetch
/// cache, a Room/CoreData query, or any IO that is naturally `async`.
///
/// The engine pipeline is synchronous (WebView bridges are synchronous: `WKURLSchemeHandler.start`
/// expects `didReceive`/`didFinish` to be called, and runs on a dedicated background queue). This
/// interface bridges that gap additively and non-breakingly: implement only `canLoad` and
/// `loadAsync`, and the inherited `load` runs `loadAsync` via a `Task` + `DispatchSemaphore` bridge
/// (design.md §9.3 — the documented workaround, now a first-class, typed extension point instead
/// of per-callers bridge boilerplate).
///
/// Caveat: `load` blocks the calling thread until `loadAsync` completes. The default engine call
/// site is `WKURLSchemeHandler.start`'s dedicated queue (not the Swift cooperative pool), so the
/// `Task` has pool threads to run on and the wait will not self-deadlock. Do NOT call `load` from a
/// Swift cooperative-pool thread (e.g. a `Task` body) — that can deadlock. For long sources,
/// prefer a sync loader that owns its own queue/thread.
public protocol AsyncResourceLoader: TypedResourceLoader {
    func loadAsync(descriptor: ResourceDescriptor) async throws -> ResourceData
}

public extension AsyncResourceLoader {
    /// Sync bridge over `loadAsync`. Blocks the calling thread until the spawned `Task` finishes.
    func load(descriptor: ResourceDescriptor) throws -> ResourceData {
        let semaphore = DispatchSemaphore(value: 0)
        var captured: Result<ResourceData, Error>?
        Task {
            do {
                captured = .success(try await loadAsync(descriptor: descriptor))
            } catch {
                captured = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try captured!.get()
    }
}
