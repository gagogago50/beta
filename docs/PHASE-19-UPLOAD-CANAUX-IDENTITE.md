# Phase 19 — Envoi de fichiers (E7.3), gestion de canaux (E2), sauvegarde d'identité (B4), jitter (C3), recherche de clients (E9)

Date : 26 août 2026

## Objectif

Cette phase avale plusieurs chantiers restants de la parité fonctionnelle, du
confort et de la sécurité :

- **E7.3 — Envoi de fichiers + progression** : le moteur savait télécharger
  (icônes, avatars) mais pas *envoyer* ; l'UI n'avait aucun suivi de transferts.
- **E2 — Gestion des canaux** : créer / éditer / supprimer / déplacer un canal,
  avec mot de passe et limite de clients.
- **B4 — Sauvegarde / restauration d'identité** : l'identité TS3 est la seule
  donnée que l'utilisateur ne peut pas recréer ; on permet un export chiffré par
  mot de passe et une import.
- **C3 — Métriques réseau** : ajout du **jitter** (le moteur tsproto n'expose pas
  la taille de la file de retransmission, documenté comme limite).
- **E9 — Confort** : recherche de **clients** dans la liste.

## B4 — Sauvegarde / restauration d'identité

- `android/.../IdentityBackup.kt` : **PBKDF2-HMAC-SHA256** (200 000 itérations,
  sel aléatoire) + **AES-GCM**. Sortie autonome :
  `nekobackup1:<iterations>:<salt_b64>:<payload_b64>` (payload = IV || ciphertext,
  le tag GCM authentifie tout, donc un mauvais mot de passe ou un blob trafiqué
  échoue au lieu de produire du bruit). N'utilise que des APIs JSE
  (`java.util.Base64`, `javax.crypto`), donc validable hors Android SDK.
- `MainActivity.kt` : canal `com.senlinjun.nek0/identity_backup`
  (`encrypt` / `decrypt`), codes d'erreur stables (`bad_password`,
  `bad_format`).
- `lib/services/identity_backup_service.dart` + réglages : « Exporter l'identité »
  (copie le blob dans le presse-papiers) et « Importer l'identité » (saisie du
  blob + mot de passe, écrit en Keystore et poussé au moteur). L'identité ne
  traverse jamais Dart en clair sauf le mot de passe fourni par l'utilisateur.

## E7.3 — Envoi de fichiers + progression

### Moteur (`native/src/api.rs`, `lib.rs`)
- `Command::UploadFile` → `con.upload_file(...)` (tsclientlib gère `ftinitupload`).
  Le serveur répond par un `StreamItem::FileUpload(handle, {stream, seek_position})`
  ou `FiletransferFailed(handle, error)` ; on garde le job dans
  `Session.upload_jobs` (clé = handle moteur) pour retrouver l'id Dart.
- `spawn_file_upload` : lit le fichier local et écrit sur le socket, avec
  **événements `file_transfer_progress`** toutes les ~64 KiB et à la fin.
- `StreamItem::FileDownload`/`FileUpload`/`FiletransferFailed` gérés (prise de
  possession du `stream` → `handle_control_item` prend désormais l'item par
  valeur).
- `ts_upload_file(conn_id, channel_id, remote, password, source, overwrite)`
  (taille bornée par `TRANSFER_HARD_LIMIT`, chemin remote doit commencer par `/`),
  et `ts_cancel_file_transfer` annule aussi les uploads en attente.
- tokio : features `fs` + `io-util` ajoutées.
- Coût anti-flood : `UploadFile` = 1.0, administration de canaux = 2.0.

### Dart
- `lib/models/file_transfer.dart` : `FileTransfer` (direction, octets, total,
  progression clampée 0..1, `done`/`ok`/`error`).
- `TsConnectionState.transfers` + `jitterMs` ; événements
  `file_transfer_progress`/`file_transfer` mis à jour dans `_handleEvent`.
- `MultiServerNotifier.uploadFile/cancelTransfer` ; façade `TsConnectionNotifier`.
- UI : bouton « Fichiers » dans la barre de contrôle (badge du nombre de
  transferts) → panneau avec barres de progression et un formulaire
  « uploader un fichier » (chemin local + chemin serveur).
- `server_screen.dart` : `_showTransfers`, `_TransferTile`, `_startUpload`.

## E2 — Gestion des canaux

### Moteur
- `Command::CreateChannel / EditChannel / DeleteChannel / MoveChannelTree`
  → messages `OutChannelCreateMessage`, `OutChannelEditMessage`,
  `OutChannelDeleteMessage`, `OutChannelMoveMessage`.
- FFI : `ts_create_channel`, `ts_edit_channel`, `ts_delete_channel`,
  `ts_move_channel_tree` (validation locale + longueurs bornées ; la permission
  est appliquée par le serveur, qui répond en `command_error` typé).

### Dart / UI
- `ChannelTree` : menu par canal (icône « plus ») → créer sous-canal / éditer /
  déplacer / supprimer.
- Dialogues de création/édition (nom, sujet, mot de passe, max clients,
  permanent / semi-permanent) et de déplacement (cible dans l'arbre).
- Façade `TsConnectionNotifier.createChannel/editChannel/deleteChannel/moveChannelTree`.

## C3 — Jitter

- `TsEvent::NetworkStats` gagne `jitter_ms` ; le moteur calcule le **jitter
  d'inter-arrivée** (moyenne absolue des différences entre RTT successifs,
  lissée en EWMA) dans `handle_control_item` (état `last_rtt_ms`/`jitter_ms`).
- Affiché dans la `ConnectionBar` à côté du RTT.
- **Limite** : tsproto n'expose pas la taille de la file de retransmission ; le
  « jitter » est fait, la « taille de la file » reste une amélioration à venir
  (imposerait un patch de tsproto).

## E9 tranche 2 — Recherche de clients

- `ClientList` devient un `StatefulWidget` avec une barre de recherche par
  pseudo (filtrage sur tous les clients du serveur, puis sur le canal courant).

## Validation

- Rust : `cargo test --locked` **24 tests OK** ; `cargo clippy -p tsclient -D
  warnings` **0 erreur** ; `cargo fmt -- --check` **OK**.
- Dart : `flutter analyze` **0 problème** ; `flutter test` **100 tests OK**
  (dont `test/file_transfer_test.dart`).
- Kotlin : `IdentityBackup.kt` compile avec `kotlinc` (JSE pur).

## Suite / limites
- **Thème clair** et **favoris par serveur** : restent à faire (le thème clair
  exige de remplacer les couleurs codées en dur dans tous les widgets, gros
  chantier).
- **Recherche de fichiers/canal d'un côté, ordre/lag de la file de retransmission**
  : documentés, non codés.
- **Build APK réel + test serveur réel** : toujours à faire sur machine ≥ 8 Go.
