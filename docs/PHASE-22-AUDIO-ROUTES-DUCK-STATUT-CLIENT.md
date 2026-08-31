# Phase 22 — Parité audio (routes auto + duck/unduck) et statut client complet

> Objectif : poursuivre la convergence avec le client TeamSpeak 3.3.4 en s'appuyant sur le
> code déobfusqué (`core_deobfusque/`). Cette phase traite trois manques identifiés dans les
> notes de logique : (A) la **route auto réellement choisie**, (F) le **duck/unduck** au focus
> audio, et la **séparation des propriétés client** (talk power, priorité, enregistrement,
> requête serveur, commandeur de canal) — que le livre tsclientlib expose mais que notre
> `TsClient` n'utilisait pas. S'ajoutent les filtres `ignore*` du carnet de contacts et le
> pré-aplatissement de l'arbre de canaux.

## Logique du client legacy (sources `core_deobfusque/`)

### `AudioRouteManager` (C4410m) — priorité de route
- 4 routes : `EARPIECE`(0), `SPEAKER`(1, si `config.handsfree`), `WIRED_HEADSET`(2),
  `BLUETOOTH_SCO`(3, si `config.bluetoothAllowed`).
- **`selectRoute()`** : priorité observée **speaker > filaire > Bluetooth autorisé > earpiece**.
- Changements de disponibilité publics via `onRouteAvailabilityChanged` (réactif).
- Filaires : `onWiredHeadsetState(state==1 → dispo, ==0 → indispo)`.
- **`connectBluetoothVoice()`** : **jusqu'à 10 essais, 500 ms entre essais** (déjà porté).

### `AudioSessionController` (C4396c) — duck/unduck
- `onAudioFocusChange` : `LOSS_TRANSIENT_CAN_DUCK`/`LOSS_TRANSIENT`/`LOSS` → **`duck()`** ;
  `GAIN` → **`unduck()`**.
- **`duck()`** : sauve `modeBeforeDuck` + `volumeBeforeDuck`, stoppe la session (capture+playback),
  `MODE_NORMAL`, `setStreamVolume(volume/2)`, `ducked=true`.
- **`unduck()`** : `setMode(modeBeforeDuck)`, relance la session, `setStreamVolume(volumeBeforeDuck)`.
- Pour notre app (audio via cpal dans Rust, volume maître) : le duck baisse le **volume maître**
  d'≈ −6 dB pour la durée de la perte de focus, et le unduck le restaure ; le silence du micro
  reste côté Dart.

### PTT : `INPUT_DEACTIVATED` vs `INPUT_MUTED`
- `setPtt(talking)` → **`INPUT_DEACTIVATED`** 0/1 (+ `voiceactivation_level=-50` si PTT).
- `setMicMuted(muted)` → **`INPUT_MUTED`** 0/1 + `flushClientSelfUpdates`.
- Équivalence dans notre app : le micro n'est capturé que si `_shouldMicBeActive`
  (PTT pressé **ou** non-mute) → mute et PTT relâché coupent la transmission.

### Propriétés du `Client` du livre tsclientlib (généré `ts_bookkeeping::data::Client`)
`client_type`, `talk_power`, `talk_power_granted`, `is_priority_speaker`,
`is_channel_commander`, `is_recording`, `input_hardware_enabled`, `output_hardware_enabled`,
`output_only_muted`, `phonetic_name`, `country_code`, `metadata`, `avatar_hash`.
`ClientType` = `Normal` | `Query { admin }` (ré-exporté à la racine `tsclientlib::ClientType`).

## Ce qui a été implémenté

### 1. `native/src/lib.rs` + `native/src/api.rs` — `TsClient` enrichi
- 13 nouveaux champs, alimentés par `refresh_from_book` (`c.<field>` du book).
- `client_type` : 0=normal, 1=server query (`match c.client_type { Normal => 0, Query{..} => 1 }`).
- Un seul site de construction de `TsClient` (dans `refresh_from_book`).

### 2. `lib/models/client.dart` — `TsClient` Dart
- Nouveaux champs + `fromJson`/`copyWith` + getters `isQuery`, `groupIconIds`.
- Défauts sûrs : `inputHardwareEnabled`/`outputHardwareEnabled`=true, autres=0/''/false.

### 3. `lib/widgets/client_list.dart` — indicateurs visuels
- `_clientIcon` : query→`smart_toy`, outputMuted→`headset_off`, inputMuted→`mic_off`,
  away→`access_time`, commandeur→`star`, priorité→`record_voice_over`, enregistrement→
  `fiber_manual_record`, sinon `person`.
- `_clientColor` : query→violet, away→secondary, muted→warning, commandeur→warning,
  priorité→accent, sinon success.
- Badges d'angle `_CornerBadge` (commandeur étoile, priorité haut-parleur, enregistrement point
  rouge) + marqueur `(query)` italique.

### 4. `lib/widgets/channel_tree.dart` — arbre pré-aplati (cache)
- Remplace la récursion (un `Column` par nœud) par une **liste plate** `(channel, depth)`
  pré-triée et **mémorisée** (`_rows` + `_flatDirty`), reconstruite seulement si
  `channels`/`favoriteChannelIds`/`sortAlphabetically`/`_expanded` changent.
- Équivalent du `rebuildVisibleTree()` legacy (racines `parentId==0` triées par `order`, puis
  aplatissement récursif des enfants triés, en respectant la pliure).
- Améliore la virtualisation (`ListView.builder` sur toute la hiérarchie) et évite de recalculer
  `children`/`_sort` par nœud.

### 5. `lib/models/ts_state.dart` — duck/unduck + filtres contacts
- `MasterVolumeNotifier.setVolumeLive(db)` : applique au moteur **sans persister** (un duck
  transitoire ne doit pas écraser la valeur choisie en réglages).
- `_duckMasterVolume()`/`_unduckMasterVolume()` : mémorise le volume maître, le baisse de
  `_duckDbOffset` (6 dB), le restaure au regain.
- `_onAudioFocusLost` → duck + mute micro ; `_onAudioFocusRegained` → unduck + unmute (si c'était
  le focus qui avait coupé le micro).
- `_contactForClient(cid, clientId)` : lit le carnet de contacts pour un client vivant
  (clé `contact_<server_uid>_<uid>`), échoue « ouvert » (null) si inconnu.
- Filtrage `text_message` : `ignorePrivateChat` (cible 1) et `ignorePublicChat` (cible 2/3)
  avant stockage — logique de `ConnectionBackground.onTextMessage`.

## Validation
- `cargo fmt --check` **OK** ; `dart format` **OK** ; `flutter pub get`/`gen-l10n` **OK**.
- `cargo check` **échec local (OOM)** : la compilation de `ts_bookkeeping` dépasse la RAM du
  sandbox (≈2 Go), même avec `debuginfo=0` et `-j1`. La vérification Rust se fait donc dans la
  CI (runner 7 Go) via `.github/workflows/ci.yml` (jobs `rust` et `flutter`).
- `flutter analyze` / `flutter test` : voir l'état de la CI.

## État
- **Fait** : duck/unduck, statut client complet, filtres `ignore*`, arbre pré-aplati.
- **Reste** : TSDNS multi-endpoints + `androidId`, refactor JNI direct PCM 16 bits (D4),
  recherche globale, gestionnaire de fichiers, validation appareil sur `voice.teamspeak.com`.
