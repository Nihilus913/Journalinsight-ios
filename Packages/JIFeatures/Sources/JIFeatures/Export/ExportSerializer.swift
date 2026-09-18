import Foundation
import JIPersistence

// W5b-L5 (P-export). Port of `mobile/src/export/serialize.ts` — pure, dependency-free CSV/JSON
// serialization of the five on-device data types, with RFC-4180 escaping. Every type is an
// explicit opt-in (`ExportSelection`, all false by default): export output is plaintext by
// definition (it leaves the vault's encrypted-at-rest boundary the moment it is written to a
// shared file), so nothing is serialized unless the user ticked it.
//
// Each type keeps its OWN column set rather than being forced into one shared schema — a
// check-in's stress/energy scores and an event's severity/prodrome have nothing in common with a
// journal entry's mood/tags.
//
// `nonisolated`: pure functions, callable off the main actor (JIFeatures defaults to MainActor).

// MARK: - CSV

/// RFC-4180 field escaping: wrap in double-quotes (and double any internal double-quote) whenever
/// the field contains a comma, a quote, or a newline.
nonisolated func escapeCSVField(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}

private nonisolated func csv(header: String, rows: [[String]]) -> String {
    ([header] + rows.map { $0.map(escapeCSVField).joined(separator: ",") }).joined(separator: "\n")
}

/// RN serializes numbers with `String(n)`: an integer-valued JS number has no decimal point, so
/// `progress: 0.4` stays `0.4` while `severity: 3` stays `3`. Swift's `String(Double)` would emit
/// `3.0`, which would break the ported byte-exact rows.
nonisolated func exportNumberText(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(format: "%g", value)
}

nonisolated let journalCSVHeader = "date,ts,mood,durationSec,tags,text"

public nonisolated func entriesToCSV(_ entries: [Entry]) -> String {
    csv(header: journalCSVHeader, rows: entries.map { e in
        [e.date, e.ts, e.mood ?? "", String(e.durationSec), e.tags.joined(separator: "; "), e.text]
    })
}

nonisolated let checkinCSVHeader = "date,mood,stress,energy,dosed,irritability,restlessness,appetite,note,updatedAt"

public nonisolated func checkinsToCSV(_ checkins: [CheckIn]) -> String {
    csv(header: checkinCSVHeader, rows: checkins.map { c in
        [
            c.date,
            c.mood?.rawValue ?? "",
            String(c.stress),
            String(c.energy),
            c.dosed ? "true" : "false",
            c.irritability.map(String.init) ?? "",
            c.restlessness.map(String.init) ?? "",
            c.appetite.map(String.init) ?? "",
            c.note ?? "",
            c.updatedAt,
        ]
    })
}

nonisolated let eventCSVHeader = "id,date,timeLocal,type,severity,prodrome,triggers,note,createdAt"

public nonisolated func eventsToCSV(_ events: [MindEvent]) -> String {
    csv(header: eventCSVHeader, rows: events.map { e in
        [
            String(e.id), e.date, e.timeLocal, e.type.rawValue, String(e.severity),
            e.prodrome.joined(separator: "; "), e.triggers, e.note ?? "", e.createdAt,
        ]
    })
}

nonisolated let who5CSVHeader = "id,date,i1,i2,i3,i4,i5,raw,pct,createdAt"

public nonisolated func who5ToCSV(_ entries: [Who5Entry]) -> String {
    csv(header: who5CSVHeader, rows: entries.map { w in
        [String(w.id), w.date] + w.items.map(String.init) + [String(w.raw), String(w.pct), w.createdAt]
    })
}

nonisolated let goalCSVHeader = "id,title,targetDate,progress,createdAt"

public nonisolated func goalsToCSV(_ goals: [Goal]) -> String {
    csv(header: goalCSVHeader, rows: goals.map { g in
        [String(g.id), g.title, g.targetDate ?? "", exportNumberText(g.progress), g.createdAt]
    })
}

// MARK: - JSON payloads
//
// The store types are not `Codable` (they are database row shapes, owned by JIPersistence and
// frozen this wave), so each gets a small encodable mirror whose keys and ORDER are the oracle's
// object literal verbatim. Optionals are encoded explicitly rather than with the synthesized
// `encodeIfPresent`, so a null field shows up as `null` — exactly as `JSON.stringify` writes it —
// instead of vanishing from the file.

