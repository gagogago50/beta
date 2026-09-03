# Phase 27 — Utiliser une permission key (`privilegekeyuse` / `tokenuse`)

> Objectif : rapprocher l'app de la fonctionnalité d'**entrée de clé de permission**
> du client legacy (`enterTokenGUI`, C3988y). Un administrateur donne une *privilege key*
> à un utilisateur pour lui octroyer un groupe ; le client l'utilise via `privilegekeyuse`
> et reçoit `notifytokenused` en confirmation.

## Logique du client legacy (sources `ts3-remote`)
- `enterTokenGUI` : boîte de saisie de la clé de permission, puis `ts3client_requestTokenUse`
  (protocole `privilegekeyuse` avec l'attribut `token`).
- La réponse serveur `notifytokenused` confirme l'octroi (avec `token1`/`token2` = ids de
  groupe/canal, `clid`/`cldbid`/`cluid`).

### Protocole (Messages.toml du livre)
- `PrivilegeKeyUse` (`privilegekeyuse` token) → `TokenUsed` (`notifytokenused`).

## Ce qui a été implémenté

### Rust (`native/src/lib.rs` + `native/src/api.rs`)
- **`TsEvent::TokenUsed`** (`token_used`) `{ token, token1, token2, client_db_id }`.
- **Commande** `UseToken` (coût anti-flood 1.0).
- **FFI** `ts_use_token(conn_id, token)`.
- **Event loop** : envoi `OutPrivilegeKeyUseMessage` ; handler `InMessage::TokenUsed`.

### Dart
- **`TsNative.useToken`**.
- **`ts_state.dart`** : champ `tokenConfirmation`, action `useToken`/`clearTokenConfirmation`,
  handler `token_used`.
- **`server_screen.dart`** : entrée « Enter permission key » dans le menu Tools +
  `_promptPrivilegeKey` ; SnackBar de confirmation via `ref.listen(tokenConfirmation)`.

### Tests
- Aucun nouveau (la logique est dans le moteur/handler ; le flux UI est validé par analyse).

## Validation
- `cargo check`/`cargo clippy -p tsclient -D warnings` : OK.
- `flutter analyze` : 0 erreur ; `dart format --set-exit-if-changed` : propre ;
  `flutter test` : 142 tests.

## État
- **Fait** : utilisation d'une permission key + confirmation.
- **Reste** : TSDNS multi-endpoints + `androidId` (couvert en partie par tsclientlib),
  refactor JNI direct PCM 16 bits (D4), validation appareil.
