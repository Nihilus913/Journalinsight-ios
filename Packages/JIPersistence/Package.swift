// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "JIPersistence",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIPersistence", targets: ["JIPersistence"])],
    dependencies: [
        .package(path: "../JICore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "JIPersistence", dependencies: ["JICore", .product(name: "GRDB", package: "GRDB.swift")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "JIPersistenceTests", dependencies: ["JIPersistence"]),
    ]
)
