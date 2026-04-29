//
//  DataExporter.swift
//  JournalInsight
//
//  Created by Claude on 24.03.2026.
//

import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, json
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

enum DataExporter {
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func exportCSV(entries: [JournalEntry]) -> String {
        var lines = ["date,text,duration_seconds,mood,tags"]
        for entry in entries {
            let date = dateFormatter.string(from: entry.date)
            let text = (entry.text ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let mood = entry.mood?.label ?? ""
            let tags = entry.tags.map(\.name).joined(separator: "; ")
            lines.append("\"\(date)\",\"\(text)\",\(Int(entry.duration)),\"\(mood)\",\"\(tags)\"")
        }
        return lines.joined(separator: "\n")
    }

    static func exportJSON(entries: [JournalEntry]) -> Data? {
        let items: [[String: Any]] = entries.map { entry in
            var dict: [String: Any] = [
                "date": dateFormatter.string(from: entry.date),
                "text": entry.text ?? "",
                "duration_seconds": Int(entry.duration)
            ]
            if let mood = entry.mood {
                dict["mood"] = mood.rawValue
            }
            if !entry.tags.isEmpty {
                dict["tags"] = entry.tags.map(\.name)
            }
            return dict
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    static func writeToTemporaryFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func writeToTemporaryFile(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
