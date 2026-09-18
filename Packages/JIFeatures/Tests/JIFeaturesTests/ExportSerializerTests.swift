import Foundation
import Testing
import JIPersistence
import JIVault
@testable import JIFeatures

// W5b-L5 (P-export). Ports `mobile/__tests__/export/serialize.test.ts` (369 L) onto the
// JIPersistence row types, plus the screen-level guarantees from `mobile/app/export.tsx`:
// nothing exports until ticked, and what exports is plaintext (no vault envelope leaks).

private let baseEntry = Entry(
    id: 1, date: "2026-08-23", ts: "2026-08-23T08:00:00.000Z", text: "Plain text, nothing weird.",
    durationSec: 300, mood: "good", tags: ["work", "focus"]
)

private func with(_ e: Entry, _ mutate: (inout Entry) -> Void) -> Entry { var c = e; mutate(&c); return c }

private func lines(_ csv: String) -> [String] { csv.components(separatedBy: "\n") }

private func parseJSON(_ text: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
}

// MARK: entriesToCSV

@Test func entriesCSVHeaderEvenWhenEmpty() {
    #expect(entriesToCSV([]) == "date,ts,mood,durationSec,tags,text")
}

@Test func entriesCSVPlainRowFieldsInOrder() {
    let l = lines(entriesToCSV([baseEntry]))
    #expect(l[0] == "date,ts,mood,durationSec,tags,text")
    #expect(l[1] == "2026-08-23,2026-08-23T08:00:00.000Z,good,300,work; focus,\"Plain text, nothing weird.\"")
}

@Test func entriesCSVJoinsTagsWithSemicolonSpace() {
    #expect(lines(entriesToCSV([with(baseEntry) { $0.tags = ["a", "b", "c"] }]))[1].contains("a; b; c"))
}

@Test func entriesCSVNullMoodIsEmptyField() {
    let row = lines(entriesToCSV([with(baseEntry) { $0.mood = nil }]))[1]
    #expect(row.components(separatedBy: ",")[2] == "")
}

@Test func entriesCSVEscapesComma() {
    #expect(lines(entriesToCSV([with(baseEntry) { $0.text = "hello, world" }]))[1].contains("\"hello, world\""))
}

@Test func entriesCSVEscapesDoubleQuote() {
    #expect(lines(entriesToCSV([with(baseEntry) { $0.text = "she said \"hi\"" }]))[1].contains("\"she said \"\"hi\"\"\""))
}

@Test func entriesCSVEscapesNewline() {
    #expect(entriesToCSV([with(baseEntry) { $0.text = "line one\nline two" }]).contains("\"line one\nline two\""))
}

@Test func entriesCSVDoesNotQuoteCleanFields() {
    #expect(lines(entriesToCSV([baseEntry]))[1].components(separatedBy: ",")[0] == "2026-08-23")
}

@Test func entriesCSVMultipleRows() {
    let l = lines(entriesToCSV([baseEntry, with(baseEntry) { $0.id = 2; $0.date = "2026-08-24" }]))
    #expect(l.count == 3)
    #expect(l[2].hasPrefix("2026-08-24"))
}

@Test func entriesCSVTagListRoundTripsUnquoted() {
    let row = lines(entriesToCSV([baseEntry]))[1]
    #expect(row.contains("work; focus"))
    #expect(!row.contains("\"work; focus\""))
}

// MARK: entriesToJSON

@Test func entriesJSONEmptyIsEmptyArray() {
    #expect(entriesToJSON([]) == "[]")
}

@Test func entriesJSONPrettyPrintsTwoSpaceIndent() {
    let json = entriesToJSON([baseEntry])
    #expect(json.hasPrefix("[\n  {\n    \""))
    #expect(json.contains("\"durationSec\" : 300"))
}

@Test func entriesJSONRoundTrips() throws {
    let entries = [baseEntry, with(baseEntry) { $0.id = 2; $0.mood = nil; $0.tags = [] }]
    let parsed = try #require(try parseJSON(entriesToJSON(entries)) as? [[String: Any]])
    #expect(parsed.count == 2)
    #expect(parsed[0]["text"] as? String == "Plain text, nothing weird.")
    #expect(parsed[0]["tags"] as? [String] == ["work", "focus"])
    #expect(parsed[0]["mood"] as? String == "good")
    // `JSON.stringify` writes a null mood as `null`, not a missing key.
    #expect(parsed[1].keys.contains("mood"))
    #expect(parsed[1]["mood"] is NSNull)
    #expect(parsed[1]["tags"] as? [String] == [])
}

