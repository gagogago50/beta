# Plan de test sur serveur réel — voice.teamspeak.com

Date : 28 août 2026

> **Contexte.** Le code est validé par compilation/unités (Dart 113 tests,
> Rust 28 tests, clippy 0, analyze 0). Rien n'a encore été vérifié **contre un
> vrai serveur** : la sandbox de développement (2 Go de RAM) ne peut pas
> produire l'APK (`flutter build apk` échoue sur `Gradle build daemon
> disappeared`). Ce document est la checklist à dérouler **sur une machine
> ≥ 8 Go** une fois l'APK installé, en utilisant le serveur public fourni :
> `voice.teamspeak.com` (port TS3 par défaut `9987`).

## 0. Pré-requis

1. Machine ≥ 8 Go de RAM (le sandbox ne suffit pas).
2. `python3 pre_build.py` avec `ANDROID_NDK_HOME` pointant vers un NDK r26d,
   pour produire `libtsclient.so` (arm64 + x86_64) — sinon l'APK se build mais
   crash au lancement (`DynamicLibrary.open`).
3. `flutter build apk --debug` puis `adb install`, sur un appareil Android 9
   (API 28) ou plus récent.
4. Réseau : le téléphone doit atteindre `voice.teamspeak.com:9987` (UDP).
5. Accorder les permissions : micro, notifications, « ne pas optimiser la
   batterie » (le guide OEM s'affiche à la première connexion).

## 1. Connectivité de base

- [ ] Ajouter un serveur : nom `Voix TS`, adresse `voice.teamspeak.com`,
      pseudo au choix (`3`..`30` caractères), canal : laisser vide (défaut).
- [ ] Se connecter. Attendre `resolving → connecting → authenticating →
      connected`. La barre de connexion doit basculer au vert et afficher le
      RTT puis le jitter (`RTT ms ~Jitter • %perte`).
- [ ] L'arbre des canaux se remplit (racine + sous-canaux). La liste des
      clients du canal courant s'affiche (au moins vous-même + les bots du
      serveur public).
- [ ] Reconnecter : `ts_disconnect` puis `connect` refait le handshake.
- [ ] Déconnexion volontaire → retour à l'écran d'accueil sans crash.

## 2. Chat (canal / privé / serveur)

- [ ] Message canal : envoyer un texte dans le canal ; il doit revenir en écho
      (affiché via `text_message`). Vérifier que **vous** ne comptez pas en
      non-lu.
- [ ] Onglets chat : canal, serveur, privé. Badge non-lu sur un message arrivé
      quand le panneau est fermé.
- [ ] Message privé : long-press un client → « envoyer un message privé ».
      Le message doit tomber dans le fil privé de ce client.
- [ ] Message serveur (`targetmode 3`) : souvent limité par permission — si le
      serveur refuse, un `command_error` typé apparaît, jamais un crash.

## 3. Audio (le cœur)

- [ ] **Écoute** : rejoindre un canal où des clients parlent. Vous devez les
      entendre. Vérifier le voyant « parle » sur le client.
- [ ] **Micro** : désactiver le mute (icône micro) → parler → les autres doivent
      vous entendre. Le niveau `micRms` bouge sur le slider.
- [ ] **VAD** : sans parler, le micro ne doit pas transmettre (le serveur
      public affiche les talking states). Parler → transmission (délai ~200 ms
      de fin).
- [ ] **PTT** : activer PTT → le son ne part que bouton tenu.
- [ ] **Whisper** : sélectionner une cible (client/canal), armer le whisper →
      seule la cible reçoit. Vérifier le compteur de targets.
- [ ] **Whisper entrant** : liste d'autorisation → seuls les UID autorisés
      peuvent vous chuchoter (compteur `ignored_count`).
- [ ] **Volume par client** : slider −20..+20 dB → changement audible pour ce
      client, et **persisté** après reconnexion.
- [ ] **Mute / full-mute** : icône micro (input), haut-parleur (output),
      casque (input+output). Le mute doit se refléter sur le serveur.
- [ ] **Gain micro** : élever le gain → l'autre partie entend plus fort.
- [ ] **Routage** : écouteur / haut-parleur / filaire / Bluetooth. Basculer
      Bluetooth → le flux sort sur le casque ; `ts_restart_audio_output`
      reconstruit le flux.
- [ ] **AEC/NS/AGC** : activer AEC en haut-parleur → l'écho ne doit plus partir ;
      NS → moins de bruit de fond.

## 4. Statut & administration

- [ ] **Away/AFK** : activer + message → votre rostre passe en away ; désactiver
      efface le message.
- [ ] **Pseudo** : changer de pseudo (3..30) → le serveur confirme ; un pseudo
      pris échoue en `nickname_in_use`.
- [ ] **Channel commander** : activer → votre voix est entendue dans le périmètre
      du groupe (si la permission existe).
- [ ] **Modération** (long-press un client) : le menu ne propose que ce qui est
      permis. Tester kick canal / kick serveur / ban / poke / déplacer.
- [ ] **Gestion de canaux** : menu « ⋯ » sur un canal → créer sous-canal, éditer
      (titre, sujet, mot de passe, max clients, permanent), déplacer dans
      l'arbre, supprimer. Les permissions réelles du serveur peuvent restreindre.

## 5. Fichiers

- [ ] **Icônes de groupe** : dans un canal avec groupes/icônes, l'icône doit
      s'afficher à côté du nom (téléchargée via `ts_download_file` puis mises en
      cache). Échec silencieux (pas d'icône).
- [ ] **Avatar** : ouvrir la fiche d'un client → avatar téléchargé/résolu ;
      sinon icône `person`/`mic`.
- [ ] **Téléversement** : panneau « Fichiers » → saisir un chemin local et un
      chemin serveur (`/public/…`) → barre de progression puis résultat.

## 6. Multi-serveur & robustesse

- [ ] **Deux serveurs simultanés** : ajouter `voice.teamspeak.com` + un autre
      serveur ; onglets par serveur ; le son des deux se **mixe** (un seul flux
      cpal) ; passer d'un onglet à l'autre ne coupe pas l'autre.
- [ ] **Micro dans la session focalisée** : le micro ne transmet que dans
      l'onglet actif.
- [ ] **Bascule Wi-Fi ↔ mobile** : le réseau change → reconnexion immédiate
      (pas d'attente du backoff).
- [ ] **Reconnexion auto** : couper le réseau → `reconnecting` avec compte à
      rebours ; le rendre → `retryNow` immédiat. Un mot de passe faux/ban
      **ne** se réessaie **pas**.
- [ ] **Reprise après kill (C5)** : se connecter, quitter l'app via le recents,
      relancer → bannière « Reprendre » → retour dans le canal, micro **mute**.
- [ ] **Swipe-away** : balayer l'app dans recents → toutes les sessions sont
      déconnectées proprement (JNI `tsDisconnect`).

## 7. Réglages & confidentialité

- [ ] **Thème** : basculer Système / Sombre / Clair / AMOLED. Le thème clair
      doit être lisible ; AMOLED noir pur.
- [ ] **Historique chiffré** : activer → messages conservés au redémarrage
      (fichiers chiffrés par serveur) ; désactiver → purge.
- [ ] **Identité** : exporter → blob chiffré ; importer → restaure l'identité.
- [ ] **Effacement secrets** : purge identité + mots de passe ; les favoris et
      l'historique sont aussi effacés.
- [ ] **Logs verbeux** : activer → un `logcat` ne doit **jamais** contenir
      d'adresse IP, de pseudo, d'UID ni d'identité (voir `check_secrets.py`).

## 8. Performance & batterie

- [ ] Laisse connecté en silence 1 h → la batterie ne doit pas se vider
      anormalement (le poll passe à 15 s en fond, snapshot à 2 s).
- [ ] En conversation : CPU faible, pas de drop (underrun/overrun). Le
      `[cpal-stats]` en logcat doit montrer `mismatches=0`.
- [ ] **Latence** : jitter buffer adaptatif — sur une liaison stable, ~40 ms de
      profondeur (faible latence) ; si le réseau se dégrade, la profondeur
      augmente jusqu'à ~160 ms (pas de coupure).

## 9. Notes

- `voice.teamspeak.com` est un serveur **public** : ne pas y faire de
  modération agressive ni de spam (anti-flood), utiliser un pseudo neutre.
- Certains réglages (route, focus audio, AEC) dépendent du matériel ; les
  vérifier sur au moins un appareil avec Bluetooth et un haut-parleur.
- Les cas « serveur réel » (multi-serveur simultané, mixe, whisper, transferts)
  ne peuvent être validés que sur appareil — la compilation/les tests unitaires
  garantissent la non-régression, pas la conformité réseau.
