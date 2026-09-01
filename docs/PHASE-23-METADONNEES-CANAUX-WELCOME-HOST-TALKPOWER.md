# Phase 23 — Métadonnées canaux, welcome/host message serveur, droit de parole

> Objectif : rapprocher l'app du client TeamSpeak 3.3.4 en exploitant le modèle du livre
> Rust. Cette phase transpose les champs du canal et les variables serveur que le client
> officiel expose, et les affiche à l'utilisateur (arbre, fiche canal, fil serveur).

## Logique du client legacy (sources `core_deobfusque/`)

- **`ChannelModel`** porte : `neededTalkPower`, `maxClients`, `codec`, `iconId`,
  `defaultChannel`, `passwordProtected`, `persistence` (`PERMANENT` / `SEMI_PERMANENT` /
  `TEMPORARY`), `hiddenFromTree`, `hasChildren`, `expanded`, `clientsDirty`.
- **`ServerConnectionHandler`** (`C3613v`) : `showWelcomeMessage()` lit
  `VIRTUALSERVER_WELCOMEMESSAGE` et l'ajoute au chat si non vide ;
  `applyHostMessagePolicy()` respecte le mode du host message (afficher / modale / couper).
- **`ChatModel.Message`** porte `serverGenerated`, `highlighted`, `censored` ; l'onglet
  serveur reçoit les messages système.
- Le client desktop refuse de parler dans un canal dont `channel_needed_talk_power` dépasse
  le `client_talk_power` de l'utilisateur (sauf `talk_power_granted`).

## Ce qui a été implémenté

### Rust (`native/src/lib.rs` + `native/src/api.rs`)
- **`TsChannel`** : +10 champs (`needed_talk_power`, `max_clients`, `codec`, `codec_quality`,
  `channel_type`[0/1/2], `is_default`, `is_private`, `subscribed`, `icon_id`, `is_unencrypted`),
  alimentés depuis `book.channels` via `refresh_from_book`.
  - `codec` : `channel_codec_code(&Codec)` → 0..5 ; `channel_type` : `channel_type_code(&ChannelType)`
    → 0=temp, 1=permanent, 2=semi-permanent ; `max_clients` : `-1` illimité, `-2` hérité, sinon le plafond.
- **`TsEvent::Connected`** : +5 champs (`welcome_message`, `host_message`, `host_message_mode`,
  `max_clients`, `needed_identity_security_level`) depuis `book.server`.
  - Host-message mode : 0=none, 1=log, 2=modal, 3=modal+disconnect (`HostMessageMode`).

### Dart
- **`TsChannel`** (`lib/models/channel.dart`) : champs + `fromJson` + getters `isPermanent`,
  `isSemiPermanent`, `isUnlimitedClients`. Défauts sûrs.
- **`TsConnectionState`** (`lib/models/ts_state.dart`) : `welcomeMessage`, `hostMessage`,
  `hostMessageMode`, `maxClients`, `neededIdentitySecurityLevel` + getters `currentChannel` et
  `canTalkInCurrentChannel` (talk power).
- **Gestion welcome/host** : `_maybeHydrateServerMessages(cid, st)` appelle à la connexion :
  - welcome → ligne système dans le fil serveur ;
  - host mode 1 (log) → ligne système ;
  - host mode 2/3 → notice (`error`) ; mode 3 → `disconnect()`.
- **`channel_tree.dart`** : marqueurs par canal (défaut `home`, permanent `verified_user`,
  semi-permanent `schedule`, mot de passe `lock`, non-abonné `volume_off`, talk power `graphic_eq`).
- **`server_screen.dart`** : fiche canal enrichie (codec, max clients, talk power requis, type,
  badges « Default/Permanent/Password/Not subscribed/Private ») via `_infoRow`/`_infoBadges`.

### Tests
- `test/channel_metadata_test.dart` : parsing des champs riches + mapping `channel_type` +
  logique `canTalkInCurrentChannel` (requis, grant, insuffisant).

## Validation
- Rust : `cargo fmt`/`check`/`clippy -D warnings`/`test` via CI (le sandbox OOM sur
  `ts-bookkeeping`).
- Dart : `flutter analyze`/`flutter test` + build APK via CI (le SDK Flutter local est
  inopérant en sandbox).

## État
- **Fait** : métadonnées canaux, welcome/host message, indicateurs d'arbre, fiche canal,
  droit de parole (`canTalkInCurrentChannel`).
- **Reste** : TSDNS multi-endpoints + `androidId`, refactor JNI direct PCM 16 bits (D4),
  recherche globale, gestionnaire de fichiers `ftlist`/`ftdelete`, validation appareil.
