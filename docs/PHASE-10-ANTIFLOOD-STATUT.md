# Phase 10 — anti-flood et statut utilisateur

Traite **C2** en entier et **E4.1/E4.2/E4.3** du plan `PLAN-C2-PARITE.md`.

## C2 — Budget de commandes (anti-flood)

Les serveurs TeamSpeak comptent des « points de flood » par client et kickent ou bannissent
au-delà d’un seuil. L’interface, elle, produit légitimement des rafales (un utilisateur qui
parcourt les canaux). Sans régulation, chaque nouvelle opération d’administration augmentait
le risque de bannissement — d’où ce chantier **avant** E1.

### Seau à jetons avec file d’attente

`CommandBudget` (`native/src/lib.rs`) :

| Paramètre | Valeur | Raison |
|---|---|---|
| Capacité (rafale) | 8 jetons | absorbe un enchaînement d’actions humaines |
| Réapprovisionnement | 3 jetons/s | volontairement sous le seuil par défaut d’un serveur |
| File maximale | 32 | au-delà, c’est un bug d’UI, pas une intention |
| Mode dégradé | 2 jetons, 0,5/s, 30 s | après un `ClientIsFlooding` du serveur |

Coûts : message texte 2,0 · renommage 2,0 · déplacement de canal 1,5 · mute/absent/commander
0,5. **Audio et déconnexion sont gratuits et contournent le budget** : l’audio n’est pas une
commande de contrôle, et une déconnexion ne doit jamais être retardée.

### File plutôt que rejet

Les commandes ne sont pas jetées mais **différées**, pour que la dernière intention de
l’utilisateur atteigne toujours le serveur. Les commandes d’état se remplacent entre elles
(`supersedes`) : 50 déplacements de canal en rafale ne produisent qu’un seul message, celui
du dernier canal choisi. Les messages texte, eux, ne sont jamais fusionnés — ce serait perdre
du contenu utilisateur.

### Réaction au serveur

À la réception d’un `ClientIsFlooding` / `BanFlooding`, le budget passe immédiatement en mode
dégradé (jetons remis à zéro) et se rétablit tout seul après 30 s. Le budget est aussi remis
à neuf à chaque `ts_connect` : la file et l’éventuel mode dégradé appartenaient à la session
précédente.

### Retour visible

Événement `command_throttled { pending, degraded }`, au plus une fois par seconde (un
backlog ne doit pas inonder la file d’événements). L’UI affiche un sablier dans la barre de
connexion — orange en mode dégradé — au lieu de paraître figée. Ce n’est **jamais** présenté
comme une erreur.

## E4 — Statut utilisateur

Trois commandes `clientupdate` exposées, toutes passant par le budget anti-flood :

- **E4.1 Absent/AFK** — `ts_set_away(away, message)`. Désactiver le statut efface aussi le
  message côté serveur, sinon un ancien « de retour dans 5 min » reste collé au client.
- **E4.2 Pseudo en session** — `ts_set_nickname(name)`, validé localement (3 à 30 caractères)
  pour répondre immédiatement, le serveur pouvant encore refuser avec `ClientNicknameInuse`
  (déjà typé en phase 7).
- **E4.3 Channel commander** — `ts_set_channel_commander(enabled)`, la permission étant
  vérifiée par le serveur qui répond par un `command_error` typé.
- **E4.4 UI** — feuille « Mon statut » (bouton dans la barre de contrôle, icône ambre quand
  absent) : pseudo, absence + message, channel commander.

### Défaut corrigé au passage

Le test « effacer l’absence efface le motif » a mis en évidence que `copyWith` ne pouvait pas
remettre `awayMessage` à `null` (`valeur ?? this.valeur` conserve l’ancienne) : l’UI aurait
continué d’afficher un motif effacé côté serveur. Corrigé avec le motif sentinelle déjà
utilisé pour `selectedChannelId` et `reconnectAt`.

## Tests

- Rust (+7, **15 au total**) : rafale puis lissage, réapprovisionnement dans le temps et
  plafond de capacité, fusion des déplacements de canal successifs, file bornée avec
  comptage des pertes, mode dégradé puis rétablissement, gratuité audio/déconnexion,
  indépendance des mises à jour de statut entre elles.
- Dart (+2, **31 au total**) : le throttling n’est pas une erreur (connexion toujours
  active, `error` nul), effacement conjoint absence + motif.

## Validation

`cargo fmt` · `cargo check --locked` · `cargo clippy -p tsclient -- -D warnings` : 0 ·
`cargo test` **15/15** · `dart format --set-exit-if-changed` · `flutter analyze` : 0 ·
`flutter test` **31/31**.

## Suite immédiate (plan `PLAN-C2-PARITE.md`)

- **E1** — opérations conditionnées par les permissions (kick/ban/poke/déplacer), désormais
  sûres à ajouter puisque le débit est maîtrisé ;
- **E4.5** — tests de longueur de pseudo au niveau FFI (nécessite un harnais FFI) ;
- **E7 → E3** — transfert de fichiers puis icônes de groupes ;
- **E5 → E6** — historique chiffré puis fils de conversation séparés ;
- **E8** — multi-serveurs, en dernier.
