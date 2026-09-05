# Phase 28 — Boucle micro zéro-allocation (D4)

> Objectif : éliminer les allocations/copies de la boucle de capture micro, qui tourne
> à 50 trames/s (20 ms @ 48 kHz). Sur un appareil, c'est une source de pression GC et de
> chauffe. Le code décompilé (`ts3-remote`) montre le backend PCM qui lit un bloc,
> le convertit et l'envoie ; la version performante conserve un fichier/jitter buffer et
> ne recrée pas ses buffers à chaque bloc.

## Chaîne avant (par trame)
1. Kotlin : `AudioRecord` → `FloatArray(960)` (réutilisé).
2. Kotlin : `ByteArray(data.size*4)` **alloué** + `ByteBuffer.wrap` **alloué** + `put`.
3. Kotlin : `runOnUiThread { sink.success(bytes) }` — **1 dispatch UI/thread par trame**.
4. Dart : `ByteData.sublistView` **alloué**, `Float32List(floatCount)` **alloué**, boucle RMS.
5. Dart : `malloc<Float>` + boucle de copie + `malloc.free` **par trame**.

Soit ~3 allocations GC + 1 malloc/free + 1 dispatch UI par trame.

## Après (zéro-allocation dans la boucle chaude)
### Dart (`lib/services/audio_service.dart`)
- Un seul `Pointer<Float>` (`_micPtr`) alloué **une fois**, réutilisé.
- Lecture du `ByteData` en **une passe** : RMS + écriture directe dans le pointeur FFI.
- Suppression du `Float32List` intermédiaire et du `malloc`/`free` par trame.
- Chemin « mic-only » (pas de session) : calcule le niveau mais ne transmet pas.

### Kotlin (`MicStreamHandler`)
- `ByteArray(960*4)` + `ByteBuffer` **réutilisés** (au lieu d'alloués par trame).
- `sink.success(bytes)` appelé **directement sur le thread de capture** (le codec sérialise
  de façon synchrone, donc le buffer est consommé avant la lecture suivante), au lieu de
  `runOnUiThread` par trame.

## Validation
- `flutter analyze` : 0 erreur ; `dart format --set-exit-if-changed` : propre ;
  `flutter test` : 142 tests.
- CI `flutter build apk --debug` : compile le Kotlin (valide le changement côté Android).

## État
- **Fait** : boucle micro Dart + Kotlin zéro-allocation.
- **Note** : le gain le plus fort (suppression des 50 dispatch UI/s) provient du Kotlin ;
  la CI le compile. À confirmer par une mesure on-device.
- **Reste** : passage JNI direct PCM 16 bits (contourner entièrement l'EventChannel),
  TSDNS multi-endpoints + `androidId`, validation appareil.
