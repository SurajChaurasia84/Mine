import 'package:flutter/material.dart';

class MineTheme {
  // WhatsApp-inspired privacy palette
  static const Color primaryTeal = Color(0xFF00A884);
  static const Color primaryDark = Color(0xFF128C7E);
  static const Color backgroundDark = Color(0xFF121B22);
  static const Color surfaceDark = Color(0xFF1F2C34);
  static const Color outgoingBubble = Color(0xFF005C4B);
  static const Color incomingBubble = Color(0xFF202C33);
  static const Color textLight = Color(0xFFE9EDEF);
  static const Color textMuted = Color(0xFF8696A0);
  static const Color accentGreen = Color(0xFF25D366);
  static const Color tickBlue = Color(0xFF53BDEB);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundDark,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: WhatsAppFadePageTransitionsBuilder(),
          TargetPlatform.iOS: WhatsAppFadePageTransitionsBuilder(),
          TargetPlatform.windows: WhatsAppFadePageTransitionsBuilder(),
          TargetPlatform.macOS: WhatsAppFadePageTransitionsBuilder(),
          TargetPlatform.linux: WhatsAppFadePageTransitionsBuilder(),
          TargetPlatform.fuchsia: WhatsAppFadePageTransitionsBuilder(),
        },
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryTeal,
        secondary: accentGreen,
        surface: surfaceDark,
        onSurface: textLight,
        onPrimary: Colors.white,
        surfaceTint: Colors.transparent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: textLight,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textLight,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryTeal,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF222D34),
        thickness: 0.6,
      ),
    );
  }
}

class WhatsAppFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const WhatsAppFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
        reverseCurve: Curves.easeInOutCubic,
      ),
      child: child,
    );
  }
}
