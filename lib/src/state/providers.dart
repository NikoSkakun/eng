import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../data/cache_repository.dart';
import '../data/dictionary_repository.dart';
import '../data/library_repository.dart';
import '../data/settings_store.dart';
import '../services/backup_service.dart';
import '../services/translation/translation_service.dart';
import 'settings_controller.dart';

/// The opened database. Overridden in `main()` with the real instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden in main()');
});

/// Loaded shared preferences. Overridden in `main()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

/// Absolute path to the directory where imported PDFs are stored.
/// Overridden in `main()`.
final libraryDirectoryProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'libraryDirectoryProvider must be overridden in main()',
  );
});

/// Shared HTTP client for all network calls.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final cacheRepositoryProvider = Provider<CacheRepository>(
  (ref) => CacheRepository(ref.watch(appDatabaseProvider)),
);

final dictionaryRepositoryProvider = Provider<DictionaryRepository>(
  (ref) => DictionaryRepository(ref.watch(appDatabaseProvider)),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(appDatabaseProvider)),
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(sharedPreferencesProvider)),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    ref.watch(dictionaryRepositoryProvider),
    ref.watch(libraryRepositoryProvider),
    ref.watch(libraryDirectoryProvider),
  ),
);

/// Translation/definition service; recreated when settings change so it always
/// reflects the current provider selection and API keys.
final translationServiceProvider = Provider<TranslationService>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  return TranslationService(
    settings,
    ref.watch(cacheRepositoryProvider),
    ref.watch(httpClientProvider),
  );
});
