import '../text/text_normalizer.dart';

/// A user's dictionary entry: a term (word or phrase) the reader is learning,
/// together with its translation and/or definition.
///
/// Entries are *shared* by default: when [scopeDocumentId] is null the term is
/// highlighted across every document in the library. Setting it to a document
/// id scopes the highlight (and lookup) to that single document.
class DictionaryEntry {
  DictionaryEntry({
    required this.id,
    required this.term,
    required this.sourceLang,
    required this.targetLang,
    this.translation,
    this.alternativeTranslations = const [],
    this.definition,
    this.notes,
    this.highlightEnabled = true,
    this.colorValue,
    this.matchPartial = false,
    this.sourceWord,
    this.scopeDocumentId,
    required this.createdAt,
    required this.updatedAt,
  }) : normalizedTerm = TextNormalizer.normalizeKey(term);

  /// Row id (`0` for an entry not yet persisted).
  final int id;

  /// Original surface form of the term as entered or selected.
  final String term;

  /// Canonical key used for matching and de-duplication.
  final String normalizedTerm;

  /// Language of [term] (the learning language), ISO 639-1.
  final String sourceLang;

  /// Language of [translation] (the native language), ISO 639-1.
  final String targetLang;

  /// User-confirmed (or suggested-then-kept) primary translation.
  final String? translation;

  /// Additional accepted translations for the same term, shown alongside the
  /// primary one and used to mark the term as having several variants. Order is
  /// the user's; never null (empty when there are none).
  final List<String> alternativeTranslations;

  /// User definition or a looked-up monolingual definition.
  final String? definition;

  /// Free-form notes.
  final String? notes;

  /// Whether this term participates in auto-highlighting.
  final bool highlightEnabled;

  /// Optional per-entry highlight color as a 32-bit ARGB value. When null the
  /// app-wide default color is used.
  final int? colorValue;

  /// When true, a single-word term also matches as a *part* of longer words at
  /// sub-word boundaries (prefix, suffix, or a hyphen/apostrophe-delimited
  /// component) — so "perturbation" also highlights inside "perturbations" and
  /// "small-perturbation". Only meaningful for single-word terms.
  final bool matchPartial;

  /// The word the term was originally selected from, when it was created from a
  /// partial in-word selection (e.g. selecting "perturbation" inside
  /// "perturbations" stores "perturbations" here). Informational.
  final String? sourceWord;

  /// When set, the entry only applies to the document with this id.
  final int? scopeDocumentId;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isGlobal => scopeDocumentId == null;

  /// Every translation to display, primary first, trimmed and de-duplicated
  /// case-insensitively (empties removed). Falls back to the alternatives when
  /// no primary is set, so display code never has to special-case that.
  List<String> get allTranslations {
    final out = <String>[];
    final seen = <String>{};
    for (final t in [?translation, ...alternativeTranslations]) {
      final s = t.trim();
      if (s.isEmpty) continue;
      if (seen.add(s.toLowerCase())) out.add(s);
    }
    return out;
  }

  /// Whether the term carries more than one translation variant — the signal
  /// used to mark it in the readers.
  bool get hasMultipleTranslations => allTranslations.length > 1;

  /// The single translation to render inline (interlinear gloss): the primary.
  String? get glossText {
    final all = allTranslations;
    return all.isEmpty ? null : all.first;
  }

  bool get hasContent =>
      allTranslations.isNotEmpty || (definition?.trim().isNotEmpty ?? false);

  DictionaryEntry copyWith({
    int? id,
    String? term,
    String? sourceLang,
    String? targetLang,
    Object? translation = _sentinel,
    List<String>? alternativeTranslations,
    Object? definition = _sentinel,
    Object? notes = _sentinel,
    bool? highlightEnabled,
    Object? colorValue = _sentinel,
    bool? matchPartial,
    Object? sourceWord = _sentinel,
    Object? scopeDocumentId = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DictionaryEntry(
      id: id ?? this.id,
      term: term ?? this.term,
      sourceLang: sourceLang ?? this.sourceLang,
      targetLang: targetLang ?? this.targetLang,
      translation: translation == _sentinel
          ? this.translation
          : translation as String?,
      alternativeTranslations:
          alternativeTranslations ?? this.alternativeTranslations,
      definition: definition == _sentinel
          ? this.definition
          : definition as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      highlightEnabled: highlightEnabled ?? this.highlightEnabled,
      colorValue: colorValue == _sentinel
          ? this.colorValue
          : colorValue as int?,
      matchPartial: matchPartial ?? this.matchPartial,
      sourceWord: sourceWord == _sentinel
          ? this.sourceWord
          : sourceWord as String?,
      scopeDocumentId: scopeDocumentId == _sentinel
          ? this.scopeDocumentId
          : scopeDocumentId as int?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const Object _sentinel = Object();
}
