import Foundation

public func currentMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}
