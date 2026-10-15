import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette Correctis V2 — Refonte juin 2026 selon maquette validée par Michel.
///
/// Charte : dark mode permanent, palette inspirée d'EduCorrect (#04080f → #3b82f6).
/// Vert (#34d399) = identité PROF · Violet (#a78bfa) = identité ADMIN.
///
/// Les noms de constantes sont conservés pour ne pas casser l'existant. Les
/// VALEURS sont mises à jour vers le nouveau dark mode.
class AppColors {
  // ─── Couleurs racines de la maquette ─────────────────────────────────────
  /// Fond principal (presque noir, base de tous les écrans)
  static const Color voidBg = Color(0xFF04080F);

  /// Carte / surface élevée
  static const Color card = Color(0xFF111E30);

  /// Variante de carte plus foncée
  static const Color card2 = Color(0xFF0D1828);

  /// Bordure très subtile (alpha 7%)
  static const Color borderSubtle = Color(0x12FFFFFF);

  // ─── ACCENTS PRINCIPAUX ──────────────────────────────────────────────────
  /// Bleu principal (#3b82f6) — actions par défaut, éléments interactifs
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF60A5FA);

  /// Vert prof (#34d399) — identité visuelle du rôle Professeur
  /// Utilisé comme `accent` historique → boutons primaires côté prof
  static const Color accent = Color(0xFF34D399);
  static const Color accentDark = Color(0xFF059669);
  static const Color profPrimary = Color(0xFF34D399);
  static const Color profDark = Color(0xFF059669);
  static const Color profDeep = Color(0xFF0D9488);

  /// Violet admin (#a78bfa) — identité visuelle du rôle Administrateur
  static const Color adminPrimary = Color(0xFFA78BFA);
  static const Color adminDark = Color(0xFF7C3AED);
  static const Color adminDeep = Color(0xFF6D28D9);

  // ─── SURFACES ────────────────────────────────────────────────────────────
  /// Fond global (était gris-bleu clair → devient quasi noir)
  static const Color background = voidBg;

  /// Surface des cards (était blanc → devient #111e30)
  static const Color surface = card;

  /// Surface secondaire (était gris-bleu clair → devient #0d1828)
  static const Color surfaceMuted = card2;

  // ─── TEXTE ───────────────────────────────────────────────────────────────
  /// Texte principal (était noir → devient blanc lumineux)
  static const Color textPrimary = Color(0xFFEEF4FF);

  /// Texte secondaire (gris-bleu, alpha ~60%)
  static const Color textSecondary = Color(0xFF99A8C0);

  /// Texte estompé (alpha ~38%)
  static const Color textMuted = Color(0xFF61708C);

  /// Texte sur fond coloré (boutons primaires)
  static const Color textOnPrimary = Colors.white;

  // ─── SÉMANTIQUE ──────────────────────────────────────────────────────────
  static const Color success = Color(0xFF34D399); // vert prof
  static const Color warning = Color(0xFFFBBF24); // amber
  static const Color danger = Color(0xFFF87171); // rouge plus doux
  static const Color info = Color(0xFF60A5FA); // bleu clair

  /// Couleur de séparation des éléments (très subtile)
  static const Color divider = borderSubtle;

  // ─── GRADIENTS UTILITAIRES ───────────────────────────────────────────────

  /// Bouton primaire côté PROF — dégradé vert
  static const Gradient profGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF0D9488)],
  );

  /// Bouton primaire côté ADMIN — dégradé violet/bleu
  static const Gradient adminGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6D28D9), Color(0xFF3B82F6)],
  );

  /// Logo Correctis — dégradé blanc → bleu → vert (effet "shiny")
  static const Gradient logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFFFF),
      Color(0xFF60A5FA),
      Color(0xFF34D399),
    ],
    stops: [0.0, 0.5, 1.0],
  );
}

/// Rayons d'arrondi — alignés sur la maquette
class AppRadius {
  static const double sm = 10; // chips, boutons sm
  static const double md = 12; // inputs, cards plates
  static const double lg = 14; // cards principales
  static const double xl = 16; // panels
  static const double xxl = 20; // hero / sections
  static const double pill = 100; // boutons full-width
}

