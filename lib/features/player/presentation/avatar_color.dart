import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

/// Pure helpers for avatar rendering — palette pick and initials extraction.
///
/// Stored colors live as hex strings like `0xFF3A7C2E` so the avatar stays
/// stable across theme switches.
class AvatarColorHelper {
  AvatarColorHelper._();

  /// Six brand-palette tones used for player avatars. Order is stable so the
  /// deterministic default-pick stays consistent across rebuilds.
  static const List<Color> palette = <Color>[
    KubbTokens.meadow500,
    KubbTokens.meadow700,
    KubbTokens.wood400,
    KubbTokens.wood600,
    KubbTokens.stone500,
    KubbTokens.stone700,
  ];

  static String encode(Color color) =>
      '0x${color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0')}';

  /// Decodes the stored value or falls back to a deterministic default.
  /// `seed` is normally the player id — same seed yields same color.
  static Color resolve(String? stored, {required String seed}) {
    if (stored != null && stored.isNotEmpty) {
      final parsed = int.tryParse(stored);
      if (parsed != null) {
        return Color(parsed);
      }
    }
    return defaultColorFor(seed);
  }

  static Color defaultColorFor(String seed) {
    if (seed.isEmpty) return palette.first;
    final hash = seed.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return palette[hash % palette.length];
  }

  /// One or two uppercase letters from the first two whitespace-separated
  /// words. Returns `?` for empty input.
  static String initialsFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }
}
