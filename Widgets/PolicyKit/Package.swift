// swift-tools-version: 6.4
import PackageDescription

/// Standalone SwiftPM package that compiles `LiveActivityCapPolicy.swift` —
/// the exact file the Widgets extension target builds, reached via a
/// filesystem symlink at `Sources/LiveActivityPolicyKit/LiveActivityCapPolicy.swift`
/// (SwiftPM rejects a target `path:` outside the package root, so a symlink
/// is the only way to share the file without copy/drift) — purely so its
/// auto-end policy is `swift test`-able outside the widget-extension
/// sandbox. This package is NOT referenced by `project.yml` / the Xcode
/// project — it exists only for `swift test --package-path Widgets/PolicyKit`.
/// Foundation-only; never add an ActivityKit/WidgetKit import here.
let package = Package(
    name: "LiveActivityPolicyKit",
    platforms: [.iOS(.v27), .watchOS(.v27), .macOS(.v27)],
    targets: [
        .target(name: "LiveActivityPolicyKit"),
        .testTarget(
            name: "LiveActivityPolicyKitTests",
            dependencies: ["LiveActivityPolicyKit"]
        ),
    ]
)
