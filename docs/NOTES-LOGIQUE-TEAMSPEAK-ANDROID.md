# Notes de logique — client TeamSpeak Android 3.3.4 (mémoire de contexte)

Date : 31 août 2026

> **But.** Consigner, fonctionnalité par fonctionnalité, les **mécanismes et la
> logique** observés dans le code source décompilé du client TeamSpeak Android
> (`core_deobfusque/`, `semantic_core.md`, `inventaire_JNI_et_natif`). Ces notes
> servent de **source d'implémentation** pour compléter notre app Android
> (Flutter + Rust `tsclientlib` + Kotlin). À relire avant chaque phase, pour ne
> pas perdre le contexte.

---

## 0. Carte des responsabilités (récap)

| Responsabilité | Classes originales | Notre équivalent | Écart |
|---|---|---|---|
| Racine application / injection | `Ts3Application`, `StartGUIFragment` | `main.dart`, providers Riverpod | — |
| Service de connexion | `ConnectionBackground` | `KeepAliveService` + `tsMultiServerProvider` | — |
| Session serveur | `C3613v` | `ServerConnectionHandler` (Rust `event_loop`) | — |
| Cible de connexion | `C3670y` | `Server` → `_ConnectRequest` | manque TSDNS |
| Identités | `C4011o` | `IdentityBackup` + `SecureStorage` | — |
| Paramètres | `C3629h0` | `SharedPreferences` + providers | — |
| Arbre des canaux | `C3516f`/`C3528l`/`C3508b` | `ChannelTree`/`TsChannel` | manque `neededTalkPower`, `codec`, `iconId`, `hiddenFromTree` |
| État client | `C3524j` | `TsClient` | manque `talkPower`, `prioritySpeaker`, `recording`, `type`, `filtered` |
| Contacts | `C4570a`/`C3564b` | `ContactSettings` (fait) | à appliquer à la volée |
| Chat | `C4517j`/`C4508a`/`C4528u` | `ChatPanel`/`ChatMessage` | manque `serverGenerated`, `censored`, `highlighted` |
| EventBus | `C4378q0`/`C4346a0` | Notifier Riverpod | — |
| PTT global | `C3511c0` | `PttController` (bouton) | manque combinaisons clavier |
| Overlay PTT | `C4607u` | — | manque (faible priorité) |
| Audio Java | `C4396c`/`C4417t`/`C4415r`/`C4416s` | `VoiceAudioController` vs `AudioService` | à fusionner |
| Routes Android | `C4410m` | `AudioRouteManager`/`audio_route_service` | manque priorité auto + retry BT |
| Capabilities audio | `C4414q` | — | manque cache de sondage |
| Moteur natif | `Ts3Jni`/`libts3client_android.so` | Rust `tsclientlib` | — |

---

## 1. Service de connexion (`ConnectionBackground` → `service/ConnectionServiceEventDispatcher.java`)

- **Multi-connexions** : `ConcurrentHashMap<handlerId, ServerConnectionHandler>` + un `current`.
- **`register`/`unregister`** : au dernier `unregister`, `notifications.stopForeground()` (arrête le service de premier plan quand plus aucun serveur).
- **`onConnectionStatusChanged`** : délègue à `handler.onNativeState(status)` ;
  - `ESTABLISHED` → `notifications.showConnected` + `ui.showConnected` ;
  - `DISCONNECTED` → `notifications.hideTalking`.
- **`onTalkStatusChanged`** : met à jour le modèle et, si le client est local, `notifications.showTalking(status == 1)`. `receivedWhisper` évite d'afficher un talk quand on reçoit un whisper.
- **`onTextMessage`** : filtre **contacts/ignores** (via `ContactSettings.ignore*`) **avant** de stocker dans `ChatModel`, puis `ui.appendMessage` + `notifications.showMessage`.
- **`onClientMoved`** : `ui.refreshChannels(oldChannel, newChannel)`.
- **`onServerStopped`** : `notifications.showServerShutdown` + `ui.showServerShutdown`.
- **Interface `NotificationPort`** : `showConnected`, `showTalking`, `hideTalking`, `showMessage`, `showServerShutdown`, `stopForeground`.
- **Interface `UiPort`** : `showConnected`, `refreshClient`, `appendMessage`, `refreshChannels`, `showServerShutdown`.