// MARK: E13-5 fixtures

private let checkin = CheckIn(
    date: "2026-08-23", mood: .good, stress: 2, energy: 4, dosed: true,
    irritability: 1, restlessness: 2, appetite: 3, note: "Plain note.", updatedAt: "2026-08-23T20:00:00.000Z"
)

private let event = MindEvent(
    id: 1, date: "2026-08-23", timeLocal: "09:15", type: .migraine, severity: 3,
    prodrome: ["neck pull", "yawning"], triggers: "bright light", note: "started after gym",
    createdAt: "2026-08-23T09:20:00.000Z"
)

private let who5 = Who5Entry(id: 1, date: "2026-08-23", items: [3, 4, 2, 5, 3], raw: 17, pct: 68, createdAt: "2026-08-23T08:00:00.000Z")

private let goal = Goal(id: 1, title: "Bench 100kg", targetDate: "2026-12-31", progress: 0.4, createdAt: "2026-08-01T00:00:00.000Z")

// MARK: checkinsToCSV

@Test func checkinsCSVHeaderEvenWhenEmpty() {
    #expect(checkinsToCSV([]) == "date,mood,stress,energy,dosed,irritability,restlessness,appetite,note,updatedAt")
}

@Test func checkinsCSVPlainRow() {
    #expect(lines(checkinsToCSV([checkin]))[1] == "2026-08-23,good,2,4,true,1,2,3,Plain note.,2026-08-23T20:00:00.000Z")
}

@Test func checkinsCSVNullFieldsAreEmpty() {
    var c = checkin
    c.mood = nil; c.irritability = nil; c.restlessness = nil; c.appetite = nil; c.note = nil
    let fields = lines(checkinsToCSV([c]))[1].components(separatedBy: ",")
    #expect(fields[1] == "")
    #expect(fields[5] == "")
    #expect(fields[6] == "")
    #expect(fields[7] == "")
    #expect(fields[8] == "")
}

@Test func checkinsCSVDosedFalseLiteral() {
    var c = checkin
    c.dosed = false
    #expect(lines(checkinsToCSV([c]))[1].contains(",false,"))
}

@Test func checkinsCSVEscapesNote() {
    var c = checkin
    c.note = "rough day, felt \"off\" and\nkept thinking about it"
    let row = lines(checkinsToCSV([c]).replacingOccurrences(of: "\r", with: "")).dropFirst().joined(separator: "\n")
    #expect(row.contains("\"rough day, felt \"\"off\"\" and\nkept thinking about it\""))
}

@Test func checkinsJSONRoundTrips() throws {
    let parsed = try #require(try parseJSON(checkinsToJSON([checkin])) as? [[String: Any]])
    #expect(parsed[0]["mood"] as? String == "good")
    #expect(parsed[0]["dosed"] as? Bool == true)
    #expect(parsed[0]["stress"] as? Int == 2)
    #expect(parsed[0]["updatedAt"] as? String == "2026-08-23T20:00:00.000Z")
}

// MARK: eventsToCSV

@Test func eventsCSVHeaderEvenWhenEmpty() {
    #expect(eventsToCSV([]) == "id,date,timeLocal,type,severity,prodrome,triggers,note,createdAt")
}

@Test func eventsCSVPlainRowProdromeJoined() {
    #expect(lines(eventsToCSV([event]))[1] == "1,2026-08-23,09:15,migraine,3,neck pull; yawning,bright light,started after gym,2026-08-23T09:20:00.000Z")
}

@Test func eventsCSVNullNoteIsEmpty() {
    var e = event
    e.note = nil
    #expect(lines(eventsToCSV([e]))[1].components(separatedBy: ",")[7] == "")
}

@Test func eventsCSVEscapesFreeText() {
    var e = event
    e.triggers = "bright light, loud noise"
    e.note = "said \"ow\" then\nlaid down"
    let row = lines(eventsToCSV([e])).dropFirst().joined(separator: "\n")
    #expect(row.contains("\"bright light, loud noise\""))
    #expect(row.contains("\"said \"\"ow\"\" then\nlaid down\""))
}

