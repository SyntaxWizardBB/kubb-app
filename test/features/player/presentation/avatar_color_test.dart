import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/player/presentation/avatar_color.dart';

void main() {
  group('initialsFor', () {
    test('returns first letter uppercased for a single word', () {
      expect(AvatarColorHelper.initialsFor('lukas'), 'L');
    });

    test('returns two letters from first two words', () {
      expect(AvatarColorHelper.initialsFor('marc brosius'), 'MB');
    });

    test('ignores extra whitespace', () {
      expect(AvatarColorHelper.initialsFor('  marc   brosius '), 'MB');
    });

    test('falls back to ? for empty input', () {
      expect(AvatarColorHelper.initialsFor(''), '?');
      expect(AvatarColorHelper.initialsFor('   '), '?');
    });
  });

  group('defaultColorFor', () {
    test('is deterministic for the same seed', () {
      final a = AvatarColorHelper.defaultColorFor('player-id-1');
      final b = AvatarColorHelper.defaultColorFor('player-id-1');
      expect(a, b);
    });

    test('always returns a palette color', () {
      for (final seed in ['a', 'lukas', 'xyz-uuid', '']) {
        expect(AvatarColorHelper.palette,
            contains(AvatarColorHelper.defaultColorFor(seed)));
      }
    });
  });

  group('encode + resolve', () {
    test('round-trips a palette color', () {
      const original = KubbTokens.meadow500;
      final encoded = AvatarColorHelper.encode(original);
      final decoded = AvatarColorHelper.resolve(encoded, seed: 'irrelevant');
      expect(decoded, original);
    });

    test('falls back to default when stored value is null or empty', () {
      final fallback = AvatarColorHelper.defaultColorFor('seed1');
      expect(
        AvatarColorHelper.resolve(null, seed: 'seed1'),
        fallback,
      );
      expect(
        AvatarColorHelper.resolve('', seed: 'seed1'),
        fallback,
      );
    });

    test('falls back to default when stored value is unparseable', () {
      final fallback = AvatarColorHelper.defaultColorFor('seed2');
      expect(
        AvatarColorHelper.resolve('not-a-hex', seed: 'seed2'),
        fallback,
      );
    });
  });

  group('palette', () {
    test('has six distinct colors', () {
      expect(AvatarColorHelper.palette.length, 6);
      expect(AvatarColorHelper.palette.toSet().length, 6);
    });

    test('every entry is a Color', () {
      expect(AvatarColorHelper.palette, everyElement(isA<Color>()));
    });
  });
}
