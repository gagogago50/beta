# Phase 21 — Qualité : tests mémoire FFI (F1), SBOM + licences (F6), anti-fuite (B3), CI (A3)

Date : 28 août 2026

## Objectif

C'est la tranche « filet de sécurité » avant tout refactor : des **tests
d'allocation**, un **SBOM** avec **politique de licences**, une **vérification
anti-fuite de secrets**, et une **CI complète** qui garde tout cela vert à
chaque commit.

## F1 — Tests mémoire FFI

- `native/src/api.rs` + test `session_lifecycle_does_not_leak_audio_state` :
  100 cycles complets « allouer une session → monter l'audio d'un client →
  démonter la session » (même chemin de teardown que `finalize_disconnect`).
  Vérifie qu'après le démontage il ne reste **aucun** artefact dans `SESSIONS`,
  `CLIENT_BUFFERS`, `AUDIO_DECODERS`, `AUDIO_DECODERS_STEREO`.
- Un vrai « connect/disconnect » exigeant un serveur n'est pas reproductible en
  test unitaire ; on exerce donc le **registre** (la partie du cycle de vie qui
  fuit si on oublie de nettoyer). Les id choisis (10 000 000+) ne collisionnent
  pas avec les autres tests parallèles.
- Résultat Rust : **26 tests OK** (un de plus que la phase 20).

## F6 — SBOM + licences

- CI (jobs `sbom` et `flutter-licenses`, `continue-on-error` pour ne pas
  bloquer un merge sur un signal qui bouge tout seul) :
  - **`cargo cyclonedx`** → SBOM CycloneDX (JSON) des dépendances Rust, uploadé
    en artefact.
  - **`cargo deny check licenses`** : autorise MIT/Apache-2.0/BSD/ISC/Zlib/
    Unlicense, **interdit** GPL/AGPL/LGPL — cohérent avec `PRIVATE_USE_NOTICE.md`
    et l'objectif « publication open source ».
  - **`flutter pub deps`** : recherche de copyleft (GPL/AGPL/LGPL/CC-BY-SA) dans
    l'arbre de dépendances Flutter.
- Des outils (cargo-audit, cargo-cyclonedx, cargo-deny) sont installés à la volée
  dans la CI ; les crates *vendored* (`local_tsclientlib`) sont inclus.

## B3 — Vérification anti-fuite

- `tools/check_secrets.py` : linter heuristique (exécuté en CI dans le job
  `secrets`). Il
  1. vérifie que les **couches de redaction existent** (`AppLog.redact` en Dart,
     `crate::redact` en Rust) ;
  2. signale toute ligne de log/notification qui **interpole une expression de
     type secret** (`$password`, `${identity}`, …) — la seule façon dont une
     *valeur* atteint une chaîne ; il ignore les simples descriptions
     (« identity saved to Keystore ») ;
  3. signale les sérialisation/notifications qui exposent un champ secret ;
  4. whitelist les fichiers où un secret doit légitimement franchir une frontière
     (`identity_backup`).
- Résultat : **aucune interpolation de secret trouvée** ; seul un log
  whitelisté de `identity.length` (la longueur, pas la valeur).
- Les fuites possibles aux points d'entrée étaient déjà couvertes : `Server.toJson`
  omet les mots de passe, `AppLog`/`redact` masquent hôtes/IP/secrets, les
  notifications n'embarquent que le nom du serveur.

## A3 — CI déjà complète, étendue

- Le workflow existait et se déclenche déjà sur **chaque** push/PR (pas seulement
  les tags) : `cargo fmt/check/clippy(-D warnings)/test`, `cargo audit`,
  `flutter pub get / gen-l10n / format / analyze / test`, build APK debug
  (et release + upload sur tags).
- Cette phase y ajoute les jobs `sbom`, `flutter-licenses` et `secrets`.

## Validation

- Rust : `cargo test --locked` **26 tests OK** ; `cargo clippy -p tsclient -D
  warnings` **0 erreur** ; `cargo fmt --check` **OK**.
- Dart : `flutter analyze` **0 problème** ; `flutter test` **107 tests OK**.
- Kotlin : `IdentityBackup.kt` compile avec `kotlinc`.
- `python3 tools/check_secrets.py` → **EXIT 0** (aucun candidat).
- `.github/workflows/ci.yml` : YAML ajouté.

## Notes / suite

- **F2/F3/F4/F5** (protocole, notifiers Flutter, tests Android instrumentés,
  réseau dégradé) restent à écrire — la plupart exigent un vrai serveur ou un
  appareil.
- **C4 FFI typée** : la sérialisation JSON du roster est le plus gros coût du
  pont ; la remplacer par des structures typées est le refactor le plus lourd
  restant (à faire après mesures sur appareil).
- **Build APK réel + test serveur réel** : toujours à faire sur machine ≥ 8 Go.
