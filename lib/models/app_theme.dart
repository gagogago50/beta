import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The four theme modes the app exposes.
enum AppThemeMode {
  system,
  dark,
  light,
  amoled;

  /// Stable persistence value (survives renames).
  String get id => name;

  static AppThemeMode fromId(String? id) => AppThemeMode.values.firstWhere(
    (m) => m.id == id,
    orElse: () => AppThemeMode.system,
  );
}

/// Semantic palette. Every color the UI refers to lives here, keyed by role
/// rather than by hex value, so a switch from dark → light → AMOLED is one
/// palette swap and never a hunt through widgets.
///
/// Implemented as a [`ThemeExtension`] so it travels with `ThemeData` and is
/// read through `context.ts` — widgets never hardcode a hex value for a role.
class TsPalette extends ThemeExtension<TsPalette> {
  final Color background;
  final Color appbar;
  final Color surface;
  final Color surfaceAlt;
  final Color card;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentAlt;
  final Color accentName;
  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerAccent;

  const TsPalette({
    required this.background,
    required this.appbar,
    required this.surface,
    required this.surfaceAlt,
    required this.card,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentAlt,
    required this.accentName,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerAccent,
  });

  /// The current deep-navy look.
  factory TsPalette.dark() => const TsPalette(
    background: Color(0xFF0F0F23),
    appbar: Color(0xFF16213E),
    surface: Color(0xFF12122A),
    surfaceAlt: Color(0xFF1F1F3A),
    card: Color(0xFF1A1A2E),
    divider: Color(0xFF2A2A4A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9E9E9E),
    textMuted: Color(0xFF555577),
    accent: Color(0xFF2196F3),
    accentAlt: Color(0xFFAA66CC),
    accentName: Color(0xFF69F0AE),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFF9800),
    danger: Color(0xFFF44336),
    dangerAccent: Color(0xFFFF5252),
  );

  /// Light, bright and readable (desktop-client like).
  factory TsPalette.light() => const TsPalette(
    background: Color(0xFFF2F4F8),
    appbar: Color(0xFF26364E),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE8ECF2),
    card: Color(0xFFFFFFFF),
    divider: Color(0xFFD0D6E0),
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF5A6472),
    textMuted: Color(0xFF8A94A2),
    accent: Color(0xFF1976D2),
    accentAlt: Color(0xFF8E44AD),
    accentName: Color(0xFF00796B),
    success: Color(0xFF2E7D32),
    warning: Color(0xFFE65100),
    danger: Color(0xFFC62828),
    dangerAccent: Color(0xFFD32F2F),
  );

  /// AMOLED: pure black surfaces and maximum contrast. Saves battery on
  /// organic display panels and is the user's explicit call.
  factory TsPalette.amoled() => const TsPalette(
    background: Color(0xFF000000),
    appbar: Color(0xFF000000),
    surface: Color(0xFF0A0A0A),
    surfaceAlt: Color(0xFF151515),
    card: Color(0xFF0D0D0D),
    divider: Color(0xFF222222),
    textPrimary: Color(0xFFF5F5F5),
    textSecondary: Color(0xFF9E9E9E),
    textMuted: Color(0xFF666666),
    accent: Color(0xFF2196F3),
    accentAlt: Color(0xFFB388FF),
    accentName: Color(0xFF64FFDA),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFFFB74D),
    danger: Color(0xFFFF5252),
    dangerAccent: Color(0xFFFF5252),
  );

  static TsPalette forMode(AppThemeMode mode) => switch (mode) {
    AppThemeMode.light => TsPalette.light(),
    AppThemeMode.amoled => TsPalette.amoled(),
    _ => TsPalette.dark(),
  };

  @override
  TsPalette copyWith({
    Color? background,
    Color? appbar,
    Color? surface,
    Color? surfaceAlt,
    Color? card,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentAlt,
    Color? accentName,
    Color? success,
    Color? warning,
    Color? danger,
    Color? dangerAccent,
  }) => TsPalette(
    background: background ?? this.background,
    appbar: appbar ?? this.appbar,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    card: card ?? this.card,
    divider: divider ?? this.divider,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    accentAlt: accentAlt ?? this.accentAlt,
    accentName: accentName ?? this.accentName,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    dangerAccent: dangerAccent ?? this.dangerAccent,
  );

  @override
  TsPalette lerp(TsPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TsPalette(
      background: l(background, other.background),
      appbar: l(appbar, other.appbar),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      card: l(card, other.card),
      divider: l(divider, other.divider),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      accentAlt: l(accentAlt, other.accentAlt),
      accentName: l(accentName, other.accentName),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      dangerAccent: l(dangerAccent, other.dangerAccent),
    );
  }
}

/// Convenience accessor: `context.ts.background`.
extension TsThemeContext on BuildContext {
  TsPalette get ts => Theme.of(this).extension<TsPalette>() ?? TsPalette.dark();
}

/// Builds a full [ThemeData] from a palette, threading the palette through as
/// a [ThemeExtension] and matching the Material roles so stock widgets (cards,
/// app bars, inputs, dividers) stay consistent.
ThemeData buildThemeData(TsPalette palette, {required Brightness brightness}) {
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: palette.background,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: Colors.white,
      secondary: palette.accentAlt,
      onSecondary: Colors.white,
      error: palette.danger,
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.appbar,
      foregroundColor: palette.textPrimary,
      elevation: 0,
    ),
    cardColor: palette.card,
    dividerColor: palette.divider,
    extensions: [palette],
  );
}

// ─── Controller / provider ──────────────────────────────────────────

class AppThemeState {
  final AppThemeMode mode;
  const AppThemeState({this.mode = AppThemeMode.dark});

  AppThemeState copyWith({AppThemeMode? mode}) =>
      AppThemeState(mode: mode ?? this.mode);
}

class AppThemeNotifier extends Notifier<AppThemeState> {
  static const _prefKey = 'theme_mode';
  static const _light = 'light';
  static const _amoled = 'amoled';
  static const _system = 'system';

  @override
  AppThemeState build() {
    // Persisted value is loaded asynchronously: return the default now and
    // reconcile after the first microtask so the UI never flashes the wrong
    // theme on a cold start.
    Future<void>.microtask(_restore);
    return const AppThemeState();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored == null) return;
    final mode = switch (stored) {
      _light => AppThemeMode.light,
      _amoled => AppThemeMode.amoled,
      _system => AppThemeMode.system,
      _ => AppThemeMode.dark,
    };
    if (state.mode != mode) state = state.copyWith(mode: mode);
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.id);
  }
}

final tsThemeProvider = NotifierProvider<AppThemeNotifier, AppThemeState>(
  AppThemeNotifier.new,
);
