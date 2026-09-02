import Foundation
import LocalAssetCore

/// Maps the core error category enum to the cross-platform string name used by the
/// error-categories / security-models / handle-lifecycle demos (matches Android's enum names).
func errorCategoryName(_ category: ResourceErrorCategory) -> String {
    switch category {
    case .parseError: return "PARSE_ERROR"
    case .resolutionError: return "RESOLUTION_ERROR"
    case .loadError: return "LOAD_ERROR"
    case .securityError: return "SECURITY_ERROR"
    }
}

/// Loads the shared `logo.svg` bytes from the demo folder reference as a resource payload for
/// handle registration / descriptor sources. Returns empty data if missing.
func demoLogoData() -> Data {
    guard let url = Bundle.main.resourceURL?.appendingPathComponent("demo/static/images/logo.svg"),
          let data = try? Data(contentsOf: url) else { return Data() }
    return data
}
