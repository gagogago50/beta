# Phase 7 — machine d’état de connexion, erreurs typées et reconnexion

## Machine d’état explicite

Le plan (Phase 3) demandait une machine d’état explicite. Le moteur émet désormais des
transitions de phase, au lieu de laisser l’UI deviner à partir d’un booléen `connecting` :

```text
idle → resolving → connecting → authenticating → connected
                                       ↓
                                    failed → reconnecting → (resolving …)
```

- Rust : `TsEvent::ConnectionPhase { phase }` (`ConnectPhase::{Resolving, Connecting,
  Authenticating, Connected}`), émis dans `do_connect`. La phase `authenticating` est aussi
  déclenchée par `IdentityLevelIncreasing`, qui n’est pas une erreur mais la preuve de travail
  exigée par le serveur — elle était auparavant remontée comme `error`.
- Dart : enum `TsPhase` (`lib/models/reconnect_policy.dart`), champ `phase` dans l’état
  Riverpod. `reconnecting` et `failed` appartiennent à la politique client.
- Une phase reçue tardivement (attente annulée) ne peut plus faire régresser une connexion
  déjà établie.

## Erreurs de connexion structurées

Auparavant : une `String` formatée, classifiée par recherche de sous-chaîne côté Dart.
Désormais :

```json
{ "type": "connect_failed", "kind": "password", "phase": "authenticating",
  "message": "...", "retryable": false }
```

`kind` est dérivé de la **variante** de `tsclientlib::Error` (jamais du texte, qui n’est pas un
contrat) via `classify_connect_error`, avec un second niveau pour les refus serveur
(`classify_server_refusal` sur `TsError`) :

| Variante / code serveur | `kind` | Réessayable |
|---|---|---|
| `ResolveAddress` | `dns` | oui |
| `InitserverTimeout`, timeout global 15 s | `timeout` | oui |
| `Connect`, `ConnectionFailed`, `Io`, `SendPacket`… | `network` | oui |
| `ServerInvalidPassword`, `ClientInvalidPassword` | `password` | non |
| `ChannelInvalidPassword` | `channel_password` | non |
| `ConnectFailedBanned`, `RenameFailedBanned` | `banned` | non |
| `ClientNicknameInuse` | `nickname_in_use` | non |
| `ServerMaxclientsReached` | `server_full` | oui |
| `IdentityLevel*`, `ClientCouldNotValidateIdentity` | `identity_level` | non |
| `ServerUidMismatch` | `server_identity_changed` | non |
| `InitserverParse`, `InitserverParamsMissing` | `protocol` | non |
| variante ajoutée en amont (`#[non_exhaustive]`) | `unknown` | oui |

`ConnectFailed { errors }` (toutes les adresses résolues ont échoué) hérite du verdict du
premier enfant. Le mapping `kind` → phrase affichée est centralisé dans un seul `switch` Dart.

## Annulation et déconnexion distinguée

- `ts_cancel_connect()` avorte la tâche de connexion (`CONNECT_TASK`) : sans cela, quitter
  l’écran laissait une tentative tourner en fond et son échec tardif s’affichait sur un écran
  sans rapport.
- `TsEvent::Disconnected` porte maintenant `expected: bool`. Une déconnexion demandée
  (bouton, notification, swipe-away) n’est jamais suivie d’une reconnexion automatique ;
  une coupure subie l’est.

## Reconnexion automatique

`ReconnectPolicy` (`lib/models/reconnect_policy.dart`), volontairement conservatrice — les
serveurs TeamSpeak limitent et bannissent les clients qui martèlent le handshake :

- backoff exponentiel : 2 s, 4 s, 8 s, 16 s… plafonné à 30 s ;
- gigue ±20 % pour ne pas faire revenir en rafale tous les clients d’un serveur redémarré ;
- 6 tentatives maximum ;
- liste explicite de `kind` jamais réessayés (mot de passe, bannissement, pseudo pris,
  niveau d’identité, refus serveur, protocole, annulation) ;
- bouton « réessayer maintenant » qui conserve l’index de tentative (l’échec suivant reprend
  le délai plus long, il ne redémarre pas la séquence) ;
- interrupteur « reconnexion automatique » persisté dans les préférences.

**Restauration du canal** : le canal courant est mémorisé (par nom, les IDs de canaux non
permanents ne survivent pas à une session) avant la remise à zéro de l’état, puis re-rejoint
après la reconnexion si le serveur ne nous y a pas déjà placés. S’il a disparu, on reste dans
le canal par défaut avec une trace de diagnostic.

## Interface

- Panneau de progression : libellé de phase, compte à rebours de la prochaine tentative
  (`Attempt 2 of 6 in 7s`), motif de l’échec, boutons Annuler / Réessayer maintenant.
- L’écran serveur ne se ferme plus pendant une reconnexion programmée.
- Barre de connexion : icône/couleur et libellé selon la phase (orange pendant les phases
  actives).
- Réglages : nouvelle section « Connexion » avec l’interrupteur de reconnexion automatique.
- Chaînes EN/ZH ajoutées, `flutter gen-l10n` régénéré.

## Tests

- Rust (+3, 6 au total) : refus non réessayables, échecs transitoires réessayables,
  héritage du verdict dans `ConnectFailed { errors }`.
- Dart (+10, 14 au total) : politique de réessai par `kind`, budget de tentatives,
  croissance exponentielle et plafond, fenêtre de gigue ±20 % (avec `Random` injecté),
  délai toujours strictement positif, mapping et `isBusy` de `TsPhase`.

## Validation

- `cargo check --locked` : réussi ;
- `cargo test --locked` : 6/6 ;
- `cargo fmt` : appliqué ;
- `flutter gen-l10n` : réussi ;
- `dart format .` : réussi ;
- `flutter analyze` : aucune anomalie ;
- `flutter test` : 14/14.

## Suite

1. Icônes de groupes et opérations d’administration conditionnées par les permissions.
2. Historique séparé et chiffré des conversations privées.
3. Bascule Wi-Fi / mobile et changement d’adresse pris en compte par la reconnexion
   (aujourd’hui traités comme une coupure générique).
4. Limitation de fréquence des commandes (anti-flood) côté moteur.
5. Build APK ARM64 avec NDK officiel et inspection du manifeste et des ELF — bloqué dans la
   sandbox actuelle (2 Go de RAM : le démon Gradle est tué par l’OOM killer), le `.so` natif
   est en revanche bien produit par `pre_build.py`.
