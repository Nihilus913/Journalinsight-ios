// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "JICore",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JICore", targets: ["JICore"])],
    targets: [
        .target(name: "JICore", resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "JICoreTests", dependencies: ["JICore"], resources: [.copy("Resources")]),
    ]
)
