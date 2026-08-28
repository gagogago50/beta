# Build & test de l'APK via CI (contourne la limite de RAM)

Date : 28 août 2026

## Pourquoi pas EAS / Expo ?

`npx eas-cli build` construit des projets **React Native / Expo** (il lit
`package.json`, `app.json`, `eas.json`). Ce projet est **Flutter + Rust + Kotlin
Android** : il n'a aucun de ces fichiers, il a `pubspec.yaml`, `lib/`,
`android/` (Gradle + Kotlin), `native/` (Rust `.so`) et `pre_build.py`. **EAS ne
peut pas le builder** et rien ne l'orientera vers le bon outil.

## Pourquoi une CI ici ?

Le vrai blocage du build est la **mémoire** : le sandbox de dev n'a que ~2 Go de
RAM, et `flutter build apk` écrase le démon Gradle (`Gradle build daemon
disappeared`). Un runner CI standard (`ubuntu-latest`, GitHub Actions) a **7 Go
de RAM**, exactement ce qu'il faut. C'est donc la bonne solution — et elle est
**déjà écrite** dans `.github/workflows/ci.yml`.

## Méthode A — GitHub Actions (recommandé)

Le workflow est complet et fait déjà tourner à chaque push :
`cargo fmt/check/clippy/test`, `cargo audit`, `python3 pre_build.py` (compile
`libtsclient.so` arm64 + x86_64 via le NDK), `flutter pub get / gen-l10n /
format / analyze / test`, puis **`flutter build apk --debug`**. Depuis cette
phase, l'APK debug est **uploadé en artefact** (`nek0-debug-apk`) à **chaque**
push, et sur un tag `v*` il produit aussi l'APK release par ABI.

### Étapes

1. Créer un dépôt GitHub (public ou privé).
2. Pousser le contenu de `nek0-personal/` :

   ```bash
   cd .../nek0-personal
   git init -b main
   git add -A
   git commit -m "NEk0: client TeamSpeak Flutter+Rust (Android)"
   git remote add origin https://github.com/<toi>/<repo>.git
   git push -u origin main
   ```

   > `libtsclient.so` est gitignoré (le fichier `.gitignore` l'exclut) et sera
   > recompilé par la CI via `pre_build.py`. C'est voulu et sûr.

3. Ouvrir l'onglet **Actions** du dépôt → la ligne **CI** se lance sur le push.
4. Une fois vert, ouvrir le run → section **Artifacts** → télécharger
   **`nek0-debug-apk`** (contient `app-debug.apk`).
5. `adb install app-debug.apk` (ou copier le fichier sur le téléphone) → tester
   avec `docs/PLAN-TEST-SERVEUR-REEL.md` contre `voice.teamspeak.com`.

### Ce que j'ai besoin que tu fournisses pour que je « le fasse à ta place »

Je **ne peux pas** produire l'APK dans la sandbox (2 Go, démon Gradle tué) — même
en installant Android SDK/NDK, Gradle n'y survivra pas. Mais je peux **orchestrer
le build GitHub à ta place** si tu me donnes un moyen de pousser :

- **Option 1 — tu pousses toi-même.** Le plus simple et le plus sûr (aucun secret
  à me transmettre). Tu lances les commandes ci-dessus, tu me donnes l'URL du
  repo, et je te guide sur le résultat de la CI. C'est ce que je recommande.
- **Option 2 — je pousse via un token.** Crée un **fine-grained PAT** GitHub
  (Settings → Developer settings → Fine-grained tokens) avec accès **repo
  (contents: write)** et **actions: write** sur un dépôt vide que tu crées. Si tu
  me le fournis (en plus du nom du repo), je peux, **dans un même tour**, faire
  `git init`, `add remote`, `push`, puis lire l'état du job Actions et te donner
  le lien de l'artefact APK.
  > ⚠️ Les jetons sont sensibles. Préfère l'Option 1 si possible.

## Méthode B — Codemagic (alternative, Flutter natif)

[Codemagic](https://codemagic.io) builder est pensé pour Flutter et a un plan
gratuit mensuel. Il suffit de connecter le repo GitHub, choisir « Flutter app »,
laisser la commande `flutter build apk --debug` (ou la config du workflow), et il
gère l'installation d'Android SDK/NDK. Pour le `.so` Rust, ajouter un pas
`python3 pre_build.py` avec `ANDROID_NDK_HOME` pointant vers un NDK r26d.

## Méthode C — Machine locale ≥ 8 Go

Construire sur une machine à toi (≥ 8 Go) :

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk-r26d
python3 pre_build.py            # produit libtsclient.so arm64 + x86_64
flutter pub get
flutter gen-l10n
flutter build apk --debug       # ou --release --split-per-abi
```

L'APK est dans `build/app/outputs/flutter-apk/`. Sur cette machine, tu peux aussi
installer et tester en direct. Cette méthode est la seule qui te permet de
**valider le serveur réel** (`voice.teamspeak.com`) de bout en bout.

## Après avoir l'APK — tester

Suis `docs/PLAN-TEST-SERVEUR-REEL.md` : connexion, chat, audio (VAD/PTT/whisper/
volume/routage/AEC), statut & modération, gestion de canaux, fichiers/icônes,
multi-serveur + mixe, robustesse Wi-Fi/reprise, thèmes, confidentialité, batterie.
