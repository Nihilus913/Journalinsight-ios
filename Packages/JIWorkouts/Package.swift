// swift-tools-version: 6.4
import PackageDescription
// B-37-L1 (P-workouts): WorkoutKit is iOS/watchOS-only — no `.macOS` platform here (host `swift test`
// does not apply; run this package's tests on the sim from `Packages/JIWorkouts`:
// `xcodebuild test -scheme JIWorkouts -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'`).
let package = Package(
    name: "JIWorkouts",
    platforms: [.iOS(.v27), .watchOS(.v27)],
    products: [.library(name: "JIWorkouts", targets: ["JIWorkouts"])],
    dependencies: [.package(path: "../JICore")],
    targets: [
        .target(name: "JIWorkouts", dependencies: ["JICore"], swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "JIWorkoutsTests", dependencies: ["JIWorkouts", "JICore"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
