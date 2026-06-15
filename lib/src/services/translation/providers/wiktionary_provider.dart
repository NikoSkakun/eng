import 'dart:convert';

import 'package:http/http.dart' as http;

import '../translation_models.dart';
import '../translation_provider.dart';

/// Wiktionary REST definition endpoint — keyless fallback for definitions.
///
/// `GET https://<lang>.wiktionary.org/api/rest_v1/page/definition/<word>`
/// Returns an object keyed by language code; definitions are HTML and must be
/// sanitized. Wikimedia etiquette requires a descriptive User-Agent.
class WiktionaryProvider implements DefinitionProvider {
  WiktionaryProvider(this._client);

  final http.Client _client;

  static const _userAgent =
      'eng-reader/1.0 (Flutter language-learning reader; contact: in-app)';

  @override
  String get id => 'wiktionary';

  @override
  String get name => 'Wiktionary';

  @override
  Future<DefinitionResult> define({
    required String word,
    required String lang,
  }) async {
    final uri = Uri.https(
      '$lang.wiktionary.org',
      '/api/rest_v1/page/definition/${Uri.encodeComponent(word)}',
    );
    final http.Response resp;
    try {
      resp = await _client.get(
        uri,
        headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
      );
    } catch (e) {
      throw ProviderException('Network error contacting Wiktionary: $e');
    }
    if (resp.statusCode == 404) {
      throw ProviderException(
        'No Wiktionary entry for "$word".',
        notFound: true,
      );
    }
    if (resp.statusCode != 200) {
      throw ProviderException('Wiktionary returned HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! Map) {
      throw ProviderException(
        'No Wiktionary entry for "$word".',
        notFound: true,
      );
    }
    // Prefer definitions in the requested language; fall back to any present.
    final List<dynamic>? entries =
        (data[lang] as List?) ??
        (data.values.firstWhere((v) => v is List, orElse: () => null) as List?);
    if (entries == null || entries.isEmpty) {
      throw ProviderException(
        'No Wiktionary entry for "$word".',
        notFound: true,
      );
    }

    final senses = <DefinitionSense>[];
    for (final e in entries) {
      if (e is! Map) continue;
      final pos = (e['partOfSpeech'] as String?)?.trim() ?? '';
      final defs = e['definitions'];
      final items = <DefinitionItem>[];
      if (defs is List) {
        for (final d in defs) {
          if (d is! Map) continue;
          final def = _stripHtml((d['definition'] as String?) ?? '');
          if (def.isEmpty) continue;
          String? example;
          final examples = d['examples'];
          if (examples is List && examples.isNotEmpty) {
            example = _stripHtml(examples.first.toString());
          }
          items.add(DefinitionItem(definition: def, example: example));
        }
      }
      if (items.isNotEmpty) {
        senses.add(DefinitionSense(partOfSpeech: pos, items: items));
      }
    }
    if (senses.isEmpty) {
      throw ProviderException(
        'No Wiktionary entry for "$word".',
        notFound: true,
      );
    }
    return DefinitionResult(
      word: word,
      senses: senses,
      providerId: id,
      attribution: 'Definitions: Wiktionary (CC BY-SA)',
    );
  }

  static final _tagPattern = RegExp(r'<[^>]*>');

  /// Strip HTML tags and decode the handful of entities Wiktionary emits.
  static String _stripHtml(String html) {
    var text = html.replaceAll(_tagPattern, '');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return text.trim();
  }
}
