# Phase 26 — Renommer un fichier (`ftrenamefile`) + info fichier (`ftgetfileinfo`)

> Objectif : compléter le gestionnaire de fichiers en s'inspirant des fonctions
> `ts3client_requestFile` / `ts3client_requestFileInfo` du client legacy. La phase 24 a ajouté
> lister / supprimer / créer un répertoire ; il restait le **renommage** (avec déplacement
> optionnel vers un autre canal) et la **consultation des métadonnées** d'un fichier.

## Logique du client legacy (sources `ts3-remote`)
- `ts3client_requestFileInfo` : interroge `ftgetfileinfo` (cid cpw name) → réponse
  `notifyfileinfo` avec `name/size/datetime`.
- Renommage : `ftrenamefile` (cid cpw tcid tcpw oldname newname) — permet de déplacer le
  fichier vers un autre canal (`tcid`).

### Protocole (Messages.toml du livre)
- `FileInfoRequest` (`ftgetfileinfo` cid cpw name) → `FileInfo` (`notifyfileinfo` cid name
  size datetime).
- `RenameFile` (`ftrenamefile` cid cpw oldname newname [tcid tcpw]).

## Ce qui a été implémenté

### Rust (`native/src/lib.rs` + `native/src/api.rs`)
- **`TsEvent::ServerFileInfo`** (`file_info`) `{ request_id, channel_id, path, name, size,
  modified, ok }` ; réponse émise sur `InMessage::FileInfo`.
- **Commandes** `RenameFile` et `FileInfoRequest` (coûts anti-flood ;
  `FileInfoRequest` fusionne les requêtes redondantes).
- **`Session.pending_file_info_requests`** : corrélation requête → réponse par
  `(channel_id, name)`.
- **FFI** `ts_rename_file` (avec `target_channel_id`/`target_channel_password` optionnels),
  `ts_file_info` (retourne `request_id`).
- **Event loop** : envoi `OutRenameFileMessage` / `OutFileInfoRequestMessage`.

### Dart
- **`ServerFileInfo`** (modèle) dans `server_file.dart` ; état `serverFileInfo`.
- **`TsNative.renameFile` / `fileInfo`**.
- **`ts_state.dart`** : actions `renameServerFile`, `fileInfo` ; handler `case 'file_info':`.
- **`server_screen.dart`** (`_FileBrowserSheet`) : bouton « Rename » → prompt nouveau nom →
  `renameServerFile` puis re-list.

### Tests
- `test/server_file_test.dart` : parsing `ServerFileInfo` (présent / défauts).

## Validation
- `cargo check`/`cargo clippy -p tsclient -D warnings` : OK.
- `flutter analyze` : 0 erreur ; `dart format --set-exit-if-changed` : propre ;
  `flutter test` : 140 tests (dont les nouveaux).

## État
- **Fait** : renommage (+déplacement) et info fichier.
- **Reste** : TSDNS multi-endpoints + `androidId` (couvert en partie par tsclientlib),
  refactor JNI direct PCM 16 bits (D4), validation appareil.
