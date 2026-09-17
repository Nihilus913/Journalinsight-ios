import Foundation
import GRDB
import JIVault

/// Mood scale shared by the daily check-in and (later, L1) journal entries — oracle
/// `mobile/src/journal/mood.ts`. Lives here (not JICore) because `CheckInStore` is this file's
/// only producer/consumer of it this wave; L1's own `MoodPicker.swift` is a distinct file this
/// lane never touches (W4 card: lanes are file-disjoint, L1/L2 run in parallel off the same wave
/// branch) — if L1 lands its own `Mood` type, reconciling the two is an integration-time concern,
/// not this lane's.
public enum Mood: String, Codable, Sendable, CaseIterable {
    case great, good, okay, bad, terrible

    public var emoji: String {
        switch self {
        case .great: "😄"
        case .good: "🙂"
        case .okay: "😐"
        case .bad: "😞"
        case .terrible: "😢"
        }
    }

    /// -1...1, oracle `moodValence`.
    public var valence: Double {
        switch self {
        case .great: 1
        case .good: 0.5
        case .okay: 0
        case .bad: -0.5
        case .terrible: -1
        }
    }
}

/// Integer 1-5 (inclusive) — oracle `isValidScore` (`mobile/src/mind/checkins.ts`).
public nonisolated func isValidScore(_ n: Int) -> Bool { n >= 1 && n <= 5 }

/// One day's mental-health check-in — oracle `CheckIn` (`mobile/src/mind/checkins.ts`).
public struct CheckIn: Sendable, Equatable {
    public var date: String
    public var mood: Mood?
    public var stress: Int
    public var energy: Int
    public var dosed: Bool
    public var irritability: Int?
    public var restlessness: Int?
    public var appetite: Int?
    public var note: String?
    public var updatedAt: String

    public init(
        date: String, mood: Mood?, stress: Int, energy: Int, dosed: Bool,
        irritability: Int?, restlessness: Int?, appetite: Int?, note: String?, updatedAt: String
    ) {
        self.date = date; self.mood = mood; self.stress = stress; self.energy = energy; self.dosed = dosed
        self.irritability = irritability; self.restlessness = restlessness; self.appetite = appetite
        self.note = note; self.updatedAt = updatedAt
    }
}

/// Oracle `NewCheckIn` (`CheckIn` minus `updatedAt`).
public struct NewCheckIn: Sendable, Equatable {
    public var date: String
    public var mood: Mood?
    public var stress: Int
    public var energy: Int
    public var dosed: Bool
    public var irritability: Int?
    public var restlessness: Int?
    public var appetite: Int?
    public var note: String?

    public init(
        date: String, mood: Mood?, stress: Int, energy: Int, dosed: Bool,
        irritability: Int?, restlessness: Int?, appetite: Int?, note: String?
    ) {
        self.date = date; self.mood = mood; self.stress = stress; self.energy = energy; self.dosed = dosed
        self.irritability = irritability; self.restlessness = restlessness; self.appetite = appetite
        self.note = note
    }
}

/// CRUD over `mind_checkin` (one row per calendar day) — oracle `CheckInStore`
/// (`mobile/src/mind/checkins.ts`). `cipher` seals every column but `date`/timestamps/`synced` at
/// the write/read boundary (E13-7 extended scope, matches `Migrations.swift`'s `v3_capture`
/// comment) — mood/note plus the numeric axes, since a low-cardinality categorical field like
/// `dosed` is still an ADHD-medication signal. Defaults to `IdentityCipher`, mirroring RN's
/// `NOOP_CIPHER` default.
public struct CheckInStore: Sendable {
    private let db: AppDatabase
    private let cipher: any FieldCipher

    public init(db: AppDatabase, cipher: any FieldCipher = IdentityCipher()) {
        self.db = db
        self.cipher = cipher
    }

    /// Insert today's check-in, or update it in place if one already exists for that date.
    public func upsertToday(_ n: NewCheckIn, now: Date = Date()) throws {
        let nowISO = now.ISO8601Format()
        let mood = try n.mood.map { try cipher.seal($0.rawValue) }
        let note = try n.note.map { try cipher.seal($0) }
        let stress = try cipher.seal(String(n.stress))
        let energy = try cipher.seal(String(n.energy))
        let dosed = try cipher.seal(n.dosed ? "1" : "0")
        let irritability = try n.irritability.map { try cipher.seal(String($0)) }
        let restlessness = try n.restlessness.map { try cipher.seal(String($0)) }
        let appetite = try n.appetite.map { try cipher.seal(String($0)) }
        try db.pool.write { conn in
            try conn.execute(
                sql: """
                INSERT INTO mind_checkin (date, mood, stress, energy, dosed, irritability, restlessness, appetite, note, created_at, updated_at, synced)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                ON CONFLICT(date) DO UPDATE SET
                  mood = excluded.mood,
                  stress = excluded.stress,
                  energy = excluded.energy,
                  dosed = excluded.dosed,
                  irritability = excluded.irritability,
                  restlessness = excluded.restlessness,
                  appetite = excluded.appetite,
                  note = excluded.note,
                  updated_at = excluded.updated_at
                """,
                arguments: [n.date, mood, stress, energy, dosed, irritability, restlessness, appetite, note, nowISO, nowISO]
            )
        }
    }

