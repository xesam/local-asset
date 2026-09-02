import Foundation
import LocalAssetCore
import os

/// An `EngineObserver` that mirrors every pipeline stage to the system log (category
/// `LocalAssetObserver`). Attach via `LocalAsset.Builder.observer(LoggingEngineObserver())`.
///
/// This is the structured-logging counterpart to `LocalAssetSchemeHandler`'s failure `NSLog` line:
/// that line only fires on terminal failures, while this observer records the *full* path —
/// adapter parse, both policy checks, every resolver's skip/hit/failure, the load step, and the
/// terminal outcome — so a Console.app trace during development shows the whole decision chain.
public final class LoggingEngineObserver: EngineObserver {
    private let logger: Logger
    private let sink: (String) -> Void

    public init(subsystem: String = "io.github.xesam.localasset") {
        self.logger = Logger(subsystem: subsystem, category: "LocalAssetObserver")
        self.sink = { message in NSLog("[LocalAssetObserver] \(message)") }
    }

    /// Testable initializer: pass a custom sink to capture formatted lines.
    public init(sink: @escaping (String) -> Void) {
        self.logger = Logger(subsystem: "io.github.xesam.localasset", category: "LocalAssetObserver")
        self.sink = sink
    }

    public func onStage(_ event: EngineStageEvent) {
        var parts: [String] = ["stage=\(event.stage)"]
        if let request = event.request { parts.append("ns=\(request.namespace)") }
        if let index = event.resolverIndex {
            parts.append("resolver[\(index)]=\(event.resolverResult.map { "\($0)" } ?? "-")")
        }
        if let descriptor = event.descriptor { parts.append("descriptor=\(descriptor.id)") }
        if let failure = event.failure {
            parts.append("failure[\(failure.category)/\(failure.stage ?? "-")] \(failure.reason)")
        }
        let message = parts.joined(separator: " ")
        logger.debug("\(message, privacy: .public)")
        sink(message)
    }
}
