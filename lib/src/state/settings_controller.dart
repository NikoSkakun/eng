import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import 'providers.dart';

/// Holds the current [AppSettings] and persists changes.
final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsStoreProvider).load();

  /// Replace the whole settings object and persist it.
  Future<void> update(AppSettings next) async {
    await ref.read(settingsStoreProvider).save(next);
    state = next;
  }

  /// Apply a transformation to the current settings and persist.
  Future<void> mutate(AppSettings Function(AppSettings) transform) =>
      update(transform(state));
}
