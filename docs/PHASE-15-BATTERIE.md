# Phase 15 — audit et optimisation de la consommation batterie

Objectif : réduire la consommation **sans retirer une seule fonctionnalité**. Aucune
capacité n’a été supprimée ni dégradée ; seules des cadences et des réveils inutiles l’ont
été.

## Audit — ce qui consommait

| # | Source | Coût observé dans le code |
|---|---|---|
| 1 | Boucle de capture micro Kotlin | `READ_NON_BLOCKING` + `Thread.sleep(10)` → **~100 réveils/s même en silence**, plus une `FloatArray(960)` et un `ByteBuffer` alloués **par trame** (~200 ko/s de déchets) |
| 2 | Polling Dart | 50 ms dès que le micro est actif, **y compris application en arrière-plan**, alors que la cadence rapide ne sert qu’à l’indicateur visuel de parole |
| 3 | Réconciliation du roster | sérialisation JSON de tous les clients **toutes les 2 s en permanence**, y compris quand rien n’est affiché |
| 4 | Tâche de maintenance Rust | tick fixe à 500 ms, y compris dans un canal totalement silencieux |
| 5 | `PARTIAL_WAKE_LOCK` | pris à la création du service et **jamais relâché**, même en sourdine totale pendant des heures |

## Corrections

### 1. Capture micro : lecture bloquante et zéro allocation

`READ_BLOCKING` remplace la scrutation : le thread est parqué par le pilote audio jusqu’à ce
qu’une trame soit disponible — c’est l’usage prévu d’`AudioRecord` et cela ne coûte rien à
l’arrêt. La `FloatArray` de trame est réutilisée. Priorité `THREAD_PRIORITY_URGENT_AUDIO`
ajoutée au passage : moins de préemption, donc moins de trames rattrapées en rafale.

**Aucune perte** : même taille de trame (20 ms), même chemin, même latence.

### 2. Polling sensible au cycle de vie

`PollPolicy` (fonction pure, testée) :

| Situation | Avant | Après |
|---|---|---|
| Premier plan, capture | 50 ms | 50 ms |
| Premier plan, connecté inactif | 2 s | 2 s |
| **Arrière-plan** | 50 ms – 2 s | **15 s** |

Le moteur Rust est déjà piloté par événements et réveille Dart par callback natif : cette
minuterie n’est qu’un filet de sécurité. **La voix ne passe jamais par elle** — le cas
d’usage principal de l’application (rester connecté en arrière-plan pendant des heures)
divise ainsi ses réveils par un facteur 300 environ.

Au retour au premier plan, un rafraîchissement immédiat évite une interface figée.

### 3. Roster : plus de JSON quand rien n’est affiché

`shouldReconcileRoster(foreground:)` : en arrière-plan, la sérialisation complète du roster
est suspendue. Les événements (arrivée, départ, changement de canal) continuent de mettre
l’état à jour — c’est seulement la réconciliation périodique de confort qui s’arrête.

### 4. Maintenance Rust adaptative

500 ms tant qu’au moins un client émet de l’audio, **2 s dans un canal silencieux**, avec
bascule automatique dans les deux sens. Le jitter buffer absorbe la latence de reprise, donc
le premier locuteur reste entendu sans retard perceptible.

### 5. Wake lock conditionnel

Le `PARTIAL_WAKE_LOCK` est désormais pris **seulement quand l’audio en a besoin** et relâché
en **sourdine totale** (ni capture ni lecture) ; il est repris immédiatement au démurage.
Le service de premier plan et la `MediaSession` continuent de maintenir le processus vivant —
la politique de survie en arrière-plan (phases précédentes) est intacte.

## Ce qui n’a délibérément pas été touché

- **Le flux de sortie cpal reste ouvert en permanence** (silence quand personne ne parle) :
  le fermer économiserait un peu, mais ajouterait une latence audible sur le premier paquet
  et provoquerait des clics de reprise sur certains appareils. C’est le compromis qu’adopte
  aussi le client de bureau.
- **La `MediaSession` reste en `PLAYING`** quand connecté : c’est précisément ce qui exempte
  l’application des politiques de destruction d’Android 14/15 (voir `AGENTS.md`).
- **Le VAD, le PTT, la reconnexion, le whisper, les icônes** : inchangés.

## Tests

Dart (+7, **65 au total**) : l’arrière-plan utilise toujours le palier lent quelles que soient
les autres conditions, les paliers premier plan restent inchangés, l’ordre des paliers est
vérifié, le palier d’arrière-plan reste sous 30 s (le filet doit rester un filet) et
représente un gain d’au moins 50× face à la cadence fixe de 200 ms du client amont, et le
roster n’est réconcilié qu’en premier plan.

Kotlin : `SecureStorage.kt`, `VoiceAudioController.kt`, `ConnectivityStreamHandler.kt`
compilent avec `kotlinc` ; `MainActivity.kt` et `KeepAliveService.kt` restent couverts par le
job Gradle de la CI.

## Validation

`cargo fmt` · `cargo check --locked` · `cargo clippy -p tsclient -- -D warnings` (exit 0) ·
`cargo test` **21/21** · `dart format --set-exit-if-changed` · `flutter analyze` 0 ·
`flutter test` **65/65**.

## Mesure réelle à faire (hors sandbox)

Ces gains sont structurels et lisibles dans le code, mais doivent être chiffrés sur appareil :

```bash
adb shell dumpsys batterystats --reset
# … 30 min connecté, écran éteint, canal silencieux …
adb shell dumpsys batterystats | grep -A 20 com.senlinjun.nek0
adb shell dumpsys power | grep -i wake        # le wake lock doit disparaître en sourdine
adb shell dumpsys activity services com.senlinjun.nek0
```

Critère proposé : **< 2 %/h** écran éteint dans un canal silencieux, **< 5 %/h** en écoute
active.
