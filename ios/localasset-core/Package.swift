// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalAssetCore",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [
        .library(name: "LocalAssetCore", targets: ["LocalAssetCore"]),
    ],
    targets: [
        .target(name: "LocalAssetCore"),
        .testTarget(name: "LocalAssetCoreTests", dependencies: ["LocalAssetCore"]),
    ]
)