@Test func eventsJSONRoundTrips() throws {
    let parsed = try #require(try parseJSON(eventsToJSON([event])) as? [[String: Any]])
    #expect(parsed[0]["type"] as? String == "migraine")
    #expect(parsed[0]["prodrome"] as? [String] == ["neck pull", "yawning"])
    #expect(parsed[0]["severity"] as? Int == 3)
}

// MARK: who5ToCSV

@Test func who5CSVHeaderEvenWhenEmpty() {
    #expect(who5ToCSV([]) == "id,date,i1,i2,i3,i4,i5,raw,pct,createdAt")
}

@Test func who5CSVExpandsItemsIntoColumns() {
    #expect(lines(who5ToCSV([who5]))[1] == "1,2026-08-23,3,4,2,5,3,17,68,2026-08-23T08:00:00.000Z")
}

@Test func who5JSONRoundTrips() throws {
    let parsed = try #require(try parseJSON(who5ToJSON([who5])) as? [[String: Any]])
    #expect(parsed[0]["items"] as? [Int] == [3, 4, 2, 5, 3])
    #expect(parsed[0]["pct"] as? Int == 68)
}

// MARK: goalsToCSV

@Test func goalsCSVHeaderEvenWhenEmpty() {
    #expect(goalsToCSV([]) == "id,title,targetDate,progress,createdAt")
}

@Test func goalsCSVPlainRow() {
    #expect(lines(goalsToCSV([goal]))[1] == "1,Bench 100kg,2026-12-31,0.4,2026-08-01T00:00:00.000Z")
}

@Test func goalsCSVNullTargetDateIsEmpty() {
    var g = goal
    g.targetDate = nil
    #expect(lines(goalsToCSV([g]))[1].components(separatedBy: ",")[2] == "")
}

@Test func goalsCSVEscapesTitleComma() {
    var g = goal
    g.title = "Bench 100kg, then row 100kg"
    #expect(lines(goalsToCSV([g]))[1].contains("\"Bench 100kg, then row 100kg\""))
}

@Test func goalsCSVWholeNumberProgressHasNoDecimalPoint() {
    var g = goal
    g.progress = 1
    #expect(lines(goalsToCSV([g]))[1] == "1,Bench 100kg,2026-12-31,1,2026-08-01T00:00:00.000Z")
}

@Test func goalsJSONRoundTrips() throws {
    let parsed = try #require(try parseJSON(goalsToJSON([goal])) as? [[String: Any]])
    #expect(parsed[0]["title"] as? String == "Bench 100kg")
    #expect(parsed[0]["progress"] as? Double == 0.4)
    #expect(parsed[0]["targetDate"] as? String == "2026-12-31")
}

// MARK: noExportSelected