> **Pour notre app** : les événements existent déjà côté Rust (`connected`, `client_joined/left`, `channels_updated`, `text_message`, `disconnected`). Le point clé est **appliquer les `ContactSettings.ignore*` avant d'afficher un message** — c'est une amélioration directe.

---

## 2. Session serveur (`ServerConnectionHandler` / `C3613v`)

**Machine d'état** : `NEW, RESOLVING, CONNECTING, CONNECTED, ESTABLISHED, STOPPING, CLOSED`.
- **`initialize()`** → `spawnConnectionHandler()` (native).
- **`onTsdnsResult(addresses, ok)`** : si `ok` et non vide → mémorise les endpoints puis `connectNextResolvedAddress()` ; sinon `fail("TSDNS resolution failed")`.
- **`connectNextResolvedAddress()`** : `resolved.remove(0)`, état → `CONNECTING`, construit `ConnectionArguments(identity, host, port, nickname, channelPath[], pathIsAbsolute, channelPassword, serverPassword, androidId)` puis `startConnection(args)`. Retour ≠ 0 → `fail`.
- **`onNativeState(NativeState)`** : mappe `CONNECTING`→`CONNECTING`, `CONNECTED`→`CONNECTED`, `ESTABLISHING`→`CONNECTED`, `ESTABLISHED`→`ESTABLISHED`, `DISCONNECTED`→`STOPPING`. Sur `DISCONNECTED` → `scheduleRetryIfAllowed()`.
- **`scheduleRetryIfAllowed()`** : si pas `reconnectAllowed` **ou** `retryScheduled` **ou** `retryCount >= retryLimit` → `fail`. Sinon `wait = max(0, 3000 - (now - lastRetryMillis))` (**minimum 3000 ms**, garde `retryScheduled`), schedule → `retryCount++`, `lastRetryMillis=now`, `connectNextResolvedAddress()`.
- **`setLocalPtt(boolean)`** : si PTT forcé, ignore ; sinon `setClientSelfInt(INPUT_DEACTIVATED, enabled?1:0)`.
- **`onForcePttPermission(required)`** : si requis et pas encore forcé → `forcedPtt=true`, `INPUT_DEACTIVATED=1`, `setPreProcessorConfig(vad=false)`, `setPreProcessorConfig(voiceactivation_level=-50)`. Si plus requis → rétablit VAD et l'état PTT local.
- **`close(reason)`** : `reconnectAllowed=false`, `retryScheduled=false`, `stopConnection`, `destroyConnectionHandler`, `state=CLOSED`.

> **our app** : backoff déjà exponentiel+jitter ; il manque le **minimum 3 s** et la **distinction `CONNECTED`/`ESTABLISHED`**. Le `reconnectAllowed` (déconnexion manuelle) est déjà géré.

---

## 3. Cible de connexion (`ConnectionTarget` / `C3670y`)

