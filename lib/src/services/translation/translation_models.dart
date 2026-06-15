/// Result of a translation lookup.
class TranslationResult {
  const TranslationResult({
    required this.translatedText,
    this.alternatives = const [],
    required this.providerId,
    this.attribution,
  });

  /// Best/primary translation.
  final String translatedText;

  /// Other candidate translations (deduplicated, excluding [translatedText]).
  final List<String> alternatives;

  /// Id of the provider that produced this result.
  final String providerId;

  /// Optional attribution string to display (license/source requirements).
  final String? attribution;

  Map<String, Object?> toJson() => {
    'translatedText': translatedText,
    'alternatives': alternatives,
    'providerId': providerId,
    'attribution': attribution,
  };

  static TranslationResult fromJson(Map<String, Object?> json) =>
      TranslationResult(
        translatedText: json['translatedText'] as String? ?? '',
        alternatives:
            (json['alternatives'] as List?)?.whereType<String>().toList() ??
            const [],
        providerId: json['providerId'] as String? ?? 'cache',
        attribution: json['attribution'] as String?,
      );
}

/// A part-of-speech grouping of definitions.
class DefinitionSense {
  const DefinitionSense({required this.partOfSpeech, required this.items});
  final String partOfSpeech;
  final List<DefinitionItem> items;

  Map<String, Object?> toJson() => {
    'partOfSpeech': partOfSpeech,
    'items': items.map((e) => e.toJson()).toList(),
  };

  static DefinitionSense fromJson(Map<String, Object?> json) => DefinitionSense(
    partOfSpeech: json['partOfSpeech'] as String? ?? '',
    items:
        (json['items'] as List?)
            ?.whereType<Map>()
            .map((e) => DefinitionItem.fromJson(e.cast<String, Object?>()))
            .toList() ??
        const [],
  );
}

/// A single sense/definition, optionally with an example sentence.
class DefinitionItem {
  const DefinitionItem({required this.definition, this.example});
  final String definition;
  final String? example;

  Map<String, Object?> toJson() => {
    'definition': definition,
    'example': example,
  };

  static DefinitionItem fromJson(Map<String, Object?> json) => DefinitionItem(
    definition: json['definition'] as String? ?? '',
    example: json['example'] as String?,
  );
}

/// Result of a monolingual definition lookup.
class DefinitionResult {
  const DefinitionResult({
    required this.word,
    this.phonetic,
    this.senses = const [],
    required this.providerId,
    this.attribution,
    this.audioUrl,
  });

  final String word;
  final String? phonetic;
  final List<DefinitionSense> senses;
  final String providerId;
  final String? attribution;
  final String? audioUrl;

  bool get isEmpty => senses.isEmpty;

  Map<String, Object?> toJson() => {
    'word': word,
    'phonetic': phonetic,
    'senses': senses.map((e) => e.toJson()).toList(),
    'providerId': providerId,
    'attribution': attribution,
    'audioUrl': audioUrl,
  };

  static DefinitionResult fromJson(Map<String, Object?> json) =>
      DefinitionResult(
        word: json['word'] as String? ?? '',
        phonetic: json['phonetic'] as String?,
        senses:
            (json['senses'] as List?)
                ?.whereType<Map>()
                .map((e) => DefinitionSense.fromJson(e.cast<String, Object?>()))
                .toList() ??
            const [],
        providerId: json['providerId'] as String? ?? 'cache',
        attribution: json['attribution'] as String?,
        audioUrl: json['audioUrl'] as String?,
      );
}

/// Raised when a provider cannot fulfil a request (network error, quota, key
/// missing, word not found, …). The [TranslationService] uses it to decide
/// whether to fall back to another provider.
class ProviderException implements Exception {
  const ProviderException(
    this.message, {
    this.notFound = false,
    this.needsConfiguration = false,
  });

  final String message;

  /// True when the lookup simply found nothing (e.g. HTTP 404), as opposed to a
  /// transport/quota failure.
  final bool notFound;

  /// True when the provider is missing required configuration (e.g. API key or
  /// instance URL), so the UI can guide the user to settings.
  final bool needsConfiguration;

  @override
  String toString() => 'ProviderException: $message';
}
