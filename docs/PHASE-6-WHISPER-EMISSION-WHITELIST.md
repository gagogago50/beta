# Phase 6 — émission whisper, liste blanche et outillage de build

## Émission whisper

Le moteur ne savait que **recevoir** des paquets `VoiceWhisper`. Le chemin d’émission est
maintenant implémenté de bout en bout, sur le modèle du client Windows officiel.

```text
WhisperPanel (Flutter)
 → TsNative.setWhisperTargets({clients, channels})
 → ts_set_whisper_targets(json)
 → STATE.whisper_target_clients / whisper_target_channels
 → boucle d’événements Rust : AudioData::C2SWhisper { id, codec, channels, clients, data }
 → serveur
```

Points de conception :

- **Compteur de paquets séparé.** TeamSpeak numérote indépendamment le flux voix et le flux
  whisper ; `whisper_seq` est distinct de `audio_seq`, sinon le récepteur voit des trous de
  séquence et le jitter buffer jette des trames.
- **Terminateur de flux.** Au basculement voix ↔ whisper, une trame de charge utile vide est
  émise sur le flux précédent. C’est ainsi que le client officiel signale « fin de parole » ;
  sans elle les autres clients gardent l’indicateur de parole jusqu’à leur propre timeout.
- **Assainissement des cibles** (`sanitize_whisper_targets`) : suppression des IDs invalides
  (0, hors plage u16) et de son propre ID, déduplication, tri déterministe, plafond de
  100 cibles par liste (les longueurs sont codées sur un octet dans le format de paquet).
- **Cibles jamais persistées.** Les IDs client/canal sont des poignées de session que le
  serveur réutilise ; elles sont remises à zéro à chaque `ts_connect` et purgées du côté Dart
  (`_pruneWhisperTargets`) dès qu’une cible disparaît du roster.
- **Armement sans coupure.** `ts_set_whisper_active` ne fait que changer la destination des
  trames : la parole n’est jamais interrompue, et l’armement est refusé s’il n’y a aucune cible.

## Liste blanche whisper entrante

Politique **locale** (aucune commande serveur), équivalente à la liste d’ignorance whisper du
client de bureau :

- `ts_set_whisper_allow_mode(0|1)` — 0 accepte tout (défaut TeamSpeak), 1 restreint ;
- `ts_set_whisper_allowlist(["uid", ...])` — clés par UID, donc stables d’une session à l’autre ;
- en mode 1, une trame whisper est rejetée **avant décodage Opus** : coût nul en CPU audio ;
- un client dont l’UID n’est pas encore connu est rejeté (accepter un émetteur non identifié
  viderait la liste de son sens) ;
- compteur de diagnostic `whisper_ignored_count` remonté à l’UI.

Le mode et la liste sont persistés en préférences (`whisper_allowlist_enabled`,
`whisper_allowed_uids`) et repoussés au moteur à chaque connexion.

## Interface

- Bouton whisper dans la barre de contrôle : appui court = armer/désarmer, appui long =
  panneau des cibles ; pastille violette avec le nombre de cibles ; icône violette quand armé.
- `WhisperPanel` : sélection des utilisateurs et des canaux, interrupteur de liste blanche,
  sélection des UID autorisés, compteur de whispers ignorés.
- Étape de visite guidée ajoutée pour le nouveau bouton.
- Chaînes ajoutées en anglais et en chinois, `flutter gen-l10n` régénéré.

## API FFI ajoutée

| Fonction | Rôle |
|---|---|
| `ts_set_whisper_targets(json) -> u8` | `{"clients":[u32],"channels":[u64]}` |
| `ts_set_whisper_active(u8) -> u8` | arme/désarme, 0 si aucune cible |
| `ts_set_whisper_allow_mode(u8) -> u8` | 0 = tout accepter, 1 = liste blanche |
| `ts_set_whisper_allowlist(json) -> u8` | tableau d’UID |
| `ts_get_whisper_status() -> *mut c_char` | état complet + `ignored_count` |

Toutes les chaînes retournées passent par `_ptrToString` côté Dart, donc sont libérées par
`ts_free_string`. Les chaînes d’entrée sont libérées dans un `finally`.

## Tests

- Rust (`native/src/api.rs`, premiers tests unitaires du dépôt) : tri/déduplication/filtrage
  des cibles, plafond à 100, liste vide acceptée.
- Dart : armement impossible sans cible, persistance de la liste blanche à travers un
  `copyWith` non lié.

## Validation

- `cargo check --locked` : réussi ;
- `cargo test --locked` : 3/3 ;
- `cargo fmt` : appliqué ;
- `flutter gen-l10n` : réussi ;
- `dart format .` : réussi ;
- `flutter analyze` : aucune anomalie ;
- `flutter test` : 4/4.

## Suite

1. Opérations de groupes conditionnées par vérification de permission, icônes de groupes.
2. Erreurs de connexion Rust structurées (sans classification textuelle).
3. Historique séparé et chiffré des conversations privées.
4. Reconnexion automatique avec restauration du canal.
5. Machine d’état de connexion explicite (Phase 3) et backoff avec jitter.
