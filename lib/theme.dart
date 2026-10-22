import 'package:flutter/material.dart';

/// Accent when wallpaper colors are unavailable: sand, like the launcher icon.
const sand = Color(0xFF9C5B16);

ThemeData buildTheme(ColorScheme cs) => ThemeData(
  colorScheme: cs,
  scaffoldBackgroundColor: cs.surface,
  appBarTheme: AppBarTheme(backgroundColor: cs.surface, surfaceTintColor: Colors.transparent),
  cardTheme: CardThemeData(
    elevation: 0,
    color: cs.surfaceContainerLow,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 48))),
  outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48))),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 20)),
);