/// Espacements — alignés sur la maquette
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Police helpers — utilisez ces TextStyle de base pour suivre la maquette.
class AppFonts {
  /// Fraunces : titres serif élégants (h1, h2, headlines)
  static TextStyle fraunces({
    double fontSize = 22,
    FontWeight fontWeight = FontWeight.w700,
    Color? color,
    double? height,
    FontStyle? fontStyle,
  }) =>
      GoogleFonts.fraunces(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textPrimary,
        height: height,
        fontStyle: fontStyle,
      );

  /// DM Sans : texte courant
  static TextStyle sans({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.dmSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textPrimary,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// DM Mono : badges, labels techniques, codes
  static TextStyle mono({
    double fontSize = 10,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double letterSpacing = 1.5,
  }) =>
      GoogleFonts.dmMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textSecondary,
        letterSpacing: letterSpacing,
      );
}

class AppTheme {
  /// Thème principal de l'app — DARK MODE PERMANENT (selon maquette Michel).
  ///
  /// Note : la méthode s'appelle toujours `lightTheme` pour ne pas casser
  /// `main.dart`, mais elle retourne maintenant un thème SOMBRE.
  static ThemeData get lightTheme => darkTheme;

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    // Texte par défaut = DM Sans, avec les titres en Fraunces
    final textTheme = GoogleFonts.dmSansTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.fraunces(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.15,
      ),
      displayMedium: GoogleFonts.fraunces(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.2,
      ),
      headlineLarge: GoogleFonts.fraunces(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineMedium: GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineSmall: GoogleFonts.fraunces(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleLarge: GoogleFonts.fraunces(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: GoogleFonts.dmSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleSmall: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.dmSans(
        fontSize: 15,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 13,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.dmSans(
        fontSize: 11,
        color: AppColors.textSecondary,
        height: 1.5,
      ),
      labelLarge: GoogleFonts.dmMono(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.2,
        color: AppColors.textPrimary,
      ),
      labelMedium: GoogleFonts.dmMono(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.5,
        color: AppColors.textSecondary,
      ),
      labelSmall: GoogleFonts.dmMono(
        fontSize: 9,
        fontWeight: FontWeight.w500,
        letterSpacing: 2,
        color: AppColors.textMuted,
      ),
    );

    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.accent,
        onSecondary: Colors.white,
        tertiary: AppColors.adminPrimary,
        onTertiary: Colors.white,
        surface: AppColors.card,
        onSurface: AppColors.textPrimary,
        surfaceContainerHighest: AppColors.card2,
        error: AppColors.danger,
        onError: Colors.white,
        outline: AppColors.borderSubtle,
      ),
      scaffoldBackgroundColor: AppColors.voidBg,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.voidBg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.profPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.dmMono(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.borderSubtle, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.dmMono(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.dmSans(
          fontSize: 13,
          color: AppColors.textMuted,
        ),
        labelStyle: GoogleFonts.dmMono(
          fontSize: 10,
          letterSpacing: 1.5,
          color: AppColors.primaryLight,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.borderSubtle, width: 1),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.voidBg.withValues(alpha: 0.95),
        selectedItemColor: AppColors.profPrimary,
        unselectedItemColor: AppColors.textMuted,
        selectedLabelStyle: GoogleFonts.dmMono(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: GoogleFonts.dmMono(
          fontSize: 9,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.5,
        ),
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.profPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.card2,
        labelStyle: GoogleFonts.dmMono(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1,
          color: AppColors.textSecondary,
        ),
        side: const BorderSide(color: AppColors.borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.card2,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 20,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.profPrimary
              : AppColors.card2;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? AppColors.profPrimary
              : Colors.transparent;
        }),
        side: const BorderSide(color: AppColors.borderSubtle, width: 1.5),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.profPrimary,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: GoogleFonts.dmMono(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1,
        ),
        unselectedLabelStyle: GoogleFonts.dmMono(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.profPrimary, width: 2),
        ),
        dividerColor: AppColors.borderSubtle,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.card,
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.dmSans(
          fontSize: 13,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }
}
