# Phase 17 — Multi-serveurs (E8)

Date : 26 août 2026

## Objectif

Le client officiel TeamSpeak permet de rester connecté à **plusieurs serveurs en
simultané**. Avant cette phase, le moteur Rust exposait **une seule connexion
globale** (`STATE` unique), le mic et l'audio partageaient un état mono-session,
et l'UI n'affichait qu'un seul serveur. C'était la refonte la plus lourde de la
parité fonctionnelle (E8).

Cette phase introduit une **table de sessions indexée par `connection_id`** côté
moteur, une **couche Dart multi-serveur** (une seule boucle de poll, infra
partagée, une façade d'actions par session) et une **UI à onglets** (un onglet
par serveur).

## Architecture moteur (`native/src/lib.rs`, `native/src/api.rs`)

### Registre de sessions

- `ConnectionId = u64`, distribué par `NEXT_CONNECTION_ID` (jamais réutilisé :
  un événement tardif d'une vieille session ne peut pas être attribué à une
  nouvelle).
- `Session` regroupe, par connexion : `state: Arc<Mutex<TsConnection>>`
  (partagé entre la boucle d'événements et les points d'entrée FFI),
  `command_tx`, `command_budget` (anti-flood), `pending_transfers`,
  `next_transfer_id`, `server_host`, `generation`, `event_loop_alive`,
  `connect_task`, `connection` (stash pour le reconnect synchronisé).
- `SESSIONS: DashMap<ConnectionId, Session>` remplace l'ancien `STATE` unique.

### Événements enveloppés

- `EnvelopedEvent { connection_id, #[serde(flatten)] event }`.
- Une **file globale** (`EVENT_QUEUE`) est drainée par un seul `ts_poll_events`.
  Dart a donc **une** boucle de poll et **un** appel FFI pour tous les serveurs ;
  chaque événement est routé vers sa session via `connection_id`.
- `connection_id == 0` = diagnostic moteur (logs de panic).

### Audio namespacé

- `AudioKey = (ConnectionId, u16)` : deux serveurs peuvent réutiliser le même
  id numérique de client sans collision.
- `CLIENT_BUFFERS`, `AUDIO_DECODERS`, `AUDIO_DECODERS_STEREO` et
  `ACTIVE_CLIENT_IDS` sont indexés par `AudioKey`.
