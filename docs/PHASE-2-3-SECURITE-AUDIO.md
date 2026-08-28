# Avancement phases 2–3

## Réalisé

### Sécurité locale

- Android Keystore + AES-256/GCM (taille de clé gérée par le provider) pour identité et mots de passe.
- AAD liée au nom logique de chaque secret.
- IV aléatoire distinct pour chaque écriture.
- migration des anciennes préférences en clair ;
- mots de passe exclus du JSON de favoris ;
- sauvegarde/transfert Android désactivés.

### Serveurs privés

- mot de passe serveur ;
- canal par défaut ;
- mot de passe canal distinct ;
- passage FFI jusqu’à `ConnectOptions.channel_password()` ;
- indicateur du mode de chiffrement vocal déclaré par le serveur.

### Polling

- moteur Rust déjà événementiel ;
- pont Dart adaptatif 50/100/150 ms ;
- aucun timer périodique chevauchant ;
- roster complet limité à une fois toutes les deux secondes.

### PTT/VAD

- PTT prioritaire : capture arrêtée lorsque le bouton n’est pas pressé ;
- VAD hybride indépendant : volume, bruit adaptatif, zero-crossing, facteur de crête ;
- délai de relâchement 200 ms ;
- aucune bibliothèque VAD binaire précompilée.

### Groupes

- IDs de groupe canal et groupes serveur ajoutés au modèle client Rust/Dart ;
- tri déterministe des groupes serveur avant sérialisation.

### Chaîne de build

- suppression de tous les `.so` suivis dans Git ;
- compilation locale Rust `--locked` ;
- runtime C++ copié depuis le NDK Android local ;
- SHA-256 des bibliothèques packagées ;
- suppression OTA/Gitee et permission d’installation APK ;
- suppression des miroirs Maven tiers ;
- révision ReSpeak amont épinglée.

## Vérifications passées

- `git diff --check` ;
- JSON ARB valide ;
- `cargo metadata --locked` ;
- `cargo fmt` sur le crate applicatif ;
- script Python compilable ;
- aucun ELF/PE natif suivi restant dans Git.

## Vérifications bloquées par l’environnement

- APK Flutter : Flutter SDK et Android SDK absents ;
- build Rust Android : Android NDK absent ;
- `cargo check` hôte complet : headers ALSA absents.

## Prochaine étape

1. installer Flutter 3.47, JDK 17 et NDK 26/27 stable depuis les distributions officielles ;
2. régénérer `pubspec.lock` après suppression OTA ;
3. exécuter `pre_build.py` et archiver son manifeste SHA-256 ;
4. lancer `flutter analyze` et construire un APK debug ;
5. inspecter l’APK final et tester sur serveur TS3 chiffré contrôlé ;
6. ajouter noms/icônes de groupes et erreurs de permission ;
7. remplacer le polling FFI adaptatif par notification NativePort.
