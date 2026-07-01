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

/// A fully transparent ARGB value, used as the "no color" / no-highlight choice.
const int kNoColor = 0x00000000;

/// Default highlight color (semi-transparent amber). ARGB.
const int kDefaultHighlightColor = 0x66FFC107;

/// Default color (opaque blue) for the small inline translations shown under
/// highlighted words.
const int kDefaultInlineGlossColor = 0xFF1565C0;

/// Color of the small corner dot marking a term that has more than one
/// translation variant. Opaque so it reads over any page background or
/// highlight fill.
const int kVariantMarkerColor = 0xFF1565C0;

/// Default background behind the inline gloss text: none (transparent).
const int kDefaultInlineGlossBgColor = kNoColor;

/// Default inline gloss font size as a fraction of the highlighted word height.
const double kDefaultInlineGlossFontScale = 0.46;

/// Default mouse-wheel scroll speed: a multiplier applied to the raw wheel
/// delta. pdfrx's own default is 0.2; we bump it a little so scrolling feels
/// snappier out of the box, and expose it as a setting for further tuning.
const double kDefaultScrollSensitivity = 0.3;

/// Horizontal alignment of the inline gloss relative to its highlighted word.
enum GlossAlignment {
  left('left'),
  center('center'),
  right('right');

  const GlossAlignment(this.id);
  final String id;

  static GlossAlignment fromId(String id) =>
      values.firstWhere((e) => e.id == id, orElse: () => GlossAlignment.left);
}

/// Whether an ARGB value is fully transparent (the "none" highlight choice).
bool isNoColor(int argb) => (argb >> 24 & 0xff) == 0;

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
    this.inlineGlossBgColor = kDefaultInlineGlossBgColor,
    this.inlineGlossFontScale = kDefaultInlineGlossFontScale,
    this.inlineGlossLetterSpacing = 0.0,
    this.inlineGlossVerticalOffset = 0.0,
    this.inlineGlossAlignment = GlossAlignment.left,
    this.scrollSensitivity = kDefaultScrollSensitivity,
    this.joinCopiedLines = true,
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

  /// 32-bit ARGB color of the inline translation glosses (text color).
  final int inlineGlossColor;

  /// 32-bit ARGB background drawn behind each inline gloss. Transparent = none.
  final int inlineGlossBgColor;

  /// Inline gloss font size as a fraction of the highlighted word's height.
  final double inlineGlossFontScale;

  /// Extra spacing (logical px) between gloss characters.
  final double inlineGlossLetterSpacing;

  /// Vertical position of the gloss as a fraction of the word height, measured
  /// from the word's bottom edge. 0 sits just below; negative overlaps upward.
  final double inlineGlossVerticalOffset;

  /// Horizontal alignment of the gloss relative to its highlighted word.
  final GlossAlignment inlineGlossAlignment;

  /// Mouse-wheel scroll speed: a multiplier on the raw wheel delta. Higher
  /// scrolls farther per notch; pdfrx's untouched default is 0.2.
  final double scrollSensitivity;

  /// When copying text spanning multiple lines, join the lines into continuous
  /// text (newlines -> spaces) and repair words split by a line-break hyphen.
  final bool joinCopiedLines;

  /// Whether definitions can be looked up given the current learning language.
  bool get definitionsAvailable =>
      definitionProvider != DefinitionProviderId.none &&
      kDefinitionLanguages.contains(learningLang);

  /// Whether DeepL is the active translation provider and has a usable API key.
  /// Gates the in-context (paragraph) translation shown in the add-entry sheet.
  bool get deepLEnabled =>
      translationProvider == TranslationProviderId.deepL &&
      deepLApiKey.trim().isNotEmpty;

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
    int? inlineGlossBgColor,
    double? inlineGlossFontScale,
    double? inlineGlossLetterSpacing,
    double? inlineGlossVerticalOffset,
    GlossAlignment? inlineGlossAlignment,
    double? scrollSensitivity,
    bool? joinCopiedLines,
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
      inlineGlossBgColor: inlineGlossBgColor ?? this.inlineGlossBgColor,
      inlineGlossFontScale: inlineGlossFontScale ?? this.inlineGlossFontScale,
      inlineGlossLetterSpacing:
          inlineGlossLetterSpacing ?? this.inlineGlossLetterSpacing,
      inlineGlossVerticalOffset:
          inlineGlossVerticalOffset ?? this.inlineGlossVerticalOffset,
      inlineGlossAlignment: inlineGlossAlignment ?? this.inlineGlossAlignment,
      scrollSensitivity: scrollSensitivity ?? this.scrollSensitivity,
      joinCopiedLines: joinCopiedLines ?? this.joinCopiedLines,
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
  static const _kInlineGlossBgColor = 'inlineGlossBgColor';
  static const _kInlineGlossFontScale = 'inlineGlossFontScale';
  static const _kInlineGlossLetterSpacing = 'inlineGlossLetterSpacing';
  static const _kInlineGlossVerticalOffset = 'inlineGlossVerticalOffset';
  static const _kInlineGlossAlignment = 'inlineGlossAlignment';
  static const _kScrollSensitivity = 'scrollSensitivity';
  static const _kJoinCopiedLines = 'joinCopiedLines';

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
      inlineGlossBgColor:
          _prefs.getInt(_kInlineGlossBgColor) ?? kDefaultInlineGlossBgColor,
      inlineGlossFontScale:
          _prefs.getDouble(_kInlineGlossFontScale) ??
          kDefaultInlineGlossFontScale,
      inlineGlossLetterSpacing:
          _prefs.getDouble(_kInlineGlossLetterSpacing) ?? 0.0,
      inlineGlossVerticalOffset:
          _prefs.getDouble(_kInlineGlossVerticalOffset) ?? 0.0,
      inlineGlossAlignment: GlossAlignment.fromId(
        _prefs.getString(_kInlineGlossAlignment) ?? '',
      ),
      scrollSensitivity:
          _prefs.getDouble(_kScrollSensitivity) ?? kDefaultScrollSensitivity,
      joinCopiedLines: _prefs.getBool(_kJoinCopiedLines) ?? true,
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
    await _prefs.setInt(_kInlineGlossBgColor, s.inlineGlossBgColor);
    await _prefs.setDouble(_kInlineGlossFontScale, s.inlineGlossFontScale);
    await _prefs.setDouble(
      _kInlineGlossLetterSpacing,
      s.inlineGlossLetterSpacing,
    );
    await _prefs.setDouble(
      _kInlineGlossVerticalOffset,
      s.inlineGlossVerticalOffset,
    );
    await _prefs.setString(_kInlineGlossAlignment, s.inlineGlossAlignment.id);
    await _prefs.setDouble(_kScrollSensitivity, s.scrollSensitivity);
    await _prefs.setBool(_kJoinCopiedLines, s.joinCopiedLines);
  }
}
