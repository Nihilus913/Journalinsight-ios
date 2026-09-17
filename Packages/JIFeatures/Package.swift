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
    ],
    targets: [
        .target(
            name: "JIFeatures",
            dependencies: ["JICore", "JIHub", "JIPersistence", "JIDesign", "JIVault"],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(name: "JIFeaturesTests", dependencies: ["JIFeatures"], swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
    ]
)
