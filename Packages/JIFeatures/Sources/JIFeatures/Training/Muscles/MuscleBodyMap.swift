import SwiftUI
import CoreGraphics
import JICompute
import JIDesign

/// B-90 p5 — the body front / back silhouette of mockup BP-2-3 (viewBox 120 × 232). Both sides use
/// the SAME outline (Toby 2026-10-04 rendering rule); every muscle shape sits inside it, which
/// `MuscleBodyMapTests` proves on the geometry (grid points of each shape ⊂ outline path).
/// Decorative: the ranked list is the accessible surface, so the map hides from VoiceOver.
nonisolated enum MuscleBodySide: String, Sendable, CaseIterable, Identifiable {
    case front, back
    var id: String { rawValue }
    var label: String { self == .front ? "FRONT" : "BACK" }
}

nonisolated struct MuscleShape: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// `rotation` in degrees about the centre (SVG `rotate(a cx cy)`).
        case ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rotation: CGFloat)
        case roundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat)
        case polygon([CGPoint])
    }

    let muscle: Muscle
    let kind: Kind

    var path: CGPath {
        let p = CGMutablePath()
        switch kind {
        case let .ellipse(cx, cy, rx, ry, rotation):
            let t = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation * .pi / 180)
            p.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: t)
        case let .roundedRect(x, y, w, h, r):
            p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r)
        case let .polygon(points):
            p.addLines(between: points)
            p.closeSubpath()
        }
        return p
    }
}

nonisolated enum MuscleBodyGeometry {
    static let size = CGSize(width: 120, height: 232)
    static let headCenter = CGPoint(x: 60, y: 17)
    static let headRadius: CGFloat = 11

    /// The shared body outline (mockup `bodyfront` / `bodyback` path, verbatim).
    static var outline: CGPath { makeOutline() }

    private static func makeOutline() -> CGPath {
        let p = CGMutablePath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        p.move(to: pt(55, 28))
        p.addLine(to: pt(55, 34))
        p.addCurve(to: pt(28, 42), control1: pt(44, 34), control2: pt(36, 38))
        p.addCurve(to: pt(16, 80), control1: pt(22, 46), control2: pt(18, 60))
        p.addCurve(to: pt(18, 112), control1: pt(15, 92), control2: pt(16, 104))
        for (x, y) in [(26, 112), (26, 84), (30, 60), (34, 62), (34, 112), (35, 150), (37, 215), (52, 215), (53, 180),
                       (55, 150), (60, 128), (65, 150), (67, 180), (68, 215), (83, 215), (85, 150), (86, 112), (86, 62),
                       (90, 60), (94, 84), (94, 112), (102, 112)] as [(CGFloat, CGFloat)] {
            p.addLine(to: pt(x, y))
        }
        p.addCurve(to: pt(104, 80), control1: pt(104, 104), control2: pt(105, 92))
        p.addCurve(to: pt(92, 42), control1: pt(102, 60), control2: pt(98, 46))
        p.addCurve(to: pt(65, 34), control1: pt(84, 38), control2: pt(76, 34))
        p.addLine(to: pt(65, 28))
        p.closeSubpath()
        return p
    }

    private static func mirrored(_ m: Muscle, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, rotation: CGFloat = 0) -> [MuscleShape] {
        [MuscleShape(muscle: m, kind: .ellipse(cx: cx, cy: cy, rx: rx, ry: ry, rotation: rotation)),
         MuscleShape(muscle: m, kind: .ellipse(cx: 120 - cx, cy: cy, rx: rx, ry: ry, rotation: -rotation))]
    }

    static func shapes(_ side: MuscleBodySide) -> [MuscleShape] {
        switch side {
        case .front:
            return mirrored(.chest, cx: 49.5, cy: 58, rx: 10, ry: 8)
                + mirrored(.shoulders, cx: 29, cy: 50, rx: 6, ry: 6)
                + mirrored(.biceps, cx: 22.5, cy: 72, rx: 4.5, ry: 10)
                + mirrored(.forearms, cx: 21.5, cy: 98, rx: 3.8, ry: 11)
                + [MuscleShape(muscle: .core, kind: .roundedRect(x: 50, y: 70, width: 20, height: 36, radius: 7))]
                + mirrored(.quads, cx: 46, cy: 143, rx: 8, ry: 24)
        case .back:
            let upperBack = [CGPoint(x: 60, y: 40), CGPoint(x: 47, y: 50), CGPoint(x: 53, y: 68), CGPoint(x: 60, y: 72),
                             CGPoint(x: 67, y: 68), CGPoint(x: 73, y: 50)]
            return [MuscleShape(muscle: .upperBack, kind: .polygon(upperBack))]
                + mirrored(.shoulders, cx: 29, cy: 50, rx: 6, ry: 6)
                + mirrored(.triceps, cx: 22.5, cy: 72, rx: 4.5, ry: 10)
                + mirrored(.forearms, cx: 21.5, cy: 98, rx: 3.8, ry: 11)
                + mirrored(.lats, cx: 42.5, cy: 80, rx: 6, ry: 13, rotation: -8)
                + [MuscleShape(muscle: .lowerBack, kind: .roundedRect(x: 51, y: 92, width: 18, height: 16, radius: 6))]
                + mirrored(.glutes, cx: 49, cy: 118, rx: 10, ry: 9.5)
                + mirrored(.hamstrings, cx: 45.5, cy: 153, rx: 7.5, ry: 21)
                + mirrored(.calves, cx: 45, cy: 196, rx: 5, ry: 15)
        }
    }

    /// The 13 muscles the map draws (mockup vocabulary), in list order.
    static let mapMuscles: [Muscle] = [.chest, .shoulders, .triceps, .biceps, .forearms, .upperBack, .lats, .lowerBack,
                                       .core, .glutes, .quads, .hamstrings, .calves]

    /// Finer vocabulary muscles that tint a drawn shape (the mockup collapses them): front delts →
    /// Shoulders, abs / deep core → Core, traps → Upper back. Hip flexors have no shape (list only).
    static func mapShape(for muscle: Muscle) -> Muscle? {
        switch muscle {
        case .frontDelts: .shoulders
        case .abs, .deepCore: .core
        case .traps: .upperBack
        case .hipFlexors: nil
        default: muscle
        }
    }
}

