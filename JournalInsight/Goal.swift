//
//  Goal.swift
//  JournalInsight
//
//  Created by Claude on 24.03.2026.
//

import Foundation
import SwiftData

@Model
class Goal {
    var title: String
    var targetDate: Date
    var progress: Double // 0.0 to 1.0

    init(title: String, targetDate: Date, progress: Double = 0.0) {
        self.title = title
        self.targetDate = targetDate
        self.progress = min(max(progress, 0.0), 1.0)
    }
}