- `DEFAULT_VOICE_PORT = 9987`.
- Champs : `address`, `configuredPort`, `defaultChannel`, `defaultChannelPassword`, `serverPassword`, `nickname`, `storedNickname`, `token`, `clientNickname`, `currentChannelId`, `databaseId`, `endpointIndex`, `resolvedEndpoints[]`, `connectionFlags`.
- **`setResolvedEndpoints`** : reset `endpointIndex=0`.
- **`advanceEndpoint()`** : `endpointIndex++` si possible (retourne `false` en fin).
- **`effectiveHost()` / `effectivePort()`** : si endpoints résolus → `resolvedEndpoints[endpointIndex]`, sinon adresse configurée / port config ou 9987.
- **`effectiveNickname(identityNickname)`** : préfère un nickname valide (≥3 chars, pas `/` ni `\`), sinon celui de l'identité, sinon `"Android"`.

> **our app** : TSDNS (multi-endpoints) + `androidId` manquants. À ajouter côté Rust (résolveur tsdns) et exposer `effectiveHost/Port`.

---

## 4. Config audio (`AudioConfig` / `C3523i0`, `C3629h0`, `C4366k0`)

- `CUSTOM_DEVICE="custom"`, `CUSTOM_PROFILE="AndroidLegacy"`.
- `Backend { OPENSL, JAVA_PCM }`, `Route { EARPIECE, SPEAKER, WIRED_HEADSET, BLUETOOTH_SCO }`.
- Champs : `captureSampleRate`, `playbackSampleRate`, `captureSource` (défaut **7 / VOICE_COMMUNICATION**), `playbackStream` (défaut **3 / STREAM_MUSIC**), `playbackStreamBackup`, `voiceActivationLevel`, `volumeModifierHalfDb`, `agcEnabled`, `pushToTalk`, `handsfree`, `bluetoothAllowed`.
- **`volumeModifierDb()`** = `volumeModifierHalfDb / 2.0` (le Java envoie `/ 2.0` au moteur).
- **`validSampleRates()`** = `captureRate > 0 && playbackRate > 0`.

> **our app** : `AudioConfig`-like existe dans `voice_settings_panel` ; il manque `voiceActivationLevel` (dB), `handsfree` (route auto), `bluetoothAllowed`. Le `volumeModifierDb = halfDb/2` est à répliquer.

---

## 5. Routes audio (`AudioRouteManager` / `C4410m`, `C4404g`, `C4405h`, `C4407j`, `C4408k`)

- Table de disponibilité `boolean[4]` : `0=earpiece`, `1=speaker`, `2=wired`, `3=bluetooth` ; au départ `available[0]=true`, `available[1]=config.handsfree`.
- **`setAvailable(route, value)`** → publie `onRouteAvailabilityChanged`.
- **`selectRoute()`** : **priorité observée : speaker (si dispo) > wired (si dispo) > bluetooth (si dispo et autorisé) > earpiece.**
- **`onWiredHeadsetState(state)`** : `1`→dispo, `0`→indispo.
- **`onBluetoothConnected/Disconnected`** : set dispo / stopVoiceRecognition.
- **`connectBluetoothVoice()`** : **jusqu'à 10 essais, 500 ms entre essais** (`startVoiceRecognition()`).

> **our app** : choisir une route manuellement. **À ajouter** : priorité auto `selectRoute()` + retry Bluetooth (10×500 ms) dans `VoiceAudioController.kt`.

---

## 6. Backend PCM Java (`JavaPcmAudioBackend` / `C4417t`, `C4415r`, `C4416s`, `C4400e`)

- Enregistre un **périphérique custom** `"custom"`/`"AndroidLegacy"`, mono, PCM 16 bits.
- **`prepare(config)`** : `stop`, `unregisterCustomDevice`, teste les mins buffers, `registerCustomDevice`, crée `AudioRecord(captureSource, rate, 16BIT, MONO, recordMin)` et `AudioTrack(playbackStream, rate, MONO, 16BIT, playerMin, MODE_STREAM)`. **`captureBuffer = new short[(sampleRate/100)*2]`** (= 20 ms).
- **`captureLoop`** : `Process.setThreadPriority(-19)` (haute priorité), `startRecording()`, puis **`read(captureBuffer, 0, len)` bloquant** et `processCustomCaptureData(DEVICE, captureBuffer, count)`.
- **`playbackLoop`** : `setThreadPriority(-19)`, `player.play()`, puis `requestAudioData(DEVICE)` → `player.write(pcm, 0, min(len, (rate/100)*2))`. Si `null` → `stop()+flush()+sleep(100)`. **[RECOMMANDATION]** le `flush()` à chaque bloc est coûteux ; notre app garde un jitter buffer (déjà fait).
- **`close()`** : `stop`, `release`, `unregisterCustomDevice`.

> **our app** : nous capturons en **float 32 via AudioRecord** et envoyons via EventChannel→Dart→FFI (2 copies par trame). La logique legacy utilise **PCM 16 bits + JNI direct** (moins de copies). D4 (refactor JNI direct) est documenté comme le gros gain.

---

## 7. Contrôleur de session audio (`AudioSessionController` / `C4396c`)

- **`start(handlerId, capture, playback, validateBackend, forceCaptureThread)`** : `prepare` (si validate), `openDevices`, `configureVoice`, `javaBackend.start`, `active=true`.
- **`openDevices`** : `openCaptureDevice` + `activateCaptureDevice` (si capture), `openPlaybackDevice` (si playback), puis `setPreProcessorConfig(agc, config.agcEnabled)`.
- **`configureVoice`** : `setPlaybackConfig(volume_modifier, volumeModifierDb())` ; si **PTT** → `setPtt(false)` (input off + vad false + threshold -50) ; sinon `INPUT_DEACTIVATED=0`, `vad=true`, `voiceactivation_level=config.voiceActivationLevel`.
- **`setPtt(handlerId, talking)`** : parler → `INPUT_DEACTIVATED=0` (+ `voiceactivation_level=-50` si PTT) ; relâché → `INPUT_DEACTIVATED=1`.
- **`setMicMuted(handlerId, muted)`** : `INPUT_MUTED=muted` + `flushClientSelfUpdates("InputMute"/"InputUnMute")`. **Fonction distincte de l'activation PTT** — c'est la séparation `INPUT_DEACTIVATED` (parler) vs `INPUT_MUTED` (mute manuel).
- **`applyRoute(route, forceSpeaker)`** :
  - SPEAKER → `MODE_NORMAL` + `setSpeakerphoneOn(true)` + stop BT ;
  - WIRED → `MODE_NORMAL` + speaker off ;
  - BT → `MODE_NORMAL` + speaker off + `connectBluetoothVoice()` ;
  - EARPIECE → `MODE_IN_COMMUNICATION` + speaker off.
- **`onAudioFocusChange`** :
  - LOSS/TRANSIENT/DUCK → `duck()` ;
  - GAIN → `unduck()`.
- **`duck()`** : sauve `modeBeforeDuck` + `volumeBeforeDuck`, `stop`, `MODE_NORMAL`, `setStreamVolume(volumeBeforeDuck/2)`, `ducked=true`.
- **`unduck()`** : restore `mode`, `start(...)`, `setStreamVolume(volumeBeforeDuck)`, `ducked=false`.

> **our app** : nous avons AEC/NS/AGC, focus, routage. **À ajouter** : le `duck/unduck` (baisse le volume au lieu de couper au focus) et la **séparation `INPUT_DEACTIVATED` vs `INPUT_MUTED`** pour un PTT plus propre.

---

## 8. PTT global (`PttController` / `C3511c0`, `C3509b0`)

- Utilise deux **BitSet de touches** : `configuredPtt` et `configuredMute`, plus `pressed`.
- **`configure(pttKeys, pttIntercept, muteKeys, muteIntercept, pttEnabled)`**.
- **`onKeyEvent(keyCode, action, repeatCount)`** : si pas d'activation configurée → false. `DOWN` → `pressed.set(keyCode)` ; `UP` → `pressed.clear(keyCode)` + `onAllKeysReleased()`.
  - Si **toutes les touches PTT** sont pressées → `onPtt(handlerId, talking = (action == DOWN))`, consommé si `pttIntercept`.
  - Si **toutes les touches mute** sont pressées → `onMuteToggle(handlerId)` (si `repeatCount == 0`), consommé si `muteIntercept`.
- **`allConfiguredKeysPressed`** : clone `configured`, `andNot(pressed)`, retourne vide.
- Listener : `onPtt(handlerId, talking)`, `onMuteToggle(handlerId)`, `onAllKeysReleased()`.

> **our app** : PTT = simple bouton. **À ajouter** : support de combinaisons de touches + mute toggle (clavier physique) — priorité basse sur mobile.

---

## 9. Arbre serveur / canaux (`ServerTreeModel`, `ChannelModel`, `C3516f`, `C3528l`)

- `ChannelModel` : `channelId, name, parentId, order, depth, neededTalkPower, maxClients, codec, iconId, defaultChannel, passwordProtected, persistence(PERMANENT/SEMI/TEMPORARY), expanded, hiddenFromTree, hasChildren, clientIds[], sortedClientIds[]`.
- **`visibleClientIds(ClientDirectory)`** : ne reconstruit la liste **que si `clientsDirty`** (filtre les ServerQuery non autorisés via `isFiltered`, trie via `compare`). Sinon renvoie le cache.
- `ServerTreeModel` : `channels`, `clients`, `clientToChannel`, `flattened`.
  - `addChannel/addClient/removeClient/moveClient` (met à jour `clientToChannel`).
  - **`rebuildVisibleTree()`** : racines (`parentId==0`) triées par `order`, puis `flatten` récursif (enfants triés par `order`).

> **our app** : `ChannelTree` trie à la volée. **À améliorer** : cache `clientsDirty` (reconstruire seulement après mutation) et pré-aplatir (`rebuildVisibleTree`) — léger gain de perf.

---

## 10. Clients (`ClientModel` / `C3524j`)

- Propriétés : `type(NORMAL/SERVER_QUERY/UNKNOWN)`, `channelId`, `databaseId`, `nickname`, `uniqueIdentifier`, `country`, `serverGroups`, `channelGroupId`, `awayMessage`, `talkRequest`, `talkRequestMessage`, `iconId`, `talkPower`, `neededServerQueryViewPower`, `talkStatus`, `whisperStatus`, `inputMuted`, `outputMuted`, `inputHardwareDisabled`, `outputHardwareDisabled`, `away`, `channelCommander`, `prioritySpeaker`, `recording`, `talker`, `filtered`, `serverMutedByContact`, `contact`.
- **`attachContact(settings, control, localClientId)`** :
  - `null` → si `serverMutedByContact` → `requestUnmute`, `setVolumeModifier(0)`.
  - `volumeModifier != 0` → `setVolumeModifier`.
  - `muted && clientId != localClientId` → `requestMute` + `serverMutedByContact=true` ; sinon `requestUnmute`.
- **`onUniqueIdentifierResolved`** : complète l'UID async.
- **`ClientControl`** : `setVolumeModifier`, `requestMute`, `requestUnmute`.

> **our app** : manque `talkPower`, `prioritySpeaker`, `recording`, `type`, `filtered`, `talkStatus`, `whisperStatus`, `serverMutedByContact`. `attachContact` (mute persisté + volume modifier) est une **amélioration directe** — nous avons `ContactSettings` ; **à lier** au roster.

---

## 11. Contacts (`ContactSettings` / `C4570a`, `C3564b`) — **fait dans notre app**

- Colonnes : `contact_id`, `u_identifier`, `customname`, `display` (0=préfixe `[nom] nickname`, 1=nom seul, autre=nickname), `status`, `mute`, `ignorepublicchat`, `ignoreprivatechat`, `ignorepokes`, `hideaway`, `hideavatar`, `whisperallow`, `volumemodifier`.
- **`preferredDisplayName`** : `display==1 && customName` → customName ; `display==0 && customName` → `[customName] nickname` ; sinon nickname/UID.

> **our app** : `ContactSettings` + `preferredDisplayName` + provider + fiche client enrichie sont déjà implémentés. **Reste** : appliquer `mute` (volume/requestMute), `ignore*` (filtrer messages), `hideAvatar`, `allowWhispers` à la volée dans le notifier.

---

## 12. Chat (`ChatModel` / `C4517j`, `C4508a`, `C4528u`)

- `SERVER_TAB="SERVER"`, `CHANNEL_TAB="CHANNEL"`.
- `Message` : `sender`, `channel`, `text`, `timestamp`, `serverGenerated`, `highlighted`, `censored`.
- `Tab` : `key`, `type`, `messages[]`, `systemTab`, `lastMessage`, `unreadCount` ; `append` incrémente `unreadCount`, `markRead` reset.
- `initialize(handlerId)` crée les onglets serveur/canal (systemTab).
- `addSystemMessage/addChannelMessage` : `serverGenerated=true`.
  - `addKickMessage(clientName, kicker, reason)` → message système `"X was kicked by Y: reason"`.
- `closeTab` ne ferme pas l'onglet serveur.

> **our app** : `ChatThreadKey` + `unreadByThread` + `ChatThread.group`. **À ajouter** : `serverGenerated`, `censored`, `highlighted` sur `ChatMessage`, et messages système (kick/ban) dans le fil. `markRead` = notre `openThread`.

---

## 13. CoreBootstrap (`ApplicationLifecycleAndDependencyRoot` / `Ts3Application`)

- `onApplicationCreate` : `System.loadLibrary("ts3client_android")`, `startClientLibrary`, `initializeTsdns`.
- `createConnection` : `handler.initialize()` + `connectionService.register(handler)`.
- `onActivityPause` : `exportCachedData()` + `setBackgroundActionState(0)`.
- `onActivityResume` : `setBackgroundActionState(1)`.

> **our app** : `main.dart` initialise Rust + providers. **À ajouter** : `exportCachedData()`/`setBackgroundActionState` (équivalents `tsclientlib`) au pause/resume pour réduire la charge.

---

## 14. Contrat JNI natif (`NativeVoiceEngine` / `Ts3Jni`)

- **Cycle devie** : `spawnConnectionHandler`, `startConnectionEx`, `stopConnection`, `destroyServerConnectionHandler`.
- **Capture/playback** : `registerCustomDevice`, `openCaptureDevice`, `activateCaptureDevice`, `closeCaptureDevice`, `openPlaybackDevice`, `closePlaybackDevice`, `processCustomCaptureData`, `requestAudioData`.
- **Préprocesseur/état** : `setPreProcessorConfig(key, value)`, `setPlaybackConfig(key, value)`, `setClientSelfInt(ClientProperty, value)`, `flushClientSelfUpdates(returnCode)`, `setLocalTestMode(enabled)`.
- `ClientProperty { INPUT_DEACTIVATED, INPUT_MUTED, AWAY }`.
- `ConnectionArguments(uniqueIdentity, address, port, nickname, defaultChannelPath[], pathIsAbsolute, channelPassword, serverPassword, androidId)`.

> **our app** : équivalents dans Rust (`ts_*`). Il manque `requestAudioData` (le moteur cpal pousse), `setLocalTestMode`, `flushClientSelfUpdates`, l'`androidId`.

---

## 15. Pistes d'implémentation à forte valeur (synthèse)

| # | Amélioration | Où | Effort |
|---|---|---|---|
| A | **Routes auto + retry Bluetooth (10×500 ms)** | `VoiceAudioController.kt` | S |
| B | **Reconnexion min 3 s + état ESTABLISHED** | `ReconnectPolicy` | S |
| C | **Appliquer les contacts à la volée** (mute, ignore*, volume, hideAvatar) | `ts_state.dart` | M |
| D | **Chat système** (`serverGenerated`/`censored`/`highlighted`, kick/ban messages) | `ChatMessage` + handler | S |
| E | **Séparation INPUT_DEACTIVATED vs INPUT_MUTED** (PTT propre) | Rust `Command::SetMuted` | M |
| F | **`duck/unduck` au focus audio** | `VoiceAudioController.kt` | S |
| G | **Arbre : cache `clientsDirty` + pré-aplatir** | `ChannelTree` | S |
| H | **TSDNS multi-endpoints + androidId** | Rust (résolveur) | L |
| I | **Refactor JNI direct PCM 16 bits** (moins de copies) | Kotlin + Rust | L |

---

## 16. Phase 22 — statut client complet, duck/unduck, contacts ignore*, arbre pré-aplati

Résumé des ajouts de la phase 22 (voir `docs/PHASE-22-AUDIO-ROUTES-DUCK-STATUT-CLIENT.md` pour le détail).

### (A) Pré-aplatissement de l'arbre (`ChannelTree`) — **fait**
- Remplace la récursion par une **liste plate** `(channel, depth)` pré-triée et **mémorisée**
  (`_rows` + `_flatDirty`), reconstruite seulement si les entrées changent. Équivalent du
  `rebuildVisibleTree()` du client legacy.

### (B) `duck/unduck` du volume maître — **fait**
- `MasterVolumeNotifier.setVolumeLive(db)` (n'écrit pas `SharedPreferences`).
- `_duckMasterVolume()`/`_unduckMasterVolume()` : −6 dB à la perte de focus, restauration au regain,
  sans écraser la valeur choisie en réglages. Le silence du micro reste côté Dart.

### (C) Propriétés client (`TsClient`) — **fait** (Rust + Dart)
- `client_type`(0/1=query), `talk_power`, `talk_power_granted`, `is_priority_speaker`,
  `is_channel_commander`, `is_recording`, `input/output_hardware_enabled`, `output_only_muted`,
  `phonetic_name`, `country_code`, `metadata`, `avatar_hash`. Alimentées depuis le livre
  `ts_bookkeeping::data::Client`. `ClientType` = `Normal` | `Query{admin}`.

### (D) Filtres `ignore*` du carnet de contacts — **fait**
- `_contactForClient(cid, clientId)` lit le contact d'un client vivant ; `text_message` applique
  `ignorePrivateChat` (cible 1) et `ignorePublicChat` (cible 2/3) avant stockage.

### (E) `INPUT_DEACTIVATED` vs `INPUT_MUTED` (PTT) — **fait (équivalence)**
- La capture micro n'est ouverte que si `_shouldMicBeActive` (PTT pressé OU non-mute) ; mute et
  PTT relâché coupent donc la transmission sans distinction de drapeau filaire.

> **Reste (futures phases)** : TSDNS multi-endpoints + `androidId` (H), refactor JNI direct PCM
> 16 bits (I), recherche globale, gestionnaire de fichiers (ftlist/ftdelete), validation appareil
> sur `voice.teamspeak.com`.

---

## 17. Phase 23 — métadonnées canaux, welcome/host message, droit de parole

Résumé (voir `docs/PHASE-23-METADONNEES-CANAUX-WELCOME-HOST-TALKPOWER.md`).

### (A) `TsChannel` enrichi (Rust + Dart) — **fait**
- `needed_talk_power`, `max_clients` (−1 illimité, −2 hérité), `codec` (0..5), `codec_quality`,
  `channel_type` (0=temp, 1=permanent, 2=semi-permanent), `is_default`, `is_private`,
  `subscribed`, `icon_id`, `is_unencrypted`. Via `refresh_from_book` sur `book.channels`.

### (B) `TsEvent::Connected` + variables serveur — **fait**
- `welcome_message`, `host_message`, `host_message_mode` (0=none, 1=log, 2=modal,
  3=modal+disconnect), `max_clients`, `needed_identity_security_level` depuis `book.server`.

### (C) Affichage welcome/host — **fait**
- `_maybeHydrateServerMessages(cid, st)` : welcome + host-mode-log → lignes système dans le fil
  serveur ; host-mode 2/3 → notice ; mode 3 → déconnexion.

### (D) Indicateurs & fiche canal — **fait**
- Arbre : marqueurs défaut/permanent/semi-permanent/mot de passe/non-abonné/talk power.
- Fiche canal : codec, max clients, talk power requis, type, badges booléens.

### (E) Droit de parole — **fait**
- `TsConnectionState.canTalkInCurrentChannel` : `talk_power_granted` OU
  (`talk_power >= needed_talk_power`) sinon faux. Testé dans `test/channel_metadata_test.dart`.
