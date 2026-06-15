import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/data/app_database.dart';
import 'src/data/window_state_store.dart';
import 'src/state/providers.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

// Kept alive for the app's lifetime so resize events keep being persisted.
_WindowSizeObserver? _windowObserver;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the PDFium-backed engine (bundled via Dart native assets on
  // Linux, the XCFramework on iOS). Safe to call early.
  await pdfrxFlutterInitialize();

  // Keep all app data (database + imported PDFs) in an app-private directory.
  final supportDir = await getApplicationSupportDirectory();
  final libraryDir = Directory(p.join(supportDir.path, 'library'));
  if (!libraryDir.existsSync()) libraryDir.createSync(recursive: true);

  final db = AppDatabase.open(p.join(supportDir.path, 'eng.db'));
  final prefs = await SharedPreferences.getInstance();

  // Desktop only: restore the saved window size and keep it in sync.
  if (_isDesktop) {
    await windowManager.ensureInitialized();
    final windowStore = WindowStateStore(prefs);
    final savedSize = windowStore.loadSize();
    final options = WindowOptions(
      size: savedSize ?? const Size(1100, 800),
      minimumSize: const Size(480, 400),
      center: savedSize == null,
      title: 'eng',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // Persist size changes via Flutter's own metrics callback (more reliable
    // across window managers than plugin-specific resize events).
    _windowObserver = _WindowSizeObserver(windowStore);
    WidgetsBinding.instance.addObserver(_windowObserver!);
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        libraryDirectoryProvider.overrideWithValue(libraryDir.path),
      ],
      child: const EngApp(),
    ),
  );
}

/// Saves the window size (debounced) whenever the OS window metrics change.
class _WindowSizeObserver with WidgetsBindingObserver {
  _WindowSizeObserver(this._store);

  final WindowStateStore _store;
  Timer? _debounce;

  @override
  void didChangeMetrics() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final view = views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      if (size.width < 200 || size.height < 200) return; // minimized/transient
      _store.saveSize(size);
    });
  }
}
