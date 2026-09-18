// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "JICompute",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JICompute", targets: ["JICompute"])],
    targets: [
        .target(name: "JICompute", swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "JIComputeTests", dependencies: ["JICompute"], resources: [.copy("Resources")], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
