import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var showingPicker = false
    @State private var openDoc: LibraryDocument?
    @State private var renaming: LibraryDocument?
    @State private var renameText = ""
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if app.documents.isEmpty {
                    ContentUnavailableView {
                        Label("No documents", systemImage: "books.vertical")
                    } description: {
                        Text("Import a PDF or EPUB to start reading and building your dictionary.")
                    } actions: {
                        Button("Import") { showingPicker = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(app.documents) { doc in
                            Button { openDoc = doc } label: { row(doc) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { app.deleteDocument(doc) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { renaming = doc; renameText = doc.title } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }.tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingPicker = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .fullScreenCover(item: $openDoc) { doc in
            switch doc.format {
            case .pdf: ReaderView(document: doc)
            case .epub: TextReaderView(document: doc)
            }
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.pdf, .epub], allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { if let d = renaming { app.renameDocument(d, to: renameText) }; renaming = nil }
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }

    @ViewBuilder private func row(_ doc: LibraryDocument) -> some View {
        HStack(spacing: 12) {
            Image(systemName: doc.format == .epub ? "book.closed" : "doc.richtext")
                .font(.title2).foregroundStyle(.secondary).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.body).lineLimit(2)
                Text(subtitle(doc)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func subtitle(_ doc: LibraryDocument) -> String {
        var parts: [String] = []
        switch doc.format {
        case .pdf:
            if doc.pageCount > 0 { parts.append("\(doc.pageCount) pages") }
            if doc.lastOpenedAt != nil && doc.lastPage > 1 { parts.append("on page \(doc.lastPage)") }
        case .epub:
            parts.append("EPUB")
            if doc.pageCount > 0 { parts.append("\(doc.pageCount) chapters") }
            if let p = doc.epubViewState?.progress, p > 0.01 {
                parts.append("\(Int((p * 100).rounded()))% read")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do { _ = try app.importDocument(from: url) }
                catch { importError = error.localizedDescription }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
