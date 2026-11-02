import 'package:flutter/material.dart';

const ink = Color(0xFF0F0D12);
const panel = Color(0xFF1B1820);
const panelHigh = Color(0xFF28242F);
const blood = Color(0xFFD23A3A);
const gold = Color(0xFFE2B659);
const mist = Color(0xFFA9A3B2);
const good = Color(0xFF5CC58A);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: blood,
    brightness: Brightness.dark,
    primary: blood,
    onPrimary: Colors.white,
    secondary: gold,
    surface: panel,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: ink,
    fontFamily: 'Tajawal',
    appBarTheme: const AppBarTheme(
      backgroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    cardTheme: const CardThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        textStyle: const TextStyle(
          fontFamily: 'Tajawal',
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Keeps content at a readable width on a computer screen.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.width = 560});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: child,
      ),
    );
  }
}
