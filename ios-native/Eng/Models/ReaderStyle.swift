import SwiftUI
import UIKit

/// Typeface choices for the reflowable reader.
enum ReaderFont: String, CaseIterable, Identifiable {
    case system, serif, rounded

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        }
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch self {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .serif:
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.serif) { return UIFont(descriptor: d, size: size) }
            return UIFont(name: "Georgia", size: size) ?? base
        case .rounded:
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(.rounded) { return UIFont(descriptor: d, size: size) }
            return base
        }
    }
}

/// Page colour scheme for the reflowable reader.
enum ReaderTheme: String, CaseIterable, Identifiable {
    case system, light, sepia, dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }

    var background: UIColor {
        switch self {
        case .system: return .systemBackground
        case .light: return .white
        case .sepia: return UIColor(red: 0.984, green: 0.941, blue: 0.851, alpha: 1)   // #FBF0D9
        case .dark: return UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1)    // #1C1C1E
        }
    }
    var text: UIColor {
        switch self {
        case .system: return .label
        case .light: return UIColor(white: 0.10, alpha: 1)
        case .sepia: return UIColor(red: 0.357, green: 0.275, blue: 0.212, alpha: 1)   // #5B4636
        case .dark: return UIColor(red: 0.796, green: 0.796, blue: 0.816, alpha: 1)    // #CBCBD0
        }
    }
    var secondaryText: UIColor { text.withAlphaComponent(0.6) }

    var swiftUIBackground: Color { Color(background) }
    /// A visible-in-either-mode preview swatch for the picker.
    var isDarkAppearance: Bool { self == .dark }
}

/// Left/right page margin width.
enum ReaderMargin: String, CaseIterable, Identifiable {
    case narrow, medium, wide

    var id: String { rawValue }
    var label: String {
        switch self {
        case .narrow: return "Narrow"
        case .medium: return "Medium"
        case .wide: return "Wide"
        }
    }
    var inset: CGFloat {
        switch self {
        case .narrow: return 14
        case .medium: return 22
        case .wide: return 36
        }
    }
}

/// Bounds for the font-size stepper.
let kReaderFontSizeRange: ClosedRange<Double> = 13...30
let kDefaultReaderFontSize: Double = 19
