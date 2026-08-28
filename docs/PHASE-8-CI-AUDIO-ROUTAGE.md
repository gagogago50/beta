# Phase 8 — CI, effets audio de la plateforme et routage de sortie

Traite les points **A3**, **D1** et **D2** de `RESTE-A-FAIRE.md`.

## A3 — Intégration continue rétablie

Le workflow amont ne se déclenchait que sur les tags et embarquait l’OTA supprimé depuis ;
il avait été retiré. Nouveau `.github/workflows/ci.yml`, sur **chaque push et chaque PR** :

| Job | Étapes |
|---|---|
| `rust` | `cargo fmt --check`, `cargo check --locked`, `cargo clippy -p tsclient -- -D warnings`, `cargo test --locked` (+ en-têtes ALSA, cpal en dépend sur l’hôte Linux) |
| `audit` | `cargo audit` en `continue-on-error` — une alerte publiée entre deux commits ne doit pas bloquer une fusion, mais reste visible |
| `flutter` | NDK r26d → `pre_build.py` (sans le `.so`, l’APK compile mais plante au démarrage), `pub get`, `gen-l10n`, **vérification que `lib/l10n/generated` est bien commité**, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, APK debug ; APK release `--split-per-abi` + artefacts uniquement sur tag |

`-D warnings` ne s’applique qu’à `-p tsclient` : les sources ReSpeak vendored portent
337 avertissements amont qu’un fork n’a pas vocation à corriger.

**Dette clippy soldée** dans notre crate pour rendre la règle tenable : casts inutiles,
emprunts superflus, `let` de valeur unité, `if` imbriqués, `Default` manquant sur
`ClientJitterBuffer`, et un `#[allow]` documenté pour l’idiome d’initialisation de tableau
`AtomicCell` (la constante n’est jamais partagée, elle est dupliquée par slot).

## D1 — AEC / NS / AGC

La source de capture était déjà `VOICE_COMMUNICATION`, mais **aucun effet n’était
instancié** : en haut-parleur, la voix des autres repartait dans le micro.

Nouveau `VoiceAudioController.kt` :

- `AcousticEchoCanceler`, `NoiseSuppressor`, `AutomaticGainControl` attachés à
  l’`audioSessionId` de l’`AudioRecord`, chacun indépendamment et **sous condition
  d’`isAvailable()`** — un appareil qui n’en implémente qu’un doit quand même l’obtenir ;
- `MODE_IN_COMMUNICATION` activé **avant** l’attachement : sans mode voix, l’annuleur d’écho
  n’a pas de signal de référence lointain exploitable ;
- libération des effets avant celle de l’`AudioRecord` (ils référencent la session) ;
- disponibilité matérielle remontée à l’UI : un interrupteur non supporté est **désactivé et
  expliqué**, jamais coché sans effet ;
- défauts : AEC et NS activés, **AGC désactivé** — le gain micro manuel existe déjà et
  empiler les deux fait osciller le seuil du VAD ;
- bascule à chaud : changer un interrupteur ré-attache les effets sans couper le micro.

## D2 — Routage de la sortie

- Routes : automatique, écouteur, haut-parleur, casque filaire, casque USB, **Bluetooth
  SCO/BLE**. La liste est construite à partir des périphériques réellement présents
  (`AudioDeviceInfo`), et l’écouteur disparaît sur une tablette qui n’en a pas.
- Android 12+ : `setCommunicationDevice` / `clearCommunicationDevice`. API 28–30 (minSdk 28) :
  chemin hérité `isSpeakerphoneOn` / `startBluetoothSco`, isolé et documenté.
- `applyRoute` retourne la route **réellement** appliquée : un casque débranché pendant que le
  sélecteur est ouvert retombe en automatique, avec message à l’utilisateur.
- La route est ré-appliquée au démarrage du micro (l’entrée en mode communication peut la
  réinitialiser) et persistée dans les préférences.
- Permissions ajoutées : `MODIFY_AUDIO_SETTINGS`, et `BLUETOOTH_CONNECT` (Android 12+).

Côté Flutter : `AudioRouteService` (canal `com.senlinjun.nek0/audio`) qui **dégrade
proprement** — toute `PlatformException`/`MissingPluginException` laisse l’app fonctionner
avec le routage choisi par Android, exactement comme avant la fonctionnalité. Nouveau
`AudioOutputPanel` (puces de sélection + interrupteurs d’effets) dans les réglages.

## Vérification du code Kotlin

Gradle ne peut pas tourner dans cette sandbox (2 Go de RAM). Le code Android a donc été
compilé directement avec `kotlinc` contre `android.jar` (API 35) :

- `VoiceAudioController.kt` : **compile sans erreur ni avertissement** ;
- un harnais type-check les appels exactement comme `MainActivity` les fait (attache des
  effets, mode voix, liste et application des routes, route courante, Bluetooth) ;
- `MainActivity.kt`/`KeepAliveService.kt` complets restent non vérifiables hors Gradle
  (AndroidX, classe `R` générée) — c’est le job `flutter` de la CI qui les couvrira.

## Tests

- Dart (+5, **19 au total**) : aller-retour de chaque route par son identifiant de fil,
  correspondance exacte avec les constantes Kotlin (contrat inter-langages), dégradation d’un
  identifiant inconnu vers `auto`, valeurs par défaut de `AudioEffectSupport`.
- Rust : 6 tests inchangés, toujours verts.

## Validation

`cargo fmt` · `cargo check --locked` · `cargo clippy -p tsclient -- -D warnings` (0) ·
`cargo test` 6/6 · `kotlinc` OK · `flutter gen-l10n` · `dart format --set-exit-if-changed` ·
`flutter analyze` 0 · `flutter test` 19/19.

## Suite

1. **B1/B2** : logger central (les logs contiennent encore adresses et pseudos) et commande
   « effacer identité et secrets ».
2. **C1** : écoute de `ConnectivityManager` pour reconnecter immédiatement au retour du réseau
   au lieu d’attendre le backoff.
3. **D5** : `AudioFocusRequest` (interaction avec la musique et les appels entrants),
   complément naturel du travail de routage.
4. **A1/A2** : build APK et essai sur un vrai serveur — hors de portée de cette sandbox.
