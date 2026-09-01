import SwiftUI

/// Sheet for adding a new term (or editing the existing one) from a selection in
/// the reader. Auto-suggests a translation and, for single English words, a
/// definition — always leaving the wording editable.
struct AddEntrySheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let seedText: String
    let documentId: Int64

    @State private var term = ""
    @State private var translation = ""
    @State private var alternatives: [String] = []
    @State private var suggestedAlternatives: [String] = []
    @State private var definition = ""
    @State private var notes = ""
    @State private var highlightEnabled = true
    @State private var matchPartial = false
    @State private var scopeThisDocOnly = false

    @State private var editingId: Int64?
    @State private var loadingSuggestion = false
    @State private var loadingDefinition = false
    @State private var errorText: String?
    @State private var loaded = false

    private var isSingleWord: Bool { TextNormalizer.tokenize(term).count == 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Term") {
                    TextField("Term", text: $term).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if isSingleWord {
                        Toggle("Also match inside longer words", isOn: $matchPartial)
                    }
                }

                Section("Translation") {
                    HStack {
                        TextField("Translation", text: $translation)
                        if loadingSuggestion { ProgressView() }
                    }
                    if !suggestedAlternatives.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedAlternatives, id: \.self) { alt in
                                    Button(alt) { pick(alt) }
                                        .font(.footnote)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(.tint.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                    ForEach(alternatives, id: \.self) { alt in
                        HStack {
                            Text(alt).foregroundStyle(.secondary)
                            Spacer()
                            Button { alternatives.removeAll { $0 == alt } } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                if app.settings.definitionsAvailable {
                    Section("Definition") {
                        if loadingDefinition { ProgressView() }
                        TextField("Definition", text: $definition, axis: .vertical).lineLimit(1...6)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
                }

                Section {
                    Toggle("Highlight in reader", isOn: $highlightEnabled)
                    Picker("Applies to", selection: $scopeThisDocOnly) {
                        Text("Whole library").tag(false)
                        Text("This document").tag(true)
                    }
                }

                if let errorText {
                    Section { Text(errorText).font(.footnote).foregroundStyle(.secondary) }
                }

                if editingId != nil {
                    Section {
                        Button("Delete term", role: .destructive) {
                            if let id = editingId { app.deleteEntry(id) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(editingId == nil ? "Add term" : "Edit term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func pick(_ alt: String) {
        if translation.trimmingCharacters(in: .whitespaces).isEmpty {
            translation = alt
        } else if translation != alt && !alternatives.contains(alt) {
            alternatives.append(alt)
        }
        suggestedAlternatives.removeAll { $0 == alt }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        term = TextNormalizer.trimEdgePunctuation(seedText)

        if let existing = app.existingEntry(forTerm: term, documentId: documentId) {
            editingId = existing.id
            term = existing.term
            translation = existing.translation ?? ""
            alternatives = existing.alternativeTranslations
            definition = existing.definition ?? ""
            notes = existing.notes ?? ""
            highlightEnabled = existing.highlightEnabled
            matchPartial = existing.matchPartial
            scopeThisDocOnly = existing.scopeDocumentId != nil
            return
        }

        if app.settings.autoSuggestEnabled { fetchSuggestion() }
    }

    private func fetchSuggestion() {
        let svc = app.translationService
        let word = term
        loadingSuggestion = true
        let wantDefinition = app.settings.definitionsAvailable && isSingleWord
        if wantDefinition { loadingDefinition = true }

        Task {
            do {
                let r = try await svc.suggestTranslation(word)
                if translation.isEmpty { translation = r.translatedText }
                suggestedAlternatives = r.alternatives.filter { $0 != r.translatedText }
            } catch {
                errorText = "Couldn’t suggest a translation (\((error as? ProviderError)?.message ?? "offline?"))."
            }
            loadingSuggestion = false
        }

        if wantDefinition {
            Task {
                do {
                    if let d = try await svc.lookupDefinition(word), definition.isEmpty {
                        definition = d.storedText
                    }
                } catch { /* definitions are best-effort */ }
                loadingDefinition = false
            }
        }
    }

    private func save() {
        let now = Date()
        let cleanTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        func nilIfEmpty(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        }
        if let id = editingId, var entry = app.entry(id: id) {
            entry.term = cleanTerm
            entry.translation = nilIfEmpty(translation)
            entry.alternativeTranslations = alternatives
            entry.definition = nilIfEmpty(definition)
            entry.notes = nilIfEmpty(notes)
            entry.highlightEnabled = highlightEnabled
            entry.matchPartial = isSingleWord && matchPartial
            entry.scopeDocumentId = scopeThisDocOnly ? documentId : nil
            app.updateEntry(entry)
        } else {
            let entry = DictionaryEntry(
                id: 0, term: cleanTerm,
                sourceLang: app.settings.learningLang, targetLang: app.settings.nativeLang,
                translation: nilIfEmpty(translation), alternativeTranslations: alternatives,
                definition: nilIfEmpty(definition), notes: nilIfEmpty(notes),
                highlightEnabled: highlightEnabled, colorValue: nil,
                matchPartial: isSingleWord && matchPartial, sourceWord: nil,
                scopeDocumentId: scopeThisDocOnly ? documentId : nil,
                createdAt: now, updatedAt: now)
            app.addEntry(entry)
        }
        dismiss()
    }
}
