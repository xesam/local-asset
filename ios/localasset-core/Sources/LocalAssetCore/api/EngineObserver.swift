import Foundation

/// Pipeline stage name constants emitted via [EngineObserver].
public enum EngineStage {
    public static let adapterParse = "adapter_parse"
    public static let policyPre = "policy_pre"
    public static let resolve = "resolve"
    public static let policyPost = "policy_post"
    public static let load = "load"
    public static let complete = "complete"
}

/// A normalized failure carried in an [EngineStageEvent] — mirrors `EngineResult.failure`'s
/// associated values so observers can pattern-match without unpacking the result enum.
public struct EngineFailure {
    public let category: ResourceErrorCategory
    public let reason: String
    public let stage: String?

    public init(category: ResourceErrorCategory, reason: String, stage: String?) {
        self.category = category
        self.reason = reason
        self.stage = stage
    }
}

/// A single pipeline event. Only the fields relevant to `stage` are populated:
///
/// - `adapterParse` / `policyPre` / `policyPost` / `load` / `complete`: `request` is set (null only
///   for an `adapterParse` failure that occurred before the URL could be parsed); `descriptor` is
///   set once known (postCheck, load, complete); `failure` is set when this stage is the terminal
///   failure point.
/// - `resolve`: emitted once per resolver in chain order, carrying `resolverIndex` / `resolver` /
///   `resolverResult` (and `descriptor` on a `.hit`); when the whole chain skips, the engine emits
///   one final `resolve` event with `failure` set ("resource not found") and no resolver fields.
public struct EngineStageEvent {
    public let stage: String
    public let request: AssetRequest?
    public let resolverIndex: Int?
    public let resolver: ResourceResolver?
    public let resolverResult: ResolverResult?
    public let descriptor: ResourceDescriptor?
    public let failure: EngineFailure?

    public init(
        stage: String,
        request: AssetRequest?,
        resolverIndex: Int? = nil,
        resolver: ResourceResolver? = nil,
        resolverResult: ResolverResult? = nil,
        descriptor: ResourceDescriptor? = nil,
        failure: EngineFailure? = nil
    ) {
        self.stage = stage
        self.request = request
        self.resolverIndex = resolverIndex
        self.resolver = resolver
        self.resolverResult = resolverResult
        self.descriptor = descriptor
        self.failure = failure
    }

    /// True when this event is the last one the engine emits for the request — either a terminal
    /// failure (carried in `failure`) or the success `complete` event.
    public var isTerminal: Bool { failure != nil || stage == EngineStage.complete }
}

/// Observes the engine pipeline as a single request flows through it. Wire one in via
/// `LocalAsset.Builder.observer(_:)` to get structured visibility into every stage — adapter
/// parse, policy pre/post checks, each resolver's decision, the load step, and the terminal
/// outcome — without coupling to platform logging (design.md §8).
public protocol EngineObserver: AnyObject {
    func onStage(_ event: EngineStageEvent)
}
