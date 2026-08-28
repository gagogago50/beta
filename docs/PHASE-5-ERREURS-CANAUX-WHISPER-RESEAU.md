# Phase 5 — erreurs typées, canaux privés, whisper et réseau

## Erreurs TeamSpeak typées

Le moteur traite désormais les réponses `CommandError` qui n’étaient auparavant pas affichées.

Événement Rust :

```json
{
  "type": "command_error",
  "code": "PermissionsClientInsufficient",
  "message": "...",
  "missing_permission": "..."
}
```

Catégories interprétées côté application :

- mot de passe serveur/canal refusé ;
- permission insuffisante avec permission manquante ;
- limitation flood/rate limit ;
- canal supprimé ou introuvable ;
- erreur générique du serveur.

Les erreurs runtime sont maintenant affichées dans une Snackbar. Les erreurs de connexion continuent de revenir à l’écran principal.

## Déplacement vers un canal protégé

Le déplacement de canal transporte maintenant un mot de passe optionnel sur toute la chaîne :

```text
Dialogue Flutter
 → allocation FFI temporaire
 → ts_move_to_channel(id, password)
 → Command::MoveChannel
 → OutClientMovePart.channel_password
 → serveur
```

Pour un canal marqué `hasPassword`, l’application affiche un dialogue sécurisé et n’effectue plus de déplacement optimiste. Le canal courant est mis à jour uniquement à partir de l’état confirmé par le serveur.

## Whisper entrant

Les paquets `VoiceWhisper` étaient déjà décodés, mais impossibles à distinguer dans l’interface.

Ajouts :

- suivi monotone des clients qui whisperent ;
- champ Rust/Dart `isWhispering` ;
- expiration de l’indicateur ;
- indicateur violet pour whisper, bleu pour parole de canal ;
- test du parsing Dart.

La whitelist de whisper et l’émission whisper restent pour la phase suivante.

## Statistiques réseau

L’événement ReSpeak `NetworkStatsUpdated` alimente maintenant :

- RTT en millisecondes ;
- déviation RTT ;
- perte de paquets en pourcentage.

La barre de connexion affiche `RTT • perte`. La perte devient orange à partir de 5 %.

## Validation

- `cargo check --locked` : réussi ;
- code Rust formaté ;
- génération l10n : réussie ;
- format Dart : réussi ;
- tests Flutter : 2/2 ;
- analyse Flutter : aucune anomalie.

## Suite

1. whitelist de whisper par client et émission whisper ;
2. opérations groupes uniquement après vérification de permission ;
3. erreurs de connexion Rust structurées sans classification textuelle ;
4. historique séparé des conversations privées ;
5. build APK ARM64 avec NDK officiel, analyse du manifeste et des ELF.
