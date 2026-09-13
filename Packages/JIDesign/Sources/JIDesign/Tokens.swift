import SwiftUI
import JICore

public extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

/// Verbatim from mobile/src/theme/tokens.ts (dark scheme). Light scheme = W5.
public enum JIColor {
    public static let bg = Color(hex: 0x0b0f14)
    public static let surface = Color(hex: 0x141a22)
    public static let surface2 = Color(hex: 0x1c242e)
    public static let surface3 = Color(hex: 0x273040)
    public static let nested = Color(hex: 0x333e4d)
    public static let control = Color(hex: 0x3f4b5c)
    public static let text = Color(hex: 0xe6edf3)
    public static let muted = Color(hex: 0x8b98a5)
    public static let mutedNested = Color(hex: 0xb0bcca)
    // Reserved: verdict / band / 0–100 score / status ONLY. Selection + CTA = info.
    public static let go = Color(hex: 0x4ade80)
    public static let reduced = Color(hex: 0xfbbf24)
    public static let danger = Color(hex: 0xf87171)
    public static let info = Color(hex: 0x38bdf8)
    public static let sleep = Color(hex: 0xa78bfa)

    public static func color(for tone: VerdictTone) -> Color {
        switch tone { case .go: go; case .amber: reduced; case .red: danger; case .muted: muted }
    }
}

public enum JIRadius { public static let card: CGFloat = 16; public static let hero: CGFloat = 24 }
