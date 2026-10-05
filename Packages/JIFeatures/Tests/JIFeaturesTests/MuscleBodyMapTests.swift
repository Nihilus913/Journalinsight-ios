import CoreGraphics
import Foundation
import Testing
import JICompute
@testable import JIFeatures

/// B-90 p5 snapshot geometry (Toby 2026-10-04 rendering rule): every muscle shape sits inside the
/// body outline — no deltoid / arm shape on or across the contour — and front and back share one
/// silhouette. Grid points of each shape (0.25 pt step) must all be inside the outline path.
@Suite struct MuscleBodyMapTests {
    private func insidePoints(_ shape: CGPath, step: CGFloat = 0.25) -> [CGPoint] {
        let b = shape.boundingBoxOfPath
        var out: [CGPoint] = []
        var y = b.minY
        while y <= b.maxY {
            var x = b.minX
            while x <= b.maxX {
                let p = CGPoint(x: x, y: y)
                if shape.contains(p) { out.append(p) }
                x += step
            }
            y += step
        }
        return out
    }

    @Test(arguments: MuscleBodySide.allCases)
    func everyShapeIsInsideTheOutline(_ side: MuscleBodySide) {
        let outline = MuscleBodyGeometry.outline
        for shape in MuscleBodyGeometry.shapes(side) {
            let pts = insidePoints(shape.path)
            #expect(!pts.isEmpty, "\(shape.muscle) has no area")
            let outside = pts.filter { !outline.contains($0) }
            #expect(outside.isEmpty, "\(side) \(shape.muscle): \(outside.count) points outside, first \(String(describing: outside.first))")
        }
    }

    @Test func shapeBoundsStayInsideTheViewBoxAndOutlineBounds() {
        let ob = MuscleBodyGeometry.outline.boundingBoxOfPath
        for side in MuscleBodySide.allCases {
            for shape in MuscleBodyGeometry.shapes(side) {
                let b = shape.path.boundingBoxOfPath
                #expect(ob.contains(b), "\(side) \(shape.muscle) bounds \(b) leave the outline bounds \(ob)")
            }
        }
    }

    @Test func thirteenMusclesDrawnFrontAndBackTogether() {
        let drawn = Set(MuscleBodySide.allCases.flatMap { MuscleBodyGeometry.shapes($0).map(\.muscle) })
        #expect(drawn == Set(MuscleBodyGeometry.mapMuscles))
        #expect(MuscleBodyGeometry.mapMuscles.count == 13)
        // Finer vocabulary muscles tint a drawn shape (or none, hip flexors).
        for m in Muscle.allCases {
            if let shape = MuscleBodyGeometry.mapShape(for: m) { #expect(drawn.contains(shape)) }
        }
    }
}
