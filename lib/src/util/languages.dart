/// Supported languages for translation and definitions.
///
/// The app is built around a *learning* language (the language of the
/// documents, e.g. English) and a *native* language (the reader's own
/// language, e.g. Ukrainian). Translations go learning -> native and
/// definitions are looked up in the learning language.
library;

/// A language the app knows how to translate to/from.
class AppLanguage {
  const AppLanguage(this.code, this.englishName, this.nativeName);

  /// ISO 639-1 code, lower-case (e.g. `en`, `uk`).
  final String code;

  /// Name in English (for fallback display).
  final String englishName;

  /// Name in the language itself.
  final String nativeName;

  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => '$englishName ($code)';
}

/// The set of languages offered in the UI.
///
/// This is intentionally a curated subset of what the translation providers
/// support; MyMemory and DeepL support many more, but these cover the common
/// learner pairs and keep the pickers manageable.
const List<AppLanguage> kSupportedLanguages = <AppLanguage>[
  AppLanguage('en', 'English', 'English'),
  AppLanguage('uk', 'Ukrainian', 'Українська'),
  AppLanguage('de', 'German', 'Deutsch'),
  AppLanguage('fr', 'French', 'Français'),
  AppLanguage('es', 'Spanish', 'Español'),
  AppLanguage('it', 'Italian', 'Italiano'),
  AppLanguage('pl', 'Polish', 'Polski'),
  AppLanguage('pt', 'Portuguese', 'Português'),
  AppLanguage('ru', 'Russian', 'Русский'),
  AppLanguage('nl', 'Dutch', 'Nederlands'),
  AppLanguage('cs', 'Czech', 'Čeština'),
  AppLanguage('tr', 'Turkish', 'Türkçe'),
];

/// Languages for which the bundled definition providers (Free Dictionary API,
/// Wiktionary) return monolingual definitions. Free Dictionary API is
/// English-only; Wiktionary REST covers more, but English is by far the most
/// complete, so we only advertise definitions for these codes.
const Set<String> kDefinitionLanguages = <String>{'en'};

/// Look up a language by code, falling back to a synthetic entry so unknown
/// codes (e.g. restored from old settings) still render.
AppLanguage languageForCode(String code) {
  for (final lang in kSupportedLanguages) {
    if (lang.code == code) return lang;
  }
  return AppLanguage(code, code.toUpperCase(), code.toUpperCase());
}

/// Default learning language (the language of the documents being read).
const String kDefaultLearningLang = 'en';

/// Default native language (the reader's own language).
const String kDefaultNativeLang = 'uk';
