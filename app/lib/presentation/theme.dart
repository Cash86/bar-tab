import 'package:flutter/material.dart';

/// Design tokens of the approved bar-tab look (dark only).
abstract final class BarTabTheme {
  static const Color bottle = Color(0xFF16302A);
  static const Color bottle2 = Color(0xFF1E3D35);
  static const Color bottle3 = Color(0xFF2A4C43);
  static const Color paper = Color(0xFFF2EADB);
  static const Color muted = Color(0xFF9FB2AA);
  static const Color collectiveAccent = Color(0xFF9CC46A);

  /// Tier colours by tier `sort_order` index, cycling.
  static const List<Color> tierPalette = [
    Color(0xFFE3A33A),
    Color(0xFF72B8DE),
    Color(0xFFC79BF0),
    Color(0xFF9CC46A),
  ];

  static const String fontFamily = 'Archivo';

  static Color tierColor(int index) => tierPalette[index % tierPalette.length];

  static ThemeData get data {
    final base = ThemeData(
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: collectiveAccent,
        onPrimary: bottle,
        secondary: collectiveAccent,
        surface: bottle,
        onSurface: paper,
        surfaceContainerHighest: bottle3,
      ),
      scaffoldBackgroundColor: bottle,
      canvasColor: bottle,
      cardColor: bottle2,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: paper,
        displayColor: paper,
      ),
    );
  }
}
