# Phase 11 — opérations d’administration conditionnées par les permissions (E1)

## Comment savoir ce qui est permis

TeamSpeak n’envoie pas la table de permissions au client : il envoie
`notifyclientpermhints`, un **masque de bits par client cible**, qui dit exactement ce que
*nous* avons le droit de lui faire. C’est le mécanisme qu’utilise le client de bureau pour
construire son menu contextuel, et c’est celui retenu ici — plutôt qu’un `permissionlist`
complet (des centaines d’entrées à résoudre par nom, dépendantes de la version du serveur).

| Bit | Action |
|---|---|
| 1 | kick serveur |
| 2 | kick canal |
| 4 | bannir |
| 8 | déplacer |
| 16 | message privé |
| 32 | poke |
| 64 | whisper |
| 128 | plainte |
| 256 | modifier les permissions |

Le moteur stocke le masque par client (`STATE.permission_hints`) et le sérialise dans chaque
`TsClient` (`permission_hints`). Côté Dart, `ClientPermissions` décode chaque bit en getter
typé. **Rien n’est accordé par défaut** : sans hint reçu, tout est refusé — supposer l’inverse
afficherait des actions qui échouent une seconde plus tard.

## Commandes ajoutées

| FFI | Message TeamSpeak | Garde-fous |
|---|---|---|
| `ts_kick_client(id, from_server, reason)` | `clientkick` avec `Reason::KickChannel/KickServer` | refus si cible = soi-même, motif tronqué à 200 caractères |
| `ts_ban_client(id, seconds, reason)` | `banclient` (`seconds = 0` → permanent) | idem |
| `ts_poke_client(id, message)` | `clientpoke` | message vide refusé |
| `ts_move_client(id, channel, password)` | `clientmove` | réutilise le chemin de mot de passe de canal déjà en place |

Toutes passent par le budget anti-flood de la phase 10 (coût 2,0, jamais fusionnées entre
elles : deux kicks visent deux personnes différentes, les confondre en épargnerait une).

## Interface

- Appui long sur un client → feuille de modération, **construite uniquement** avec les
  actions autorisées ; aucune entrée grisée sans explication, et pas de menu du tout si
  aucune action n’est permise (un chevron discret signale les clients « actionnables »).
- Kick : dialogue de motif facultatif. Ban : durée (1 h / 1 jour / 1 semaine / permanent —
  **permanent en dernier, jamais par défaut**) plus motif.
- Un refus tardif du serveur (les hints peuvent dater d’avant un changement de groupe)
  revient en `command_error` typé, déjà affiché depuis la phase 5.

## Détails d’implémentation

- `OutBanClientPart::time` attend un `time::Duration` (crate `time`), pas
  `std::time::Duration` : `time = "0.3"` est désormais une dépendance directe, alignée sur la
  version que tsclientlib expose déjà.
- `Reason` est réexporté à la racine de `tsclientlib`, pas sous `messages`.

## Tests

- Rust (+1, **16 au total**) : les commandes de modération ne sont jamais fusionnées par le
  budget.
- Dart (+8, **39 au total**) : refus par défaut, décodage indépendant de chaque bit,
  combinaison de drapeaux, `hasAnyModeration` ignore les droits non-modération (écrire ou
  whisperer n’ouvre pas le menu), bits futurs inconnus sans effet, lecture depuis le snapshot
  moteur, conservation par `copyWith`.

## Validation

`cargo fmt` · `cargo check` · `cargo clippy -p tsclient -- -D warnings` (exit 0) ·
`cargo test` **16/16** · `dart format --set-exit-if-changed` · `flutter analyze` 0 ·
`flutter test` **39/39**.

## Reste sur E1

- `E1.5` — vérifier sur un vrai serveur que les hints arrivent bien pour tous les clients du
  canal (le serveur ne les envoie que pour les clients visibles) ;
- déplacer vers un canal *arbitraire* (aujourd’hui : vers le canal courant) ;
- mute serveur d’un client, plainte, et opérations sur les groupes (dépendent de E3/E7).
