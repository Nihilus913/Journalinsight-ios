//
//  QuestionsDetailView.swift
//  JournalInsight
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import SwiftUI
import SwiftData

struct QuestionsDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var answerText: String = ""
    @State private var selectedPrompt: String?
    @State private var showingEntry = false

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
                            let entry = JournalEntry(date: Date(), text: fullText, duration: 0)
                            modelContext.insert(entry)
                            showingEntry = false
                        }
                        .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
