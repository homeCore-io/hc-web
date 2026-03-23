import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF3F51B5); // indigo

  static ThemeData get light => ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      );
}
