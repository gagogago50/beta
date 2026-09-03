# Phase 25 — Recherche globale (canaux + clients + fichiers)

> Objectif : donner à l'app la recherche unifiée du client desktop — un seul champ qui
> retrouve un canal, un utilisateur ou un fichier et permet d'agir directement dessus.
> La recherche est purement côté Dart (aucun changement moteur) ; la logique de filtrage
> est isolée dans un modèle testable.

## Logique du client legacy (sources `ts3-remote`)
- Le client Windows/Android propose une recherche de canaux et d'utilisateurs (l'index
  `C3516f`/`C3528l` et le roster `C3524j`) et une liste de fichiers par canal.
- Le résultat affiche le **chemin** du canal (Parent › Enfant) pour lever l'ambiguïté entre
  deux canaux de même nom, et permet de **rejoindre** directement le canal trouvé.

## Ce qui a été implémenté

### `lib/models/server_search.dart` (modèle testable)
- `ServerSearchHits { channels, clients, files }` + `isEmpty`.
- `searchServer(query, channels:, clients:, files:)` : filtre insensible à la casse par
  sous-chaîne sur le nom ; requête vide ⇒ aucun résultat.
- `channelPath(channels, channelId)` : construit `Parent › Enfant › …` (racine en premier).

### `lib/screens/server_screen.dart`
- Bouton `Icons.search` dans l'en-tête « Channels » → ouvre `_GlobalSearchSheet`.
- `_GlobalSearchSheet` (`ConsumerStatefulWidget`) : un champ unique filtre canaux,
  utilisateurs et fichiers ; la liste est groupée par section avec un sous-titre de chemin
  pour les canaux/clients.
  - Canal → `notifier.selectChannel(id)`.
  - Utilisateur → popover de volume (même comportement que le roster).
  - Fichier répertoire → ouvre le navigateur de fichiers à ce chemin ; fichier → no-op.
  - Aucun résultat → message « No results ».

### Tests
- `test/server_search_test.dart` : `searchServer` (vide, insensible à la casse, aucun match)
  et `channelPath` (imbriqué, racine, 0/inconnu).

## Validation
- `flutter analyze` : 0 erreur.
- `dart format --set-exit-if-changed` : propre (aligné sur le runner Flutter 3.47).
- `flutter test` : 140 tests (dont les nouveaux).
- CI : à valider (les jobs Rust passent — aucune modification moteur).

## État
- **Fait** : recherche globale canaux/utilisateurs/fichiers + actions.
- **Reste** : TSDNS multi-endpoints + `androidId`, refactor JNI direct PCM 16 bits (D4),
  `ftgetfileinfo`/`ftrenamefile`, validation appareil.
