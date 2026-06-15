import 'dart:convert';

import 'package:http/http.dart' as http;

import '../translation_models.dart';
import '../translation_provider.dart';

/// MyMemory translation API — keyless, supports en<->uk and many pairs.
///
/// `GET https://api.mymemory.translated.net/get?q=..&langpair=en|uk&de=email`
/// An email (optional) raises the anonymous quota from 5k to 50k chars/day.
/// Per-request text is capped at ~500 bytes, which is fine for words/phrases.
class MyMemoryProvider implements TranslationProvider {
  MyMemoryProvider(this._client, {this.email = ''});

  final http.Client _client;
  final String email;

  @override
  String get id => 'mymemory';

  @override
  String get name => 'MyMemory';

  @override
  bool get requiresConfiguration => false;

  @override
  Future<TranslationResult> translate({
    required String text,
    required String from,
    required String to,
  }) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': text,
      'langpair': '$from|$to',
      if (email.trim().isNotEmpty) 'de': email.trim(),
    });
    final http.Response resp;
    try {
      resp = await _client.get(uri);
    } catch (e) {
      throw ProviderException('Network error contacting MyMemory: $e');
    }
    if (resp.statusCode != 200) {
      throw ProviderException('MyMemory returned HTTP ${resp.statusCode}');
    }
    final json =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, Object?>;
    final status = json['responseStatus'];
    final statusOk = status == 200 || status == '200';
    final data = json['responseData'] as Map<String, Object?>?;
    final primary = (data?['translatedText'] as String?)?.trim() ?? '';
    if (!statusOk || primary.isEmpty) {
      final detail = json['responseDetails']?.toString() ?? 'no translation';
      throw ProviderException('MyMemory: $detail');
    }

    final alternatives = <String>[];
    final matches = json['matches'];
    if (matches is List) {
      for (final m in matches) {
        if (m is Map) {
          final t = (m['translation'] as String?)?.trim();
          if (t != null &&
              t.isNotEmpty &&
              t.toLowerCase() != primary.toLowerCase() &&
              !alternatives.contains(t)) {
            alternatives.add(t);
          }
        }
      }
    }

    return TranslationResult(
      translatedText: primary,
      alternatives: alternatives.take(6).toList(),
      providerId: id,
      attribution: 'Translation by MyMemory',
    );
  }
}