    public func getByDate(_ date: String) throws -> CheckIn? {
        try db.pool.read { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT date, mood, stress, energy, dosed, irritability, restlessness, appetite, note, updated_at FROM mind_checkin WHERE date = ?",
                arguments: [date]
            ) else { return nil }
            return try rowToCheckIn(row)
        }
    }

    /// Most recent `days` check-ins, newest first.
    public func recent(_ days: Int) throws -> [CheckIn] {
        try db.pool.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT date, mood, stress, energy, dosed, irritability, restlessness, appetite, note, updated_at FROM mind_checkin ORDER BY date DESC LIMIT ?",
                arguments: [days]
            ).map { try rowToCheckIn($0) }
        }
    }

    /// Every check-in ever recorded, newest first — full-history export (E13-5).
    public func listAll() throws -> [CheckIn] {
        try db.pool.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT date, mood, stress, energy, dosed, irritability, restlessness, appetite, note, updated_at FROM mind_checkin ORDER BY date DESC"
            ).map { try rowToCheckIn($0) }
        }
    }

    private func rowToCheckIn(_ row: Row) throws -> CheckIn {
        let moodRaw: String? = row["mood"]
        let mood = try moodRaw.map { try cipher.open($0) }.flatMap { Mood(rawValue: $0) }
        let noteRaw: String? = row["note"]
        let irritabilityRaw: String? = row["irritability"]
        let restlessnessRaw: String? = row["restlessness"]
        let appetiteRaw: String? = row["appetite"]
        return CheckIn(
            date: row["date"],
            mood: mood,
            stress: Int(try cipher.open(row["stress"] as String)) ?? 0,
            energy: Int(try cipher.open(row["energy"] as String)) ?? 0,
            dosed: (try cipher.open(row["dosed"] as String)) == "1",
            irritability: try irritabilityRaw.map { try cipher.open($0) }.flatMap { Int($0) },
            restlessness: try restlessnessRaw.map { try cipher.open($0) }.flatMap { Int($0) },
            appetite: try appetiteRaw.map { try cipher.open($0) }.flatMap { Int($0) },
            note: try noteRaw.map { try cipher.open($0) },
            updatedAt: row["updated_at"]
        )
    }
}

/// Oracle `MindEventType` (`mobile/src/mind/events.ts`).
public enum MindEventType: String, Codable, Sendable, CaseIterable {
    case migraine, vomiting, reflux, neck_pain, other
}

public nonisolated func eventTypeLabel(_ t: MindEventType) -> String {
    switch t {
    case .migraine: "Migraine"
    case .vomiting: "Vomiting"
    case .reflux: "Reflux"
    case .neck_pain: "Neck pain"
    case .other: "Other"
    }
}

/// Oracle `PRODROME_OPTIONS`.
public nonisolated let PRODROME_OPTIONS: [String] = ["neck pull", "yawning", "mood shift", "food cravings"]

public nonisolated func isValidSeverity(_ n: Int) -> Bool { n >= 1 && n <= 5 }

/// Oracle `MindEvent` (`mobile/src/mind/events.ts`).
public struct MindEvent: Sendable, Equatable {
    public var id: Int64
    public var date: String
    public var timeLocal: String
    public var type: MindEventType
    public var severity: Int
    public var prodrome: [String]
    public var triggers: String
    public var note: String?
    public var createdAt: String

    public init(
        id: Int64, date: String, timeLocal: String, type: MindEventType, severity: Int,
        prodrome: [String], triggers: String, note: String?, createdAt: String
    ) {
        self.id = id; self.date = date; self.timeLocal = timeLocal; self.type = type; self.severity = severity
        self.prodrome = prodrome; self.triggers = triggers; self.note = note; self.createdAt = createdAt
    }
}

public struct NewMindEvent: Sendable, Equatable {
    public var date: String
    public var timeLocal: String
    public var type: MindEventType
    public var severity: Int
    public var prodrome: [String]
    public var triggers: String
    public var note: String?

