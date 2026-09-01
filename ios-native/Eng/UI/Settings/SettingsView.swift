import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    private static let colorPresets = [0x66FFC107, 0x6600C853, 0x662196F3, 0x66E91E63, 0x669C27B0, 0x66FF5722]

    private func bind<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { app.settings[keyPath: keyPath] },
                set: { v in app.mutateSettings { $0[keyPath: keyPath] = v } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Languages") {
                    Picker("I'm learning", selection: bind(\.learningLang)) {
                        ForEach(kSupportedLanguages) { l in Text(l.nativeName).tag(l.code) }
                    }
                    Picker("Translate to", selection: bind(\.nativeLang)) {
                        ForEach(kSupportedLanguages) { l in Text(l.nativeName).tag(l.code) }
                    }
                    if !kDefinitionLanguages.contains(app.settings.learningLang) {
                        Text("Definitions are only available for English.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Providers") {
                    Picker("Translation", selection: bind(\.translationProvider)) {
                        ForEach(TranslationProviderId.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Definitions", selection: bind(\.definitionProvider)) {
                        ForEach(DefinitionProviderId.allCases) { Text($0.label).tag($0) }
                    }
                    if app.settings.translationProvider == .myMemory {
                        TextField("MyMemory email (optional)", text: bind(\.myMemoryEmail))
                            .textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled()
                    }
                }
                if app.settings.translationProvider == .googleUnofficial {
                    Section {
                        Text("The unofficial Google endpoint is undocumented and may break or rate-limit; its use can violate Google's ToS.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Highlighting") {
                    Toggle("Highlight saved terms", isOn: bind(\.highlightingEnabled))
                    Toggle("Auto-suggest translations", isOn: bind(\.autoSuggestEnabled))
                    HStack {
                        Text("Color")
                        Spacer()
                        ForEach(Self.colorPresets, id: \.self) { argb in
                            Circle().fill(Color(argb: argb))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.primary, lineWidth: app.settings.highlightColor == argb ? 2 : 0))
                                .onTapGesture { app.mutateSettings { $0.highlightColor = argb } }
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "eng — PDF reader")
                    Text("Translations by MyMemory / Google. Definitions from the Free Dictionary API and Wiktionary (CC BY-SA).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
