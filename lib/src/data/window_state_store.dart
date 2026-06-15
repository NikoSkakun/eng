import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the desktop window size across launches.
class WindowStateStore {
  WindowStateStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kWidth = 'window.width';
  static const _kHeight = 'window.height';

  /// The last saved window size, or null if none/implausible.
  Size? loadSize() {
    final w = _prefs.getDouble(_kWidth);
    final h = _prefs.getDouble(_kHeight);
    if (w == null || h == null) return null;
    if (w < 400 || h < 300 || w > 20000 || h > 20000) return null;
    return Size(w, h);
  }

  Future<void> saveSize(Size size) async {
    await _prefs.setDouble(_kWidth, size.width);
    await _prefs.setDouble(_kHeight, size.height);
  }
}
