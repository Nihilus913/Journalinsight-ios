import Foundation

/// §8.5 one cell of the screenshot sweep. Sizes are points (portrait unless the name says
/// landscape). iPad rows are added when §8.3 turns iPad on.
public nonisolated struct SweepCell: Sendable, Hashable {
    public let device: String, width: CGFloat, height: CGFloat, dark: Bool, ax: Bool
    public var fileStem: String { "\(device)-\(Int(width))x\(Int(height))-\(dark ? "dark" : "light")-\(ax ? "ax3" : "default")" }
}

public nonisolated enum SweepMatrix {
    public static let sizes: [(device: String, width: CGFloat, height: CGFloat)] = [
        ("iphone18pro", 393, 852),
        ("iphone18promax", 440, 956),
        ("iphone18promax-landscape", 956, 440),
    ]
    public static var cells: [SweepCell] {
        sizes.flatMap { s in
            [false, true].flatMap { dark in
                [false, true].map { ax in SweepCell(device: s.device, width: s.width, height: s.height, dark: dark, ax: ax) }
            }
        }
    }
}
