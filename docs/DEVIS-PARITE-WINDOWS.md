# Devis de parité — client TeamSpeak Windows → app Android NEk0

Date : 28 août 2026

Ce document catalogue les fonctionnalités, options et écrans du **client
TeamSpeak 3 pour Windows** et indique leur **équivalent dans l'app Android**
ainsi que son **statut**. Légende :

- ✅ **fait** : implémenté et validé (compilation/tests).
- 🟡 **partiel** : présent mais incomplet ou à valider sur serveur réel.
- ❌ **manquant** : à construire.
- 🔧 **à peaufiner** : présent mais à améliorer (perf/UX).

L'app visée est *l'équivalent fonctionnel* du client Windows ; la liste suit les
grandes sections du client officiel.

---

## 1. Connexion & comptes de serveur

| Fonctionnalité Windows | Équivalent Android | Statut |
|---|---|---|
| Liste de favoris (signets serveur) | Écran d'accueil + `ServerFormDialog` + `serverListProvider` | ✅ |
| Ajouter / modifier / supprimer un serveur | `_addOrEditServer`, `_deleteServer` | ✅ |
| Mot de passe serveur / canal (chiffré) | `SecureStorage` (Keystore) + migration legacy | ✅ |
| Connexion à plusieurs serveurs simultanés | Onglets `ServerScreen`, `SESSIONS` table | ✅ |
| Reprise après fermeture du processus | `ResumeIntent` + bannière « Reprendre » | ✅ |
| Profil d'identité TS3 | Keystore + export/import chiffré (`IdentityBackup`) | ✅ |
| Anti-flood (file + budget) | `CommandBudget` (token bucket + degraded) | ✅ |
| Machine d'état de connexion + reconnexion | `TsPhase` + `ReconnectPolicy` | ✅ |

---

## 2. Arbre des canaux

| Fonctionnalité Windows | Équivalent Android | Statut |
|---|---|---|
| Arbre imbriqué, plier/déplier | `ChannelTree` | ✅ |
| Compteur de clients par canal | badge `clientCount` | ✅ |
| Recherche de canal (+ chemin) | barre de recherche dans l'arbre | ✅ |
| Tri (ordre serveur / alphabétique) | `channelsSortedAlpha` + bouton | ✅ |
| Favoris par canal (épingler) | `favoriteChannelIds` + étoile + long-press | ✅ |
| Info canal (sujet / description) | bouton « Menu » → **Info canal** | ✅ (ajouté) |
| Créer / éditer / supprimer / déplacer un canal | menu « ⋯ » + dialogues | ✅ |
| Mot de passe / limite de clients / permanent | dialogue de création/édition | ✅ |

---

## 3. Liste des clients & statut

| Fonctionnalité Windows | Équivalent Android | Statut |
|---|---|---|
| Liste des clients du canal | `ClientList` | ✅ |
| Recherche de client | barre de recherche | ✅ |
| Icônes de groupe | `GroupIcon` (download + cache) | ✅ |
| Avatar | `IconCache.avatar` | ✅ |
| Volume par client (−20..+20 dB) | slider persistant par UID | ✅ |
| Statut : away, muted in/out, talking, whispering | icônes + badges | ✅ |
| Kick canal / serveur | `ModerationSheet` (perm. gate) | ✅ |
| Ban / poke / déplacer / message privé | `ModerationSheet` | ✅ |

---

## 4. Chat

| Fonctionnalité Windows | Équivalent Android | Statut |
|---|---|---|
| Chat canal / serveur / privé | `ChatPanel` + onglets | ✅ |
| Fils de conversation + badges non-lus | `ChatThreadKey`, `unreadByThread` | ✅ |
| Historique chiffré (optionnel) | `ChatHistoryService` (fichiers Keystore) | ✅ |
| Sons d'événement (opt-in) | `eventSoundsEnabled` | ✅ |
| Message privé depuis la liste | long-press → « envoyer un message privé » | ✅ |

---

## 5. Audio & voix

