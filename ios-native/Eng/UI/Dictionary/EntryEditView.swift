import SwiftUI

/// Editor for an existing dictionary entry, shared by the reader popup and the
/// dictionary manager.
struct EntryEditView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let entryId: Int64

    @State private var term = ""
    @State private var translation = ""
    @State private var alternatives: [String] = []
    @State private var definition = ""
    @State private var notes = ""
    @State private var highlightEnabled = true
    @State private var matchPartial = false
    @State private var isScoped = false
    @State private var reSuggesting = false
    @State private var loaded = false

    private var isSingleWord: Bool { TextNormalizer.tokenize(term).count == 1 }

    var body: some View {
        Form {
            Section("Term") {
                TextField("Term", text: $term).textInputAutocapitalization(.never).autocorrectionDisabled()
                if isSingleWord { Toggle("Also match inside longer words", isOn: $matchPartial) }
            }
            Section("Translation") {
                HStack {
                    TextField("Translation", text: $translation)
                    if reSuggesting { ProgressView() } else {
                        Button { reSuggest() } label: { Image(systemName: "sparkles") }.buttonStyle(.plain)
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
            Section("Definition") {
                TextField("Definition", text: $definition, axis: .vertical).lineLimit(1...8)
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4)
            }
            Section {
                Toggle("Highlight in reader", isOn: $highlightEnabled)
                if isScoped {
                    Toggle("Scoped to one document", isOn: $isScoped)
                }
            }
        }
        .navigationTitle("Edit term")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded, let e = app.entry(id: entryId) else { return }
        loaded = true
        term = e.term
        translation = e.translation ?? ""
        alternatives = e.alternativeTranslations
        definition = e.definition ?? ""
        notes = e.notes ?? ""
        highlightEnabled = e.highlightEnabled
        matchPartial = e.matchPartial
        isScoped = e.scopeDocumentId != nil
    }

    private func reSuggest() {
        let svc = app.translationService
        let word = term
        reSuggesting = true
        Task {
            if let r = try? await svc.suggestTranslation(word) {
                if !r.translatedText.isEmpty {
                    if !translation.isEmpty && translation != r.translatedText && !alternatives.contains(translation) {
                        alternatives.insert(translation, at: 0)
                    }
                    translation = r.translatedText
                }
            }
            reSuggesting = false
        }
    }

    private func save() {
        guard var e = app.entry(id: entryId) else { dismiss(); return }
        func nilIfEmpty(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t
        }
        e.term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        e.translation = nilIfEmpty(translation)
        e.alternativeTranslations = alternatives
        e.definition = nilIfEmpty(definition)
        e.notes = nilIfEmpty(notes)
        e.highlightEnabled = highlightEnabled
        e.matchPartial = isSingleWord && matchPartial
        // Clearing the scope toggle promotes a document-scoped term to global.
        if !isScoped { e.scopeDocumentId = nil }
        app.updateEntry(e)
        dismiss()
    }
}
