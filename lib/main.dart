import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/app_localizations.dart';
import 'models/app_locale.dart';
import 'models/app_theme.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: TeamSpeakApp()));
}

class TeamSpeakApp extends ConsumerWidget {
  const TeamSpeakApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final mode = ref.watch(tsThemeProvider).mode;

    final dark = buildThemeData(TsPalette.dark(), brightness: Brightness.dark);
    final light = buildThemeData(
      TsPalette.light(),
      brightness: Brightness.light,
    );
    // AMOLED is a distinct dark palette, so it uses the dark branch but its own
    // colors. ThemeMode has no "highContrast", so a forced AMOLED is expressed
    // as dark with the amoled palette in both slots.
    final amoled = buildThemeData(
      TsPalette.amoled(),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'TeamSpeak',
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: switch (mode) {
        AppThemeMode.amoled => amoled,
        AppThemeMode.system => light,
        _ => dark,
      },
      darkTheme: switch (mode) {
        AppThemeMode.amoled => amoled,
        _ => dark,
      },
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        _ => ThemeMode.dark,
      },
      home: const HomeScreen(),
    );
  }
}
