import Foundation
import UniformTypeIdentifiers
import LocalAssetCore

func guessMimeType(_ path: String) -> String? {
    let ext = (path as NSString).pathExtension.lowercased()
    guard !ext.isEmpty else { return nil }
    return UTType(filenameExtension: ext)?.preferredMIMEType
}

func resolverNormalize(_ prefix: String) -> String {
    let p = prefix.hasPrefix("/") ? prefix : "/\(prefix)"
    return p.hasSuffix("/") ? String(p.dropLast()) : p
}

func resolverMatchesPrefix(_ path: String, _ prefix: String) -> Bool {
    path == prefix || path.hasPrefix(prefix + "/")
}
