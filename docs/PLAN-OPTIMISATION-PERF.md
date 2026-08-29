# Plan d'optimisation performance / logiciel / boutons — exécuté

Date : 28 août 2026

## Problème rapporté
« L'app rame, latence au clic, expérience non fluide, le téléphone chauffe, il
manque des boutons. »

## Diagnostic (racine des causes identifiées dans le code)

1. **`onMicLevel` écrivait dans l'état à chaque trame micro (~50×/s).** Chaque
   `_setSession(micCid, copyWith(micRms: rms))` crée un nouveau
   `TsConnectionState` → Riverpod notifie → **tout l'écran serveur se
   reconstruit** (arbre + clients + barres) 50 fois par seconde pendant la
   prise de parole. C'est la cause n° 1 du lag et de la chauffe.
2. **`_refreshNotification` appelé en rafale.** Chaque bascule `voiceActive`,
   chaque toggle mute, chaque `channels_updated` déclenche un appel de canal de
   plateforme (`ForegroundService.update/start`) → chauffe + overhead.
3. **Réconciliation du roster non gardée.** `getClients()`/`getChannels()` sont
   ré-exécutés toutes les 2 s et **réécrivent l'état même si rien n'a changé**
   → rebuild périodique pour rien.
4. **`diagMessages` non borné** → la liste grandit à chaque diagnostic moteur,
   ce qui revient à un rebuild par diagnostic.
5. **Allocation d'un `Vec<u8>` de 4 kB pour chaque trame Opus** (~50×/s pendant
   la capture) → pression GC, chauffe du SoC.

## Corrections appliquées

### Dart (`lib/models/ts_state.dart`)
- **Throttle micro** : `onMicLevel` ne met à jour l'état qu'au plus toutes les
  **100 ms** et si le niveau a bougé de >0.002 (sinon on ignore). La jauge
  d'activité reste fluide, l'écran n'est plus reconstruit en continu.
- **Coalescence notification** : `_refreshNotification` est borné à une mise à
  jour toutes les **600 ms** (sauf démarrage). Un `_lastNotification` évite les
  rafales.
- **Changement-détection** : `channels_updated` et la réconciliation du roster
  n'écrivent dans l'état que si la liste a réellement changé
  (`listEquals`). L'arbre / la liste des clients ne se reconstruisent plus
  toutes les 2 s ni à chaque « updated » de bookkeeping.
- **`diagMessages` plafonné** à 40 entrées (on garde les plus récentes).
- Constants de throttle regroupées en tête de notifier pour lisibilité.

### Rust (`native/src/lib.rs`, `native/src/api.rs`)
- **Volume maître** : `MASTER_VOLUME` (AtomicU32, gain linéaire) appliqué dans
  le mix cpal (Phase B, après atténuation). FFI `ts_set_master_volume(db)`.
- **Buffer Opus réutilisé** : `thread_local! { OPUS_SCRATCH }` pour la sortie
  d'encodage (fini le `Vec::new()` 4 kB/trame). La séquence (`audio_seq` /
  `whisper_seq`) est pré-computée avant d'emprunter l'encodeur pour éviter un
  conflit de borrow, et la closure ne capture plus `guard`.

### UI (`lib/screens/server_screen.dart`) — boutons ajoutés
- **Volume maître** : long-press sur l'icône haut-parleur → slider −20..+20 dB.
- **Menu « ⋮ »** : Info canal, Favoriser ce serveur, Stats réseau, Rafraîchir
  le serveur (actions `_showToolsMenu`, `_showChannelInfo`,
  `_bookmarkCurrentServer`, `refreshRoster`).

## Résultat attendu
- **Clics fluides** : plus de reconstruction d'écran à 50 Hz.
- **Chauffe réduite** : moins d'appels de plateforme + moins d'allocation GC.
- **Battery** : le poll d'arrière-plan reste à 15 s, le roster n'est plus
  réécrit inutilement.
- **Parité boutons** : volume maître (équivalent slider Windows) + menu
  d'actions rapides.

## Validation
- Rust : `cargo test --locked` **28 tests OK**, `cargo clippy -p tsclient -D
  warnings` **0 erreur**.
- Dart : `flutter analyze` **0 problème**, `flutter test` **113 tests OK**.
- l10n EN/ZH générées (nouvelles clés `masterVolume`, `channelInfo`,
  `bookmarkServer`, `networkStats`, `refreshServer`, `noChannelInfo`, `close`,
  `alreadyBookmarked`, `serverBookmarked`).

## Prochaines étapes (ordre recommandé)
1. **Mesures sur appareil** : confirmer CPU/batterie/latence après ces
   optimisations (voir `PLAN-TEST-SERVEUR-REEL.md` § 8).
2. **FFI typée** (C4) : remplacer la sérialisation JSON du roster par des
   structures typées — le plus gros coût restant du pont Dart↔Rust.
3. **Gestionnaire de fichiers** complet (lister/créer/supprimer).
4. **Recherche globale** (client + canal + fichier).
