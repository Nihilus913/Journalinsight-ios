import SwiftUI
import Testing
@testable import JIDesign

private func points(_ n: Int) -> [TrendPoint] {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    return (0..<n).map { TrendPoint(date: t0.addingTimeInterval(Double($0) * 60), value: Double($0)) }
}

@Test func rangeDaysMatchTheHealthPicker() {
    #expect(TrendRange.allCases.map(\.rawValue) == ["D", "W", "M", "6M", "Y"])
    #expect(TrendRange.allCases.map(\.days) == [1, 7, 30, 182, 365])
}

@Test func downsampleLeavesSmallSeriesAlone() {
    let p = points(400)
    #expect(downsample(p) == p)
}

@Test func downsampleCapsAtMaxPointsWithBucketMeans() {
    let out = downsample(points(1000), maxCount: 400)
    #expect(out.count <= 400)
    // bucket = ceil(1000/400) = 3 → first bucket is values 0,1,2 → mean 1
    #expect(out.first?.value == 1)
    #expect(out.first?.date == points(1).first?.date)
}

@Test func trendAverageIsNilForEmpty() {
    #expect(trendAverage([]) == nil)
    #expect(trendAverage(points(3)) == 1)
}

@Test @MainActor func trendChartRenders() {
    expectRenders("TrendChart", width: 360, height: 300) {
        TrendChart(points: points(60), tint: .blue, unit: "ms", range: .constant(.week), showAll: {})
    }
    expectRenders("TrendChart empty", width: 360, height: 300) {
        TrendChart(points: [], tint: .blue, unit: nil, range: .constant(.day), showAll: nil)
    }
}
