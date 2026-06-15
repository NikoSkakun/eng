import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/data/app_database.dart';
import 'src/state/providers.dart';

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
