# Phase 9 — journalisation caviardée, effacement des secrets, réseau et focus audio

Traite **B1**, **B2**, **C1** et **D5** de `RESTE-A-FAIRE.md`.

## B1 — Logger central avec caviardage

Constat de l’audit : 31 `debugPrint` Dart et 26 `eprintln!` Rust, dont l’adresse du serveur,
le pseudo, des JSON d’état complets — tout cela finit dans logcat, lisible par un rapport de
bug ou par de l’outillage sur l’appareil.

**Dart — `lib/services/app_log.dart`**

- niveaux `debug/info/warn/error` ; en release le plancher est `warn`, donc le trafic
  de diagnostic n’est même pas construit ;
- `redact()` appliqué à **chaque** message : valeurs des clés sensibles
  (`password`, `token`, `secret`, `identity`, `uid`, `nickname`…), blobs base64 ≥ 24
  caractères (identités et UID TeamSpeak), noms d’hôtes et IPv4 avec ou sans port ;
- `AppLog.e(tag, message, error)` journalise le **type** de l’exception, jamais l’instance :
  les messages d’exception embarquent régulièrement la valeur fautive (URL, clé, mot de passe) ;
- les 31 appels existants ont été convertis, et les plus bavards réécrits pour ne plus
  contenir la donnée du tout (`connect($address, $nickname)` → `connect requested
  (channel set: true)`).

**Rust — `native/src/lib.rs`**

- `LOG_LEVEL` atomique (défaut : `debug` en build de développement, `warn` en release) ;
- macros `log_error!/log_warn!/log_info!/log_debug!` qui filtrent **avant** de formater et
  passent par `redact()` ;
- les 25 `eprintln!` d’`api.rs` convertis, `ts_connect` ne journalise plus du tout l’adresse ;
- le hook de panique reste toujours actif — c’est la seule trace qui vaut un rapport de bug —
  mais son message est caviardé lui aussi ;
- `ts_set_log_level(0..4)` : un seul interrupteur UI pilote les deux côtés.

## B2 — Effacer identité et secrets

Nouvelle commande dans Réglages → Confidentialité, avec dialogue de confirmation explicite
(l’identité est la seule chose que l’utilisateur ne peut pas recréer).

Séquence, chaque étape indépendante pour qu’un échec n’en laisse pas d’autres derrière :

1. déconnexion (une session ouverte continue d’utiliser l’identité) ;
2. `ts_clear_identity()` — **sans cela**, la copie en mémoire du moteur serait réécrite dans
   le stockage sécurisé à la connexion suivante, ressuscitant silencieusement l’identité ;
3. suppression de l’entrée Keystore et de l’ancienne préférence en clair ;
4. suppression de tous les mots de passe serveur/canal (`ServerListNotifier.eraseAllSecrets`,
   avec `Server.copyWith(clearPassword:)` pour purger aussi les copies en mémoire) ;
5. suppression des volumes par client (clés par UID : ils disent avec qui on parle) et de la
   liste blanche whisper.

Les favoris sont conservés : `Server.toJson` ne contient aucun secret.

## C1 — Reconnexion pilotée par la connectivité

`ConnectivityStreamHandler.kt` (EventChannel `com.senlinjun.nek0/connectivity`) diffuse
disponibilité, transport et un identifiant opaque de réseau. Trois comportements :

- **retour du réseau** pendant une attente de reconnexion → tentative immédiate au lieu de
  laisser filer jusqu’à 30 s de backoff ;
- **perte du réseau** → le compte à rebours est mis en pause plutôt que de consommer le
  budget de tentatives dans le vide ;
- **bascule Wi-Fi ↔ mobile en pleine session** → l’adresse locale a changé, la session est
  déjà morte même si rien n’a l’air cassé : on force la déconnexion (et donc la reconnexion
  avec restauration du canal) au lieu d’attendre le timeout serveur.

Un réseau monté mais **non validé** (portail captif) est traité comme indisponible.

## D5 — Focus audio

`AudioFocusRequest` en `USAGE_VOICE_COMMUNICATION` / `CONTENT_TYPE_SPEECH`, pris au démarrage
du mode voix et rendu à l’arrêt. À la perte de focus (appel entrant, autre application vocale)
le micro est **coupé** — sans cela l’appel téléphonique de l’utilisateur partirait dans le
canal TeamSpeak — puis rétabli au retour du focus, **uniquement** si c’est bien la perte de
focus qui l’avait coupé : un mute manuel n’est jamais annulé automatiquement.

## Vérifications

- `cargo fmt`, `cargo check --locked`, `cargo clippy -p tsclient -- -D warnings` : 0 ;
- `cargo test` : **8/8** (+2 : caviardage des adresses/UID, préservation des diagnostics) ;
- `kotlinc` contre `android.jar` (API 35) + `flutter.jar` : `VoiceAudioController.kt` et
  `ConnectivityStreamHandler.kt` compilent, harnais de type-check des appels de `MainActivity`
  (dont les nouveaux callbacks de focus) ;
- `dart format --set-exit-if-changed`, `flutter analyze` : 0 ;
- `flutter test` : **29/29** (+10 : caviardage adresses/clés/blobs, idempotence, filtre de
  niveau, type d’exception seul, détection de bascule réseau).

## Suite

1. **A1/A2** — build APK et essai sur un vrai serveur (hors sandbox : 2 Go de RAM).
2. **B3** — vérifier qu’aucun secret ne subsiste dans une sauvegarde ou une notification,
   maintenant que le caviardage existe.
3. **C2** — limitation de fréquence des commandes (anti-flood).
4. **E1/E3/E4** — première tranche de parité : opérations par permission, icônes de groupes,
   statut absent/pseudo.
