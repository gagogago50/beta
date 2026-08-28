# Plan TODO — anti-flood et parité fonctionnelle

Découpage exécutable de **C2**, **E1/E3/E4** et **E5–E8** de `RESTE-A-FAIRE.md`.
Chaque tâche indique les fichiers touchés, le critère d’acceptation et la vérification.

Convention d’état : `[ ]` à faire · `[~]` en cours · `[x]` fait.

---

## C2 — Limitation de fréquence des commandes (anti-flood) — ✅ **phase 10**

Pourquoi d’abord : sans elle, chaque nouvelle opération d’administration (E1) multiplie le
risque de faire kicker ou bannir l’utilisateur. TeamSpeak applique un compteur de flood
par client (`FloodPoints`), et dépasser le seuil coûte un `ClientBanned`/kick automatique.

- [x] **C2.1 — Budget de commandes côté Rust.** Seau à jetons dans `native/src/lib.rs`
      (`CommandBudget`) : capacité et réapprovisionnement paramétrables, coût par type de
      commande (texte > déplacement > mise à jour de statut).
      *Acceptation* : jamais plus de N commandes par fenêtre glissante, quel que soit le
      rythme d’appel côté Dart.
- [x] **C2.2 — File d’attente plutôt que rejet.** Les commandes dépassant le budget sont
      mises en file et rejouées quand des jetons se libèrent ; la file a une taille maximale
      et déduplique les commandes idempotentes (deux déplacements vers le même canal =
      un seul).
      *Acceptation* : une rafale de 50 déplacements de canal ne produit qu’un seul message
      réseau final, sans perte de la dernière intention.
- [x] **C2.3 — Retour visible.** Événement `command_throttled { pending }` pour que l’UI
      indique une action différée au lieu de paraître figée.
- [x] **C2.4 — Réaction au flood serveur.** À la réception d’un `CommandError` de type
      flood/rate-limit, réduire temporairement le budget (mode dégradé) et le restaurer
      progressivement.
- [x] **C2.5 — Tests Rust.** Consommation/réapprovisionnement du seau, plafond de file,
      déduplication, mode dégradé après flood.

## E4 — Statut utilisateur — ✅ **phase 10** (E4.5 restant)

Aucune commande `clientupdate` n’est exposée aujourd’hui hors mute.

- [x] **E4.1 — Absent/AFK avec message.** `ts_set_away(bool, message)` →
      `OutClientUpdatePart { is_away, away_message }` ; affichage dans la liste des clients
      (l’indicateur `away` est déjà parsé côté Dart).
- [x] **E4.2 — Changement de pseudo en session.** `ts_set_nickname(name)`, avec gestion de
      l’erreur `ClientNicknameInuse` (déjà classifiée en phase 7).
- [x] **E4.3 — Channel commander et talk power.** Champs `is_channel_commander` /
      `is_talker`, exposés en lecture puis en écriture si la permission le permet.
- [x] **E4.4 — UI.** Feuille « mon statut » (pseudo, AFK + message, commander) accessible
      depuis la barre de connexion.
- [ ] **E4.5 — Tests.** Sérialisation des mises à jour, refus lorsque déconnecté, longueur
      maximale du pseudo (30 octets côté serveur).

## E1 — Opérations conditionnées par les permissions — ✅ **phase 11** (E1.5 à valider sur serveur réel)

- [x] **E1.1 — Lire les permissions effectives.** Requête `permget`/cache par client, exposé
      en `ts_get_permissions()`.
- [x] **E1.2 — Modèle Dart de permissions** avec accès typé (`canKick`, `canBan`,
      `canMoveOthers`, `canPoke`…), défaut « refusé » tant que la réponse n’est pas arrivée.
- [x] **E1.3 — Commandes.** Kick canal/serveur (avec motif), ban (durée + motif), poke,
      déplacer un autre client, mute serveur.
- [x] **E1.4 — UI.** Les entrées du menu contextuel client n’apparaissent **que** si la
      permission est accordée ; sinon absentes, jamais grisées sans explication.
