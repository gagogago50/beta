# Phase 20 — Thèmes sombre / clair / AMOLED + jitter buffer adaptatif

Date : 26 août 2026

## Objectif

Deux axes, demandés explicitement :

1. **Thème** : l'app était entièrement en couleurs sombres codées en dur.
   Ajout d'un système sombre / clair / AMOLED / système, persistant, avec
   sélecteur dans les réglages.
2. **Latence & qualité audio (D3)** : le jitter buffer était à profondeur fixe
   (40 ms). Le rendre **adaptatif** au jitter réseau mesuré → latence minimale
   sur une liaison saine, profondeur qui grossit seulement quand le réseau
   l'exige (anti underrun), plafonnée pour ne pas exploser la latence.

## Thème (`lib/models/app_theme.dart`, `lib/main.dart`)

### Palette sémantique (`TsPalette`)

- Implémentation d'une **`ThemeExtension<TsPalette>`** : les rôles de couleur
  (`background`, `surface`, `card`, `divider`, `textPrimary`, `accent`,
  `success`, `warning`, `danger`, …) sont nommés, jamais des hex. Le rendu se
  lit via `context.ts.background`, etc.
- Quatre modes (`AppThemeMode`) : `system`, `dark`, `light`, `amoled`.
  - **dark** : navy profond (l'ancien look).
  - **light** : fond clair, cartes blanches, texte sombre (façon client bureau).
  - **amoled** : surfaces **noir pur** (`0x000000`) — économise la batterie des
    panneaux OLED, et maximale.
- `buildThemeData(palette, brightness:)` construit un `ThemeData` complet (Material
  3) qui **fait transiter la palette** en `extensions:[palette]` et aligne les
  rôles Material (colorScheme, appBar, cardColor, divider) sur la palette.

### Switch (main.dart)

- `MaterialApp.theme` / `darkTheme` / `themeMode` pilotés par `tsThemeProvider`.
  - `system` → `ThemeMode.system`.
  - `light` → `ThemeMode.light`.
  - `amoled` → `ThemeMode.dark` **avec** la palette AMOLED dans les deux slots.
  - `dark` → `ThemeMode.dark`.

### Persistance & sélecteur

- `AppThemeNotifier` (Riverpod) charge la préférence `theme_mode` depuis
  `SharedPreferences` (au démarrage, sans flash au mauvais thème) et la restitue.
- Réglages → nouvelle section **« Apparence »** avec une tuile par mode (icône +
  coche), à côté de Connexion.

### Conversion des widgets

- Tous les littéraux de couleur des `lib/screens/` et `lib/widgets/` ont été
  remplacés par des rôles de la palette :
  - `0xFF0F0F23→background`, `0xFF16213E→appbar`, `0xFF12122A→surface`,
    `0xFF1A1A2E→card`, `0xFF2A2A4A→divider`, `0xFF1F1F3A→surfaceAlt`,
  - `Colors.white→textPrimary`, `Colors.white70→textSecondary`, `Colors.grey→textSecondary`,
    `Colors.blue→accent`, `Colors.red→danger`, `Colors.green→success`, …
- Le `CustomPainter` du spotlight ne peut pas lire `context` ; la couleur
  d'accent y est maintenant **passée en paramètre** depuis le build.
- Corrections induites : suppression de `const` autour des expressions non
  constantes (`context.ts.x`), paramètres par défaut de couleur (ne peuvent
  pas référencer `context`), etc.

## Jitter buffer adaptatif (`native/src/api.rs`)

- `BASE_DELAY_FRAMES = 2` (40 ms) : la latence minimale sur liaison saine.
- `JITTER_TO_FRAMES_DIVISOR = 20` : +1 trame (20 ms) par tranche de 20 ms de
  jitter.
- `MAX_DELAY_FRAMES = 8` (160 ms) : plafond.
- `adaptive_delay_frames(conn_id)` lit le `jitter_ms` de la session et renvoie le
  nombre de trames cible.
- Appliqué aux **deux** points qui créent/rebassent la cartographie
  (init baseline et rebase après overrun), donc aux nouveaux buffers — les flux
  en cours gardent leur mapping (aucune rupture), et un nouveau locuteur démarre
  avec une profondeur adaptée au réseau actuel.

## Validation

- Dart : `flutter analyze` **0 problème** ; `flutter test` **107 tests OK**
  (dont `test/app_theme_test.dart` — palettes distinctes, AMOLED noir pur,
  `ThemeExtension`, `fromId`).
- Rust : `cargo test --locked` **25 tests OK** (dont
  `adaptive_delay_stays_bounded`) ; `cargo clippy -p tsclient -D warnings`
  **0 erreur** ; `cargo fmt --check` **OK**.
- Android : `minSdk = 28` (Android 9), `compileSdk/targetSdk` ceux de Flutter.

## Notes / suite

- Thème clair fonctionnel ; quelques accents ponctuels restent en hex (bouton
  PTT, chips) — cohérents mais non thématisables, amélioration cosmétique à
  terme.
- D3 « taille de la file de retransmission » : non exposée par tsproto (patch
  requis), documenté.
- Optimisations CPU (réutilisation des buffers `opus_out`/`pcm_out` dans la
  boucle d'encodage) : conservatrices, laissées pour ne pas fragiliser le
  chemin audio ; à évaluer après mesures sur appareil.
- **Build APK réel + test serveur réel** : toujours à faire sur machine ≥ 8 Go.
