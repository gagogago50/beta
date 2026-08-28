# Phase 13 — affichage des icônes de groupes (E3.3)

Complète la phase 12 : le cache existait, il lui manquait la source des identifiants et le
rendu.

## Identifiants exposés par le moteur

Le livre TeamSpeak contient déjà `icon` sur `ServerGroup` et `ChannelGroup`. `TsClient`
expose désormais :

- `channel_group_icon_id` (0 = pas d’icône) ;
- `server_group_icon_ids`, **aligné par index** avec `server_group_names`.

L’alignement est le seul point délicat : les noms étaient déjà triés alphabétiquement avant
sérialisation, les icônes devaient donc l’être **selon la même clé**, sinon l’interface
associerait l’icône d’un groupe au nom d’un autre. Les deux listes sont maintenant dérivées
d’un unique vecteur `(nom, icône)` trié une fois — et un test verrouille cette invariante.

## Identité de serveur stable

Le cache d’icônes est indexé par serveur, mais un nom de serveur change. `TsEvent::Connected`
porte désormais `server_uid` : le base64 du hachage de la clé publique du serveur, la seule
identité qui survit à un renommage. Elle est stockée dans l’état Riverpod et transmise à la
liste des clients.

## Rendu

`GroupIcon` : widget de décoration, jamais bloquant.

- pendant le transfert, et définitivement si le serveur refuse l’icône, il affiche le
  **repli** (le nom du groupe) — ni indicateur de chargement, ni image cassée ;
- `errorBuilder` couvre le fichier corrompu ou tronqué : une liste ne doit pas lever
  d’exception à cause d’une icône ;
- le rechargement n’est déclenché que si l’identifiant d’icône change réellement, alors que
  le roster reconstruit la liste toutes les deux secondes ;
- au plus trois icônes par client, suivies des noms de groupes : l’icône seule est illisible
  pour qui ne connaît pas l’iconographie du serveur.

## Tests

- Rust (+1, **21 au total**) : l’alignement noms/icônes après tri (`Admin, Guest, Moderator`
  ↔ `10, 0, 20`).
- Dart (+4, **48 au total**) : parsing des deux sources d’icônes, `0` ignoré (jamais demandé
  au serveur), icône du groupe de canal en premier, conservation par `copyWith`.

## Validation

`cargo fmt` · `cargo check --locked` · `cargo clippy -p tsclient -- -D warnings` (exit 0) ·
`cargo test` **21/21** · `dart format --set-exit-if-changed` · `flutter analyze` 0 ·
`flutter test` **48/48**.

## Suite

- **E7.3** — avatars (`/avatar_<uid>`) : même chemin de transfert, à brancher sur la feuille
  client ;
- **E5** — historique de chat chiffré, puis **E6** — fils de conversation séparés ;
- **E8** — multi-serveurs, en dernier ;
- rappel : **A1/A2** (build APK et essai sur serveur réel) restent hors de portée de cette
  sandbox et conditionnent la validation de tout ce qui précède.
