import 'package:flutter/material.dart';

/// Retro jukebox palette: dark cabinet, chrome, neon amber, and cream
/// title-strip cards with a red band.
abstract final class Jb {
  static const cabinet = Color(0xFF140C0A);
  static const cabinetHi = Color(0xFF2A1712);
  static const chrome = Color(0xFFC9CED6);
  static const neon = Color(0xFFFFB02E);
  static const neonDim = Color(0x55FFB02E);
  static const band = Color(0xFFB3261E);
  static const paper = Color(0xFFF6EEDB);
  static const paperLine = Color(0xFFE3D6B8);
  static const ink = Color(0xFF2B1D14);
  static const inkSoft = Color(0xFF7A6553);
  static const playing = Color(0xFFFFD27A);

  static const mono = ['Consolas', 'Menlo', 'Roboto Mono', 'monospace'];

  static ThemeData theme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: neon,
        brightness: Brightness.dark,
        primary: neon,
        surface: cabinetHi,
      ),
      scaffoldBackgroundColor: cabinet,
      useMaterial3: true,
    );
    return base.copyWith(
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cabinetHi,
        contentTextStyle: TextStyle(color: neon, fontSize: 18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  static BoxDecoration chromeButton({bool active = false}) => BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: active
              ? const [Color(0xFFFFD27A), Color(0xFFE08A00)]
              : const [Color(0xFF4A3A33), Color(0xFF241510)],
        ),
        border: Border.all(color: active ? neon : const Color(0xFF6B5348)),
      );
}
