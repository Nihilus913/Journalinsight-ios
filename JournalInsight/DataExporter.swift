//
//  DataExporter.swift
//  JournalInsight
//

import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, json
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// Plain-text record for export. Caller is responsible for decrypting
/// `JournalEntry` ciphertext into this shape via `EntryRepository`.
struct ExportRecord {
    let date: Date
    let text: String
    let durationSeconds: Int
    let mood: String?
    let tags: [String]
}

enum DataExporter {
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Characters whose presence at the start of a CSV cell can cause spreadsheet
    /// applications to interpret the value as a formula. Audit S-9.
    private static let dangerousFirstChars: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    static func sanitize(_ s: String) -> String {
        guard let first = s.first, dangerousFirstChars.contains(first) else { return s }
        return "'" + s
    }

    /// Backwards-compatibility shim used by audit tests that pass plain entries.
    /// Builds an ExportRecord assuming `entry.text` (legacy plaintext) is set.
    static func exportCSV(entries: [JournalEntry]) -> String {
        let records = entries.map {
            ExportRecord(
                date: $0.date,
                text: $0.text ?? "",
                durationSeconds: Int($0.duration),
                mood: $0.moodRaw.flatMap(Mood.init(rawValue:))?.label,
                tags: $0.tags.map(\.name)
            )
        }
        return exportCSV(records: records)
    }

    static func exportCSV(records: [ExportRecord]) -> String {
        var lines = ["date,text,duration_seconds,mood,tags"]
        for r in records {
            let date = dateFormatter.string(from: r.date)
            let text = sanitize(r.text).replacingOccurrences(of: "\"", with: "\"\"")
            let mood = sanitize(r.mood ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let tags = sanitize(r.tags.joined(separator: "; ")).replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(date)\",\"\(text)\",\(r.durationSeconds),\"\(mood)\",\"\(tags)\"")
        }
        return lines.joined(separator: "\n")
    }

    static func exportJSON(records: [ExportRecord]) -> Data? {
        let items: [[String: Any]] = records.map { r in
            var dict: [String: Any] = [
                "date": dateFormatter.string(from: r.date),
                "text": r.text,
                "duration_seconds": r.durationSeconds
            ]
            if let mood = r.mood { dict["mood"] = mood }
            if !r.tags.isEmpty { dict["tags"] = r.tags }
            return dict
        }
        return try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    /// Backwards-compat shim
    static func exportJSON(entries: [JournalEntry]) -> Data? {
        let records = entries.map {
            ExportRecord(
                date: $0.date,
                text: $0.text ?? "",
                durationSeconds: Int($0.duration),
                mood: $0.moodRaw,
                tags: $0.tags.map(\.name)
            )
        }
        return exportJSON(records: records)
    }

    static func writeToTemporaryFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            return url
        } catch {
            return nil
        }
    }

    static func writeToTemporaryFile(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
            return url
        } catch {
            return nil
        }
    }
}
