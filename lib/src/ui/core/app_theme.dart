import 'package:flutter/material.dart';

const Color ideFrameColor = Color(0xFF171717);
const Color ideSurfaceColor = Color(0xFF1F1F1F);
const Color idePanelColor = Color(0xFF242424);
const Color ideEditorColor = Color(0xFF191919);
const Color ideBorderColor = Color(0xFF343434);
const Color ideMutedTextColor = Color(0xFF9DA3A6);
const Color ideAccentColor = Color(0xFF4FB286);
const Color ideWarningColor = Color(0xFFE6B450);

const double idePanelGap = 8;
const double idePanelRadius = 6;

ThemeData buildCompactTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: ideAccentColor,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme.copyWith(
      surface: ideSurfaceColor,
      primary: ideAccentColor,
      secondary: ideWarningColor,
    ),
    scaffoldBackgroundColor: ideFrameColor,
    visualDensity: VisualDensity.compact,
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        fixedSize: const Size(30, 30),
        minimumSize: const Size(30, 30),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 12),
      bodySmall: TextStyle(fontSize: 11),
      titleSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}
