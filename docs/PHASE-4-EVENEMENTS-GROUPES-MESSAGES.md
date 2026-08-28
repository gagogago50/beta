# Phase 4 — événements, groupes, messages et dépendances

## SDK officiel évalué

Le SDK TeamSpeak 3.5.2 officiel a été téléchargé et vérifié :

```text
SHA-256 9eabe05abebf949e288553c6646abb4ef3854b6d196118c2ae87eb2436644865
```

Il fournit Android ARM64/x86_64, mais reste propriétaire et sa licence interdit la redistribution sans accord. Aucun binaire ou fichier du SDK n’est intégré au projet. Voir `EVALUATION-SDK-OFFICIEL.md`.

## Événements Rust → Dart

Ajout d’un signal natif edge-triggered :

```text
Rust met TsEvent en file
 → callback C sans payload
 → NativeCallable.listener
 → retour sur isolate Dart
 → ts_poll_events()
 → Riverpod
```

Le callback peut être invoqué depuis les workers Rust. Il ne fait qu’envoyer un réveil vers l’isolate ; les événements restent possédés et sérialisés par Rust. Un debounce microtask évite de drainer plusieurs fois pour une rafale d’événements.

Le polling résiduel sert seulement à :

- indicateur vocal pendant capture : 50 ms ;
- timeout/sécurité connexion : 1 s ;
- réconciliation roster : 2 s.

## Messages

Correction d’un défaut où `target_mode` était ignoré et tout message partait vers le canal.

Sont maintenant implémentés :

- canal : `target_mode = 2` ;
- client privé : `target_mode = 1` avec ID client ;
- serveur : `target_mode = 3` ;
- remontée d’une erreur si l’envoi ReSpeak échoue ;
- validation des pointeurs, IDs et messages vides.

La méthode Flutter de message privé appelle réellement Rust/TeamSpeak avant l’ajout local dans la conversation.

## Groupes

Chaque client expose maintenant :

- ID et nom du groupe canal ;
- IDs et noms des groupes serveur ;
- tri déterministe avant sérialisation.

L’interface affiche les noms sous le nickname du client.

## Source vendored réparée

Les répertoires Rust nommés `build/` n’étaient pas persistés par la plateforme de workspace. Les générateurs de `ts-bookkeeping` et `tsproto-types` ont été restaurés depuis la même révision NEk0, déplacés sous `codegen/`, et les chemins Cargo/templates ont été mis à jour.

## Audit RustSec

Le premier audit a trouvé :

- `RUSTSEC-2026-0204` dans `crossbeam-epoch 0.9.18` ;
- `RUSTSEC-2026-0119` dans `hickory-proto 0.24.4`.

Corrections :

- `crossbeam-epoch` → 0.9.20 ;
- migration DNS vers `hickory-net`/`hickory-resolver` 0.26.1 ;
- adaptation du résolveur à la nouvelle API ;
- `rand` → 0.10 pour ce résolveur.

Résultat final `cargo audit` : **aucune vulnérabilité connue**. Il reste un avertissement RustSec sur `anyhow 1.0.102` concernant `downcast_mut`; le chemin concerné n’est pas utilisé par le runtime applicatif et aucune version corrigée n’est proposée dans l’avis au moment de l’audit.

## Validation

- `cargo check --locked` : réussi ;
- `cargo audit` : zéro vulnérabilité, un warning autorisé ;
- Flutter 3.47.0 / Dart 3.13.0 ;
- `flutter pub get` : réussi, lockfile régénéré sans OTA ;
- `flutter gen-l10n` : réussi ;
- `dart format --set-exit-if-changed` : réussi ;
- `flutter analyze` : aucune anomalie ;
- `flutter test` : 2 tests réussis.

## Étape suivante

- erreurs TeamSpeak typées et affichage spécifique mot de passe/permission ;
- icônes de groupes ;
- opérations d’administration conditionnées par permission ;
- whisper et whitelist ;
- build Android NDK officiel et inspection de l’APK.
