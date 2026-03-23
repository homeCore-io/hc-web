import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => FlexThemeData.light(
        scheme: FlexScheme.indigo,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 9,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          blendOnColors: false,
        ),
        useMaterial3: true,
      );

  static ThemeData get dark => FlexThemeData.dark(
        scheme: FlexScheme.indigo,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 15,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
        ),
        useMaterial3: true,
      );
}
