# Reste à faire — inventaire détaillé (16 août 2026)

Audit du code réel (`lib/`, `native/src/`, `android/`) confronté à `PLAN-DEVELOPPEMENT.md`,
aux rapports `teamspeak-analysis/reports/` et au périmètre du client Windows officiel.

**Fait à ce jour** : connexion + machine d’état + reconnexion, canaux/clients, chat
canal/privé/serveur, whisper émission + liste blanche, volume par client, VAD hybride/PTT/
mute, service de fond + MediaSession, identité et mots de passe chiffrés (Keystore),
statistiques RTT/perte, i18n EN/ZH, 6 tests Rust + 14 tests Dart.

Légende effort : **S** ≤ ½ journée · **M** 1–3 jours · **L** > 3 jours.

---

## A. Bloquants du premier jalon

| # | Tâche | Où | Effort |
|---|---|---|---|
| A1 | **Build APK debug + release réel** et installation sur appareil. Le `.so` arm64/x86_64 est produit, mais Gradle n’a jamais tourné jusqu’au bout (sandbox 2 Go, démon tué par l’OOM killer). À refaire sur une machine ≥ 8 Go. | `android/` | S |
| A2 | **Test sur serveur TeamSpeak réel** : aucune des fonctionnalités réseau n’a été validée contre un vrai serveur (whisper, reconnexion, mots de passe, erreurs typées). | — | M |
| ~~A3~~ | ✅ **Fait (phase 8)** — CI : `.github/workflows/ci.yml` a été supprimé lors du durcissement (il embarquait l’OTA). À réécrire : `cargo check/test/fmt/clippy`, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`, build APK — **sur chaque commit**, pas seulement sur les tags. | `.github/` | S |
| A4 | Simplifier le bloc de signature release Gradle (hérité de l’amont, conditionnel et fragile). | `android/app/build.gradle.kts` | S |

---

## B. Sécurité et vie privée (Phase 2 restante)

| # | Tâche | Détail | Effort |
|---|---|---|---|
| ~~B1~~ | ✅ **Fait (phase 9)** — filtre de logs central | 31 `debugPrint/print` en Dart et 26 `eprintln!` en Rust, dont des adresses de serveur, pseudos et JSON d’état. Il faut un logger unique avec niveaux, coupé en release, et interdiction de logger secrets/adresses. | M |
| ~~B2~~ | ✅ **Fait (phase 9)** — commande d’effacement | Aucune UI pour révoquer l’identité TS3 et les mots de passe stockés : purge Keystore + préférences + confirmation. | S |
| ~~B3~~ | ✅ **Fait (phase 21)** — `tools/check_secrets.py` en CI (interpolation de secrets, sérialisation/notifications, couches de redaction présentes). | S |
| ~~B4~~ | ✅ **Fait (phase 19)** — import/export d’identité protégé | Sauvegarde chiffrée par mot de passe (PBKDF2+AES-GCM), export en blob portable copiable, restauration vers Keystore + moteur. | M |

---

## C. Réseau et moteur (Phase 3 restante)

| # | Tâche | Détail | Effort |
|---|---|---|---|
| ~~C1~~ | ✅ **Fait (phase 9)** — bascule Wi-Fi ↔ mobile | Aujourd’hui traité comme une coupure générique. Il faut écouter `ConnectivityManager` et déclencher une reconnexion immédiate (sans attendre le backoff) au retour du réseau, plus gérer le changement d’IP locale. | M |
| ~~C2~~ | ✅ **Fait (phase 10)** — anti-flood commandes | Aucune limitation : une UI trop réactive (déplacements de canal en rafale) peut faire kicker/bannir. Il faut une file avec débit borné côté Rust. | M |
| ~~C3~~ (partiel) | ✅ **Fait (phase 19, jitter)** — jitter d’inter-arrivée (EWMA) exposé et affiché. **Restant** : taille de la file de retransmission (non exposée par tsproto, exigerait un patch). | S |
| C4 | **FFI typée** | La sérialisation JSON à chaque cycle (roster complet toutes les 2 s) est le plus gros coût du pont. À remplacer par des structures/buffers typés **si** le profilage le justifie. | L |
| ~~C5~~ | ✅ **Fait (phase 22)** — reprise après kill | `ResumeIntent` persisté à la connexion, effacé à la déconnexion ; bannière « Reprendre » à l'accueil ; le micro ne se ré-ouvre **jamais** automatiquement (mute par défaut). | M |

---

## D. Audio (Phase 4 — la plus grosse dette)

| # | Tâche | Détail | Effort |
|---|---|---|---|
| ~~D1~~ | ✅ **Fait (phase 8)** — AEC / NS / AGC | La source est bien `VOICE_COMMUNICATION`, mais `AcousticEchoCanceler`, `NoiseSuppressor` et `AutomaticGainControl` ne sont **jamais instanciés** : en haut-parleur, l’écho est renvoyé aux autres. Activation conditionnelle avec `isAvailable()` + interrupteurs UI. | M |
| ~~D2~~ | ✅ **Fait (phase 8)** — sélection de la sortie | Aucun routage : écouteur / haut-parleur / filaire / USB / **Bluetooth SCO** (+ `BLUETOOTH_CONNECT` sur Android 12+). C’est l’absence la plus visible à l’usage en mobilité. | M |
| ~~D3~~ (partiel) | ✅ **Fait (phase 20, adaptatif)** — jitter buffer piloté par le jitter réseau mesuré (40 ms min → 160 ms max, re-calculé aux nouveaux buffers). **Restant** : taille de la file de retransmission (tsproto), PLC Opus sur perte, mesures sur appareil. | M |
| ~~D4~~ | ✅ **Fait (phase 15)** — zéro allocation dans la boucle micro | Chaîne Kotlin `AudioRecord` → EventChannel → Dart → FFI : au moins une copie et des allocations par trame de 20 ms. Évaluer un passage direct JNI → Rust. | L |
| ~~D5~~ | ✅ **Fait (phase 9)** — focus audio | Aucun `AudioFocusRequest` : pas d’interaction propre avec la musique ou un appel entrant. | S |
| D6 | **Campagne de mesures** | Latence bout-en-bout, underruns/overruns, CPU, capture 48 kHz/960 sur Android 9/11/13/15+, PTT/VAD/mute après interruption téléphonique. | L |

---

## E. Parité fonctionnelle avec le client officiel

Le moteur n’expose que 30 fonctions FFI ; toute l’administration TeamSpeak manque.

| # | Tâche | Détail | Effort |
|---|---|---|---|
| ~~E1~~ | ✅ **Fait (phase 11)** — opérations conditionnées par permission | Kick canal/serveur, ban, poke, déplacer un autre client, mute serveur — chacune n’étant proposée que si la permission est réellement accordée. | L |
| ~~E2~~ | ✅ **Fait (phase 19)** — créer / éditer / supprimer / déplacer un canal (titre, sujet, mot de passe, max clients, permanent / semi-permanent), menu par canal, permission appliquée par le serveur. | L |
| ~~E3~~ | ✅ **Fait (phases 12-13)** — icônes de groupes | Les noms de groupes sont affichés ; les icônes (téléchargement via file transfer + cache) manquent. | M |
| E4 | **Statut utilisateur** | Absent/AFK avec message, changement de pseudo en session, *channel commander*, *priority speaker*, talk power. | M |
| ~~E5~~ | ✅ **Fait (phase 14)** — historique chiffré | Les messages ne vivent qu’en mémoire : tout est perdu à la déconnexion. Historique optionnel, chiffré, avec purge. | M |
| ~~E6~~ | ✅ **Fait (phase 16)** — fils de conversation | Un seul flux mélange canal, privé et serveur : il faut des onglets/fils par interlocuteur avec badges non lus. | M |
| ~~E7~~ | ✅ **Téléchargement + avatars (phases 12/16) + envoi (phase 19)** — envoi de fichiers | `ts_upload_file` + événements `file_transfer_progress`, panneau de transferts avec barres de progression, annulation. | L |
| ~~E8~~ | ✅ **Fait (phase 17)** — multi-serveurs | Registre de sessions `connection_id` (état, commandes, budget, transfers, audio namespacé `(conn, client)`), un flux cpal qui mixe les serveurs, UI à onglets, notification agrégée, mic dans la session focalisée. (À valider sur appareil réel.) | L |
| ~~E9~~ (tranches 1-3) | ✅ **Fait (phases 18-20)** — recherche de canaux/clients, tri, favoris, sons d’événements, **théme système/sombre/clair/AMOLED**. **Restant** : favoris par serveur, réglages fins des sons, quelques accents thématisables. | M |

---

## F. Qualité et outillage (Phase 6 restante)

| # | Tâche | Détail | Effort |
|---|---|---|---|
| ~~F1~~ (partiel) | ✅ **Fait (phase 21)** — 100 cycles de cycle de vie de session sans fuite (SESSIONS/buffers/décodeurs). Le « connect réel » reste à valider sur serveur. | M |
| ~~F2~~ (partiel) | ✅ **Fait (phase 22)** — classification/coûts anti-flood, propagation des refus serveur, redaction, cycle de vie sans fuite. **Restant** : parseurs crypto/fragmentation/ACK/pertes (nécessitent un vrai serveur). | L |
| F3 | **Tests Flutter** | Notifiers (reconnexion, whisper, migrations de préférences) et formulaires ; aujourd’hui seuls les modèles purs sont couverts. | M |
| F4 | **Tests Android instrumentés** | Permissions, service de fond, Bluetooth, processus tué, Doze. | L |
| F5 | **Tests réseau dégradé** | Perte, duplication, réordonnancement, latence, MTU réduit (serveur de test + shaping). | M |
| ~~F6~~ | ✅ **Fait (phase 21)** — SBOM CycloneDX (Cargo), `cargo deny` (licences permissives seules), vérif copyleft côté Flutter, `cargo audit` en CI, `check_secrets.py` (B3). | S |
| F7 | **Statut de licence du fork** | `PRIVATE_USE_NOTICE.md` : l’amont n’a pas de licence open source. Une publication « open source » exige une autorisation écrite ou une réécriture propre. **Question juridique, pas technique — mais bloquante pour l’objectif affiché.** | — |

---

## Ordre conseillé

1. **A1–A3** : un APK qui tourne sur un vrai appareil contre un vrai serveur, et une CI qui garde le tout vert.
2. **D1 + D2** : écho et routage Bluetooth — ce qui rend l’app réellement utilisable en mobilité.
3. **B1 + B2** : hygiène des logs et effacement des secrets, avant toute diffusion.
4. **C1 + C2** : robustesse réseau réelle (bascule Wi-Fi/mobile, anti-flood).
5. **E1 + E3 + E4** : première tranche de parité (opérations par permission, icônes, statut).
6. **F1 + F3** : filet de sécurité de non-régression avant les gros chantiers (E7, E8, C4, D4).
