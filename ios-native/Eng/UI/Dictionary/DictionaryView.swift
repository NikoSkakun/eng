import SwiftUI

/// Manage every saved term: search, edit, delete, and toggle highlighting.
struct DictionaryView: View {
    @EnvironmentObject var app: AppState
    @State private var search = ""

    private var filtered: [DictionaryEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return app.entries }
        return app.entries.filter {
            $0.term.lowercased().contains(q) ||
            $0.allTranslations.contains { $0.lowercased().contains(q) } ||
            ($0.definition?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if app.entries.isEmpty {
                    ContentUnavailableView("No terms yet", systemImage: "character.book.closed",
                        description: Text("Select a word while reading to add it here."))
                } else {
                    List {
                        ForEach(filtered) { entry in
                            NavigationLink { EntryEditView(entryId: entry.id) } label: { card(entry) }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { app.deleteEntry(entry.id) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { app.toggleHighlight(entry) } label: {
                                        Label(entry.highlightEnabled ? "Mute" : "Highlight", systemImage: "highlighter")
                                    }.tint(entry.highlightEnabled ? .gray : .orange)
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Dictionary")
            .searchable(text: $search, prompt: "Search terms")
        }
    }

    /// A word card that grows vertically to show every translation in full — no
    /// truncation, each variant wrapped onto as many lines as it needs.
    @ViewBuilder private func card(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(entry.highlightEnabled ? Color(argb: entry.colorValue ?? app.settings.highlightColor) : Color.clear)
                    .overlay(Circle().strokeBorder(.quaternary))
                    .frame(width: 13, height: 13)
                Text(entry.term).font(.body)
                if entry.matchPartial {
                    Image(systemName: "textformat.abc.dottedunderline").font(.caption2).foregroundStyle(.tertiary)
                }
                if entry.scopeDocumentId != nil {
                    Image(systemName: "doc").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            // Same type treatment as the old single-line row (.caption/.secondary) —
            // only the truncation is gone, so the card grows to fit every variant.
            let translations = entry.allTranslations
            if translations.isEmpty {
                Text(entry.definition?.isEmpty == false ? entry.definition! : "No translation yet")
                    .font(.caption)
                    .foregroundStyle(entry.definition?.isEmpty == false ? .secondary : .tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(translations.enumerated()), id: \.offset) { _, t in
                        Text(t)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)   // full, wrapped, never clipped
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemBackground)))
    }
}