/// One side of the silhouette, filled per muscle. `fills` misses → the shape is drawn as an
/// outline only (no data).
struct MuscleBodyView: View {
    let side: MuscleBodySide
    let fills: [Muscle: Color]
    var showsLabel = true
    @Environment(\.jiTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Canvas { ctx, size in
                let s = min(size.width / MuscleBodyGeometry.size.width, size.height / MuscleBodyGeometry.size.height)
                let dx = (size.width - MuscleBodyGeometry.size.width * s) / 2
                let dy = (size.height - MuscleBodyGeometry.size.height * s) / 2
                let t = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: s, y: s)
                let line = theme.color(.muted).opacity(0.7)
                let none = theme.color(.muted).opacity(0.14)
                for shape in MuscleBodyGeometry.shapes(side) {
                    let p = Path(shape.path).applying(t)
                    ctx.fill(p, with: .color(fills[shape.muscle] ?? none))
                }
                let head = Path(ellipseIn: CGRect(x: MuscleBodyGeometry.headCenter.x - MuscleBodyGeometry.headRadius,
                                                  y: MuscleBodyGeometry.headCenter.y - MuscleBodyGeometry.headRadius,
                                                  width: MuscleBodyGeometry.headRadius * 2, height: MuscleBodyGeometry.headRadius * 2))
                ctx.stroke(head.applying(t), with: .color(line), lineWidth: 1.2)
                ctx.stroke(Path(MuscleBodyGeometry.outline).applying(t), with: .color(line),
                           style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
            .aspectRatio(MuscleBodyGeometry.size.width / MuscleBodyGeometry.size.height, contentMode: .fit)
            if showsLabel {
                Text(side.label).font(.system(size: 9, weight: .semibold)).tracking(0.4)
                    .foregroundStyle(theme.color(.muted))
            }
        }
        .accessibilityHidden(true)
    }
}
