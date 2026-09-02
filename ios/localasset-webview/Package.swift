// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalAssetWebView",
    platforms: [.iOS(.v14), .macOS(.v12)],
    products: [
        .library(name: "LocalAssetWebView", targets: ["LocalAssetWebView"]),
    ],
    dependencies: [
        .package(path: "../localasset-core"),
    ],
    targets: [
        .target(
            name: "LocalAssetWebView",
            dependencies: [.product(name: "LocalAssetCore", package: "localasset-core")]
        ),
        .testTarget(
            name: "LocalAssetWebViewTests",
            dependencies: ["LocalAssetWebView"],
            path: "Tests/LocalAssetWebViewTests"
        ),
    ]
)
