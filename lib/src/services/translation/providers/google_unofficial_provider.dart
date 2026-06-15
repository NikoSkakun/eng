import 'dart:convert';

import 'package:http/http.dart' as http;

import '../translation_models.dart';
import '../translation_provider.dart';

/// Unofficial Google Translate endpoint (`translate_a/single`).
///
/// Keyless and high quality, but undocumented and unsupported by Google: it can
/// be rate-limited or changed without notice, and use likely violates Google's
/// ToS. Opt-in only — never the default.
class GoogleUnofficialProvider implements TranslationProvider {
  GoogleUnofficialProvider(this._client);

  final http.Client _client;

  @override
  String get id => 'google';

  @override
  String get name => 'Google (unofficial)';

  @override
  bool get requiresConfiguration => false;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String from,
    required String to,
  }) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': from,
      'tl': to,
      'dt': 't',
      'q': text,
    });
    final http.Response resp;
    try {
      resp = await _client.get(uri);
    } catch (e) {
      throw ProviderException('Network error contacting Google: $e');
    }
    if (resp.statusCode != 200) {
      throw ProviderException(
        'Google endpoint returned HTTP ${resp.statusCode}',
      );
    }
    // Response shape: [ [ [translatedChunk, sourceChunk, ...], ... ], ... ]
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is! List || data.isEmpty || data[0] is! List) {
      throw const ProviderException(
        'Unexpected response from Google endpoint.',
      );
    }
    final buffer = StringBuffer();
    for (final segment in data[0] as List) {
      if (segment is List && segment.isNotEmpty && segment[0] is String) {
        buffer.write(segment[0] as String);
      }
    }
    final translated = buffer.toString().trim();
    if (translated.isEmpty) {
      throw const ProviderException('Google endpoint returned no translation.');
    }
    return TranslationResult(
      translatedText: translated,
      providerId: id,
      attribution: 'Translation by Google',
    );
  }
}