- **Un seul flux cpal** mixe toutes les sessions actives (Phase A : collecte
  d'une trame par source ; Phase B : atténuation `1/sqrt(active)`).
- `ensure_output_stream_running()` **ne réinitialise pas** la lecture quand un
  second serveur se connecte ; `restart_output_stream()` (changement de route
  matérielle / erreur de flux) reconstruit en vidant tous les buffers.
- `CLIENT_VOLUMES` (par UID) reste global : le UID TeamSpeak d'un utilisateur
  est le même sur tous les serveurs, donc un volume par utilisateur est
  naturellement partagé.
- La tâche de maintenance (snapshot/cleanup) n'est lancée **qu'une seule fois**
  (`MAINTENANCE_STARTED`).

### FFI session-aware

Toutes les fonctions *par session* prennent `connection_id` en **premier
argument** (`ts_get_channels(cid)`, `ts_set_muted(cid, …)`, …) ; `ts_connect`
**retourne** le `connection_id` nouvellement alloué. Les fonctions *moteur* ne
changent pas : `ts_set_identity`, `ts_get_identity`, `ts_clear_identity`,
`ts_set_log_level`, `ts_set_event_notifier`, `ts_poll_events`,
`ts_restart_audio_output`.

### Cycle de vie

- `finalize_disconnect(cid, …)` marque la session déconnectée, pousse
  l'événement `disconnected`, vide la queue de commandes, retire l'audio de la
  session, **ne coupe le flux cpal que s'il s'agissait du dernier serveur**, puis
  retire la session de la table.
- Le mic **ne transmet que dans la session active/focalisée** (`ts_start_audio`,
  `ts_send_audio`, `ts_stop_audio` prennent `cid`). C'est un choix assumé, calqué
  sur le modèle « activer l'onglet dans lequel on parle » du client de bureau —
  il évite d'encoder N fois le même micro.

## Architecture Dart

### Modèles (`lib/models/ts_state.dart`)

- `TsConnectionState` porte maintenant `connectionId` (0 = vide/moteur).
- `MultiServerState { sessions: Map<int, TsConnectionState>, order: List<int>,
  selectedId: int?, labels: Map<int, String> }` : l'instantané de toutes les
  connexions, l'ordre des onglets et les libellés.
- `TsSessionView { state, actions }` : la vue par session (état + façade
  d'actions) exposée par `tsSessionProvider(cid)`.

### Contrôleur unique `MultiServerNotifier`

- Une seule boucle de poll (`_scheduleNextPoll` / `_pollEvents`), une seule
  infrastructure partagée (ForegroundService, réseau, cycle de vie, focus
  audio, mic, notification agrégée).
- `_pollEvents()` route chaque `TsEngineEvent` vers sa session via
  `connection_id`.
- Reconnexion par session (backoff + jitter), historique chiffré par serveur
  (`serverUid`), whisper par session, chat fils par session, reconnect au
  `channelToRestore` par session.
- `setChatHistoryEnabled`/`setChatRetention`/`setAudioEffects`/`setAudioRoute`
  s'appliquent à toutes les sessions (préférences globales).
- `tsSelectedProvider` renvoie la session focalisée (état + actions).

### Façade par session `TsConnectionNotifier`

- Une instance par session, construite par `controllerFor(cid)`, qui délègue
  toutes les actions au contrôleur avec le `connectionId` encodé. Les widgets
  gardent donc le même type `TsConnectionNotifier` et les mêmes noms de
  méthodes.

### UI (`lib/screens/server_screen.dart`)

- `ServerScreen` devient un écran à onglets : un `TabBar` par serveur (libellé =
  adresse avant connexion, nom de serveur ensuite), un `TabBarView` avec un
  `_SessionTab` par session, une croix pour fermer une session, et un `+` pour
  connecter un serveur supplémentaire depuis les favoris.
- Chaque `_SessionTab` réutilise l'ancienne mise en page (arbre de canaux, liste
  de clients, barre de contrôle, chat) liée à `tsSessionProvider(cid)`.
- `_maybeShowOemGuide` est déclenché à la première connexion.
- La navigation ne rebascule vers l'accueil que lorsque **toutes** les sessions
  sont fermées.

### Services

- `lib/services/ts_ffi.dart` : chaque fonction session-scopée prend
  `connectionId` ; `pollEvents` renvoie `List<TsEngineEvent>`.
- `lib/services/audio_service.dart` : `connectionId` de la session focalisée.
- `lib/services/icon_cache.dart` : `connectionId` pour les téléchargements
  d'icônes/avatars ; le déduplication en vol est scopé par serveur
  (`serverUid`), car deux serveurs peuvent partager un même id d'icône.

## Micro/téléphone et notification

- Une seule notification de premier plan pour N serveurs : titre « N servers »,
  texte = noms des serveurs ; actions globales (mute / full-mute / déconnexion
  de tout).
- `KeepAliveService.onTaskRemoved` (swipe de l'app depuis les récents) appelle
  le JNI `tsDisconnect` qui **déconnecte toutes** les sessions.

## Validation

- Rust : `cargo test --locked` **23 tests OK** ; `cargo clippy --locked -p
  tsclient -- -D warnings` **0 erreur**.
- Dart : `flutter analyze` **0 problème** ; `flutter test` **88 tests OK**
  (dont `test/multi_server_test.dart` — nouveau).

## Limites / prochaines étapes

- **Micro-test** (settings) : avec la nouvelle exigence d'une session pour
  encoder, le test micro ne fonctionne plus sans connexion ; il faudra soit
  l'autoriser via une session de test, soit le garder derrière une connexion.
- **Notifications sonores d'événements** et **envoi de fichiers** (E2/E7.3
  restants) demeurent hors périmètre.
- La **vérification sur appareil réel** (multi-serveur simultané, mixe audio
  multi-serveurs, notification agrégée) reste à faire sur une machine ≥ 8 Go.
