// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "JISnapshot",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JISnapshot", targets: ["JISnapshot"])],
    dependencies: [.package(path: "../JICore")],
    targets: [
        .target(name: "JISnapshot", dependencies: ["JICore"], swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "JISnapshotTests", dependencies: ["JISnapshot"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