- [ ] **E1.5 — Tests.** Mapping permission → action, absence d’action sans permission,
      erreurs serveur `PermissionsClientInsufficient` déjà typées remontées à l’UI.

## E3 — Icônes et badges de groupes — ✅ **phases 12-13** (avatars restants, cf. E7.3)

- [x] **E3.1 — `icon_id` des groupes** exposé par le moteur (déjà présent dans le book).
- [x] **E3.2 — Téléchargement via file transfer** (voir E7) et cache disque par
      `serverUid/iconId`, avec purge et taille maximale.
- [x] **E3.3 — Rendu** dans `client_list` et le panneau client, avec repli sur le nom de
      groupe quand l’icône manque.
- [x] **E3.4 — Tests.** Nommage/validation du cache, repli, refus d’un fichier trop gros.

## E5 — Historique de chat chiffré — ✅ **phase 14**

- [x] **E5.1 — Stockage.** Table locale (fichier JSON chiffré via la clé Keystore existante,
      ou SQLite chiffré) — décision à documenter avant implémentation.
- [x] **E5.2 — Opt-in explicite** : désactivé par défaut, avec purge manuelle et rétention
      configurable (7/30/90 jours).
- [x] **E5.3 — Intégration** : rechargement à la connexion, pas de fuite dans les
      sauvegardes (`data_extraction_rules` déjà en place).
- [x] **E5.4 — Tests.** Chiffrement/déchiffrement, rétention, purge, migration d’un
      historique absent.

## E6 — Conversations privées séparées — ✅ **phase 16**

- [x] **E6.1 — Modèle de fils** (`canal`, `serveur`, `client:<uid>`) au lieu d’une liste
      unique de messages.
- [x] **E6.2 — UI à onglets** avec badges non lus par fil.
- [x] **E6.3 — Persistance** branchée sur E5.
- [x] **E6.4 — Tests.** Routage d’un message entrant vers le bon fil, comptage des non lus.

## E7 — Transfert de fichiers et avatars — ✅ **phase 12** (téléchargement ; envoi et progression restants)

- [x] **E7.1 — Protocole.** `ftinitdownload`/`ftinitupload`, clé de transfert, connexion TCP
      dédiée côté Rust (le protocole voix reste en UDP).
- [~] **E7.2 — API FFI.** Démarrage/annulation/progression d’un transfert.
- [x] **E7.3 — Avatars** (`/avatar_<uid>`) et icônes (E3) comme premiers consommateurs.
- [x] **E7.4 — Sécurité.** Taille maximale, validation du type, écriture hors du répertoire
      public, jamais d’exécution.
- [x] **E7.5 — Tests.** Parsing des réponses, annulation, dépassement de taille.

## E8 — Multi-serveurs — **phase 17** (refonte)

- [ ] **E8.1 — Supprimer l’état global.** `STATE`/`COMMAND_TX`/`CLIENT_BUFFERS` deviennent
      une table de sessions indexée par `connection_id` ; toutes les fonctions FFI prennent
      ce handle.
- [ ] **E8.2 — Mixage multi-sessions** dans le flux cpal unique.
- [ ] **E8.3 — Riverpod par session** (famille de providers) et onglets de serveurs.
- [ ] **E8.4 — Service de fond** : notification agrégée, déconnexion sélective.
- [ ] **E8.5 — Tests.** Isolation des sessions, absence de fuite entre deux connexions,
      100 cycles connexion/déconnexion multi-sessions.

---

## Ordre et dépendances

```text
C2 (anti-flood)  ─────────────► E1 (opérations admin)
                                   │
E4 (statut) ───────────────────────┤
                                   ▼
E7 (file transfer) ──► E3 (icônes/avatars)

E5 (historique chiffré) ──► E6 (fils privés)

E8 (multi-serveurs) : à faire en dernier, il touche tout le reste
```

Règle de travail : chaque phase se termine par `cargo fmt/clippy/test`,
`dart format/analyze/test`, `kotlinc` si du Kotlin a bougé, et un document
`docs/PHASE-N-*.md`.
