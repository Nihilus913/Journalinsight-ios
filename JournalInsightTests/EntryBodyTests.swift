// JournalInsightTests/EntryBodyTests.swift
import Testing
import Foundation
@testable import JournalInsight

@Suite("EntryBody")
struct EntryBodyTests {

    @Test("EntryBody encodes and decodes losslessly")
    func codableRoundTrip() throws {
        let original = EntryBody(text: "Hello", mood: .good, tags: ["one", "two"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EntryBody.self, from: data)
        #expect(decoded.text == original.text)
        #expect(decoded.mood == original.mood)
        #expect(decoded.tags == original.tags)
    }

    @Test("EntryBody with nil mood encodes correctly")
    func nilMood() throws {
        let original = EntryBody(text: "x", mood: nil, tags: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EntryBody.self, from: data)
        #expect(decoded.mood == nil)
    }

    @Test("EntryBody preserves tag order")
    func tagOrder() throws {
        let original = EntryBody(text: "x", mood: nil, tags: ["c", "a", "b"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EntryBody.self, from: data)
        #expect(decoded.tags == ["c", "a", "b"])
    }
}