    public init(
        date: String, timeLocal: String, type: MindEventType, severity: Int,
        prodrome: [String], triggers: String, note: String?
    ) {
        self.date = date; self.timeLocal = timeLocal; self.type = type; self.severity = severity
        self.prodrome = prodrome; self.triggers = triggers; self.note = note
    }
}

/// CRUD over `mind_event` — oracle `EventStore` (`mobile/src/mind/events.ts`). `cipher` seals
/// `type`/`severity`/`prodrome`/`triggers`/`note` (spec §5.4 encrypt-from-day-one plus E13-7's
/// triggers/note — matches `Migrations.swift`'s `v3_capture` comment: every column but
/// `id`/`date`/`time_local`/`created_at`/`synced`).
public struct EventStore: Sendable {
    private let db: AppDatabase
    private let cipher: any FieldCipher

    public init(db: AppDatabase, cipher: any FieldCipher = IdentityCipher()) {
        self.db = db
        self.cipher = cipher
    }

    @discardableResult
    public func addEvent(_ n: NewMindEvent, now: Date = Date()) throws -> Int64 {
        let nowISO = now.ISO8601Format()
        let type = try cipher.seal(n.type.rawValue)
        let severity = try cipher.seal(String(n.severity))
        let prodromeJSON = try cipher.seal(Self.encodeProdrome(n.prodrome))
        let triggers = try cipher.seal(n.triggers)
        let note = try n.note.map { try cipher.seal($0) }
        return try db.pool.write { conn in
            try conn.execute(
                sql: """
                INSERT INTO mind_event (date, time_local, type, severity, prodrome, triggers, note, created_at, synced)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
                """,
                arguments: [n.date, n.timeLocal, type, severity, prodromeJSON, triggers, note, nowISO]
            )
            return conn.lastInsertedRowID
        }
    }

    public func recent(_ limit: Int) throws -> [MindEvent] {
        try db.pool.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT id, date, time_local, type, severity, prodrome, triggers, note, created_at FROM mind_event ORDER BY date DESC, time_local DESC, id DESC LIMIT ?",
                arguments: [limit]
            ).map { try rowToEvent($0) }
        }
    }

    /// Every event ever recorded, newest first — full-history export (E13-5).
    public func listAll() throws -> [MindEvent] {
        try db.pool.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT id, date, time_local, type, severity, prodrome, triggers, note, created_at FROM mind_event ORDER BY date DESC, time_local DESC, id DESC"
            ).map { try rowToEvent($0) }
        }
    }

    public func deleteEvent(_ id: Int64) throws {
        try db.pool.write { conn in
            try conn.execute(sql: "DELETE FROM mind_event WHERE id = ?", arguments: [id])
        }
    }

    private func rowToEvent(_ row: Row) throws -> MindEvent {
        let noteRaw: String? = row["note"]
        let typeRaw = try cipher.open(row["type"] as String)
        let prodromeRaw = try cipher.open(row["prodrome"] as String)
        return MindEvent(
            id: row["id"],
            date: row["date"],
            timeLocal: row["time_local"],
            type: MindEventType(rawValue: typeRaw) ?? .other,
            severity: Int(try cipher.open(row["severity"] as String)) ?? 0,
            prodrome: Self.decodeProdrome(prodromeRaw),
            triggers: try cipher.open(row["triggers"] as String),
            note: try noteRaw.map { try cipher.open($0) },
            createdAt: row["created_at"]
        )
    }

    private static func encodeProdrome(_ items: [String]) -> String {
        (try? String(data: JSONEncoder().encode(items), encoding: .utf8)) ?? "[]"
    }

    private static func decodeProdrome(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
}

/// Oracle `Who5Entry` (`mobile/src/mind/who5.ts`).
public struct Who5Entry: Sendable, Equatable {
    public var id: Int64
    public var date: String
    public var items: [Int]
    public var raw: Int
    public var pct: Int
    public var createdAt: String

    public init(id: Int64, date: String, items: [Int], raw: Int, pct: Int, createdAt: String) {
        self.id = id; self.date = date; self.items = items; self.raw = raw; self.pct = pct; self.createdAt = createdAt
    }
}

public struct NewWho5: Sendable, Equatable {
    public var date: String
    public var items: [Int]
    public init(date: String, items: [Int]) { self.date = date; self.items = items }
}

public enum Who5Error: Error, Equatable, Sendable {
    case invalidItems
}

/// CRUD over `mind_who5` — oracle `Who5Store` (`mobile/src/mind/who5.ts`). Every column
/// (i1-i5/raw/pct) is sealed: WHO-5 is an Art.9 depression-screening-cutoff signal, unlike the
/// low-cardinality categorical fields elsewhere that got a scope carve-out.
public struct Who5Store: Sendable {
    private let db: AppDatabase
    private let cipher: any FieldCipher

