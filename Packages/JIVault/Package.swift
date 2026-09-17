// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "JIVault",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIVault", targets: ["JIVault"])],
    targets: [
        .target(
            name: "JIVault",
            swiftSettings: [.swiftLanguageMode(.v6), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "JIVaultTests",
            dependencies: ["JIVault"],
            resources: [.copy("Resources/fold_vault_vectors.json")],
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
    ]
)
