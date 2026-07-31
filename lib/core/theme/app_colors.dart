import 'package:flutter/material.dart';

/// Centralised color palette for the Waslny Rider app.
///
/// Phase 1 design-system colors:
/// - [primaryGreen]: brand accent (neon green)
/// - [darkBg]: main background
/// - [cardBg]: card / elevated surface
/// - [white]: primary text
///
/// All existing legacy aliases are preserved so earlier screens keep working
/// while adopting the new palette.
class AppColors {
  AppColors._();

  // ── Brand colors (Phase 1) ─────────────────────────
  static const Color primaryGreen = Color(0xFF7CFC00);
  static const Color darkBg = Color(0xFF1A1A1A);
  static const Color cardBg = Color(0xFF2A2A2A);
  static const Color white = Color(0xFFFFFFFF);

  // Primary Background — dark
  static const Color primaryBg = darkBg;

  // Secondary Background
  static const Color secondaryBg = Color(0xFF0A0A0A);

  // Surface
  static const Color surface = Color(0xFF111111);

  // Cards
  static const Color card = cardBg;
  static const Color cardElevated = Color(0xFF222222);

  // Text — White per brand identity
  static const Color textPrimary = white;
  static const Color textSecondary = white;
  static const Color textMuted = Color(0xFFE0E0E0);
  static const Color textOnPrimary = Color(0xFF000000);

  // Primary Accent — Neon Green (#7CFC00)
  static const Color primary = primaryGreen;
  static const Color primaryDark = Color(0xFF5BC400);
  static const Color primaryLight = Color(0xFF9FFF33);
  static const Color primaryFaded = Color(0x337CFC00);
  static const Color primaryContainer = Color(0xFF123000);

  // Online Status
  static const Color online = primaryGreen;

  // Borders
  static const Color border = Color(0xFF303030);
  static const Color borderLight = Color(0xFF3A3A3A);

  // Semantic
  static const Color success = primaryGreen;
  static const Color successContainer = Color(0xFF123000);
  static const Color error = Color(0xFFFF4D4F);
  static const Color errorContainer = Color(0xFF2A0F0F);
  static const Color warning = Color(0xFFFFC107);
  static const Color warningContainer = Color(0xFF2A2008);
  static const Color info = Color(0xFF38BDF8);
  static const Color infoContainer = Color(0xFF0F1F2A);

  // Overlays
  static const Color scrim = Color(0xB3000000);
  static const Color overlayLight = Color(0x14FFFFFF);
  static const Color overlayMedium = Color(0x26FFFFFF);
  static const Color shimmerBase = Color(0xFF242424);
  static const Color shimmerHighlight = Color(0xFF2A2A2A);

  // Legacy aliases for compatibility
  static const Color neonGreen = primaryGreen;
  static const Color bg = darkBg;
  static const Color surfaceDark = surface;
  static const Color surfaceElevated = cardElevated;
  static const Color glassBg = Color(0x14FFFFFF);
  static const Color glassBorder = border;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryLight, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [surface, primaryBg],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient overlayGradient = LinearGradient(
    colors: [Colors.transparent, Color(0xE60D0D0D)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.20),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.28),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.36),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
  ];

  static List<BoxShadow> shadowPrimary = [
    BoxShadow(
      color: primaryDark.withValues(alpha: 0.35),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}
