import 'package:shared_preferences/shared_preferences.dart';

import '../util/languages.dart';

/// Identifiers for the available translation providers.
enum TranslationProviderId {
  myMemory('mymemory', 'MyMemory (free, no key)'),
  libreTranslate('libretranslate', 'LibreTranslate (self-host / mirror)'),
  deepL('deepl', 'DeepL (your API key)'),
  googleUnofficial('google', 'Google (unofficial, no key)');

  const TranslationProviderId(this.id, this.label);
  final String id;
  final String label;

  static TranslationProviderId fromId(String id) => values.firstWhere(
    (e) => e.id == id,
    orElse: () => TranslationProviderId.myMemory,
  );
}

/// Identifiers for the available definition providers.
enum DefinitionProviderId {
  dictionaryApi('dictionaryapi', 'Free Dictionary API (English)'),
  wiktionary('wiktionary', 'Wiktionary'),
  none('none', 'None');

  const DefinitionProviderId(this.id, this.label);
  final String id;
  final String label;

  static DefinitionProviderId fromId(String id) => values.firstWhere(
    (e) => e.id == id,
    orElse: () => DefinitionProviderId.dictionaryApi,
  );
}

/// Default highlight color (semi-transparent amber). ARGB.
const int kDefaultHighlightColor = 0x66FFC107;

/// Default color (opaque blue) for the small inline translations shown under
/// highlighted words.
const int kDefaultInlineGlossColor = 0xFF1565C0;

/// Immutable snapshot of all user settings.
class AppSettings {
  const AppSettings({
    this.learningLang = kDefaultLearningLang,
    this.nativeLang = kDefaultNativeLang,
    this.translationProvider = TranslationProviderId.myMemory,
    this.definitionProvider = DefinitionProviderId.dictionaryApi,
    this.myMemoryEmail = '',
    this.deepLApiKey = '',
    this.libreTranslateUrl = '',
    this.libreTranslateApiKey = '',
    this.highlightingEnabled = true,
    this.autoSuggestEnabled = true,
    this.highlightColor = kDefaultHighlightColor,
    this.inlineTranslationEnabled = false,
    this.inlineGlossColor = kDefaultInlineGlossColor,
  });

  /// Language of the documents being read (and of definitions).
  final String learningLang;

  /// The reader's own language (translation target).
  final String nativeLang;

  final TranslationProviderId translationProvider;
  final DefinitionProviderId definitionProvider;

  /// Optional email to raise MyMemory's anonymous quota (5k -> 50k chars/day).
  final String myMemoryEmail;

  final String deepLApiKey;

  /// Base URL of a LibreTranslate instance, e.g. `https://translate.example.org`.
  final String libreTranslateUrl;
  final String libreTranslateApiKey;

  final bool highlightingEnabled;
  final bool autoSuggestEnabled;

  /// 32-bit ARGB color used for highlights without a per-entry color.
  final int highlightColor;

  /// Whether to render each highlighted term's translation in a small font
  /// just under the word (interlinear gloss).
  final bool inlineTranslationEnabled;

  /// 32-bit ARGB color of the inline translation glosses.
  final int inlineGlossColor;

  /// Whether definitions can be looked up given the current learning language.
  bool get definitionsAvailable =>
      definitionProvider != DefinitionProviderId.none &&
      kDefinitionLanguages.contains(learningLang);

