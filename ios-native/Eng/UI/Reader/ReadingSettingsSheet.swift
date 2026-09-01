import SwiftUI

/// Live reading-view customization for the reflowable reader: theme, typeface,
/// size, spacing, margins and justification. Every change flows through
/// `AppState.mutateSettings`, which the open reader observes and re-renders.
struct ReadingSettingsSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    private func bind<T>(_ kp: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { app.settings[keyPath: kp] }, set: { v in app.mutateSettings { $0[keyPath: kp] = v } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    HStack(spacing: 12) {
                        ForEach(ReaderTheme.allCases) { theme in
                            themeSwatch(theme)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }

                Section("Text") {
                    Picker("Typeface", selection: bind(\.readerFont)) {
                        ForEach(ReaderFont.allCases) { Text($0.label).tag($0) }
                    }
                    sizeStepper
                    Picker("Line spacing", selection: lineSpacingBinding) {
                        Text("Compact").tag(LineSpace.compact)
                        Text("Normal").tag(LineSpace.normal)
                        Text("Relaxed").tag(LineSpace.relaxed)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Layout") {
                    Picker("Margins", selection: bind(\.readerMargin)) {
                        ForEach(ReaderMargin.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Justify text", isOn: bind(\.readerJustified))
                }
            }
            .navigationTitle("Reading view")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: theme swatch

    @ViewBuilder private func themeSwatch(_ theme: ReaderTheme) -> some View {
        let selected = app.settings.readerTheme == theme
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.swatchBackground)
                Text("Aa").font(.headline).foregroundStyle(theme.swatchText)
            }
            .frame(height: 52)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.12),
                              lineWidth: selected ? 2.5 : 1))
            Text(theme.label).font(.caption2).foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.mutateSettings { $0.readerTheme = theme } }
    }

    // MARK: font-size stepper

    private var sizeStepper: some View {
        HStack {
            Text("Size")
            Spacer()
            Button {
                app.mutateSettings { $0.readerFontSize = max(kReaderFontSizeRange.lowerBound, $0.readerFontSize - 1) }
            } label: { Image(systemName: "textformat.size.smaller") }
                .disabled(app.settings.readerFontSize <= kReaderFontSizeRange.lowerBound)
            Text("\(Int(app.settings.readerFontSize))")
                .font(.body.monospacedDigit()).frame(width: 34)
            Button {
                app.mutateSettings { $0.readerFontSize = min(kReaderFontSizeRange.upperBound, $0.readerFontSize + 1) }
            } label: { Image(systemName: "textformat.size.larger") }
                .disabled(app.settings.readerFontSize >= kReaderFontSizeRange.upperBound)
        }
        .buttonStyle(.borderless)
    }

    // MARK: line spacing presets

    private enum LineSpace { case compact, normal, relaxed
        var value: Double { self == .compact ? 3 : (self == .normal ? 7 : 12) }
        static func nearest(_ v: Double) -> LineSpace {
            [compact, normal, relaxed].min { abs($0.value - v) < abs($1.value - v) } ?? .normal
        }
    }
    private var lineSpacingBinding: Binding<LineSpace> {
        Binding(get: { LineSpace.nearest(app.settings.readerLineSpacing) },
                set: { ls in app.mutateSettings { $0.readerLineSpacing = ls.value } })
    }
}

private extension ReaderTheme {
    var swatchBackground: Color { Color(background) }
    var swatchText: Color { Color(text) }
}
