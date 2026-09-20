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
        // W8-L4 (B-12): ONE `HKPermission` app-wide — JIFeatures now consumes JIHealthKit's instead of
        // carrying a same-named duplicate that `AppEnvironment` had to map case by case.
        .package(path: "../JIHealthKit"),
        // B-37-L1 (P-workouts): `WorkoutSending` + `WorkoutBuilder` for the Training "Send to Watch" sheet (L3).
        .package(path: "../JIWorkouts"),
    ],
    targets: [
        .target(
            name: "JIFeatures",
            dependencies: ["JICore", "JIHub", "JIPersistence", "JIDesign", "JIVault", "JICompute", "JIHealthKit", "JIWorkouts"],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(name: "JIFeaturesTests", dependencies: ["JIFeatures"], resources: [.copy("GateConfigFixtures")], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
