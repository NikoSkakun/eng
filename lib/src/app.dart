import 'package:flutter/material.dart';

import 'ui/home_shell.dart';

/// Root widget. Light/dark themes follow the system setting.
class EngApp extends StatelessWidget {
  const EngApp({super.key});

  static const Color _seed = Color(0xFF3F51B5); // indigo

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eng — foreign-language reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
