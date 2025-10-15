import 'package:flutter/material.dart';

/// Paleta LIA-Staylo (azules del icono #3D8CD1)
class LIAColors {
  static const Color primary = Color(0xFF3D8CD1);
  static const Color primaryDark = Color(0xFF1F6FB3);
  static const Color primaryLight = Color(0xFF69A9E3);

  static const Color ink = Color(0xFF1F2A37); // texto principal
  static const Color success = Color(0xFF1ABC9C);
  static const Color warning = Color(0xFFF39C12);
  static const Color danger  = Color(0xFFE74C3C);

  static const Color bgLight = Color(0xFFF7FAFC);
  static const Color cardLight = Colors.white;

  static const Color bgDark = Color(0xFF0F172A);
  static const Color cardDark = Color(0xFF111827);
}

/// Gradientes usados en pantallas (login/hero/botones)
class LIAGradients {
  // Degradado de marca (diagonal) — el que solemos usar en el login
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      LIAColors.primaryLight, // #69A9E3
      LIAColors.primary,      // #3D8CD1
      LIAColors.primaryDark,  // #1F6FB3
    ],
  );

  // Aliases para compatibilidad con código previo
  static const LinearGradient hero = brand;
  static const LinearGradient loginBg = brand;
  static const LinearGradient primary = brand;
  static const LinearGradient blue = brand; // <-- evita "Member not found: 'blue'"

  // Un gradiente sutil opcional
  static const LinearGradient subtle = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFFEAF3FB),
      Color(0xFFDDEBFA),
    ],
  );
}

class LIATheme {
  // --------- ALIAS DE COLORES (compatibilidad con código previo) ----------
  // Ej.: había referencias a LIATheme.brandBlue / brandBlueDark / surfaceDark
  static const Color brandBlue = LIAColors.primary;
  static const Color brandBlueDark = LIAColors.primaryDark;
  static const Color surfaceDark = LIAColors.bgDark;

  // --------- TEXT STYLES DE ACCESO RÁPIDO (compatibilidad) ----------
  // Evita errores como "Member not found: 'LIATheme.h1'" o "subtitle"
  static TextStyle h1(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall ??
      const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: LIAColors.ink);

  static TextStyle subtitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium ??
      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: LIAColors.ink);

  // ---------- LIGHT ----------
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: LIAColors.primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: LIAColors.primary,
        secondary: LIAColors.primaryLight,
        onPrimary: Colors.white,
        surface: LIAColors.cardLight,
        onSurface: LIAColors.ink,
      ),
      scaffoldBackgroundColor: LIAColors.bgLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: LIAColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),

      // Tu entorno espera CardThemeData (no CardTheme)
      cardTheme: CardThemeData(
        color: LIAColors.cardLight,
        elevation: 1,
        surfaceTintColor: LIAColors.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LIAColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: LIAColors.primary,
          side: const BorderSide(color: LIAColors.primary, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: LIAColors.primary, width: 1.6),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5E7EB),
        thickness: 1,
      ),
      iconTheme: const IconThemeData(color: LIAColors.ink),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: LIAColors.ink),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: LIAColors.ink),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: LIAColors.ink),
        bodyLarge: TextStyle(fontSize: 16, color: LIAColors.ink),
        bodyMedium: TextStyle(fontSize: 14, color: LIAColors.ink),
        labelLarge: TextStyle(fontWeight: FontWeight.w600),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LIAColors.primary,
        contentTextStyle: TextStyle(color: Colors.white),
      ),

      // Nota: no configuramos tabBarTheme para evitar incompatibilidad
      // con builds que esperan TabBarThemeData? en lugar de TabBarTheme.
    );
  }

  // ---------- DARK ----------
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: LIAColors.primary,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(primary: LIAColors.primary),
      scaffoldBackgroundColor: LIAColors.bgDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B61A4),
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      // Tu entorno espera CardThemeData (no CardTheme)
      cardTheme: CardThemeData(
        color: LIAColors.cardDark,
        elevation: 1,
        surfaceTintColor: LIAColors.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LIAColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0B1220),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1F2937)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: LIAColors.primary, width: 1.6),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: LIAColors.primary,
        contentTextStyle: TextStyle(color: Colors.white),
      ),

      // Igual que en light(): evitamos tabBarTheme por compatibilidad.
    );
  }
}
