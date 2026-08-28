# Phase 14 — historique de chat chiffré (E5)

## Principes

Trois règles ont guidé cette fonctionnalité, dans cet ordre :

1. **Désactivé par défaut.** Un client vocal qui enregistre silencieusement toutes les
   conversations privées est un risque, pas une fonctionnalité. L’activation est un choix
   explicite dans Réglages → Confidentialité.
2. **Chiffré au repos.** Le contenu passe par la clé Android Keystore qui protège déjà
   l’identité TeamSpeak. Du JSON en clair dans le stockage applicatif serait lisible par
   n’importe quel chemin de sauvegarde.
3. **Borné.** Rétention en jours **et** plafond d’entrées : un serveur actif ne doit pas
   faire grossir le fichier indéfiniment.

## Stockage Keystore par fichier

`SharedPreferences` est le mauvais support pour un historique : il est chargé entièrement en
mémoire et réécrit à chaque modification. `SecureStorage.kt` gagne donc un chemin **fichier** :

- même clé Keystore, même discipline d’AAD — **le nom du fichier authentifie le chiffré**,
  donc un fichier renommé ne se déchiffre pas ;
- écriture d’abord dans un `.tmp` puis `rename` : un processus tué en pleine écriture ne
  laisse pas un historique indéchiffrable ;
- déchiffrement en échec (fichier altéré, tronqué, ou clé disparue après restauration sur un
  autre appareil) → le fichier est supprimé et traité comme absent ;
- noms validés côté Kotlin : jamais un chemin, uniquement des caractères sûrs, pas de `..` ;
- `deleteAllFiles()` pour la commande « effacer identité et secrets ».

## Service Dart

`ChatHistoryService` : **un fichier par serveur** (les historiques ne doivent pas fuir d’un
serveur à l’autre, et un fichier unique devrait être réécrit en entier à chaque message),
nommé à partir du `server_uid` stable introduit en phase 13.

- `prune()` est une fonction **pure** — rétention + plafond de 500 messages, les plus récents
  conservés — donc testable sans canal de plateforme ;
- décodage tolérant : une entrée sans horodatage exploitable est ignorée, un fichier corrompu
  donne un historique vide plutôt qu’un plantage ;
- écriture **débouncée à 3 s** : sans cela, un canal actif re-chiffrerait toute la
  conversation à chaque message reçu.

## Intégration

- Restauration à la connexion, insérée **avant** les messages reçus depuis ;
- vidage forcé à la déconnexion, **avant** la remise à zéro de l’état, sinon les derniers
  messages de la session sont perdus ;
- la remise à zéro conserve la préférence et la rétention (le reste de l’état est effacé) ;
- désactiver la fonctionnalité **supprime aussi** ce qui était déjà stocké : laisser une
  archive derrière soi viderait l’interrupteur de son sens ;
- changer la rétention pour une fenêtre plus courte est appliqué immédiatement ;
- « effacer identité et secrets » (phase 9) purge désormais aussi les conversations.

## Interface

Réglages → Confidentialité : interrupteur, choix de rétention (7 / 30 / 90 jours) et
suppression manuelle des conversations stockées.

## Tests

Dart (+10, **58 au total**) : fenêtre de rétention (longue et courte), plafond d’entrées avec
conservation des plus récentes, valeur de rétention inconnue repliée sur 30 jours,
aller-retour de sérialisation, données corrompues sans plantage, entrées sans horodatage
ignorées, nommage de fichier sûr pour la plateforme, unicité par serveur, UID vide.

Kotlin : `SecureStorage.kt`, `VoiceAudioController.kt` et `ConnectivityStreamHandler.kt`
compilent avec `kotlinc` contre `android.jar` (API 35) et `flutter.jar`.

## Validation

`dart format --set-exit-if-changed` · `flutter analyze` 0 · `flutter test` **58/58** ·
`kotlinc` sans erreur · Rust inchangé (**21/21**).

## Suite

- **E6** — fils de conversation séparés (canal / serveur / privé par UID), qui s’appuiera sur
  ce stockage ;
- **E7.3** — avatars ;
- **E8** — multi-serveurs ;
- **A1/A2** — build APK et essai sur serveur réel, toujours hors de portée de la sandbox.