  AppSettings copyWith({
    String? learningLang,
    String? nativeLang,
    TranslationProviderId? translationProvider,
    DefinitionProviderId? definitionProvider,
    String? myMemoryEmail,
    String? deepLApiKey,
    String? libreTranslateUrl,
    String? libreTranslateApiKey,
    bool? highlightingEnabled,
    bool? autoSuggestEnabled,
    int? highlightColor,
    bool? inlineTranslationEnabled,
    int? inlineGlossColor,
  }) {
    return AppSettings(
      learningLang: learningLang ?? this.learningLang,
      nativeLang: nativeLang ?? this.nativeLang,
      translationProvider: translationProvider ?? this.translationProvider,
      definitionProvider: definitionProvider ?? this.definitionProvider,
      myMemoryEmail: myMemoryEmail ?? this.myMemoryEmail,
      deepLApiKey: deepLApiKey ?? this.deepLApiKey,
      libreTranslateUrl: libreTranslateUrl ?? this.libreTranslateUrl,
      libreTranslateApiKey: libreTranslateApiKey ?? this.libreTranslateApiKey,
      highlightingEnabled: highlightingEnabled ?? this.highlightingEnabled,
      autoSuggestEnabled: autoSuggestEnabled ?? this.autoSuggestEnabled,
      highlightColor: highlightColor ?? this.highlightColor,
      inlineTranslationEnabled:
          inlineTranslationEnabled ?? this.inlineTranslationEnabled,
      inlineGlossColor: inlineGlossColor ?? this.inlineGlossColor,
    );
  }
}

/// Reads/writes [AppSettings] through [SharedPreferences].
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kLearningLang = 'learningLang';
  static const _kNativeLang = 'nativeLang';
  static const _kTranslationProvider = 'translationProvider';
  static const _kDefinitionProvider = 'definitionProvider';
  static const _kMyMemoryEmail = 'myMemoryEmail';
  static const _kDeepLKey = 'deepLApiKey';
  static const _kLibreUrl = 'libreTranslateUrl';
  static const _kLibreKey = 'libreTranslateApiKey';
  static const _kHighlighting = 'highlightingEnabled';
  static const _kAutoSuggest = 'autoSuggestEnabled';
  static const _kHighlightColor = 'highlightColor';
  static const _kInlineTranslation = 'inlineTranslationEnabled';
  static const _kInlineGlossColor = 'inlineGlossColor';

  AppSettings load() {
    return AppSettings(
      learningLang: _prefs.getString(_kLearningLang) ?? kDefaultLearningLang,
      nativeLang: _prefs.getString(_kNativeLang) ?? kDefaultNativeLang,
      translationProvider: TranslationProviderId.fromId(
        _prefs.getString(_kTranslationProvider) ?? '',
      ),
      definitionProvider: DefinitionProviderId.fromId(
        _prefs.getString(_kDefinitionProvider) ?? '',
      ),
      myMemoryEmail: _prefs.getString(_kMyMemoryEmail) ?? '',
      deepLApiKey: _prefs.getString(_kDeepLKey) ?? '',
      libreTranslateUrl: _prefs.getString(_kLibreUrl) ?? '',
      libreTranslateApiKey: _prefs.getString(_kLibreKey) ?? '',
      highlightingEnabled: _prefs.getBool(_kHighlighting) ?? true,
      autoSuggestEnabled: _prefs.getBool(_kAutoSuggest) ?? true,
      highlightColor: _prefs.getInt(_kHighlightColor) ?? kDefaultHighlightColor,
      inlineTranslationEnabled: _prefs.getBool(_kInlineTranslation) ?? false,
      inlineGlossColor:
          _prefs.getInt(_kInlineGlossColor) ?? kDefaultInlineGlossColor,
    );
  }

  Future<void> save(AppSettings s) async {
    await _prefs.setString(_kLearningLang, s.learningLang);
    await _prefs.setString(_kNativeLang, s.nativeLang);
    await _prefs.setString(_kTranslationProvider, s.translationProvider.id);
    await _prefs.setString(_kDefinitionProvider, s.definitionProvider.id);
    await _prefs.setString(_kMyMemoryEmail, s.myMemoryEmail);
    await _prefs.setString(_kDeepLKey, s.deepLApiKey);
    await _prefs.setString(_kLibreUrl, s.libreTranslateUrl);
    await _prefs.setString(_kLibreKey, s.libreTranslateApiKey);
    await _prefs.setBool(_kHighlighting, s.highlightingEnabled);
    await _prefs.setBool(_kAutoSuggest, s.autoSuggestEnabled);
    await _prefs.setInt(_kHighlightColor, s.highlightColor);
    await _prefs.setBool(_kInlineTranslation, s.inlineTranslationEnabled);
    await _prefs.setInt(_kInlineGlossColor, s.inlineGlossColor);
  }
}
