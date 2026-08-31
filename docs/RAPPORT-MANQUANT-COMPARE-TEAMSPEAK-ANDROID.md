# Rapport — écarts entre notre app et le client TeamSpeak Android 3.3.4

Date : 31 août 2026

Source : code source du noyau TeamSpeak Android décompilé, récupéré depuis le
serveur HTTP fourni (dossier `core_deobfusque/`, `inventaire_JNI_et_natif`,
`catalogue_fonctions_TeamSpeak_3.3.4.md`, `semantic_core.md`). Les commentaires
`[SOURCE]` du code décompilé décrivent un comportement confirmé ; on compare à
notre app (Flutter + Rust `tsclientlib` + Kotlin).

---

## 1. Ce que le client Android fait et que nous n'avons pas (en résumé)

| # | Comportement réel (observé) | Notre app | Importance |
|---|---|---|---|
| 1 | **Routes audio avec priorité** : speaker > filaire > Bluetooth SCO > earpiece. Le Bluetooth SCO est **connecté après 10 essais (500 ms)**. | Nous proposons un choix manuel ; pas de priorité auto ni de retry Bluetooth. | Haute |
| 2 | **PTT multi-touches** : plusieurs combinaisons de touches (BitSet), interception, `onAllKeysReleased`. | PTT = un simple bouton ; pas de raccourci clavier, pas de combinaison. | Moyenne |
| 3 | **Reconnexion avec délai minimal fixe de 3 s**, `reconnectAllowed`, `retryCount`/`retryLimit`, garde anti-double-retry, **état CONNECTED vs ESTABLISHED**. | Nous avons un backoff exponentiel + jitter ; pas de « minimum 3 s » ni d'état `ESTABLISHED` distinict. | Haute |
| 4 | **`forcedPtt`** : quand le serveur exige le PTT (permission), force `INPUT_DEACTIVATED=1` et `vad=false` à `-50`, et le **retourne** à VAD quand ce n'est plus requis. | Pas de gestion « PTT forcé par le serveur ». | Moyenne |
| 5 | **TSDNS / `tsdns`** : `parseTs3Address`, `isTsServerName`, résolution en **plusieurs endpoints**, `advanceEndpoint`, `effectiveHost/Port`. | Nous connectons directement à une adresse ; pas de résolution TSDNS ni d'itération endpoints. | Moyenne |
| 6 | **`androidId`** passé à `startConnection` (anti-reconnexion / profil). | Pas fourni. | Basse |
| 7 | **Contrats par contact** (`ContactSettings`) : `customName`, `displayMode` (pseudo affiché / `[customName] pseudo`), `muted`, `ignorePublicChat`, `ignorePrivateChat`, `ignorePokes`, `hideAway`, `hideAvatar`, `allowWhispers`, `volumeModifier` — **persistés en base**. | Nous n'avons que `clientVolumes` (par UID) ; pas de carnet de contacts par serveur avec ces options. | Moyenne |
| 8 | **Propriétés de client riches** : `talkPower`, `neededServerQueryViewPower`, `talkStatus`, `whisperStatus`, `prioritySpeaker`, `recording`, `serverMutedByContact`, `type` (NORMAL / SERVER_QUERY). | Nous avons `isTalking`/`isWhispering`/`away`/mute mais pas `talkPower`, `prioritySpeaker`, `recording`, `type`. | Moyenne |
| 9 | **MODÈLE d'arbre** : `rebuildVisibleTree()` — canaux triés par `order`, **aplati** récursivement, `moveClient`/`removeClient` tient `clientToChannel` à jour. | Notre `ChannelTree` trie à la volée ; la gestion de `clientToChannel` est plus diffuse. | Basse |
| 10 | **Chat** avec `serverGenerated`, `highlighted`, `censored`, `lastMessage`/`unreadCount`. | Nous avons `highlighted` implicite ; pas de `serverGenerated`/`censored`. | Basse |
| 11 | **`setPreProcessorConfig`** : `agc`, `vad`, `voiceactivation_level` (seuil VAD en dB). | Nous avons `setVadThreshold`/`setVadEnabled`/AGC via Kotlin ; pas de `voiceactivation_level` envoyé au moteur. | Basse |
| 12 | **`setClientSelfVariableAsInt` `INPUT_DEACTIVATED`** séparé de `INPUT_MUTED` (distinction activation PTT / mute). | Nous n'avons qu'un `setMuted` ; le PTT est géré côté Dart. | Moyenne |

