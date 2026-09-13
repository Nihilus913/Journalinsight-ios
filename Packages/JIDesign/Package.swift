// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "JIDesign",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    products: [.library(name: "JIDesign", targets: ["JIDesign"])],
    dependencies: [.package(path: "../JICore")],
    targets: [
        .target(name: "JIDesign", dependencies: ["JICore"], swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]),
        .testTarget(name: "JIDesignTests", dependencies: ["JIDesign"]),
    ]
)