    public init(db: AppDatabase, cipher: any FieldCipher = IdentityCipher()) {
        self.db = db
        self.cipher = cipher
    }

    @discardableResult
    public func add(_ n: NewWho5, now: Date = Date()) throws -> Int64 {
        guard n.items.count == 5, n.items.allSatisfy(isValidResponse) else { throw Who5Error.invalidItems }
        let raw = who5Raw(n.items)
        let pct = who5Percent(raw)
        let nowISO = now.ISO8601Format()
        let encItems = try n.items.map { try cipher.seal(String($0)) }
        let encRaw = try cipher.seal(String(raw))
        let encPct = try cipher.seal(String(pct))
        return try db.pool.write { conn in
            try conn.execute(
                sql: """
                INSERT INTO mind_who5 (date, i1, i2, i3, i4, i5, raw, pct, created_at, synced)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                """,
                arguments: [n.date, encItems[0], encItems[1], encItems[2], encItems[3], encItems[4], encRaw, encPct, nowISO]
            )
            return conn.lastInsertedRowID
        }
    }

    public func latest() throws -> Who5Entry? {
        try db.pool.read { conn in
            guard let row = try Row.fetchOne(
                conn,
                sql: "SELECT id, date, i1, i2, i3, i4, i5, raw, pct, created_at FROM mind_who5 ORDER BY date DESC, id DESC LIMIT 1"
            ) else { return nil }
            return try rowToEntry(row)
        }
    }

    public func recent(_ limit: Int) throws -> [Who5Entry] {
        try db.pool.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT id, date, i1, i2, i3, i4, i5, raw, pct, created_at FROM mind_who5 ORDER BY date DESC, id DESC LIMIT ?",
                arguments: [limit]
            ).map { try rowToEntry($0) }
        }
    }

    /// Every WHO-5 entry ever recorded, newest first — full-history export (E13-5).
    public func listAll() throws -> [Who5Entry] {
        try db.pool.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT id, date, i1, i2, i3, i4, i5, raw, pct, created_at FROM mind_who5 ORDER BY date DESC, id DESC"
            ).map { try rowToEntry($0) }
        }
    }

    private func rowToEntry(_ row: Row) throws -> Who5Entry {
        let items = try ["i1", "i2", "i3", "i4", "i5"].map { col -> Int in
            Int(try cipher.open(row[col] as String)) ?? 0
        }
        return Who5Entry(
            id: row["id"],
            date: row["date"],
            items: items,
            raw: Int(try cipher.open(row["raw"] as String)) ?? 0,
            pct: Int(try cipher.open(row["pct"] as String)) ?? 0,
            createdAt: row["created_at"]
        )
    }
}

/// Sum of the 5 item scores (each 0-5) => raw score in [0,25]. Oracle `who5Raw`.
public nonisolated func who5Raw(_ items: [Int]) -> Int { items.reduce(0, +) }

/// Raw score (0-25) => percentage trend (0-100). Oracle `who5Percent`.
public nonisolated func who5Percent(_ raw: Int) -> Int { raw * 4 }

/// True iff n is an integer response in [0,5]. Oracle `isValidResponse`.
public nonisolated func isValidResponse(_ n: Int) -> Bool { n >= 0 && n <= 5 }

/// True iff there is no WHO-5 recorded in the current ISO week (Mon-Sun) of `now` — oracle
/// `who5DueThisWeek` (`mobile/src/mind/who5.ts`). `latestDate` is the most recent recorded entry's
/// date (yyyy-mm-dd, or an ISO timestamp — only the leading 10 chars are used), or nil if none
/// exists yet. Pure — takes an explicit `Calendar` so this stays reproducible in tests (never
/// `Calendar.current` implicitly smuggled in as a default that silently varies by device).
public nonisolated func who5DueThisWeek(_ latestDate: String?, now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Bool {
    guard let latestDate else { return true }
    var cal = calendar
    cal.firstWeekday = 2 // Monday
    let weekday = cal.component(.weekday, from: now) // 1=Sun...7=Sat
    let dow = (weekday + 5) % 7 // Mon=0..Sun=6
    guard let monday = cal.date(byAdding: .day, value: -dow, to: cal.startOfDay(for: now)),
          let sunday = cal.date(byAdding: .day, value: 6, to: monday)
    else { return true }
    let mondayISO = localISO(monday, calendar: cal)
    let sundayISO = localISO(sunday, calendar: cal)
    let d = String(latestDate.prefix(10))
    return !(d >= mondayISO && d <= sundayISO)
}

/// `yyyy-MM-dd` in `calendar`'s components — mirrors the oracle's private `localISO`.
private nonisolated func localISO(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}
