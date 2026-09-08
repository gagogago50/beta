# Phase 29 — Administration de clients/canaux (Lot A : M1–M8)

> Objectif : combler le plus gros écart fonctionnel identifié dans le rapport de parité
> (`RAPPORT-PARITE-COMPLET-2026-09.md`, §3) — le « menu client/canal administratif » du
> client officiel : ban enrichi (UID/IP), liste des bans, subscribe/unsubscribe de canal,
> description de canal, groupes serveur et plaintes.

## Fonctionnalités ajoutées (moteur + UI)

| # | Fonction | Commande protocole | Part c2s / réponse s2c |
|---|---|---|---|
| M2 | **Ban par UID** (`banadd uid=…`) | `banadd` | `OutBanAddPart { ip,name,uid,time,ban_reason }` |
| M2 | **Ban par adresse/nom** (`banadd ip/name`) | `banadd` | `OutBanAddPart` |
| M2 | **Table des bans** (`banlist`) | `banlist` | `InMessage::BanList` → `TsEvent::BanList` |
| M2 | **Supprimer un ban** (`bandel`) | `bandel` | `OutBanDelPart { ban_id }` |
| M1 | **S'abonner / se désabonner** (`channelSubscribe/Unsubscribe`) | `channelsubscribe`/`channelunsubscribe` | `OutChannelSubscribe/UnsubscribePart { channel_id }` |
| M8 | **Description du canal** (`channeldescription`) | `channeldescription` | `InMessage::ChannelDescriptionChanged` + `OptionalChannelData.description` |
| M3 | **Ajouter/retirer un groupe serveur** (`servergroupaddclient`/`servergroupdelclient`) | `servergroupadd`/`del` | `OutServerGroupAdd/DelClientPart { server_group_id, client_db_id }` |
| M4 | **Plainte** (`complainadd`) | `complainadd` | `InMessage::ComplainList` → `TsEvent::ComplainList` |

### Nouveaux événements moteur
`ban_list`, `complain_list`, `channel_description`, `client_updated` (rafraîchissement roster
quand un groupe change).

### Nouvelles fonctions FFI (`ts_*`)
`ts_ban_uid`, `ts_ban_address`, `ts_ban_delete`, `ts_list_bans`, `ts_subscribe_channel`,
`ts_unsubscribe_channel`, `ts_channel_description`, `ts_add_client_to_group`,
`ts_remove_client_from_group`, `ts_complain_add`.

### `TsClient` enrichi
- Nouveau champ `database_id` (le livre expose `client.database_id: ClientDbId`), nécessaire
  pour `ban_dbid` et `servergroupadd/delclient`.

## Décisions d'implémentation
- **Ban par DBID** : le livre ne modélise pas `banclient cldbid` (pas de part générée) —
  il est couvert par le ban par **UID** (`banadd uid=…`, équivalent pour l'identité) et le ban
  **par client_id** (existant). → `ban_dbid` marqué « pas dans le livre » (SDK-only).
- **Décodeur UID base64** : `base64_decode_uid` intégré (RFC 4648, sans dépendance) car le champ
  `uid` de `OutBanAddPart` attend un `UidBuf` d'octets décodés.
- **`requestClientSetIsTalker`** (faire taire) : fonction **SDK-native** sans commande protocole
  publique → non portée (le mute par contact `requestMuteClients` couvre déjà « faire taire »).

## Audit de faille effectué
- `OutBanListRequestMessage::new()` sans arguments (pas d'itérateur) — corrigé.
- `time::Duration` utilise `whole_seconds()` (pas `as_secs()`) — corrigé.
- Clippy `-D warnings` : patterns `{ .. }` de variants unitaires (`ListBans`) — corrigés.
- Corrélation requête→réponse : idempotent (de-dup des bans par `ban_id`, accumulateur borné).

## Validation
- `cargo check`/`cargo clippy -p tsclient -D warnings` : OK.
- `flutter analyze` : 0 erreur ; `dart format --set-exit-if-changed` : propre ;
  `flutter test` : 142 tests.
- Rust engine CI : **success** (fmt/check/clippy/test).

## État / reste
- **Fait** : Lot A (M1/M2/M3/M4/M8).
- **Reste** : M5 (isTalker SDK-only), M6 (mot de passe temporaire SDK-only), M7 (liste des
  permissions), Lot B (PTT clavier + PTT forcé), Lot C (stats serveur, états de parole).
