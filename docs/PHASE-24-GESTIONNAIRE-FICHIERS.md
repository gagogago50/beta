# Phase 24 — Gestionnaire de fichiers serveur (`ftgetfilelist` / `ftdeletefile` / `ftcreatedir`)

> Objectif : porter la partie "file transfer" du client TeamSpeak 3.3.4 observée dans
> `ts3-remote`. Le moteur Rust expose déjà l'upload (`ftinitupload`) et le download
> (`ftinitdownload`) ; il manquait le **parcours du répertoire** d'un canal : lister,
> descendre dans les sous-dossiers, supprimer et créer un répertoire. Cette phase ajoute
> ces trois commandes et un navigateur de fichiers dans l'UI.

## Logique du client legacy (sources `ts3-remote`)

- `ts3client_requestFile` / `ts3client_requestFileInfo` : le client officiel interroge la
  liste des fichiers d'un canal (`ftgetfilelist`), renvoie une série de notifications
  `FileList` puis `FileListFinished`, et permet `ftdeletefile` / `ftcreatedir` depuis
  le menu contextuel du canal.
- Le canal cible et le mot de passe (`cpw`) accompagnent chaque commande ; la réponse est
  asynchrone (une notification multi-parts, pas une réponse synchrone), donc l'UI doit
  corréler une requête à sa réponse.

### Protocole (Messages.toml du livre)
- `FileListRequest` (`ftgetfilelist` cid cpw path) → une ou plusieurs `FileList`
  (`notifyfilelist` cid path name size datetime type@ft) puis `FileListFinished`.
- `DeleteFile` (`ftdeletefile` cid cpw name).
- `CreateDirectory` (`ftcreatedir` cid cpw dirname).

## Ce qui a été implémenté

### Rust (`native/src/lib.rs` + `native/src/api.rs`)
- **`TsServerFile`** `{ name, size, modified (epoch), is_directory }`, sérialisé vers Dart.
- **`TsEvent::ServerFileList`** (`file_list`) `{ request_id, channel_id, path, ok, error, files }`.
- **Commandes** : `RequestFileList`, `DeleteFile`, `CreateDirectory` (+ coûts anti-flood,
  supersedes sur `RequestFileList`).
- **`Session`** : `pending_file_requests: HashMap<(u64,String), u32>` et `next_request_id`.
- **`TsConnection.file_list_buffers`** : accumulateur par `(channel_id, path)`.
- **FFI** : `ts_list_files` (retourne `request_id`), `ts_delete_file`, `ts_create_directory`.
- **Event loop** : envoi des messages c2s (`OutFileListRequestMessage`,
  `OutDeleteFileMessage`, `OutCreateDirectoryMessage`) ; réception de `InMessage::FileList`
  (buffer) et `InMessage::FileListFinished` (émission de `ServerFileList`).

### Dart
- **`lib/models/server_file.dart`** : modèle `ServerFile` + `sizeLabel`, `fromJson`.
- **`ts_ffi.dart`** : `TsNative.listFiles` / `deleteFile` / `createDirectory`.
- **`ts_state.dart`** : champs `serverFiles`, `serverFilePath`, `serverFilesLoading`,
  `serverFilesError` + actions `listChannelFiles`, `refreshFilePanel`, `deleteServerFile`,
  `createChannelDirectory` ; handler `case 'file_list'` (corrélation par `request_id`).
- **`server_screen.dart`** : entrée « Files » dans le menu Tools + `_FileBrowserSheet`
  (`ConsumerWidget` réactif) — navigation, téléchargement vers le cache, suppression,
  création de répertoire.

### Tests
- `test/server_file_test.dart` : parsing + `sizeLabel`.

## Validation
- Rust : `cargo fmt`/`check`/`clippy -D warnings`/`test` via CI.
- Dart : `flutter analyze`/`test` + build APK via CI.

## État
- **Fait** : liste de fichiers par canal, téléchargement, suppression, création de répertoire.
- **Reste** : `ftgetfileinfo`, renommage (`ftrenamefile`), copie, validation appareil.
