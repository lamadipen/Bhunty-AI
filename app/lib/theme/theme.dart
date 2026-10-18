import 'package:flutter/material.dart';

/// Colours from the design prototype (see CLAUDE.md, "Visual direction").
abstract final class BColors {
  static const ground = Color(0xFFEEF2EF);
  static const ink = Color(0xFF17201B);
  static const inkSoft = Color(0xFF4A564F);
  static const muted = Color(0xFF7C8A82);
  static const line = Color(0xFFD6DDD8);
  static const lineSoft = Color(0xFFE6EBE7);
  static const white = Color(0xFFFFFFFF);

  static const green = Color(0xFF1D6B45);
  static const greenDark = Color(0xFF14512F);
  static const greenTint = Color(0xFFE3F0E8);
  static const greenOnDark = Color(0xFF7BD3A2);

  static const orange = Color(0xFFC2541B);
  static const blue = Color(0xFF1E3E73);
  static const blueTint = Color(0xFFE3EAF6);
  static const gold = Color(0xFF6B4A00);
  static const goldTint = Color(0xFFF6E3B4);

  static const warnBg = Color(0xFFFCE9DC);
  static const warnInk = Color(0xFF8A3A10);
  static const warnCard = Color(0xFFFFF6EF);
  static const warnBorder = Color(0xFFE8A57A);

  static const disabled = Color(0xFF9FB0A6);
  static const scrim = Color(0x8C17201B);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BColors.green,
    primary: BColors.green,
    secondary: BColors.orange,
    surface: BColors.white,
    onSurface: BColors.ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Mukta',
    scaffoldBackgroundColor: BColors.ground,
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: BColors.ink,
      displayColor: BColors.ink,
      fontFamily: 'Mukta',
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: BColors.white,
      modalBarrierColor: BColors.scrim,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
  );
}
