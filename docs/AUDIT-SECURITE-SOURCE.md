# Audit sécurité de la base NEk0 — source uniquement

**Date :** 14 août 2026  
**Révision amont de départ :** `f5497d12ed368f8f2969f15d7f1dfabe05434a22`

## Conclusion

Aucune logique évidente de backdoor, stealer, keylogger, exfiltration de contacts/SMS, service d’accessibilité, administration d’appareil ou collecte d’identifiants matériels n’a été trouvée dans les sources applicatives examinées.

Ce résultat n’est pas une preuve mathématique d’absence de malware : il faut encore compiler localement, auditer les dépendances résolues, examiner l’APK final et comparer ses fichiers natifs au manifeste SHA-256.

## Surfaces examinées

- Dart/Flutter : UI, stockage, FFI, audio et mise à jour OTA ;
- Kotlin : activité, microphone, service, notification et chargement natif ;
- Rust : FFI, réseau, état, audio et code ReSpeak vendored ;
- manifests et permissions Android ;
- scripts de build et workflow GitHub ;
- fichiers binaires suivis par Git ;
- endpoints réseau codés en dur ;
- appels processus/shell et chargement dynamique.

## Résultats

### Pas d’obfuscation applicative détectée

- aucune étape Dart `--obfuscate` dans le projet ;
- aucun packer Android ou chargeur DEX dynamique ;
- pas de `DexClassLoader`/`PathClassLoader` ;
- la bibliothèque Rust est un ELF natif normal ;
- le client Windows officiel est optimisé et majoritairement stripped, mais pas protégé par un packer évident dans l’analyse précédente.

### Chargement dynamique attendu

Deux chargements concernent uniquement le moteur local :

- Dart : `DynamicLibrary.open("libtsclient.so")` ;
- Kotlin : `System.loadLibrary("tsclient")`.

Aucun téléchargement dynamique de bibliothèque native n’a été trouvé.

### Réseau attendu

Après suppression de l’OTA, les accès prévus sont :

- UDP/TCP vers le serveur TeamSpeak choisi par l’utilisateur ;
- DNS/SRV/TSDNS ;
- `https://named.myteamspeak.com/lookup` dans le résolveur ReSpeak lorsque la résolution par nickname est utilisée.

Aucun endpoint de télémétrie ou d’exfiltration propre à l’application n’a été trouvé.

### Risques trouvés et corrigés

1. **Mise à jour OTA auto-installable**  
   Elle téléchargeait un APK depuis GitHub/Gitee et demandait `REQUEST_INSTALL_PACKAGES`. Cette fonctionnalité et ses permissions ont été retirées. Les mises à jour doivent être construites/installées manuellement.

2. **Binaires natifs précompilés suivis par Git**  
   Deux `libc++_shared.so` provenant d’un NDK bêta étaient inclus. Ils ont été supprimés. `pre_build.py` construit désormais `libtsclient.so` depuis les sources verrouillées et copie `libc++_shared.so` uniquement depuis le NDK local choisi.

3. **Miroirs Maven tiers**  
   Les dépôts Aliyun ont été retirés. Seuls Google Maven, Maven Central et Gradle Plugin Portal restent configurés.

4. **Automatisation de publication**  
   Le workflow de publication GitHub/Gitee et le script d’upload Gitee ont été retirés du prototype personnel.

5. **Secrets en clair**  
   L’identité TS3, le mot de passe serveur et le mot de passe canal passent maintenant par AES-GCM avec une clé non exportable Android Keystore. Une migration retire les anciennes valeurs de SharedPreferences après écriture chiffrée confirmée.

6. **Sauvegarde/transfert Android**  
   Auto Backup et device transfer sont désactivés jusqu’à revue complète des données.

7. **Fuites mémoire FFI**  
   Les chaînes Dart passées à Rust sont libérées systématiquement dans des blocs `finally`.

## Build de confiance

`pre_build.py` impose maintenant :

- Android API 28 pour les compilateurs NDK ;
- `cargo build --locked` ;
- compilation locale ARM64 et x86_64 ;
- suppression des `.so` obsolètes avant copie ;
- runtime C++ provenant du NDK local ;
- manifeste SHA-256 `android/app/src/main/jniLibs/native-build.sha256`.

Les `.so` et le manifeste généré sont ignorés par Git pour empêcher leur redistribution accidentelle.

## Points encore ouverts

- régénérer `pubspec.lock` avec un Flutter SDK approuvé puis examiner chaque package et checksum ;
- épingler les dépendances Rust git à une révision précise dans `Cargo.toml`, pas seulement à `master` ;
- exécuter `cargo audit` et un scanner SCA après installation de l’outillage ;
- réduire les blocs `unsafe` FFI et valider longueur/pointeurs ;
- vérifier l’APK final avec `apkanalyzer`, `aapt2`, `readelf` et un scan antivirus multi-moteur hors ligne si disponible ;
- tester qu’aucun secret n’apparaît dans Logcat, tombstones ou messages d’erreur ;
- remplacer à terme le pont microphone EventChannel par JNI direct pour réduire copies et surface mémoire.

## Permissions restantes justifiées

- `INTERNET` : serveur TeamSpeak ;
- `RECORD_AUDIO` : voix ;
- `FOREGROUND_SERVICE*` : connexion/audio en arrière-plan ;
- `POST_NOTIFICATIONS` : notification du service ;
- `WAKE_LOCK` : session vocale active.

Aucun accès stockage externe, installation APK, contacts, SMS, caméra, localisation ou accessibilité n’est demandé.
