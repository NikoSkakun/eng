import 'dart:convert';

import 'package:http/http.dart' as http;

import '../translation_models.dart';
import '../translation_provider.dart';

/// Free Dictionary API (dictionaryapi.dev) — keyless English definitions.
///
/// `GET https://api.dictionaryapi.dev/api/v2/entries/en/<word>`
/// Returns an array of entries; 404 means the word has no entry. Data is
/// sourced from Wiktionary under CC BY-SA.
class DictionaryApiProvider implements DefinitionProvider {
  DictionaryApiProvider(this._client);

  final http.Client _client;

  @override
  String get id => 'dictionaryapi';

  @override
  String get name => 'Free Dictionary API';

  @override
  Future<DefinitionResult> define({
    required String word,
    required String lang,
  }) async {
    final uri = Uri.https(
      'api.dictionaryapi.dev',
      '/api/v2/entries/$lang/${Uri.encodeComponent(word)}',
    );
    final http.Response resp;
    try {
      resp = await _client.get(uri);
    } catch (e) {
      throw ProviderException('Network error contacting the dictionary: $e');
    }
    if (resp.statusCode == 404) {
      throw ProviderException(
        'No definition found for "$word".',
        notFound: true,
      );
    }
    if (resp.statusCode != 200) {
      throw ProviderException(
        'Dictionary API returned HTTP ${resp.statusCode}',
      );
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! List || data.isEmpty) {
      throw ProviderException(
        'No definition found for "$word".',
        notFound: true,
      );
    }

    String? phonetic;
    String? audioUrl;
    final senses = <DefinitionSense>[];

    for (final entryRaw in data) {
      if (entryRaw is! Map) continue;
      phonetic ??= (entryRaw['phonetic'] as String?)?.trim();
      final phonetics = entryRaw['phonetics'];
      if (phonetics is List) {
        for (final p in phonetics) {
          if (p is Map) {
            phonetic ??= (p['text'] as String?)?.trim();
            final a = (p['audio'] as String?)?.trim();
            if (audioUrl == null && a != null && a.isNotEmpty) audioUrl = a;
          }
        }
      }
      final meanings = entryRaw['meanings'];
      if (meanings is List) {
        for (final m in meanings) {
          if (m is! Map) continue;
          final pos = (m['partOfSpeech'] as String?)?.trim() ?? '';
          final defs = m['definitions'];
          final items = <DefinitionItem>[];
          if (defs is List) {
            for (final d in defs) {
              if (d is! Map) continue;
              final def = (d['definition'] as String?)?.trim();
              if (def == null || def.isEmpty) continue;
              items.add(
                DefinitionItem(
                  definition: def,
                  example: (d['example'] as String?)?.trim(),
                ),
              );
            }
          }
          if (items.isNotEmpty) {
            senses.add(DefinitionSense(partOfSpeech: pos, items: items));
          }
        }
      }
    }

    if (senses.isEmpty) {
      throw ProviderException(
        'No definition found for "$word".',
        notFound: true,
      );
    }

    return DefinitionResult(
      word: word,
      phonetic: (phonetic?.isEmpty ?? true) ? null : phonetic,
      senses: senses,
      providerId: id,
      attribution: 'Definitions: Wiktionary (CC BY-SA) via dictionaryapi.dev',
      audioUrl: audioUrl,
    );
  }
}
