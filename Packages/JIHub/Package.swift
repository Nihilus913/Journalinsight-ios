// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "JIHub",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIHub", targets: ["JIHub"])],
    dependencies: [.package(path: "../JICore")],
    targets: [
        .target(name: "JIHub", dependencies: ["JICore"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "JIHubTests", dependencies: ["JIHub"]),
    ]
)