nonisolated struct EntryPayload: Encodable {
    let id: Int64, date: String, ts: String, text: String, durationSec: Int, mood: String?, tags: [String]
    enum CodingKeys: String, CodingKey { case id, date, ts, text, durationSec, mood, tags }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(date, forKey: .date); try c.encode(ts, forKey: .ts)
        try c.encode(text, forKey: .text); try c.encode(durationSec, forKey: .durationSec)
        try c.encode(mood, forKey: .mood); try c.encode(tags, forKey: .tags)
    }
    init(_ e: Entry) {
        id = e.id; date = e.date; ts = e.ts; text = e.text
        durationSec = e.durationSec; mood = e.mood; tags = e.tags
    }
}

nonisolated struct CheckInPayload: Encodable {
    let date: String, mood: String?, stress: Int, energy: Int, dosed: Bool
    let irritability: Int?, restlessness: Int?, appetite: Int?, note: String?, updatedAt: String
    enum CodingKeys: String, CodingKey {
        case date, mood, stress, energy, dosed, irritability, restlessness, appetite, note, updatedAt
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date); try c.encode(mood, forKey: .mood)
        try c.encode(stress, forKey: .stress); try c.encode(energy, forKey: .energy)
        try c.encode(dosed, forKey: .dosed); try c.encode(irritability, forKey: .irritability)
        try c.encode(restlessness, forKey: .restlessness); try c.encode(appetite, forKey: .appetite)
        try c.encode(note, forKey: .note); try c.encode(updatedAt, forKey: .updatedAt)
    }
    init(_ c: CheckIn) {
        date = c.date; mood = c.mood?.rawValue; stress = c.stress; energy = c.energy; dosed = c.dosed
        irritability = c.irritability; restlessness = c.restlessness; appetite = c.appetite
        note = c.note; updatedAt = c.updatedAt
    }
}

nonisolated struct MindEventPayload: Encodable {
    let id: Int64, date: String, timeLocal: String, type: String, severity: Int
    let prodrome: [String], triggers: String, note: String?, createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, date, timeLocal, type, severity, prodrome, triggers, note, createdAt
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(date, forKey: .date)
        try c.encode(timeLocal, forKey: .timeLocal); try c.encode(type, forKey: .type)
        try c.encode(severity, forKey: .severity); try c.encode(prodrome, forKey: .prodrome)
        try c.encode(triggers, forKey: .triggers); try c.encode(note, forKey: .note)
        try c.encode(createdAt, forKey: .createdAt)
    }
    init(_ e: MindEvent) {
        id = e.id; date = e.date; timeLocal = e.timeLocal; type = e.type.rawValue; severity = e.severity
        prodrome = e.prodrome; triggers = e.triggers; note = e.note; createdAt = e.createdAt
    }
}

nonisolated struct Who5Payload: Encodable {
    let id: Int64, date: String, items: [Int], raw: Int, pct: Int, createdAt: String
    init(_ w: Who5Entry) {
        id = w.id; date = w.date; items = w.items; raw = w.raw; pct = w.pct; createdAt = w.createdAt
    }
}

nonisolated struct GoalPayload: Encodable {
    let id: Int64, title: String, targetDate: String?, progress: Double, createdAt: String
    enum CodingKeys: String, CodingKey { case id, title, targetDate, progress, createdAt }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
        try c.encode(targetDate, forKey: .targetDate); try c.encode(progress, forKey: .progress)
        try c.encode(createdAt, forKey: .createdAt)
    }
    init(_ g: Goal) {
        id = g.id; title = g.title; targetDate = g.targetDate; progress = g.progress; createdAt = g.createdAt
    }
}

/// `JSON.stringify(value, null, 2)`: 2-space indent, declaration-order keys (NOT `.sortedKeys` —
/// that would reorder the file's keys away from the oracle's), and `/` left unescaped.
nonisolated let exportJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    return encoder
}()

private nonisolated func jsonText(_ value: some Encodable) -> String {
    guard let data = try? exportJSONEncoder.encode(value), let text = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return text
}

public nonisolated func entriesToJSON(_ entries: [Entry]) -> String {
    entries.isEmpty ? "[]" : jsonText(entries.map(EntryPayload.init))
}

public nonisolated func checkinsToJSON(_ checkins: [CheckIn]) -> String {
    checkins.isEmpty ? "[]" : jsonText(checkins.map(CheckInPayload.init))
}

public nonisolated func eventsToJSON(_ events: [MindEvent]) -> String {
    events.isEmpty ? "[]" : jsonText(events.map(MindEventPayload.init))
}

public nonisolated func who5ToJSON(_ entries: [Who5Entry]) -> String {
    entries.isEmpty ? "[]" : jsonText(entries.map(Who5Payload.init))
}

public nonisolated func goalsToJSON(_ goals: [Goal]) -> String {
    goals.isEmpty ? "[]" : jsonText(goals.map(GoalPayload.init))
}

