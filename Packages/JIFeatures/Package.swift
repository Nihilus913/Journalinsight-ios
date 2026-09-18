// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "JIFeatures",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIFeatures", targets: ["JIFeatures"])],
    dependencies: [
        .package(path: "../JICore"),
        .package(path: "../JIHub"),
        .package(path: "../JIPersistence"),
        .package(path: "../JIDesign"),
        .package(path: "../JIVault"),
        // W5b-L3 (P-gate-config): the gate-config editor previews an override by running the REAL
        // `JICompute.evaluate()` against one bundled fixture day — never a re-implementation.
        .package(path: "../JICompute"),
    ],
    targets: [
        .target(
            name: "JIFeatures",
            dependencies: ["JICore", "JIHub", "JIPersistence", "JIDesign", "JIVault", "JICompute"],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(name: "JIFeaturesTests", dependencies: ["JIFeatures"], resources: [.copy("GateConfigFixtures")], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
