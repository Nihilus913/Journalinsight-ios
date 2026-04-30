//
//  QuestionsDetailView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData
import os

struct QuestionsDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.entryRepository) private var repo
    @State private var answerText: String = ""
    @State private var selectedPrompt: String?
    @State private var showingEntry = false
    @State private var selectedMood: Mood?

    private static let prompts: [String] = [
        "What are you grateful for today?",
        "What was the highlight of your day?",
        "What challenge did you face, and how did you handle it?",
        "What did you learn today?",
        "How are you feeling right now, and why?",
        "What's one thing you'd like to improve tomorrow?",
        "Describe a moment that made you smile today.",
        "What's something you accomplished recently that you're proud of?",
        "If you could change one thing about today, what would it be?",
        "What are your intentions for tomorrow?"
    ]

    private var todaysPrompts: [String] {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let startIndex = (dayOfYear * 3) % Self.prompts.count
        return (0..<3).map { Self.prompts[(startIndex + $0) % Self.prompts.count] }
    }

    var body: some View {
        List {
            Section("Today's Prompts") {
                ForEach(todaysPrompts, id: \.self) { prompt in
                    Button {
                        selectedPrompt = prompt
                        answerText = ""
                        selectedMood = nil
                        showingEntry = true
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(AppTheme.primaryColor)
                            Text(prompt)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }

            Section("All Prompts") {
                ForEach(Self.prompts, id: \.self) { prompt in
                    Button {
                        selectedPrompt = prompt
                        answerText = ""
                        selectedMood = nil
                        showingEntry = true
                    } label: {
                        Text(prompt)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationTitle("Prompts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEntry) {
            NavigationStack {
                Form {
                    if let prompt = selectedPrompt {
                        Section {
                            Text(prompt)
                                .font(.headline)
                                .foregroundColor(AppTheme.primaryColor)
                        }
                    }

                    Section("How are you feeling?") {
                        HStack(spacing: 16) {
                            ForEach(Mood.allCases) { mood in
                                Button {
                                    selectedMood = selectedMood == mood ? nil : mood
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(mood.emoji)
                                            .font(.title2)
                                        Text(mood.label)
                                            .font(.caption2)
                                    }
                                    .padding(6)
                                    .background(selectedMood == mood ? AppTheme.primaryColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Section("Your Response") {
                        TextEditor(text: $answerText)
                            .frame(minHeight: 150)
                    }
                }
                .navigationTitle("Write Entry")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingEntry = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let fullText: String
                            if let prompt = selectedPrompt {
                                fullText = "\(prompt)\n\n\(answerText.trimmingCharacters(in: .whitespacesAndNewlines))"
                            } else {
                                fullText = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            let mood = selectedMood
                            guard let repo else { return }
                            Task { @MainActor in
                                do {
                                    try await repo.create(date: Date(), duration: 0, text: fullText, mood: mood, tags: [])
                                    showingEntry = false
                                } catch {
                                    Logger.vault.error("prompt entry save failed: \(error.localizedDescription, privacy: .public)")
                                }
                            }
                        }
                        .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repo == nil)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        QuestionsDetailView()
    }
    .modelContainer(for: JournalEntry.self, inMemory: true)
}
