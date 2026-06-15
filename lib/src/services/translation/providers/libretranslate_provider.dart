import 'dart:convert';

import 'package:http/http.dart' as http;

import '../translation_models.dart';
import '../translation_provider.dart';

/// LibreTranslate — open-source MT. Self-hosted instances need no key; the
/// flagship libretranslate.com now requires one. Configure the base URL (and
/// optional key) in settings.
///
/// `POST {baseUrl}/translate` with JSON `{q, source, target, format, api_key}`.
class LibreTranslateProvider implements TranslationProvider {
  LibreTranslateProvider(
    this._client, {
    required this.baseUrl,
    this.apiKey = '',
  });

  final http.Client _client;
  final String baseUrl;
  final String apiKey;

  @override
  String get id => 'libretranslate';

  @override
  String get name => 'LibreTranslate';

  @override
  bool get requiresConfiguration => true;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String from,
    required String to,
  }) async {
    final base = baseUrl.trim();
    if (base.isEmpty) {
      throw const ProviderException(
        'LibreTranslate URL is not set.',
        needsConfiguration: true,
      );
    }
    final uri = Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/translate');
    final http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': text,
          'source': from,
          'target': to,
          'format': 'text',
          if (apiKey.trim().isNotEmpty) 'api_key': apiKey.trim(),
        }),
      );
    } catch (e) {
      throw ProviderException('Network error contacting LibreTranslate: $e');
    }
    if (resp.statusCode != 200) {
      // The body may be a JSON error or an HTML/proxy page; don't let a parse
      // failure mask the real HTTP status.
      var detail = 'HTTP ${resp.statusCode}';
      try {
        final err = jsonDecode(utf8.decode(resp.bodyBytes));
        if (err is Map && err['error'] != null) {
          detail = err['error'].toString();
        }
      } catch (_) {
        // Non-JSON error body; keep the HTTP status as the detail.
      }
      throw ProviderException(
        'LibreTranslate: $detail',
        needsConfiguration: resp.statusCode == 403,
      );
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (e) {
      throw ProviderException('LibreTranslate sent a malformed response: $e');
    }
    final translated =
        (body is Map ? body['translatedText'] as String? : null)?.trim() ?? '';
    if (translated.isEmpty) {
      throw const ProviderException('LibreTranslate returned no translation.');
    }
    return TranslationResult(
      translatedText: translated,
      providerId: id,
      attribution: 'Translation by LibreTranslate',
    );
  }
}
