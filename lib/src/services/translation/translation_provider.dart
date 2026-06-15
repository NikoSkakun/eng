import 'translation_models.dart';

/// Translates text from one language to another.
abstract interface class TranslationProvider {
  String get id;
  String get name;

  /// Whether the provider needs user-supplied configuration (API key/URL).
  bool get requiresConfiguration;

  /// Translate [text] from [from] to [to] (ISO 639-1 codes).
  ///
  /// Throws [ProviderException] on failure.
  Future<TranslationResult> translate({
    required String text,
    required String from,
    required String to,
  });
}

/// Provides monolingual definitions of a word.
abstract interface class DefinitionProvider {
  String get id;
  String get name;

  /// Look up [word] in language [lang]. Throws [ProviderException] (with
  /// `notFound: true` when the word simply has no entry).
  Future<DefinitionResult> define({required String word, required String lang});
}
