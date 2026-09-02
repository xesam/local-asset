import Foundation

/// The loaded resource payload. `bytes` is materialized content; `stream` carries the re-openable
/// factory from `ResourceSource.stream` so the platform response layer can open, pump, and close
/// it without the engine/loader ever buffering or holding an open stream.
public enum ResourceData {
    case bytes(Data, String?)
    case stream(() -> InputStream, String?)

    public var mimeType: String? {
        switch self {
        case .bytes(_, let mt): return mt
        case .stream(_, let mt): return mt
        }
    }
}
