import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/cache_repository.dart';
import '../../data/settings_store.dart';
import 'providers/deepl_provider.dart';
import 'providers/dictionary_api_provider.dart';
import 'providers/google_unofficial_provider.dart';
import 'providers/libretranslate_provider.dart';
import 'providers/mymemory_provider.dart';
import 'providers/wiktionary_provider.dart';
import 'translation_models.dart';
import 'translation_provider.dart';

/// Orchestrates translation and definition providers based on [AppSettings],
/// with a keyless fallback and an on-disk cache.
///
/// A new instance is created whenever settings change (so it always reflects
/// the current provider/keys), which is why it holds an immutable snapshot.
class TranslationService {
  TranslationService(this.settings, this._cache, this._client);

  final AppSettings settings;
  final CacheRepository _cache;
  final http.Client _client;

  /// How long a "no definition found" result is cached before re-checking.
  static const int _negativeDefinitionTtlMs = 24 * 60 * 60 * 1000; // 1 day

  TranslationProvider _primaryTranslationProvider() =>
      _buildTranslationProvider(settings.translationProvider);

  /// Construct the provider for [id] using the current settings (keys/URLs).
  TranslationProvider _buildTranslationProvider(TranslationProviderId id) {
    switch (id) {
      case TranslationProviderId.myMemory:
        return MyMemoryProvider(_client, email: settings.myMemoryEmail);
      case TranslationProviderId.libreTranslate:
        return LibreTranslateProvider(
          _client,
          baseUrl: settings.libreTranslateUrl,
          apiKey: settings.libreTranslateApiKey,
        );
      case TranslationProviderId.deepL:
        return DeepLProvider(_client, apiKey: settings.deepLApiKey);
      case TranslationProviderId.googleUnofficial:
        return GoogleUnofficialProvider(_client);
    }
  }

  DefinitionProvider? _primaryDefinitionProvider() {
    switch (settings.definitionProvider) {
      case DefinitionProviderId.dictionaryApi:
        return DictionaryApiProvider(_client);
      case DefinitionProviderId.wiktionary:
        return WiktionaryProvider(_client);
      case DefinitionProviderId.none:
        return null;
    }
  }

  /// Translate [text] (default langs come from settings). Tries the configured
  /// provider, then keyless MyMemory as a fallback, and caches the result.
  ///
  /// Throws [ProviderException] only if every attempt fails.
  Future<TranslationResult> suggestTranslation(
    String text, {
    String? from,
    String? to,
  }) async {
    final src = from ?? settings.learningLang;
    final dst = to ?? settings.nativeLang;
    final trimmed = text.trim();
    // Provider-specific so switching providers re-queries instead of returning
    // another provider's cached result.
    final cacheKey =
        'tr:${settings.translationProvider.id}:$src>$dst:${trimmed.toLowerCase()}';
    final cached = _readCache(cacheKey);
    if (cached != null) return TranslationResult.fromJson(cached);

    final attempts = <TranslationProvider>[_primaryTranslationProvider()];
    // Add keyless MyMemory as a safety net unless it is already primary.
    if (settings.translationProvider != TranslationProviderId.myMemory) {
      attempts.add(MyMemoryProvider(_client, email: settings.myMemoryEmail));
    }

    ProviderException? lastError;
    for (final provider in attempts) {
      try {
        final result = await provider.translate(
          text: trimmed,
          from: src,
          to: dst,
        );
        _cache.put(cacheKey, jsonEncode(result.toJson()));
        return result;
      } on ProviderException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = ProviderException('$e');
      }
    }
    throw lastError ?? const ProviderException('Translation failed.');
  }

  /// Translate [text] with a single, specific provider and **no fallback**, so
  /// the caller can be certain which engine produced the result (e.g. to show a
  /// DeepL-only "translation in context"). Results are cached under the same
  /// provider-namespaced scheme as [suggestTranslation], so a word translated by
  /// the primary path and the same text translated here share cache entries.
  ///
  /// Throws [ProviderException] if that one provider fails.
  Future<TranslationResult> translateWith(
    TranslationProviderId providerId,
    String text, {
    String? from,
    String? to,
  }) async {
    final src = from ?? settings.learningLang;
    final dst = to ?? settings.nativeLang;
    final trimmed = text.trim();
    final cacheKey = 'tr:${providerId.id}:$src>$dst:${trimmed.toLowerCase()}';
    final cached = _readCache(cacheKey);
    if (cached != null) return TranslationResult.fromJson(cached);

    final result = await _buildTranslationProvider(
      providerId,
    ).translate(text: trimmed, from: src, to: dst);
    _cache.put(cacheKey, jsonEncode(result.toJson()));
    return result;
  }

  /// Look up a definition for [word]. Returns null if no provider finds one (or
  /// definitions are disabled). Throws [ProviderException] only on a hard
  /// failure that isn't "not found".
  Future<DefinitionResult?> lookupDefinition(
    String word, {
    String? lang,
  }) async {
    final language = lang ?? settings.learningLang;
    final primary = _primaryDefinitionProvider();
    if (primary == null) return null;

    final trimmed = word.trim();
    final cacheKey = 'def:${primary.id}:$language:${trimmed.toLowerCase()}';
    final cached = _readCache(cacheKey);
    if (cached != null) {
      if (cached['_empty'] == true) {
        final exp = cached['_exp'];
        final stillFresh =
            exp is int && DateTime.now().millisecondsSinceEpoch < exp;
        if (stillFresh) return null;
        // Expired negative entry: fall through and re-fetch.
      } else {
        return DefinitionResult.fromJson(cached);
      }
    }

    final attempts = <DefinitionProvider>[primary];
    if (primary.id != 'wiktionary') {
      attempts.add(WiktionaryProvider(_client));
    }

    ProviderException? hardError;
    for (final provider in attempts) {
      try {
        final result = await provider.define(word: trimmed, lang: language);
        _cache.put(cacheKey, jsonEncode(result.toJson()));
        return result;
      } on ProviderException catch (e) {
        if (!e.notFound) hardError = e;
        // On not-found, continue to the next provider.
      } catch (e) {
        hardError = ProviderException('$e');
      }
    }
    if (hardError != null) throw hardError;
    // Every provider returned "not found": cache the negative result with a TTL
    // so the word is eventually re-checked (a provider may add it later).
    _cache.put(
      cacheKey,
      jsonEncode({
        '_empty': true,
        '_exp':
            DateTime.now().millisecondsSinceEpoch + _negativeDefinitionTtlMs,
      }),
    );
    return null;
  }

  Map<String, Object?>? _readCache(String key) {
    final raw = _cache.get(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }
}
