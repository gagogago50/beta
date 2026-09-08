# Plan d'implémentation — fonctionnalités restantes (sept 2026)

> Source de vérité : `ts3-remote` (client décompilé + catalogue JNI + livre `tsclientlib`).
> Le plan ne liste que ce qui manque encore (voir `RAPPORT-PARITE-COMPLET-2026-09.md`),
> et précise le **nom exact des parts c2s/s2c générées** (fichier `out/*.rs`) pour chaque
> commande, afin d'implémenter au premier coup. Chaque lot est validé par la CI puis audité.

Légende effort : **S** ≤ ½ j · **M** 1–2 j · **L** > 2 j.

---

## Lot A — Administration de clients/canaux (M1–M8) — *le plus gros écart, priorité 1*

### A1. Ban enrichi (UID / DBID / IP) + liste des bans + delete (M2)
- **Commandes Rust** déjà générées :
  - `OutBanAddPart { ip:Option<IpAddr>, name:Option<Cow<str>>, uid:Option<Cow<Uid>>, time, ban_reason }`
  - `OutBanClientPart { client_id:ClientId, time, ban_reason }` (existant pour ban par clid)
  - `OutBanDelPart { ban_id }`, `OutBanDelAllMessage`, `OutBanListRequestMessage`.
  - **Réponse s2c** : `InBanListPart { ban_id, ip, name, uid, my_ts_id, last_nickname, created, duration, invoker_database_id, invokername, … }`.
- **FFI** : `ts_ban_address(ip, name, seconds, reason)` (banadd) ; `ts_ban_uid(uid, seconds, reason)` ;
  `ts_ban_dbid(db_id, seconds, reason)` ; `ts_ban_delete(ban_id)` ; `ts_ban_delete_all()` ;
  `ts_list_bans()` → événement `ban_list`.
- **UI** : menu client → « Ban (par identité) », « Ban par adresse/IP » ; menu outils → « Bans » (liste + delete).

### A2. Groupes serveur : ajouter/retirer un client (M3)
- `OutServerGroupAddClientPart { server_group_id:ServerGroupId, client_db_id:ClientDbId }`
- `OutServerGroupDelClientPart` (idem).
- **FFI** : `ts_add_client_to_group(db_id, group_id)` ; `ts_remove_client_from_group(db_id, group_id)`.
- **UI** : menu client → « Groupes serveur » (liste `serverGroupIds` + un picker, ajout/retrait).

### A3. Complain (plainte) (M4)
- `OutComplainAddPart { target_client_db_id:ClientDbId, message:Cow<str> }`.
- **Réponse** : `InComplainListPart { target_client_db_id, target_name, from_client_db_id, from_name, message, timestamp }`.
- **FFI** : `ts_complain_add(client_id, message)` ; `ts_list_complains()` → événement `complain_list`.
- **UI** : menu client → « Signaler » (plainte avec message).

### A4. Marquer « talker » (fait taire) (M5)
- **Attention** : `requestClientSetIsTalker` est une fonction **SDK native** (`ts3client_requestClientSetIsTalker`) qui n'a pas de commande protocole publique dans ce livre (grep `client_set_is_talker` vide). → À **marquer SDK-only** et ne pas porter tant que le livre ne l'expose pas. *Alternative non protocole* : `requestClientKickFromChannel`/`requestMuteClients` (déjà faits) pour faire taire un client — utiliser le mute par contact (`requestMuteClients`) déjà présent.

### A5. Passerelle de permissions & description du canal (M7/M8)
- **Description** : `OutChannelDescriptionRequestPart { channel_id:ChannelId }` ;
  réponse `InChannelDescriptionChanged` (s2c, porte le texte → à lire dans le book ? vérifier le champ).
- **FFI** : `ts_channel_description(channel_id)` → événement `channel_description` ; afficher dans la fiche canal.
- **Permissions** : `OutClientPermListRequestPart` / `OutChannelPermListRequestPart` /
  `OutServerGroupPermListRequestPart` → `InPermissionList`/`InPermissionOverview`.
  → **FFI** `ts_client_permissions(client_id)` (lecture), à afficher en lecture seule.