| Fonctionnalité Windows | Équivalent Android | Statut |
|---|---|---|
| Micro (VAD) | `AudioService` + VAD hybride | ✅ |
| PTT | bouton PTT | ✅ |
| Mute input / output / full mute | icônes micro / haut-parleur / casque | ✅ |
| Whisper (émettre) | `WhisperPanel` + `ts_set_whisper_targets` | ✅ |
| Whisper entrant (liste d'autorisation) | `whisper_allow_mode` + UID allowlist | ✅ |
| Volume maître | **long-press haut-parleur → slider maître** | ✅ (ajouté) |
| Gain micro | slider | ✅ |
| Routage (écouteur/speaker/filaire/USB/BT) | `VoiceAudioController` + `AudioRoute` | ✅ |
| AEC / NS / AGC | DSP de plateforme | ✅ |
| Focus audio (appel entrant) | `AudioFocusRequest` | ✅ |
| Jitter buffer adaptatif | `adaptive_delay_frames` (40→160 ms) | ✅ |
| Mixe audio multi-serveurs | `cpal` single stream + mixe | ✅ |

---

## 6. Fichiers & manipulations

| Fonctionnalité Windows | Équivalent Android | Statut |
|---|---|---|
| Télécharger (icônes/avatars) | `ts_download_file` + `IconCache` | ✅ |
| Télé-verser un fichier | `ts_upload_file` + panneau « Fichiers » | ✅ |
| Progression / annulation | `FileTransfer` + `file_transfer_progress` | ✅ |
| Gestionnaire de fichiers (liste/lister) | 🟡 (upload manuel par chemin) | 🟡 |

---

## 7. Options / préférences

| Fonctionnalité Windows | Équivalent Android | Statut |
|---|---|---|
| Thème (système/sombre/clair/AMOLED) | `AppThemeMode` + `TsPalette` | ✅ |
| Langue (EN/ZH/système) | `localeProvider` | ✅ |
| Reconnexion automatique | `auto_reconnect` | ✅ |
| Historique + rétention | `chatRetention` (7/30/90 j) | ✅ |
| Logs verbeux (redaction) | `AppLog` + `crate::redact` | ✅ |
| Notification de premier plan + actions | `KeepAliveService` | ✅ |

---

## 8. Nouveautés de cette phase (2026-08-28)

### 🔧 Optimisations de performance / chauffe / fluidité (exécutées)
- **`onMicLevel` throttlé** (50×/s → max 10×/s, + seuil de changement) : c'était la
  cause n° 1 de lag/jank pendant la prise de parole (chaque trame micro
  reconstruisait tout l'écran serveur).
- **`_refreshNotification` coalescé** (~600 ms) : la notification est un appel de
  canal de plateforme ; on ne l'appelle plus en rafale.
- **Roster & `channels_updated` gardés par `listEquals`** : on n'écrit dans
  l'état que si les données ont vraiment changé (évite un rebuild toutes les 2 s).
- **`diagMessages` borné** (40 max) : plus de croissance non bornée.
- **Buffer Opus réutilisé (thread-local)** : suppression d'une allocation de
  4 kB par trame micro (~50×/s) → moins de GC et de chauffe pendant la capture.

### 🔘 Boutons ajoutés (parité Windows)
- **Volume maître** : long-press sur l'icône haut-parleur → slider −20..+20 dB
  (gain appliqué dans le mix audio, partagé par tous les serveurs).
- **Menu « ⋮ »** regroupant : **Info canal**, **Favoriser ce serveur**,
  **Stats réseau**, **Rafraîchir le serveur**.

---

## 9. Reste à faire (pour l'équivalence complète)

| # | Élément | Priorité |
|---|---|---|
| 1 | **Gestionnaire de fichiers** (lister/créer dossier/supprimer `ftlist`, `ftdelete`) | Moyenne |
| 2 | **Recherche globale** (client+canal+fichier) | Moyenne |
| 3 | **Hotkeys / raccourcis** (PTT global, push-to-talk matériel) | Basse |
| 4 | **Amis / contacts** (`friendlist`) | Basse |
| 5 | **Permissions** (vue `permission_hints`, édition avancée) | Moyenne |
| 6 | **Lecture de fichiers téléchargés** (ouvrir depuis le téléchargement) | Basse |
| 7 | **Tests globaux sur serveur réel** vs `voice.teamspeak.com` (voir PLAN-TEST) | Haute |
| 8 | **FFI typée** (remplacer la sérialisation JSON du roster par des structures) | Haute (perf) |
| 9 | **Mesures CPU/batterie & tuning du jitter buffer** | Haute |
| 10 | **Édition de permissions de canal** (UI) | Basse |

---

## Estimation indicative

| Catégorie | Fait | Partiel | Manquant | Note |
|---|---|---|---|---|
| Connexion & favoris | 8 | 0 | 0 | complet |
| Canaux | 7 | 0 | 0 | complet |
| Clients & statut | 6 | 1 | 0 | quasi complet |
| Chat | 5 | 0 | 0 | complet |
| Audio & voix | 12 | 0 | 0 | complet |
| Fichiers | 3 | 1 | 0 | upload/download ok, gestionnaire à venir |
| Options | 6 | 0 | 0 | complet |
| **Total** | **47** | **2** | **0** | |

Le cœur fonctionnel (connexion, canaux, clients, chat, audio/voix, fichiers,
options, multi-serveur, thèmes) est **à parité** du client Windows ; les écarts
restants sont des **extensions de confort** (gestionnaire de fichiers, hotkeys,
amis, permissions) et de la **validation sur serveur réel**. Le prochain axe
prioritaire est la **perf** (FFI typée + mesures) puis le **gestionnaire de
fichiers**.