---

## 2. Détail : fonctionnalités & façon de les implémenter

### 2.1 Routes audio avec priorité + retry Bluetooth (n°1)
**Dans `VoiceAudioController.kt`** (l'équivalent de `AudioRouteManager` C4410m) :
- Ajouter `selectRoute()` en **priorité speaker > filaire > BT (si autorisé) > earpiece**,
  en écoutant l'état du filaire (`onWiredHeadsetState`) et du BT (`onBluetoothDisconnected`).
- **Connecter le SCO Bluetooth en 10 tentatives de 500 ms** (`connectBluetoothVoice()`),
  comme observé.
- Notre Dart a déjà `availableRoutes`/`setRoute` ; renforcer la **priorité auto**
  et le **retry BT**.

### 2.2 Reconnexion type client (n°3)
Dans `ReconnectPolicy`/`_maybeScheduleReconnect` :
- Ajouter un **`minDelay = 3 s`** (on ne reconnecte jamais avant 3 s), en plus du
  backoff exponentiel.
- Distinguer **`connected`** (handshake réseau) et **`established`** (book serveur
  reçu) — le `connected` retourne déjà `TsPhase.connected` ; ajouter un état
  `ESTABLISHED` si l'UI le besoin (pour afficher « connecté »).
- Le **`reconnectAllowed`** (déconnecter manuellement = plus de retry) est déjà
  géré (on efface l'intention de reprise).

### 2.3 PTT forcé par le serveur (n°4)
- Écouter `command_error` avec permission `b_client_*_talk_power`/`needed_talk_power`
  ou un événement « talk power » du serveur. Quand le serveur refuse la VAD,
  passer en PTT forcé : `setVadEnabled(false)`, `setClientSelfVariable INPUT_DEACTIVATED=1`,
  et désactiver le VAD `/ voix` au seuil -50. Revenir à la VAD quand la permission disparaît.

### 2.4 TSDNS + multi-endpoints (n°5)
- Ajouter un **résolveur** côté Rust : `tsdns_parseTs3Address` / `isTsServerName` /
  `startResolve` (le moteur `tsclientlib` gère partiellement ; exposer une fonction
  qui retourne `[{host, port}]`). À l'échec d'un endpoint, `advanceEndpoint()`.
- Opportunité surtout pour des adresses type `voice.teamspeak.com` qui
  résolvent vers plusieurs IP.

### 2.5 Carnet de contacts (n°7, le plus structurant)
Nouveau modèle + persistance :
- `ContactSettings { uid, serverHandlerId, customName, displayMode, muted,
  ignorePublicChat, ignorePrivateChat, ignorePokes, hideAway, hideAvatar,
  allowWhispers, volumeModifier }`, persisté par (serveur, UID) dans une table
  `contacts` (SharedPreferences ou fichier Keystore, comme l'historique).
- `preferredDisplayName()` : `[customName] pseudo` / `customName` / `pseudo`.
- UI : fiche client (déjà présente) → élargir avec « mute », « ignorer le chat
  public/privé/pokes », « cacher avatar/away », « autoriser whisper ».
- Appliquer `muted`/`ignore*` à la réception (messages/pokes) et `volumeModifier`.

### 2.6 Propriétés de client supplémentaires (n°8)
Dans `TsClient` (Rust `refresh_from_book`) : exposer `talkPower`,
`prioritySpeaker`, `recording`, `type` (NORMAL/SERVER_QUERY), `talkStatus`,
`neededServerQueryViewPower`. `tsclientlib` fournit ces champs dans le livre ;
il suffit de les sérialiser.

### 2.7 Arbre : `flatten` + `clientToChannel` (n°9)
- Au lieu de recalculer les enfants à chaque rendu, pré-lister
  `rebuildVisibleTree()` (tri par `order`, aplatissement récursif) et maintenir
  `clientToChannel`. Neutre en perf (la liste est déjà triée) — l'important est
  d'avoir un « canal visible » = `rebuildVisibleTree`.

### 2.8 Chat : `serverGenerated` / `censored` (n°10)
- `ChatMessage` : ajouter `serverGenerated` (message système venant du serveur,
  sans auteur « invoker ») et `censored` (affiché masqué). Très facile à porter,
  le moteur `tsclientlib` et `TextMessage` le distinguent via `MessageTarget`.

### 2.9 Préprocesseur (n°11) & activation PTT (n°12)
- Kotlin/Rust : envoyer `agc`, `vad`, `voiceactivation_level` au moteur (au lieu
  de seulement `setVadThreshold` côté Dart).
- Distinguer `INPUT_DEACTIVATED` (PTT relâché) de `INPUT_MUTED` (mute manuel),
  comme le client : 2 propriétés distinctes → plus naturel pour PTT.

---

## 3. Boutons / options à ajouter (ergonomie)

| Bouton | Logique client | Promo |
|---|---|---|
| **Sélecteur de route auto** (priorité speaker/filaire/BT/earpiece) | `AudioRouteManager.selectRoute()` | Haute |
| **« PTT forcé »** dans le panneau statut | `forcedPtt` | Moyenne |
| **Carnet de contacts** (fiche client enrichie) | `ContactSettings` | Haute |
| **Mode « established »** dans la barre de connexion | `STATE.ESTABLISHED` | Basse |
| **`talkPower` / `prioritySpeaker`** dans le client list | propriétés client | Moyenne |
| **Message « serverGenerated / censored »** | `ChatModel.Message` | Basse |
| **Sélecteur de micro/prefs audio** (agc/vad/level dB) | `setPreProcessorConfig` | Moyenne |

---

## 4. Plan d'implémentation (ordre de valeur)

1. **Routes auto (priorité + retry BT)** — le plus visible en mobilité (n°1).
2. **Carnet de contacts + propriétés (talkPower, prioritySpeaker, type)** — parité
   (n°7, n°8). Structurant, mais gros gain fonctionnel.
3. **Reconnexion « min 3 s » + état ESTABLISHED** (n°3) — robustesse.
4. **PTT forcé serveur** (n°4) — cas réel sur serveurs à permission.
5. **TSDNS / multi-endpoints** (n°5) — pour `voice.teamspeak.com`.
6. **`serverGenerated`/`censored` chat + préprocesseur + `INPUT_DEACTIVATED`**
   (n°10, 11, 12) — fignolage.

---

## 5. Fichiers fournis, téléchargés dans `ts3-remote/`

Rapports : `catalogue_fonctions_TeamSpeak_3.3.4.md` (1 Mo, catalogue complet),
`inventaire_JNI_et_natif_TeamSpeak_3.3.4.md`, `rapport_analyse_TeamSpeak_3.3.4.md`,
`rapport_analyse_TeamSpeak_3.3.4_complement_approfondi.md`.

`core_deobfusque/` (code réécrit lisible) : `connection/ServerConnectionHandler.java`,
`audio/{AudioRouteManager,AudioSessionController,JavaPcmAudioBackend}.java`,
`config/AudioConfig.java`, `ptt/PttController.java`,
`model/{ContactSettings,ClientModel,ChannelModel,ChatModel,ConnectionTarget,ServerTreeModel}.java`,
`native/NativeVoiceEngine.java`, `service/ConnectionServiceEventDispatcher.java`,
`map_core.{md,json}`, `eventbus_map.{md,json}`, `semantic_core.md`,
`class_aliases.csv`, `architecture.{mmd,dot}`.

---

## 6. Fin de la note de licence

Ce dossier est une **réécriture lisible** de l'architecture observée dans l'APK
candidat, pas le binaire ni les sources originales. Le moteur natif
(`libts3client_android.so`) **reste propriétaire TeamSpeak** ; nous ne le
redistribuons pas. Notre app garde son moteur **open source** (`tsclientlib`).
Les comportements ci-dessus servent de **référence fonctionnelle**, pas de copie
de code propriétaire.
