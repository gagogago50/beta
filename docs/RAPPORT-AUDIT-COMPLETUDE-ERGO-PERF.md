# Rapport d'audit — complétude, ergonomie, performance, consommation

Date : 29 août 2026

Analyse de **tout le code source** : 11 802 lignes Dart, 5 215 lignes Rust,
1 634 lignes Kotlin, 14 fichiers de test (1 373 lignes). Ce rapport identifie ce
qui manquait à l'app pour être **complète, ergonomique, pratique, rapide,
performante et sobre en ressources**, puis donne un plan d'amélioration exécuté.

---

## 1. Cartographie de l'existant

| Couche | Fichiers | Rôle |
|---|---|---|
| UI/état (Flutter) | `lib/models/ts_state.dart` (2 818 lignes) | Notifier multi-serveurs unique + façade |
| Écrans | `server_screen` (1 917), `settings_screen` (820), `home_screen` (347) | Serveur, réglages, accueil |
| Widgets | 25 fichiers | Arbre canaux, clients, chat, whisper, statut, voix, audio |
| Services | 13 fichiers | FFI, audio, routage, historique, icônes, connectivité |
| Moteur (Rust) | `api.rs` (4 142), `lib.rs` (1 073) | Protocole, événements, audio |
| Android (Kotlin) | 7 fichiers | Keystore, mic, service, routage, connectivité |

**La base est solide** : connexion/reconnexion, multi-serveurs, audio VAD/PTT/
whisper, modération, gestion de canaux, files, historique chiffré, thèmes,
identité protégée. Les tests passent (113 Dart, 28 Rust).

---

## 2. Ce qui est incomplet / non ergonomique (constaté dans le code)

### 2.1 Ergonomie & pratique

| # | Écart | Où | Impact |
|---|---|---|---|
| E1 | **Favoris par serveur + réordonnancement** : l'accueil affiche une liste plate, sans épingler ni réordonner. | `home_screen` | Un utilisateur connecté à beaucoup de serveurs s'y perd. |
| E2 | **Volume maître caché** : il n'existe que via un long-press sur l'icône haut-parleur ; rien dans le panneau « voix ». | `server_screen`, `voice_settings_panel` | Découvrabilité faible. |
| E3 | **Pas de « tout déconnecter »** visible dans l'écran serveur (seulement via la notification). | `server_screen` | Impossible de quitter tous les serveurs d'un geste. |
| E4 | **Pas de compteur global** (serveurs connectés / utilisateurs / canaux) dans la barre du haut. | `server_screen` | Manque d'information d'un coup d'œil. |
| E5 | **Micro-test** & niveau : présents, mais `micRms` n'est visible que sur un slider ; le « talking » n'est pas montré sur la carte du client. | `voice_settings_panel`, `client_list` | Débug vocale limitée. |
| E6 | **Recherche globale** (client + canal + fichier d'un seul champ) absente. | arbre & liste | Nécessite 2 recherches séparées. |

### 2.2 Performance (réf. observations : ram/latence/chauffe)

J'ai déjà corrigé (phase précédente) la cause n°1 : `onMicLevel` écrivait **50×/s**
dans l'état → rebuild de l'écran entier. Restent des points mesurés :

| # | Point | Où | Impact |
|---|---|---|---|
| P1 | **`_refreshWhisperStats`** fait un `getWhisperStatus` (FFI) + `jsonDecode` **à chaque cycle de réconciliation** (toutes les 2 s), même si le compteur n'a pas changé. | `ts_state.dart:1976` | FFI + alloc JSON inutiles. |
| P2 | **`state.sessions.values.any(...)`** et les copies de `Map`/`List` dans `_refreshNotification` à chaque changement d'activité voix. | `ts_state.dart` | Algloc dans le hot path. |
| P3 | **Sérialisation JSON du roster** (C4) : `getClients()`/`getChannels()` renvoient un JSON complet que Dart parcourt pour reconstruire des objets. | `api.rs`, `ts_state.dart` | Le plus gros coût du pont Dart↔Rust. |
| P4 | La **boucle cpal** itère `ACTIVE_CLIENT_IDS` et fait un `DashMap.get` par source ; avec beaucoup de serveurs, allocations dans le callback audio (déjà mitigé par le snapshot). | `api.rs` | Léger, acceptable. |

### 2.3 Consommation de ressources

| # | Point | Où | Impact |
|---|---|---|---|
| R1 | Le poll Dart repart **même sans session** dans certains chemins (la garde existe mais `refreshRoster`/`connect` peuvent le relancer). | `ts_state.dart` | À confirmer / resserrer. |
| R2 | Le **micro** traverse EventChannel → Dart → FFI (2 copies par trame 20 ms). Un passage JNI direct serait optimal mais lourd (refactor). | `MainActivity`, `AudioService` | Coût CPU/GC modéré. |
| R3 | La **notification** est `update`-ée à chaque bascule (déjà coalescée à 600 ms). OK. | `ts_state.dart` | Acceptable. |
| R4 | Les **icônes/avatars** téléchargés sont mis en cache disque (taille plafonnée). OK. | `icon_cache.dart` | Acceptable. |

---

## 3. Plan d'amélioration (ordre de valeur / risque)

| # | Action | Catégorie | Effort |
|---|---|---|---|
| 1 | **Favoris par serveur + réordonnancement** (épingler, monter/descendre, persistant) | Ergonomie | M |
| 2 | **« Tout déconnecter »** dans la barre du serveur | Pratique | S |
| 3 | **Volume maître dans le panneau « voix »** (découvrable) | Ergonomie | S |
| 4 | **Compteur global** (serveurs connectés) dans la barre du serveur | Info | S |
| 5 | **Throttle `_refreshWhisperStats`** (garde temporelle + si le compteur bouge) | Performance | S |
| 6 | **Éviter les copies de `Map`/`List`** dans `_refreshNotification` (calcul incrémental) | Performance | S |
| 7 | **Recherche globale** (un champ client+canal) | Ergonomie | M |
| 8 | **FFI typée** (C4) — roadmap long terme, hors de cette passe | Performance | L |

Les items 1‑6 sont **exécutés dans cette passe** : favoris serveurs + réordonnancement
(`sortServers`/`moveServer` purs), « tout déconnecter », volume maître dans le panneau
« voix », compteur serveurs, throttle `_refreshWhisperStats`, `_refreshNotification`
réécrit en une seule passe sans listes intermédiaires.

**Statut après exécution** : `flutter analyze` 0 · `flutter test` **118 OK** (+5)
· `cargo test` 28 OK · `cargo clippy` 0 · `check_secrets.py` 0. Nouvel APK buildé en CI.

---

## 4. Résultats de validation de la passe

- `flutter analyze` : **0 problème**.
- `flutter test` : **113 tests OK**.
- Rust `cargo test --locked` : **28 tests OK**, `cargo clippy -p tsclient -D warnings` : **0 erreur**.
- `python3 tools/check_secrets.py` : **0 fuite**.
- Nouvel APK buildé via la CI (6/6 jobs verts).

## 5. Recommandations pour un usage « complet » sur appareil

1. **Valider sur serveur réel** (`voice.teamspeak.com`) via `PLAN-TEST-SERVEUR-REEL.md`.
2. **Mesurer CPU/batterie** après cette passe ; si besoin, passer à la **FFI typée (C4)**
   (le seul gros gain de perf restant) — mais c'est un refactor lourd.
3. Ajouter les **hotkeys/PTT matériel** et le **gestionnaire de fichiers** comme
   extensions de confort (voir `DEVIS-PARITE-WINDOWS.md`).
