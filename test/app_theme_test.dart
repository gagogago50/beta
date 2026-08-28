import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:NEk0/models/app_theme.dart';

void main() {
  group('TsPalette.forMode', () {
    test('returns distinct palettes per mode', () {
      final dark = TsPalette.forMode(AppThemeMode.dark);
      final light = TsPalette.forMode(AppThemeMode.light);
      final amoled = TsPalette.forMode(AppThemeMode.amoled);
      expect(dark.background, isNot(light.background));
      expect(light.background, isNot(amoled.background));
      expect(dark.background, isNot(amoled.background));
    });

    test('AMOLED uses pure black surfaces', () {
      final amoled = TsPalette.forMode(AppThemeMode.amoled);
      expect(amoled.background, const Color(0xFF000000));
      expect(amoled.appbar, const Color(0xFF000000));
    });

    test('system defaults to the dark palette', () {
      expect(TsPalette.forMode(AppThemeMode.system), TsPalette.dark());
    });
  });

  group('AppThemeMode', () {
    test('fromId round-trips known ids', () {
      for (final mode in AppThemeMode.values) {
        expect(AppThemeMode.fromId(mode.id), mode);
      }
    });

    test('fromId falls back to system for an unknown value', () {
      expect(AppThemeMode.fromId('neon'), AppThemeMode.system);
      expect(AppThemeMode.fromId(null), AppThemeMode.system);
    });
  });

  group('buildThemeData', () {
    test('carries the palette as a ThemeExtension', () {
      final theme = buildThemeData(
        TsPalette.amoled(),
        brightness: Brightness.dark,
      );
      final palette = theme.extension<TsPalette>();
      expect(palette, isNotNull);
      expect(palette!.background, const Color(0xFF000000));
    });

    test('scaffold background matches the palette', () {
      final theme = buildThemeData(
        TsPalette.light(),
        brightness: Brightness.light,
      );
      expect(theme.scaffoldBackgroundColor, TsPalette.light().background);
    });
  });
}
