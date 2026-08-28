# Phase 12 — transfert de fichiers (E7) et cache d’icônes (E3.1/E3.2)

## E7 — Chemin de téléchargement TeamSpeak

Le protocole TeamSpeak sépare commandes et fichiers : les commandes voyagent sur la
connexion UDP chiffrée, les fichiers sur une **connexion TCP dédiée**, ouverte à la demande
avec une clé à usage unique.

```text
ts_download_file(cid, "/icon_1234", target, max)
 → Command::DownloadFile (budget anti-flood, coût 1,0)
 → ftinitdownload { clientftfid, name, cid, cpw, seekpos=0, proto=0 }
 ← notifystartdownload { clientftfid, ftkey, port, size, ip? }
 → TCP vers ip|hôte:port, envoi de ftkey, lecture de `size` octets
 → événement file_transfer { transfer_id, local_path, bytes, ok, error }
```

### Décisions de conception

- **Le transfert ne touche jamais la boucle d’événements.** Il est exécuté dans une tâche
  tokio séparée : un serveur lent ne doit pas figer la voix.
- **Mise en tampon mémoire puis écriture unique.** Un fichier tronqué sur disque serait
  ensuite servi par le cache comme s’il était valide ; en cas d’échec, aucun fichier n’est
  laissé derrière (et un éventuel reliquat est supprimé).
- **Deux plafonds, pas un.** La taille annoncée par le serveur est vérifiée *avant* la
  connexion, et le flux réel est recompté pendant la lecture : la taille annoncée n’est
  qu’une affirmation.
- **Plafond dur de 8 Mio** dans le moteur, au-dessus de la limite demandée par l’appelant.
- **Chemin cible validé** : refus des chemins relatifs et de tout `..`. Le chemin vient
  d’Android (`cacheDir`), Dart ne le fabrique pas à la main.
- **Réponse non sollicitée ignorée** : un `notifystartdownload` sans entrée correspondante
  dans `PENDING_TRANSFERS` n’ouvre aucune socket.
- **Repli d’adresse** : si le serveur ne fixe pas d’IP, l’hôte de la connexion courante
  (`SERVER_HOST`, mémorisé à `ts_connect`) est résolu.
- Délais : 10 s pour la connexion, 30 s d’inactivité en lecture.

### API

| FFI | Rôle |
|---|---|
| `ts_download_file(cid, remote, cpw, target, max) -> u32` | démarre, renvoie l’id de transfert ou 0 |
| `ts_cancel_file_transfer(id) -> u8` | oublie un transfert non encore démarré |

## E3.1/E3.2 — Cache d’icônes

`IconCache` (Dart) : téléchargement de `/icon_<id>` dans le canal 0, cache disque dans le
répertoire privé fourni par Android (`cache_dir` sur le canal `…/audio`), clé
`serverUid_iconId` — les identifiants d’icônes ne sont uniques qu’à l’intérieur d’un serveur
virtuel.

- plafond **512 Kio** par icône (les vraies font quelques dizaines de Kio) ;
- expiration à 30 jours, purge au démarrage de session ;
- **coalescence** : deux demandes simultanées de la même icône ne produisent qu’un transfert ;
- **échecs mémorisés pour la session** : une icône refusée n’est pas redemandée à chaque
  rafraîchissement du roster (le serveur limiterait le port de transfert) ;
- `reset()` à chaque connexion : un autre serveur a d’autres icônes et d’autres permissions ;
- l’identifiant d’icône TeamSpeak est un u32 non signé : la conversion depuis l’entier signé
  Dart est explicite.

## Tests

- Rust (+4, **20 au total**) : refus des chemins avec `..` et des chemins relatifs, refus
  d’une limite nulle ou supérieure au plafond dur, annulation d’un transfert inconnu sans
  effet, annulation d’un transfert en attente qui l’oublie réellement (la réponse tardive du
  serveur sera ignorée).
- Dart (+5, **44 au total**) : plafond d’icône très en deçà de la limite moteur, durée de
  cache bornée, `reset()` sans état en cours, événements de transfert inconnus ignorés.

## Validation

`cargo fmt` · `cargo check --locked` · `cargo clippy -p tsclient -- -D warnings` (exit 0) ·
`cargo test` **20/20** · `dart format --set-exit-if-changed` · `flutter analyze` 0 ·
`flutter test` **44/44**.

L’ajout Kotlin est une seule ligne (`cacheDir.absolutePath` exposé sur le canal audio) ;
`MainActivity` complet reste vérifiable uniquement par le job Gradle de la CI.

## Reste sur E3/E7

- **E3.3** — afficher les icônes : il faut d’abord exposer `icon_id` des groupes de canal et
  de serveur dans `TsClient` (le livre les contient déjà), puis remplacer le nom de groupe
  par l’icône avec repli texte.
- **E7.3** — avatars (`/avatar_<uid>`), même chemin que les icônes.
- **E7.2** — progression des transferts (aujourd’hui : résultat final seulement) et envoi
  (`ftinitupload`), utiles seulement quand un cas d’usage le demandera.