// MARK: - Selection + bundles

/// Which export types the per-type selection screen lets the user opt into — all false by default
/// (nothing exports unless explicitly ticked). The case order is `TYPE_ROWS`' order, which is also
/// the screen's row order.
public nonisolated enum ExportType: String, Sendable, CaseIterable, Codable {
    case journal, checkins, events, who5, goals

    /// RN `TYPE_ROWS` label + caption, verbatim.
    public var label: String {
        switch self {
        case .journal: "Journal entries"
        case .checkins: "Mind check-ins"
        case .events: "Mind events"
        case .who5: "WHO-5"
        case .goals: "Goals"
        }
    }

    public var caption: String {
        switch self {
        case .journal: "Free-text entries, mood, tags."
        case .checkins: "Daily mood/stress/energy check-ins."
        case .events: "Logged migraine/reflux/other events."
        case .who5: "Weekly well-being index scores."
        case .goals: "Ad-hoc goal list and progress."
        }
    }

    /// The `# <label>` section heading in a combined CSV bundle (RN `SECTION_LABEL`).
    var sectionLabel: String { label }
}

/// RN `ExportSelection` (`Record<ExportType, boolean>`) — a set is the Swift shape of the same
/// thing, and `noExportSelected()` is the empty one.
public nonisolated struct ExportSelection: Sendable, Equatable {
    private var selected: Set<ExportType>

    public init(_ selected: Set<ExportType> = []) { self.selected = selected }

    public func contains(_ type: ExportType) -> Bool { selected.contains(type) }
    public var isEmpty: Bool { selected.isEmpty }

    public mutating func toggle(_ type: ExportType) {
        if selected.contains(type) { selected.remove(type) } else { selected.insert(type) }
    }
}

/// RN `noExportSelected()` — every type starts unticked.
public nonisolated func noExportSelected() -> ExportSelection { ExportSelection() }

/// RN `ExportData` — only the keys for ticked types need to actually hold data.
public nonisolated struct ExportData: Sendable {
    public var entries: [Entry]?
    public var checkins: [CheckIn]?
    public var events: [MindEvent]?
    public var who5: [Who5Entry]?
    public var goals: [Goal]?

    public init(
        entries: [Entry]? = nil, checkins: [CheckIn]? = nil, events: [MindEvent]? = nil,
        who5: [Who5Entry]? = nil, goals: [Goal]? = nil
    ) {
        self.entries = entries; self.checkins = checkins; self.events = events
        self.who5 = who5; self.goals = goals
    }
}

/// Multi-type CSV bundle: one `# <label>` line + that type's own header/row block per selected
/// type, blank-line separated — so each type keeps its own column set while still landing in one
/// shareable file. An unticked type contributes nothing.
public nonisolated func combinedCSV(_ selection: ExportSelection, _ data: ExportData) -> String {
    var sections: [String] = []
    for type in ExportType.allCases where selection.contains(type) {
        let body: String = switch type {
        case .journal: entriesToCSV(data.entries ?? [])
        case .checkins: checkinsToCSV(data.checkins ?? [])
        case .events: eventsToCSV(data.events ?? [])
        case .who5: who5ToCSV(data.who5 ?? [])
        case .goals: goalsToCSV(data.goals ?? [])
        }
        sections.append("# \(type.sectionLabel)\n\(body)")
    }
    return sections.joined(separator: "\n\n")
}

/// Multi-type JSON bundle: one key per selected type — an unticked type's key is omitted entirely,
/// not an empty array, so the file itself shows what wasn't exported. Assembled textually (rather
/// than through one `Encodable` struct) so the key ORDER stays `ExportType.allCases`' order, the
/// oracle's insertion order.
public nonisolated func combinedJSON(_ selection: ExportSelection, _ data: ExportData) -> String {
    var members: [String] = []
    for type in ExportType.allCases where selection.contains(type) {
        let body: String = switch type {
        case .journal: entriesToJSON(data.entries ?? [])
        case .checkins: checkinsToJSON(data.checkins ?? [])
        case .events: eventsToJSON(data.events ?? [])
        case .who5: who5ToJSON(data.who5 ?? [])
        case .goals: goalsToJSON(data.goals ?? [])
        }
        // Re-indent the nested array by two spaces, the way `JSON.stringify`'s 2-space indent
        // nests an array inside its parent object.
        let indented = body.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : "  " + $0.element }
            .joined(separator: "\n")
        members.append("  \"\(type.rawValue)\" : \(indented)")
    }
    return members.isEmpty ? "{}" : "{\n" + members.joined(separator: ",\n") + "\n}"
}
