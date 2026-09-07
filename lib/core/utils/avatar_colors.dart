import 'package:flutter/material.dart';

/// Provides deterministic, distinct WhatsApp-authentic dark mode avatar colors.
class AvatarColors {
  final Color background;
  final Color foreground;

  const AvatarColors({required this.background, required this.foreground});

  static const List<AvatarColors> _palette = [
    AvatarColors(background: Color(0xFF362C22), foreground: Color(0xFFD4B892)), // Olive Brown / Beige
    AvatarColors(background: Color(0xFF16384C), foreground: Color(0xFF53BDEB)), // Slate Navy / Sky Blue
    AvatarColors(background: Color(0xFF3B1F34), foreground: Color(0xFFE170B7)), // Deep Plum / Rose Pink
    AvatarColors(background: Color(0xFF143828), foreground: Color(0xFF25D366)), // Deep Pine / Emerald Green
    AvatarColors(background: Color(0xFF3D2714), foreground: Color(0xFFFFA726)), // Warm Mahogany / Amber
    AvatarColors(background: Color(0xFF2A1F3D), foreground: Color(0xFFB388FF)), // Deep Purple / Lilac
    AvatarColors(background: Color(0xFF3D1920), foreground: Color(0xFFFF6B81)), // Dark Wine / Coral
    AvatarColors(background: Color(0xFF163836), foreground: Color(0xFF4DD0E1)), // Deep Teal / Turquoise
    AvatarColors(background: Color(0xFF363214), foreground: Color(0xFFDCE775)), // Olive / Lime
    AvatarColors(background: Color(0xFF232B32), foreground: Color(0xFFB0BEC5)), // Slate Grey / Cool Silver
  ];

  static AvatarColors forName(String nameOrId) {
    if (nameOrId.trim().isEmpty) return _palette[0];
    final key = nameOrId.trim().toLowerCase();
    int hash = 0;
    for (int i = 0; i < key.length; i++) {
      hash = (hash * 31 + key.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return _palette[hash % _palette.length];
  }
}

/// A reusable, responsive Avatar that gracefully handles:
/// - Letters -> displays uppercase initial ('A' - 'Z')
/// - Numeric numbers -> displays the first numeric number ('0' - '9')
/// - Emojis / symbols -> displays person icon
class UserAvatar extends StatelessWidget {
  final String nameOrId;
  final double radius;
  final double? fontSize;
  final double? iconSize;

  const UserAvatar({
    super.key,
    required this.nameOrId,
    this.radius = 24,
    this.fontSize,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AvatarColors.forName(nameOrId);
    final trimmed = nameOrId.trim();

    Widget child;
    if (trimmed.isEmpty) {
      child = Icon(
        Icons.person_rounded,
        color: colors.foreground,
        size: iconSize ?? (radius * 1.1),
      );
    } else {
      final firstGrapheme = trimmed.characters.first;
      final isDigit = RegExp(r'^[0-9]$').hasMatch(firstGrapheme);
      final isAlpha = RegExp(r'^[a-zA-Z\u00C0-\u024F\u0900-\u097F]$').hasMatch(firstGrapheme);

      if (isDigit) {
        // First numeric number
        child = Text(
          firstGrapheme,
          style: TextStyle(
            fontSize: fontSize ?? (radius * 0.82),
            fontWeight: FontWeight.bold,
            color: colors.foreground,
          ),
        );
      } else if (isAlpha) {
        // Uppercase alphabet
        child = Text(
          firstGrapheme.toUpperCase(),
          style: TextStyle(
            fontSize: fontSize ?? (radius * 0.82),
            fontWeight: FontWeight.bold,
            color: colors.foreground,
          ),
        );
      } else {
        // Emoji, symbol, etc -> Show person icon
        child = Icon(
          Icons.person_rounded,
          color: colors.foreground,
          size: iconSize ?? (radius * 1.1),
        );
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.background,
      child: child,
    );
  }
}