@Test func noExportSelectedIsAllFalse() {
    let s = noExportSelected()
    for t in ExportType.allCases { #expect(!s.contains(t)) }
    #expect(s.isEmpty)
}

// MARK: combinedCSV

private let allData = ExportData(entries: [baseEntry], checkins: [checkin], events: [event], who5: [who5], goals: [goal])
private let allSelected = ExportSelection(Set(ExportType.allCases))

@Test func combinedCSVEmptySelectionIsEmptyString() {
    #expect(combinedCSV(noExportSelected(), allData) == "")
}

@Test func combinedCSVOnlySelectedSection() {
    let csv = combinedCSV(ExportSelection([.checkins]), allData)
    #expect(csv.contains("# Mind check-ins"))
    #expect(csv.contains("2026-08-23,good,2,4,true,1,2,3,Plain note.,2026-08-23T20:00:00.000Z"))
    #expect(!csv.contains("# Journal entries"))
    #expect(!csv.contains("# Mind events"))
    #expect(!csv.contains("# WHO-5"))
    #expect(!csv.contains("# Goals"))
}

@Test func combinedCSVAllTypesKeepOwnColumnSets() {
    let csv = combinedCSV(allSelected, allData)
    #expect(csv.contains("date,ts,mood,durationSec,tags,text"))
    #expect(csv.contains("date,mood,stress,energy,dosed,irritability,restlessness,appetite,note,updatedAt"))
    #expect(csv.contains("id,date,timeLocal,type,severity,prodrome,triggers,note,createdAt"))
    #expect(csv.contains("id,date,i1,i2,i3,i4,i5,raw,pct,createdAt"))
    #expect(csv.contains("id,title,targetDate,progress,createdAt"))
    #expect(csv.contains("2026-08-23,good,2,4,true,1,2,3,Plain note.,2026-08-23T20:00:00.000Z"))
    #expect(csv.contains("1,2026-08-23,09:15,migraine,3,neck pull; yawning,bright light,started after gym,2026-08-23T09:20:00.000Z"))
    #expect(csv.contains("1,2026-08-23,3,4,2,5,3,17,68,2026-08-23T08:00:00.000Z"))
    #expect(csv.contains("1,Bench 100kg,2026-12-31,0.4,2026-08-01T00:00:00.000Z"))
    // Sections are blank-line separated, in TYPE_ROWS order.
    #expect(csv.hasPrefix("# Journal entries\n"))
    #expect(csv.contains("\n\n# Mind check-ins\n"))
}

@Test func combinedCSVMissingDataForSelectedTypeIsHeaderOnly() {
    #expect(combinedCSV(ExportSelection([.goals]), ExportData()) == "# Goals\nid,title,targetDate,progress,createdAt")
}

// MARK: combinedJSON

@Test func combinedJSONEmptySelectionIsEmptyObject() throws {
    let parsed = try #require(try parseJSON(combinedJSON(noExportSelected(), allData)) as? [String: Any])
    #expect(parsed.isEmpty)
}

@Test func combinedJSONUntickedKeyOmittedEntirely() throws {
    let parsed = try #require(try parseJSON(combinedJSON(ExportSelection([.goals]), allData)) as? [String: Any])
    #expect(Array(parsed.keys) == ["goals"])
}

@Test func combinedJSONAllTypesKeepShape() throws {
    let text = combinedJSON(allSelected, allData)
    let parsed = try #require(try parseJSON(text) as? [String: Any])
    #expect(Set(parsed.keys) == Set(ExportType.allCases.map(\.rawValue)))
    #expect((parsed["journal"] as? [[String: Any]])?.first?["text"] as? String == "Plain text, nothing weird.")
    #expect((parsed["checkins"] as? [[String: Any]])?.first?["dosed"] as? Bool == true)
    #expect((parsed["events"] as? [[String: Any]])?.first?["type"] as? String == "migraine")
    #expect((parsed["who5"] as? [[String: Any]])?.first?["raw"] as? Int == 17)
    #expect((parsed["goals"] as? [[String: Any]])?.first?["progress"] as? Double == 0.4)
    // Insertion order is the oracle's, not alphabetical.
    let order = ExportType.allCases.compactMap { text.range(of: "\"\($0.rawValue)\" :")?.lowerBound }
    #expect(order == order.sorted())
}

@Test func combinedJSONSelectedTypeWithNoDataIsEmptyArray() throws {
    let parsed = try #require(try parseJSON(combinedJSON(ExportSelection([.who5]), ExportData())) as? [String: Any])
    #expect((parsed["who5"] as? [Any])?.isEmpty == true)
}

// MARK: ExportViewModel over seeded, vault-sealed stores (export.tsx)

/// A deterministic stand-in for the vault's AES-GCM cipher: seals with RN's `htv1:` column marker
/// so a leaked ciphertext is trivially greppable, and never touches the Keychain.
nonisolated struct MarkerCipher: FieldCipher {
    func seal(_ plain: String) throws -> String { "htv1:" + Data(plain.utf8).base64EncodedString() }
    func open(_ stored: String) throws -> String {
        guard stored.hasPrefix("htv1:"), let data = Data(base64Encoded: String(stored.dropFirst(5))) else { return stored }
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
private func seededModel() throws -> (ExportViewModel, AppDatabase) {
    let db = try AppDatabase.inMemory()
    let cipher = MarkerCipher()
    let journal = JournalStore(db: db, cipher: cipher)
    let checkins = CheckInStore(db: db, cipher: cipher)
    let events = EventStore(db: db, cipher: cipher)
    let who5 = Who5Store(db: db, cipher: cipher)
    let goals = GoalStore(db: db)
    try journal.addEntry(NewEntry(date: "2026-08-23", text: "Plain text, nothing weird.", durationSec: 300, mood: "good", tags: ["work", "focus"]))
    try checkins.upsertToday(NewCheckIn(date: "2026-08-23", mood: .good, stress: 2, energy: 4, dosed: true, irritability: 1, restlessness: 2, appetite: 3, note: "Plain note."))
    try events.addEvent(NewMindEvent(date: "2026-08-23", timeLocal: "09:15", type: .migraine, severity: 3, prodrome: ["neck pull", "yawning"], triggers: "bright light", note: "started after gym"))
    try who5.add(NewWho5(date: "2026-08-23", items: [3, 4, 2, 5, 3]))
    try goals.addGoal(NewGoal(title: "Bench 100kg", targetDate: "2026-12-31", progress: 0.4))
    let model = ExportViewModel(stores: .init(journal: journal, checkins: checkins, events: events, who5: who5, goals: goals))
    return (model, db)
}

@Test @MainActor func viewModelCountsEveryStoreAndStartsUnticked() throws {
    let (model, _) = try seededModel()
    model.load()
    #expect(!model.isLoading)
    for t in ExportType.allCases {
        #expect(model.count(t) == 1)
        #expect(!model.isSelected(t))
    }
    #expect(!model.anySelected)
    #expect(model.payload(.csv) == "")
    #expect(model.payload(.json) == "{}")
}

@Test @MainActor func viewModelExportsPlaintextNeverTheVaultEnvelope() throws {
    let (model, db) = try seededModel()
    model.load()
    for t in ExportType.allCases { model.toggle(t) }
    let csv = model.payload(.csv)
    let json = model.payload(.json)

    // The rows on disk ARE sealed …
    let rawText = try JournalStore(db: db).rawColumns(id: 1)?.text
    #expect(rawText?.hasPrefix("htv1:") == true)
    // … and the export is byte-identical to the serializer over the plaintext rows.
    #expect(csv.contains("date,ts,mood,durationSec,tags,text"))
    #expect(csv.contains(",good,300,work; focus,\"Plain text, nothing weird.\""))
    #expect(csv.contains("2026-08-23,good,2,4,true,1,2,3,Plain note.,"))
    #expect(csv.contains("1,2026-08-23,09:15,migraine,3,neck pull; yawning,bright light,started after gym,"))
    #expect(csv.contains("1,2026-08-23,3,4,2,5,3,17,68,"))
    #expect(csv.contains("1,Bench 100kg,2026-12-31,0.4,"))
    #expect(!csv.contains("htv"))
    #expect(!json.contains("htv"))
    let parsed = try #require(try parseJSON(json) as? [String: Any])
    #expect((parsed["journal"] as? [[String: Any]])?.first?["text"] as? String == "Plain text, nothing weird.")
    #expect((parsed["checkins"] as? [[String: Any]])?.first?["note"] as? String == "Plain note.")
}

@Test @MainActor func viewModelToggleInvalidatesThePayload() throws {
    let (model, _) = try seededModel()
    model.load()
    model.toggle(.goals)
    #expect(model.payload(.csv).hasPrefix("# Goals\nid,title,targetDate,progress,createdAt\n1,Bench 100kg,2026-12-31,0.4,"))
    model.toggle(.goals)
    #expect(model.payload(.csv) == "")
    model.toggle(.who5)
    #expect(model.payload(.csv).hasPrefix("# WHO-5\n"))
}

@Test @MainActor func viewModelWithNoStoresReportsZeroRowsNotACrash() {
    let model = ExportViewModel(stores: .init())
    model.load()
    for t in ExportType.allCases { #expect(model.count(t) == 0) }
    #expect(model.errorMessage == nil)
    model.toggle(.journal)
    #expect(model.payload(.csv) == "# Journal entries\ndate,ts,mood,durationSec,tags,text")
}

@Test func exportFormatFilenamesMatchRN() {
    #expect(ExportFormat.csv.filename == "healthtraining-export.csv")
    #expect(ExportFormat.json.filename == "healthtraining-export.json")
}