### A6. Mot de passe temporaire serveur (M6)
- **Commandes** ? Le livre expose-t-il `ServerTemporaryPasswordAdd`/`Del`/`List` ?
  → grep : pas de part `OutServerTemporaryPassword*` trouvée → **likely SDK-only** ; à confirmer
  (le SDK expose `ts3client_requestServerTemporaryPasswordAdd/Del/List`, mais le protocole
  complet `servertemppasswordadd` n'est peut-être pas dans les Messages.toml du livre).
  → À marquer **SDK-only** sauf si le livre l'expose.

### A7. Subscribe/unsubscribe d'un canal (M1)
- `OutChannelSubscribePart { channel_id }`, `OutChannelUnsubscribePart { channel_id }` (déjà générés).
- **FFI** : `ts_subscribe_channel(cid)` / `ts_unsubscribe_channel(cid)`.
- **UI** : menu canal → « S'abonner / Se désabonner ».

---

## Lot B — Ergonomie audio/PTT (priorité 2)

### B1. PTT clavier (hotkeys) multi-touches (M11)
- Inspiré de `PttController` (BitSet combinaisons + interception + `onAllKeysReleased`).
- **Objectif** : en plus du bouton, permettre de configurer une **touche de pousser-pour-parler**
  persistée, gérée globalement (KeyEvent) → `setPttPressed`.
- **Flutter** : `KeyboardListener` + `RawKeyboard`/`HardwareKeyboard`/`Focus` (éviter `KeyEvent` déprécié).
- Persistance dans `SharedPreferences` (string de scancodes).

### B2. PTT forcé par le serveur (M12)
- Écouter `command_error` (permission) / événement `talkpower` ; si le canal exige un PTT,
  forcer `setVadEnabled(false)` + `INPUT_DEACTIVATED=1` + `voiceactivation_level=-50`.
- **Implémentation** : dans `ts_state.dart`, ajouter `forcedPtt` ; basculer au recalcul du
  `canTalkInCurrentChannel`. Porter éventuellement `setClientSelfInt(INPUT_DEACTIVATED)`.

### B3. `androidId` + port dédié (M9/M13)
- FFI `ts_connect` : ajouter un paramètre `android_id` (via `android.provider.Settings.Secure`).
- UI : champ **port** séparé (défaut 9987) et booléen « résoudre en nom de serveur TS ».
- `tsclientlib` gère déjà la résolution TSDNS ; exposer `host:port` dans `effectiveHost`.

---

## Lot C — Richesses moteur/affichage (priorité 3)

### C1. États de parole détaillés (M14)
- `talkStatus` (0=non, 1=talking, 2=whisper) + `whisperStatus` ; indicateur « tu parles » robuste.
- Ajouter `isTalker` (qui parle) à `TsClient` (le livre a `client_is_talker`).

### C2. Stats serveur complètes (M24)
- `ConnectionServerData` : bandwidth, bytes, packets, uptime, connect_time → `TsEvent::NetworkStats`
  enrichi. `OutServerConnectionInfoRequest`.
- **UI** : panneau stats (bandwidth up/down, packets, uptime).

### C3. `setBackgroundActionState` / export cache (M20)
- Équivalent `_onForegroundChanged` robuste : suspendre le décodage audio idle en arrière-plan
  (réutiliser la maintenance adaptative) + `tsclientlib` a peut-être `set_background_action_state`
  (`OutServerConnectionInfo` ?) — sinon un flag moteur.

### C4. Amélioration d'identité (niveau affiché) (M21)
- Afficher le niveau d'identité couru pendant `IdentityLevelIncreasing` ; éventuellement bouton
  « Améliorer mon identité » (tsclientlib `improve_identity`).

---

## Lot D — Qualité (sécurité/tests) — transversal, à chaque lot

- **Audit de faille** post-implémentation : (1) chemins de fichiers sûrs, (2) bornes de taille
  (8 Mo), (3) redaction des logs pour UID/DBID/adresse, (4) anti-flood (coût des nouvelles
  commandes), (5) corrélation requête→réponse (ids), (6) **captures** de valeurs non attendues
  (Option → unwrap_or), (7) `catch_unwind` sur event-loop déjà en place, (8) tests unitaires
  sur les nouveaux sanitizers.
- **Tests** : ajouter des tests Rust (sanitiser bans/groups/permissions) + un test Dart par
  nouvelle action/état.

## Ordre d'exécution
1. **A7 + A1** (subscribe/unsub + ban enrichi) — fermes, protocole clair, gros impact.
2. **A2 + A3** (groupes + complain) — simples, ajoutent les menus client.
3. **A5** (description + permissions lecture) — enrichit la fiche canal.
4. **B2 + B1** (PTT forcé + hotkeys) — ergonomie.
5. **C2 + C1** (stats serveur + états de parole).
6. **A6 + A4 + M13/M21** (SDK-only : documenter ou porter si dispo).

> Chaque lot : `cargo fmt` + `cargo clippy -D warnings` + `flutter analyze` + `flutter test`
> localement, puis push déclenchant la CI.
