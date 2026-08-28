# Phase 16 — fils de conversation (E6) et avatars (E7.3)

## E6 — Fils canal / serveur / privé

Jusqu’ici une seule liste mélangeait tout : une réponse privée ressemblait à un message de
canal, et rien n’indiquait *quelle* conversation avait du nouveau.

### Clé de fil

`targetmode` seul ne suffit pas : deux conversations privées avec deux personnes partagent
`targetmode = 1`. La clé est donc `channel`, `server`, ou `client:<id du pair>`.

**Le point délicat est le pair d’un message sortant.** Un message que l’on envoie a
`fromClientId = notre id` : classé tel quel, il atterrissait dans un fil « nous-même », et la
conversation se retrouvait coupée en deux. `ChatMessage` porte donc `peerId` (et `peerName`,
capturé à la création car un client peut se déconnecter et disparaître du roster) :

- message privé **entrant** → le pair est l’expéditeur ;
- message privé **sortant** → le pair est le destinataire ;
- message d’un historique ancien sans pair → repli sur l’expéditeur, ce qui reste correct
  pour tout ce qui a été reçu.

### Compteurs de non-lus

Par fil, dans l’état. Deux règles : nos propres messages ne comptent jamais, et le fil
actuellement ouvert à l’écran ne compte pas non plus. La barre de chat affiche le total, les
onglets affichent leur propre badge, et ouvrir un onglet remet son compteur à zéro.

### Interface

Onglets défilants en haut de la feuille de chat, canal et serveur **épinglés en tête** (leur
position ne doit pas bouger sous le doigt), fils privés triés par activité récente. Le champ
de saisie rappelle la destination dans son indice — c’est ce qui évite d’envoyer une réponse
privée à tout le canal. L’envoi utilise l’onglet actif : privé, serveur ou canal.

Si un pair se déconnecte et que son fil disparaît, l’affichage retombe sur le canal au lieu
de montrer un écran vide.

Nouvelle entrée « envoyer un message privé » dans la feuille client, affichée quand la
permission `PrivateMessage` est accordée — la feuille s’ouvre désormais aussi pour un client
sur lequel on n’a *aucun* pouvoir de modération mais à qui on peut écrire.

### Persistance

`peer` et `peer_name` sont sérialisés dans l’historique chiffré de la phase 14 (absents pour
les messages de canal), donc les fils privés se reconstituent correctement après un
redémarrage.

## E7.3 — Avatars

Même chemin de transfert que les icônes : `/avatar_<uid client>` dans le canal 0.

- plafond propre de **1 Mio** (les avatars sont fournis par les utilisateurs, contrairement
  aux icônes de quelques dizaines de kio) ;
- cache par `serveur + uid client`, expiration commune de 30 jours ;
- **l’absence d’avatar est le cas normal**, pas une erreur : elle est mémorisée pour la
  session afin que le roster ne redemande pas à chaque rafraîchissement ;
- affichage dans la feuille client, avec repli sur l’icône micro/personne et `errorBuilder`
  pour un fichier corrompu.

## Tests

Dart (+16, **81 au total**) :

- routage des fils : canal, serveur, entrant, **sortant classé chez le destinataire**,
  message ancien sans pair, deux pairs jamais confondus, extraction de l’id de pair ;
- regroupement : canal et serveur toujours présents même vides, fils privés triés par
  activité, titre repris du nom du pair, compteurs de non-lus attachés au bon fil, ordre des
  messages préservé ;
- persistance : le pair survit à un aller-retour de chiffrement, aucun champ `peer` pour un
  message de canal ;
- avatars : plafond distinct et borné, uid vide sans transfert, `reset()` sans état.

## Validation

`dart format --set-exit-if-changed` · `flutter analyze` 0 · `flutter test` **81/81** ·
Rust inchangé (**21/21**).

## Suite

- **E8 — multi-serveurs** : dernier gros chantier, il touche tout (état global Rust →
  sessions indexées, mixage multi-sessions, providers Riverpod par session, notification
  agrégée) ;
- **A1/A2** — build APK et essai sur serveur réel, toujours hors sandbox.
