// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "JIHealthKit",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIHealthKit", targets: ["JIHealthKit"])],
    // W7-L3: `JICompute` joins the graph so the T2 provider computes its sleep score with the
    // frozen W6 parity port (`computeSleepScore`) instead of re-implementing the arithmetic.
    dependencies: [.package(path: "../JICore"), .package(path: "../JIHub"), .package(path: "../JICompute")],
    targets: [
        .target(name: "JIHealthKit", dependencies: ["JICore", "JIHub", "JICompute"], swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "JIHealthKitTests", dependencies: ["JIHealthKit", "JICompute"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
