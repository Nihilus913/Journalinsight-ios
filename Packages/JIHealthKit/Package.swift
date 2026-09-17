// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "JIHealthKit",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIHealthKit", targets: ["JIHealthKit"])],
    dependencies: [.package(path: "../JICore"), .package(path: "../JIHub")],
    targets: [
        .target(name: "JIHealthKit", dependencies: ["JICore", "JIHub"], swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "JIHealthKitTests", dependencies: ["JIHealthKit"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
