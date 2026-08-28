# Plan détaillé — fork personnel NEk0

## Statut

Ce répertoire est un prototype personnel basé sur le dépôt public `senlinjun/NEk0`, révision initiale `f5497d12ed368f8f2969f15d7f1dfabe05434a22` du 13 août 2026.

Le dépôt amont ne contient pas de licence open source standard au moment du clonage et son README indique « For educational use ». Le prototype ne doit donc pas être publié, redistribué ou relicencié sans autorisation écrite du détenteur des droits. Les dépendances ReSpeak conservent leurs licences MIT/Apache-2.0.

## Cible

- Android 9/API 28 minimum.
- ARM64 pour appareils réels ; x86_64 pour émulateur.
- Flutter UI + Riverpod.
- Kotlin pour capture micro et service Android.
- Rust pour protocole TS3, état, Opus et rendu audio.

## Architecture existante

```text
Flutter/Riverpod
├── favoris, écrans, état et paramètres
├── polling FFI toutes les 200 ms
└── EventChannel micro / MethodChannel service

Kotlin Android
├── AudioRecord 48 kHz mono
├── ForegroundService microphone/mediaPlayback
├── MediaSession et notification
└── routage des événements vers Flutter

Rust cdylib
├── ReSpeak tsclientlib/tsproto
├── connexion UDP et événements
├── identité TS3
├── Opus 48 kHz / trames 960
├── jitter buffers par client
└── mixage/rendu cpal
```

## Phase 1 — stabiliser la base

- [x] Cloner et figer la révision amont.
- [x] Définir explicitement `minSdk = 28`.
- [x] Interdire Android Auto Backup tant que l’identité et les mots de passe sont en préférences locales.
- [x] Corriger les allocations FFI Dart des chaînes d’entrée.
- [x] Installer Flutter, JDK 17, Rust et Android NDK 26 dans l’environnement de build.
- [ ] Exécuter `cargo check`, `dart format`, `flutter analyze` et un build APK debug.
- [ ] Simplifier le bloc Gradle de signature release après validation du build amont.
- [ ] Créer des tests pour chaque fonction FFI qui alloue/retourne une chaîne.

## Phase 2 — sécurité locale

- [x] Remplacer le stockage de `client_identity` dans SharedPreferences par Android Keystore + AES-GCM.
- [x] Déplacer les mots de passe serveur/canal des favoris dans le stockage chiffré.
- [x] Ajouter migration atomique des anciennes préférences en clair puis suppression logique après confirmation.
- [x] Supprimer les logs de diagnostic sensibles et ajouter un filtre central (caviardage Dart + Rust).
- [x] Ajouter une commande « effacer identité et secrets ».
- [ ] Vérifier qu’aucun secret n’est inclus dans sauvegarde, capture d’erreur ou notification.

## Phase 3 — connexion et état

- [x] Remplacer le polling fixe 200 ms par un pont adaptatif sans chevauchement.
- [x] Ajouter une notification native Rust → `NativeCallable.listener` pour réveiller immédiatement Dart.
- [ ] Remplacer à terme la sérialisation JSON FFI par des structures/buffers typés si le profiling le justifie.
- [x] Ajouter machine d’état explicite : idle, resolving, connecting, authenticating, connected, reconnecting, failed.
- [x] Ajouter timeout, annulation de connexion et backoff exponentiel avec jitter.
- [x] Gérer bascule Wi-Fi/mobile, perte temporaire et changement d’adresse.
- [ ] Exposer RTT, perte, jitter et file de retransmission depuis Rust.
- [x] Exposer RTT, déviation et perte de paquets dans l’état/UI.
- [x] Limiter la fréquence des commandes pour éviter les kicks flood (seau à jetons + file + mode dégradé).

## Phase 4 — audio

- [ ] Tester capture 48 kHz/960 sur Android 9, 11, 13 et 15+.
- [x] Éviter toute allocation dans la boucle micro Kotlin→Dart→Rust (trame réutilisée, lecture bloquante).
- [ ] Évaluer un passage direct Kotlin/JNI→Rust pour éviter la copie via EventChannel.
- [~] Mesurer latence bout-en-bout, underruns, overruns et CPU (optimisations batterie phase 15 ; mesures sur appareil restantes).
- [ ] Ajuster le jitter buffer à partir de métriques réseau plutôt qu’une fenêtre fixe.
- [x] Ajouter sélection sortie : écouteur, haut-parleur, filaire, USB, Bluetooth SCO.
- [x] Ajouter AEC/NS/AGC conditionnels avec détection de disponibilité.
- [x] Ajouter un VAD hybride indépendant (gate + bruit adaptatif + forme vocale + hangover 200 ms).
- [ ] Tester PTT, VAD hybride, mute complet et restauration après interruption téléphonique.

## Phase 5 — fonctionnalités

- [x] Messages privés réels côté moteur, plus envoi au canal et au serveur.
- [x] Mot de passe serveur et mot de passe canal séparés, chiffrés au repos et transmis au moteur.
- [x] Ajouter dialogue de mot de passe lors du déplacement vers un canal protégé.
- [x] Remonter les erreurs serveur/permission/mot de passe sous forme structurée.
- [x] Détecter et afficher les whisper entrants.
- [x] Ajouter whitelist et émission whisper.
- [x] Exposer en lecture les IDs et noms de groupe canal/groupes serveur par client.
- [x] Charger les icônes de groupes et ajouter les opérations autorisées par permissions.
- [x] Reconnexion et restauration du canal.
- [ ] Import/export d’identité protégé.
- [x] Historique de chat facultatif et chiffré.

## Phase 6 — qualité

- [ ] Tests Rust : parseurs, crypto, fragmentation, ACK, pertes, jitter et rollover.
  - [x] Premiers tests unitaires Rust : assainissement des cibles whisper et classification des erreurs de connexion.
- [ ] Tests Flutter : modèles, notifiers, migration et formulaires.
  - [x] Politique de reconnexion (backoff, gigue, kinds non réessayables) et phases.
- [ ] Tests Android instrumentés : permissions, service, Bluetooth, processus tué et Doze.
- [ ] Tests réseau : perte, duplication, réordonnancement, latence et MTU réduit.
- [x] CI sur chaque commit, pas uniquement sur les tags (fmt, clippy strict, tests Rust et Flutter, APK).
- [ ] SBOM, dépendances verrouillées et vérification des licences.

## Critères du premier jalon

1. APK debug installable sur Android 9 et Android récent.
2. Connexion fiable à un serveur de test autorisé.
3. Liste canaux/clients correcte.
4. Réception audio stable pendant 30 minutes.
5. PTT et mute ne transmettent jamais hors état attendu.
6. Aucune fuite d’allocation FFI lors de 100 cycles connexion/déconnexion.
7. Identité et mots de passe absents des sauvegardes et logs.
