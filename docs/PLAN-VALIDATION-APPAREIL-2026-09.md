# Plan de validation sur serveur réel — voix, fichiers, tokens, recherche

> Les changements des phases 23–28 sont validés par la CI (compile/analyze/test + APK), mais
> les fonctions réseau/audio n'ont jamais été éprouvées contre un vrai serveur. Ce plan
> documente comment tester l'APK (`nek0-debug-apk.zip`) sur un appareil Android contre
> `voice.teamspeak.com` et, idéalement, un serveur de test local que l'on contrôle.

## Prérequis
- Appareil Android 9+ (API 28+), réseau Wi-Fi stable.
- APK à installer : `/home/user/nek0-debug-apk.zip` (→ `app-debug.apk`).
- Serveur de test **que vous contrôlez** (le plus utile pour les perms/tokens) ; sinon
  `voice.teamspeak.com`.

## 1. Connexion / welcome-host
- Se connecter à `voice.teamspeak.com` (ou votre serveur).
- **Attendu** : barre de statut `résolution → connexion → authentification → connecté` ;
  le **welcome message** apparaît dans l'onglet Serveur ; le **host message** selon son mode
  (0=none, 1=log, 2=modal, 3=déconnexion).
- Si un serveur exige un niveau d'identité : le refus doit être explicite
  (`needed_identity_security_level`), pas un simple « connexion échouée ».

## 2. Canaux enrichis (phase 23)
- Naviguer dans l'arbre : marqueurs **défaut / permanent / semi-permanent / mot de passe /
  non-abonné / talk power requis**.
- Fiche canal : codec, max clients, talk power requis, type, badges.

## 3. Audio (phase 28 — mesurer !)
- Parler avec le micro ouvert : le témoin **« Speaking »** doit s'allumer. Le ✓ est le plus
  visible : la boucle micro passe de 50 dispatch UI/s à un envoi direct (moins de chauffe).
- Vérifier le **PTT**, le **mute**, le **volume par client**, la **route** (écouteur /
  haut-parleur / filaire / Bluetooth SCO).
- Changer de route, retirer/rebrancher un casque : le flux DOIT survivre
  (`ts_restart_audio_output`).
- Mesurer grossièrement : CPU en silence (VAD actif) pendant 5 min ; latence perçue.

## 4. Gestionnaire de fichiers (phases 24 & 26)
- Menu Outils → **Files** : liste le répertoire du canal courant.
- **Télécharger** un fichier → il doit arriver dans `<cache>/downloads/`.
- **Créer un dossier**, **renommer** un fichier (optionnellement vers un autre canal),
  **supprimer** un fichier (re-liste automatique).
- Sur un serveur avec `b_file*` permissifs, vérifier que ces actions aboutissent ; sinon un
  `command_error` typé doit s'afficher.

## 5. Recherche globale (phase 25)
- Icône loupe dans l'en-tête « Channels » : taper un nom doit retrouver **canal (avec chemin
  Parent › Enfant)**, **utilisateur**, **fichier** ; agir dessus (rejoindre / volume / navigateur).

## 6. Permission key (phase 27)
- Meni Outils → **Enter permission key** : coller une clé d'admin. **Attendu** : SnackBar
  « Permission key accepted (granted …) » ; si la clé est invalide, une erreur.

## 7. Reconnexion / réseau
- Couper le Wi-Fi puis le rétablir : reconnexion automatique (min 3 s, backoff, max 6 essais),
  avec restauration du canal précédent. Un changement Wi-Fi↔mobile doit forcer une reconnexion.
- Mettre l'app en arrière-plan puis revenir : la notification de service reste, le rostle
  continue à se rafraîchir.

## Télémétrie de débug
- `adb logcat | grep -iE "tsclient|cpal|event_loop"` pour observer le moteur.
- Le fichier de diagnostic `diagMessages` (borné) est visible dans l'UI ; vérifier l'absence
  d'allocs/panic.

## Critères de "done"
- [ ] Connexion + welcome + host.
- [ ] Canaux enrichis + fiche.
- [ ] Parler / PTT / mute / volume / routes (mesure CPU en silence < seuil raisonnable).
- [ ] Lister / télécharger / créer / renommer / supprimer des fichiers.
- [ ] Recherche globale.
- [ ] Permission key acceptée.
- [ ] Reconnexion + backoff + restauration du canal.
