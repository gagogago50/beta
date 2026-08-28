# Sauvegarde du code source dans le workspace

## Où se trouve le projet

`/home/user/nek0-personal` — code source complet du fork NEk0 (Flutter + Rust + Kotlin),
docs de phases incluses. **Ce dossier persiste** d’une session à l’autre.

## Ce qui ne persiste pas

| Chemin | Raison |
|---|---|
| `nek0-personal/.git` | supprimé par la plateforme entre les tours (exclusion des chemins de type identifiants) |
| `nek0-personal/native/target`, `build/`, `.dart_tool/` | répertoires de build exclus des instantanés |
| `~/.cargo`, `~/.cache/sdk/flutter`, `~/.cache/android`, `~/.cache/kotlin` | chaînes d’outils, réinstallées à chaque session |
| `android/app/src/main/jniLibs/*/libtsclient.so` | produit par `python3 pre_build.py` |

Le versionnement Git ne survit donc pas : à la place, une **archive de sauvegarde** est
régénérée à la fin de chaque phase.

## Archive

`/home/user/nek0-source-backup.tar.gz` — environ 6 Mo, 344 entrées, sans les répertoires de
build ni les binaires.

Restauration :

```bash
cd /home/user
tar xzf nek0-source-backup.tar.gz          # recrée ./nek0-personal
```

Régénération (à refaire après toute modification importante) :

```bash
cd /home/user
tar --exclude='./nek0-personal/build' \
    --exclude='./nek0-personal/native/target' \
    --exclude='./nek0-personal/.dart_tool' \
    --exclude='./nek0-personal/android/app/src/main/jniLibs/*/*.so' \
    -czf nek0-source-backup.tar.gz ./nek0-personal
```

## Remise en route d’un environnement de build

```bash
# Rust
curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal -c rustfmt -c clippy
sudo apt-get install -y libasound2-dev          # cpal a besoin d'ALSA sur l'hôte Linux
cd nek0-personal/native && cargo test --locked

# Flutter 3.47 (la version exigée par pubspec)
curl -sL -o f.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.0-stable.tar.xz
tar xf f.tar.xz && export PATH=$PWD/flutter/bin:$PATH
cd nek0-personal && flutter pub get && flutter gen-l10n && flutter analyze && flutter test

# Android (NDK 26 requis pour le .so, SDK + JDK 17 pour l'APK)
export ANDROID_NDK_HOME=<ndk>/26.3.11579264
python3 pre_build.py && flutter build apk --debug
```

## État de la vérification

| Élément | Statut |
|---|---|
| Rust `cargo test` | 21/21 |
| Rust `cargo clippy -p tsclient -- -D warnings` | 0 |
| Dart `flutter test` | 65/65 |
| `flutter analyze` | 0 anomalie |
| Kotlin autonome (`kotlinc`) | 3 fichiers compilés sans erreur |
| Build APK | **jamais exécuté** — la sandbox (2 Go de RAM) tue le démon Gradle |
