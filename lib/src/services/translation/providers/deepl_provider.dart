import 'dart:convert';

import 'package:http/http.dart' as http;

import '../translation_models.dart';
import '../translation_provider.dart';

/// DeepL translation — highest quality, requires a user-supplied API key.
///
/// Free keys (suffixed `:fx`) use `api-free.deepl.com`; paid keys use
/// `api.deepl.com`. Ukrainian is supported (`target_lang=UK`).
class DeepLProvider implements TranslationProvider {
  DeepLProvider(this._client, {required this.apiKey});

  final http.Client _client;
  final String apiKey;

  @override
  String get id => 'deepl';

  @override
  String get name => 'DeepL';

  @override
  bool get requiresConfiguration => true;

  bool get _isFreeKey => apiKey.trim().endsWith(':fx');

  @override
  Future<TranslationResult> translate({
    required String text,
    required String from,
    required String to,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const ProviderException(
        'DeepL API key is not set.',
        needsConfiguration: true,
      );
    }
    final host = _isFreeKey ? 'api-free.deepl.com' : 'api.deepl.com';
    final uri = Uri.https(host, '/v2/translate');
    final http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: {
          'Authorization': 'DeepL-Auth-Key $key',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'text': text,
          'source_lang': from.toUpperCase(),
          'target_lang': to.toUpperCase(),
        },
      );
    } catch (e) {
      throw ProviderException('Network error contacting DeepL: $e');
    }
    if (resp.statusCode == 403) {
      throw const ProviderException(
        'DeepL rejected the API key.',
        needsConfiguration: true,
      );
    }
    if (resp.statusCode != 200) {
      throw ProviderException('DeepL returned HTTP ${resp.statusCode}');
    }
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, Object?>;
    final translations = json['translations'];
    if (translations is! List || translations.isEmpty) {
      throw const ProviderException('DeepL returned no translation.');
    }
    final text0 =
        ((translations.first as Map)['text'] as String?)?.trim() ?? '';
    if (text0.isEmpty) {
      throw const ProviderException('DeepL returned an empty translation.');
    }
    return TranslationResult(
      translatedText: text0,
      providerId: id,
      attribution: 'Translation by DeepL',
    );
  }
}
