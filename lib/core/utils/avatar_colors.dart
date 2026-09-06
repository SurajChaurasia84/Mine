import 'package:flutter/material.dart';

/// Provides deterministic, distinct WhatsApp-authentic dark mode avatar colors.
class AvatarColors {
  final Color background;
  final Color foreground;

  const AvatarColors({required this.background, required this.foreground});

  static const List<AvatarColors> _palette = [
    AvatarColors(background: Color(0xFF362C22), foreground: Color(0xFFD4B892)), // Olive Brown / Beige (as in screenshot)
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
