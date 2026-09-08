# Rapport de parité — NEk0 vs client TeamSpeak 3.3.4 (Android/Windows)

**Date :** 8 septembre 2026 · **Code source :** `nek0-personal` + `ts3-remote` (core décompilé, catalogue JNI, semantic_core)

> Méthode : exploration parallèle de toutes les couches (= les « agents » d'audit) :
> (1) moteur Rust `native/src/{lib,api}.rs` (FFI, commandes, événements, globals),
> (2) couche Dart `lib/{models,services,screens,widgets}`, (3) plateforme Kotlin
> `android/.../teamspeak_apk/`, (4) le client décompilé `ts3-remote/core_deobfusque/`
> et le catalogue JNI de 137 fonctions. Le but : **un clone fidèle mais modernisé**
> (plus stable, plus rapide, moins gourmand en CPU, ergonomique).

---

## 1. Architecture cible (notre app)

| Couche | Rôle | Fichiers clés |
|---|---|---|
| **Moteur Rust** `.so` | protocole, codec Opus, VAD hybride, jitter buffer, réseau, multi-sessions | `native/src/lib.rs`, `native/src/api.rs` |
| **État/contrôle Dart** | machine d'état, providers Riverpod, réconciliation roster, anti-flood UI | `lib/models/ts_state.dart`, `lib/models/*.dart` |
| **UI Flutter** | écrans + panneaux (serveur, réglages, chat, arbre, clients, whisper…) | `lib/screens/*`, `lib/widgets/*` |
| **Plateforme** | audio (AudioRecord/cpal), routes, service de fond, Keystore | `android/.../*.kt` |

Expose **53 fonctions FFI** (`ts_*`), **20 événements moteur** (`TsEvent`), **~34 commandes** (`Command`).

---

## 2. Ce qui est FAIT (inventaire par domaine + phase)

### 2.1 Connexion & machine d'état
- **Multi-serveurs** simultanés (tabs) — *Phase 17*.
- Machine d'état : `idle → resolving → connecting → authenticating → connected → failed/reconnecting`
  (événements `connection_phase`, `connect_failed` typés) — *Phase 7*.
- **Reconnexion** : backoff exponentiel 2→30 s + ±20 % jitter, **minimum 3 s**,
  6 essais max, **jamais** pour mot de passe/ban/annulation, restauration du canal précédent,
  `reconnectAllowed` — *Phases 7/22*.
- **Identité** : création/stockage Keystore, import/export chiffré PBKDF2+AES-GCM, purge,
  migration legacy — *Phases 19/B4*.
- **Anti-flood** : budget à jetons + file bornée (fusion des commandes d'état, degré dégradé
  après `ClientIsFlooding`/`BanFlooding`) — *Phase 10*.
- **Bascul réseau** Wi-Fi↔mobile → reconnexion forcée ; offline → pause du retry — *C1*.
- Résolution d'adresse + **TSDNS multi-endpoints** fait *en interne* par `tsclientlib`
  (SRV `_tsdns`, résolveur hickory, nickname→http, système).

### 2.2 Canaux & clients (parité riche)
- `TsChannel` : nom, parent, topic, mot de passe, client_count, ordre, **talk power requis**,
  **max_clients** (illimité/hérité/cap), **codec+quality**, **type** (permanent/semi/temp),
  **is_default**, **is_private**, **subscribed**, **icon_id**, **is_unencrypted** — *Phase 23*.
- `TsClient` : type (query/normal), **talk_power / talk_power_granted**, **priority_speaker**,
  **channel_commander**, **recording**, hardware flags, output_only_muted, phonetic_name,
  country, metadata, avatar_hash, permissions — *Phases 22/23*.
- **Arbre pré-aplati** (`refreshVisibleTree`, cache `_flatDirty`) = `rebuildVisibleTree()`
  du legacy — *Phases 22*.
- **Recherche globale** canaux+utilisateurs+fichiers avec chemin `Parent › Enfant`
  (`searchServer`/`channelPath`) — *Phase 25*.
- **Fonctions canaux** : créer/éditer/déplacer/supprimer (avec permissions), fiche canal
  enrichie (codec, talk power, type, badges) — *Phases 19/23*.

### 2.3 Clients : actions de modération
- Kick (canal/serveur), ban (durées pré-définies), poke, déplacer, mute/volume par client,
  whisper ciblé — *Phases 6/11/12*.
- **Permissions** : `permission_hints` du serveur → seuls les menus possibles sont proposés —
  *Phase 11*.

### 2.4 Audio (le cœur)
- **Codec Opus** mono/stéréo, jitter buffer **adaptatif** 40→160 ms — *Phase 20*.
- **VAD hybride** (gating volume + forme du signal, seuil réglable 0.0005–1.0, plancher de bruit
  adaptatif) ; **PTT** bouton + micro ; **mute** — *Phases 2-3/8*.
- **Gain micro** (0–3×), **volume maître** (−20..+20 dB), **volume par client** (persisté par UID) — *Phases 8/12*.
- **Routes** manuelles : auto / écouteur / haut-parleur / filaire / USB / **Bluetooth SCO**
  (retry 10×500 ms, modulo 28-30 legacy) — *Phases 8/22*.
- **Effets DSP** AEC/NS/AGC (par disponibilité device, session ID, MODE_IN_COMMUNICATION) — *Phase 8*.
- **Duck/unduck** au focus audio (−6 dB + mute micro) ; focus regained restaure — *Phase 22*.
- **Boucle micro zéro-allocation** (D4) : `Pointer<Float>` réutilisé en Dart, `ByteArray`+
  `ByteBuffer` réutilisés en Kotlin, `sink.success` sans dispatch UI — *Phase 28*.
- Single cpal **output stream** mixant tous les serveurs ; maintenance adaptative (500 ms actif /
  2 s inactif) ; restart sur changement de device.

### 2.5 Whisper
- Émission `C2SWhisper` avec liste cibles (clients+canaux, cap 100), terminator zéro-longueur
  à chaque bascule voix↔whisper — *Phase 6*.
- **Réception** : liste blanche par UID (`allowWhispers`), compteur ignoré, throttlé — *Phase 6*.
- Panneau de configuration (cibles + allow-list) — *Phase 6*.

### 2.6 Chat & contacts
- Fils : serveur / canal / **privés par interlocuteur** (badges non lus, `markRead`=openThread) — *Phase 16*.
- **Messages système** (`serverGenerated`/`highlighted`), welcome + host message (modes 0/1/2/3),
  historique.
- **Carnet de contacts** : customName + displayMode, mute (−20 dB), volumeModifier,
  `ignorePublicChat`/`ignorePrivateChat` filtrés, `hideAvatar`, `allowWhispers` — *Phase 19/22*.
- **Historique chiffré** (XOR/AES) avec rétention + purge — *Phase 14*.
- **Avatars** + **icônes de groupes** (cache + téléchargement fichier) — *Phases 12/13/16*.

### 2.7 Fichiers serveur
- **Lister** `ftgetfilelist` (navigation), **télécharger**, **créer un répertoire**,
  **supprimer**, **renommer** (+déplacement), **info fichier** `ftgetfileinfo` — *Phases 24/26*.
- Anti-taille (8 Mo max), corrélation requête→réponse par `request_id`, chemins sûrs.

### 2.8 Permission key
- **Utiliser une privilege key** (`privilegekeyuse`) + confirmation `notifytokenused` — *Phase 27*.

### 2.9 Service de fond, notification, confort
- **Foreground service** + MediaSession (Play/Pause) ; notification agrégée multi-serveurs
  (mute/déconnexion) ; swipe-away = déconnexion — *Phase 17/9*.
- **Thème** système/sombre/clair/**AMOLED** — *Phase 20*.
- Recherche canaux, tri alpha/ordre, favoris (serveur+canal), sons d'événements, suppression
  multi-serveurs, stats réseau (RTT/jitter/perte) — *Phases 18/19*.
- **i18n EN/ZH** — *Phase 21*.

### 2.10 Sécurité & qualité
- Logs **filtrés/redactés**, niveaux, coupés en release ; `tools/check_secrets.py` — *Phase 9/B3*.
- SBOM (cyclonedx), **cargo deny** (licences permissives), audit, vérif copyleft — *Phase 21*.
- Tests Rust + Dart (142) ; `cargo clippy -D warnings` ; CI 6 jobs + build APK.

---

## 3. Ce qui MANQUE encore vs client officiel (écarts)

### 3.1 Hautes priorités (impact utilisateur)
| # | Manque | Détail/Note d'implémentation | Source legacy |
|---|---|---|---|
| M1 | **Déconnecter explicitement un canal** (subscribe/unsubscribe individuel) et accéder aux canaux non abonnés | Requêtes `requestChannelSubscribe/Unsubscribe` ; la liste se fait via `ChannelListRequest`. Aujourd'hui on souscrit tout à la connexion. | `ts3client_requestChannelSubscribe/Unsubscribe/All` |
| M2 | **Ban par UID / par DBID** (+ `banadd` IP, liste des bans `requestBanList`) | `ts_ban_client` ne banit que par client_id. Ajouter `ban_uid`, `ban_db_id`, `banadd`, `bandel`, `bandelall`, lister les bans. | `ts3client_banclientUID/banclientdbid/banadd/bandel/requestBanList` |
| M3 | **Ajouter/retirer un groupe serveur** à un client, **set channel group** | `requestServerGroupAddClient/DelClient`, `requestSetClientChannelGroup`. | `ts3client_requestServerGroupAddClient/DelClient/SetClientChannelGroup` |
| M4 | **Complain (plainte)** | `requestComplainAdd` (qui + message), éventuellement lister. | `ts3client_requestComplainAdd` |
| M5 | **Marquer « talker »** d'un client (`requestSetIsTalker`/`requestIsTalker`) | "Faire taire" un client qui parle trop. | `ts3client_requestClientSetIsTalker` |
| M6 | **Mot de passe temporaire serveur** (add/del/list) | `requestServerTemporaryPasswordAdd/Del/List`. | `ts3client_requestServerTemporaryPassword*` |
| M7 | **Carte des permissions** (view `requestPermissionList`, `requestChannelDescription`) | "Voir les perms" / "description du canal" (lecture). | `ts3client_requestPermissionList` |
| M8 | **Description du canal** | `requestChannelDescription` → afficher dans la fiche. | `ts3client_requestChannelDescription` |

### 3.2 Priorité moyenne (parité de menu/options)
| # | Manque | Note |
|---|---|---|
| M9 | **Port personnalisé** au bookmark + display `host:port` | Aujourd'hui le champ adresse peut contenir `:port` mais pas de champ dédié ; port par défaut 9987. |
| M10 | **TSDNS « nom de serveur »** en plus de `host:port` | `tsclientlib` résout déjà ; exposer « résoudre un nom TS » dans l'UI (autocomplete). |
| M11 | **PTT clavier (hotkeys) multi-touches** | Le legacy a des `BitSet` de touches + interception (`PttController`). Nous n'avons que le bouton. |
| M12 | **PTT forcé par le serveur** (permission `b_client_*`), retour à la VAD | Détecter `command_error`/signaux de talk power et basculer `INPUT_DEACTIVATED`/`vad=false`/`voiceactivation_level=-50`, puis revenir. |
| M13 | **`androidId`** passé à la connexion | `ConnectionArguments(androidId)` ; utile pour le profilage/anti-reconnexion serveur. |
| M14 | **Statut des clients : `talkStatus`/`whisperStatus` détaillés** (`client_is_talker`, states 0/1/2) | On a `isTalking`/`isWhispering` booléens ; le legacy différencie les états. |
| M15 | **On dirait que le client compose / ferme le chat** (`clientChatComposing/Closed`) | Indicateurs de frappe en privé. |
| M16 | **Away/AFK de contrôle** — changer le `awayMessage` du côté serveur | On a `setAway`. OK, mais pas de message par défaut « back in 5 ». |
| M17 | **`setLocalTestMode`** (mode test local audio) | Utile pour tester sans serveur. |
| M18 | **Channel commander** — déjà fait ; **request `b_client_*` pour `is_priority_speaker`** côté serveur | Priorité speaker est une perm que le client ne fixe pas lui-même ; rien à faire, mais afficher. |

### 3.3 Basse priorité / architecturales
| # | Manque | Note |
|---|---|---|
| M19 | **Contrat JNI « custom device »** (`registerCustomDevice`, `processCustomCaptureData`, `requestAudioData`) | **Choix d'architecture** : nous pilotons l'audio nous-mêmes (cpal + AudioRecord), donc ce chemin JNI n'est pas nécessaire. À documenter, pas à porter. |
| M20 | **`exportCachedData` / `setBackgroundActionState`** au pause/resume | Le legacy exporte le cache natif et signale le background. Pour nous : mettre en pause la maintenance / réduire le polling. (Partiellement fait via `_onForegroundChanged`.) |
| M21 | **`improveIdentity`/`abortImproveIdentity`** explicite | On gère `IdentityLevelIncreasing` passivement pendant la connexion ; pas de bouton « améliorer l'identité » ni de niveau affiché. |
| M22 | **Overlay de fenêtre/statut** | Le legacy a un overlay PTT (`C4607u`). Pas de plan (Android 9+ restrictif). |
| M23 | **Séparer `INPUT_DEACTIVATED` vs `INPUT_MUTED`** dans le moteur | Équivalence fonctionnelle actuelle (micro coupé si mute OU PTT relâché) ; un portage exact nécessite 2 drapeaux FFI. |
| M24 | **Stats serveur complètes** (bandwidth, uptime, packets, `ConnectionServerData`) | On affiche RTT/jitter/perte. Le legacy affiche bandwidth, uptime, connect_time, packets. |

---

## 4. Options / paramètres : comparaison UI & préférences

| Option | Client officiel | Nous | État |
|---|---|---|---|
| Entrée serveur | adresse/nom, port, pseudo, canal par défaut (+pwd canal/serveur), token | adresse, label, pseudo, canal, pwd serveur, pwd canal | ✅ (port implicite, pas de token au connect) |
| Pseudo | oui | oui | ✅ |
| PTT | bouton **+ hotkeys** | bouton seul | ⚠️ (M11) |
| VAD | seuil + `voiceactivation_level` | seuil 0..1 + switch | ✅ |
| Gain micro | oui | oui | ✅ |
| Volume maître | oui | oui | ✅ |
| Volume /client | oui | oui (+persisté) | ✅ |
| Route | auto/speaker/wired/BT/earpiece | idem | ✅ |
| Effets AEC/NS/AGC | oui | oui | ✅ |
| Whisper | émission ciblée + allow-list | idem | ✅ |
| Notifications | sons + perso | sons événements + mute/disconnexion | ⚠️ |
| Historique | oui | oui (chiffré) | ✅ |
| Contacts | carnet complet | mute/volume/ignore/customName | ⚠️ (pas de `ignorePokes`/`hideAway`/`hideAvatar` exhaustif) |
| Thème | clair/sombre | système/sombre/clair/**AMOLED** | ✅ (mieux) |
| Langue | multi | EN/ZH | ✅ |
| Auto-start / veille OEM | oui | guide OEM | ✅ (Phase 19) |
| Mots de passe | média | média + activer | ✅ |

---

## 5. Robustesse, CPU, stabilité — ce qui est déjà optimisé

- **Aucune allocation dans la boucle micro** (D4) ; **scratch Opus thread-local** (fini 4 Ko/frame) ; **volume maître atomique**.
- **Throttles** : `onMicLevel` ≤10/s, notification coalescée 600 ms, `listEquals` roster/canaux,
  `_refreshWhisperStats` 3 s, `diagMessages` borné 40.
- **Anti-flood** côté moteur + **reconnexion** robuste ; **jitter adaptatif** (latence basse en réseau sain).
- **Ergonomie** : menus par permission (jamais d'action impossible), tooltips, long-press mic → réglages, recherche globale, favoris.
- **Crash-safety** : `catch_unwind` sur l'event loop, `install_panic_hook`, redaction, chemins de fichiers sûrs, bornes de taille.

### À affiner (qualité restante)
- **Zéro-alloc côté Kotlin** : `FloatArray(960)` de `MainActivity` est réutilisé, mais `readMicBuffer`
  retourne une copie si read < size (rare). OK.
- Le **pegging** de la maintenance en arrière-plan : `_onForegroundChanged` réduit déjà le cadence ; fournir `setBackgroundActionState` équivalent pour suspendre le décodage audio inutile.
- **Talk power / états de parole détaillés** (`talkStatus`) pour l'indicateur « tu parles » plus proche de TS.
- **Tests de flux** : notifiers / forms (F3) et tests instrumentés (F4) — gros chantier, à planifier.

---

## 6. Roadmap priorisée

1. **M1+M2+M3+M4+M5+M6+M7+M8** (block « menu client/canal » : bans étendus, groupes, complain, talker, perms, description) — étend le moteur Rust + menus.
2. **M11+M12** PTT hotkeys + PTT forcé serveur — ergonomie/parité audio.
3. **M9+M10+M13** port dédié + résolution de nom TS + `androidId`.
4. **M14+M24** états de parole détaillés + stats serveur (bandwidth/uptime).
5. **M20+M21** background-state explicite + amélioration d'identité (niveau affiché).
6. **Tests F3/F4** + **validation appareil** (`PLAN-VALIDATION-APPAREIL-2026-09.md`).

---

## 7. Annexes

### 7.1 Mapping fonctions JNI officielles → notre moteur (couverture)
- **Connexion** : `startConnectionEx`, `stopConnection`, `destroyServerConnectionHandler`,
  `spawnNewServerConnectionHandler` → notre `ts_connect`/`ts_disconnect`/session.
- **Identité** : `createIdentity`, `identityStringToUniqueIdentifier`, `identityStringToFilename`,
  `improveIdentity`, `abortImproveIdentity`, `getIdentityQuality` → partiel (import/export,
  montée passive du niveau).
- **Audio capture/playback** : `registerCustomDevice`, `openCaptureDevice`, `activateCaptureDevice`,
  `processCustomCaptureData`, `requestAudioData` → **non utilisé** (nous pilotons l'audio via cpal/Kotlin).
- **Préprocesseur/state** : `setPreProcessorConfigValue` (agc/vad/voiceactivation_level),
  `setPlaybackConfigValue`, `setClientSelfVariableAsInt` (INPUT_DEACTIVATED/INPUT_MUTED/AWAY),
  `flushClientSelfUpdates`, `setLocalTestMode` → `setVadThreshold`/`setVadEnabled`/`setMuted`/`setAway`/`setChannelCommander`.
- **Clients** : `requestClientKickFromChannel/FromServer`, `requestClientPoke`, `requestClientMove`,
  `requestMuteClients`, `requestUnmuteClients`, `setClientVolumeModifier`,
  `requestClientUIDfromClientID`, `requestClientSetIsTalker` → kick/poke/move/mute/volume/UID ✅ ; **isTalker ⚠️**.
- **Canaux** : `requestChannelCreate`/`Edit`/`Delete`/`Move`, `requestChannelDescription`,
  `requestChannelSubscribe(All)/Unsubscribe(All)`, `verifyChannelPassword`, `getChannelList`,
  `getChannelClientList` → créer/éditer/suppr/déplacer/mot de passe ✅ ; **subscribe individuel & description ⚠️**.
- **Variables serveur** : `requestServerVariables`, `getServerVariableAsInt/String`,
  `requestServerConnectionInfo` → welcome/host/maxclients/identity level/voIP encryption ✅ ;
  **bandwidth/uptime/packets ⚠️**.
- **Chat** : `requestSendChannelTextMsg`/`PrivateTextMsg`/`ServerTextMsg`,
  `clientChatComposing`/`clientChatClosed` → envoi ✅ ; **composing ⚠️**.
- **Ban/permissions** : `banadd`, `banclient`, `banclientUID`, `banclientdbid`, `bandel`,
  `bandelall`, `requestBanList`, `requestPermissionList`, `requestServerGroupList`,
  `requestServerGroupAddClient`/`DelClient`, `requestSetClientChannelGroup`,
  `requestComplainAdd` → ban client ✅ ; **liste/UID/DBID/add/del/complain/permissions/groups ⚠️**.
- **Transferts** : `requestFile`, `requestFileInfo`, `requestChannelDescription` →
  gérer lister/télécharger/create/rename/delete/info ✅ ; renommé via `ftrenamefile`.
- **Tokens** : `privilegeKeyUse` → ✅ (Phase 27).
- **Divers** : `exportCachedData`, `setBackgroundActionState`, `cleanUpConnectionInfo`,
  `androidCheckSignatureData` → ⚠️/non nécessaires.

### 7.2 Référentiel des phases
`PHASE-{2..28}-*.md` + `PLAN-*`, `RAPPORT-*`, `DEVIS-*` dans `docs/`.
