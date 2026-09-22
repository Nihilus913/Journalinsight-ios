// swift-tools-version: 6.4
import PackageDescription
// B-37-L1 (P-workouts): WorkoutKit is iOS/watchOS-only — run THIS package's tests on the sim:
// `xcodebuild test -scheme JIWorkouts -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'`.
let package = Package(
    name: "JIWorkouts",
    // B-33 fix round 2 (F3): `.macOS` added so the JIFeatures HOST test suite can resolve this
    // package — WorkoutKit stays iOS/watchOS-only and is `#if canImport`-guarded in the sources.
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIWorkouts", targets: ["JIWorkouts"])],
    dependencies: [.package(path: "../JICore")],
    targets: [
        .target(name: "JIWorkouts", dependencies: ["JICore"], swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "JIWorkoutsTests", dependencies: ["JIWorkouts", "JICore"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
