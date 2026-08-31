# Rapport — fonctions du client TeamSpeak Windows manquantes / à implémenter

Date : 31 août 2026

> **Accès au code source en ligne** : le serveur HTTP fourni
> (`https://4795b630695b6a.lhr.life`) renvoie **`503 no tunnel here`** — le
> tunnel `localhost.run` est **éphémère** et n'est actif que pendant que le
> serveur local tourne sur ton PC. Je ne peux pas le lire tant qu'il est arrêté.
> En attendant, ce rapport s'appuie sur l'analyse déjà présente dans le
> workspace : `teamspeak-analysis/reports/sdk-functions.csv` (**231 fonctions
> SDK TS3** classées par catégorie), `rapport-analyse-teamspeak3.md`,
> `moteur-ts3-clean-room.md`, `strings-*.txt` et `plan-client-android-ts3.md`.

---

## 0. Ce que sait faire l'app aujourd'hui (notre FFI, 34 fonctions `ts_*`)

Connexion/reconnexion, multi-serveurs, canaux/champs, chat canal/privé/serveur,
modération (kick/ban/poke/move), statut (away/nickname/commander), whisper
(émettre + allow list entrante), mute, VAD/PTT, gain micro, volume par client,
**volume maître**, downloads + uploads de fichiers, gestion de canaux
(créer/éditer/supprimer/déplacer), icônes/avatars, identité (Keystore +
backup/restore), thèmes, historique chiffré, sons d'événement, favoris &
tri de serveurs.

Les 231 fonctions SDK couvrent un périmètre plus riche (audit de permissions,
3D, hotkeys, amis, groupes, métriques de transfert). Voici le **gap** réel,
découpé en **fonctions manquantes** et **sa façon d'implémenter** dans notre
pile Flutter + Rust (`tsclientlib`) + Kotlin.

---

## 1. Fonctions **client** manquantes (du SDK → implémentation)

| # | Fonction SDK | Ce qu'elle fait | Comment l'implémenter | Priorité |
|---|---|---|---|---|
| C1 | `requestClientSetWhisperList` | Définir qui peut **te** chuchoter (liste d'allow) | Déjà fait côté émiseur (`setWhisperTargets`). Le côté **récepteur** (`whisper_allowed_uids`) existe ; l'exposer en UI par UID (pas par ID de session). | Haute |
| C2 | `requestClientSetIsTalker` | Donner/retirer le **talk power** à un client | Commande `clientupdate` (le moteur contient `OUT_CLIENTUPDATE`), via `Command` Rust ; UI dans la modération. | Moyenne |
| C3 | `requestClientEditDescription` | Modifier la **description** d'un client | `clientupdatedb` (permission `b_client_edit_description`). Pas encore exposé. | Moyenne |
| C4 | `requestClientMove` / `requestClientsMove` | Déplacer un/des clients | **Déjà fait** (`ts_move_client`). Etendre à plusieurs clients sélectionnés. | Basse |
| C5 | `requestMuteClients` / `requestUnmuteClients` | **Mute local** d'un client | Déjà fait (`setClientVolume`). Distinguer « volume 0 » de « muted » visuellement. | Basse |
| C6 | `requestServerGroupAddClient` / `DelClient` | Affecter/retirer un **groupe serveur** | Commande `servergroupaddclient`/`servergroupdelclient` (bloqué par permission). UI admin. | Moyenne |
| C7 | `requestClientDBIDfromUID` / `requestClientNamefromUID/DBID` | Résoudre UID ↔ DBID ↔ nom | `clientdbidfromuid`/`clientidfromname`/`clientnamefromdbid`. Utile pour amis/perm. | Basse |

## 2. Fonctions **canal** manquantes

| # | Fonction SDK | Ce qu'elle fait | Implémentation | Priorité |
|---|---|---|---|---|
| CH1 | `requestChannelSubscribe/Unsubscribe` | **S'abonner/se désabonner** d'un canal (visibilité) | `channelsubscribe`/`channelunsubscribe`. Le moteur s'abonne à tout (`subscribeall`) ; ajouter un toggle par canal. | Moyenne |
| CH2 | `verifyChannelPassword` | Vérifier le **mot de passe** avant de joindre | Déjà géré par `channelPassword` ; re-tester sur serveur réel. | Basse |
| CH3 | `channelset3DAttributes` / `systemset3DListenerAttributes` | **Audio 3D** positionnel | Nécessite un moteur spatial ; hors périmètre MVP — à documenter. | Basse |
| CH4 | `getChannelVariableAsUInt64` | Lire la limite de clients native | `get_channel_maxclients` ; exiger la **permission** pour créer un canal. | Basse |

## 3. Fonctions **serveur / permission** manquantes

| # | Fonction SDK | Ce qu'elle fait | Implémentation | Priorité |
|---|---|---|---|---|
| S1 | `requestChannelPermList` / `requestClientPermList` | **Audit de permissions** (ce qui est permis à qui) | `channelpermlist`/`clientpermlist`. **Important pour la parité** : c'est ce qui permet d'afficher/masquer les actions. Le moteur fournit déjà `notifyclientpermhints` ; compléter avec l'inventaire de permissions. | Haute |
| S2 | `requestChannelPermList` + `setChannelVariableAsInt` | **Éditer les permissions** d'un canal | `channeladdperm`/`channeldelperm`. Exiger la permission `b_channel_*`. | Moyenne |
| S3 | `requestComputeMD5` / MD5 channel | Vérifier le mot de passe canal | Déjà géré par `verifyChannelPassword`. | Basse |
| S4 | `getServerGroupNameByID` / `getChannelGroupNameByID` | Noms de groupes | **Déjà fait** (`server_group_names`/`channel_group_name`). | Fait |

## 4. Fonctions **fichiers / transferts** manquantes

| # | Fonction SDK | Ce qu'elle fait | Implémentation | Priorité |
|---|---|---|---|---|
| F1 | `requestFileList` | **Lister** les fichiers d'un canal | Commande `ftgetfilelist` → renvoyer `channel://`+ `/` (fichiers). Ulis pour un gestionnaire. | Haute |
| F2 | `requestFile` / `haltTransfer` | Télécharger / **annuler** | **Déjà fait** (`ts_download_file`/`cancelTransfer`). Étendre à un `ftlist`. | Basse |
| F3 | `requestDeleteFile` / `requestRenameFile` | **Supprimer / renommer** un fichier | `ftdeletefile`/`ftrenamefile`. UI gestionnaire. | Moyenne |
| F4 | `getTransferStatus` / `getTransfer*` | Métriques (vitesse, taille, durée) | `FileTransfer` les porte déjà ; exposer `bytes/sec`. | Basse |

## 5. Fonctions **audio / hotkeys / divers** manquantes

| # | Fonction SDK | Ce qu'elle fait | Implémentation | Priorité |
|---|---|---|---|---|
| A1 | `activateCaptureDevice` / `openPlaybackDevice` / `close*` | Sélection de **device** capture/lecture | Déjà fait (`AudioRoute`, AEC/NS/AGC). Exposer le **choix micro** natif (liste de devices). | Moyenne |
| A2 | `getPlaybackModeList` / `getCaptureModeList` | Modes (normale/voix/…) | L'app gère VAD/PTT ; exposer les modes comme le client. | Basse |
| A3 | `getHotkeyFromKeyword` / `showHotkeySetup` / `requestHotkeyInputDialog` | **Raccourcis clavier** | Nécessite un clavier physique ; sur mobile, rester en PTT. À documenter. | Basse |
| A4 | `createBookmark` / `getBookmarkList` / `guiConnectBookmark` | **Favoris / connexion par favori** (le client connecte via un favori et garde mdp) | **Déjà fait** (`Server`, `serverListProvider`, `SecureStorage`). Compléter : permettre de **se connecter depuis un favori déjà existant**. | Basse |
| A5 | `playWaveFile` / `playWaveFileHandle` | **Sons d'événement** | Partiellement fait (`SystemSound`). Remplacer par des `.wav` associés à un événement (message, join, leave). | Moyenne |
| A6 | `requestClientIDs` / `getClientID` (globaux) | IDs | Déjà géré par session. | Fait |

---

## 6. **Boutons** manquants / à revoir (ergonomie)

| # | Bouton | Rôle | Promo |
|---|---|---|---|
| B1 | **Rejoindre un favori existant** (sans re-saisir) | Depuis l'accueil, cliquer un serveur = connexion | ✅ (existant) |
| B2 | **Abonnement canal** (visibilité) | Désabonner un canal bruyant | À ajouter |
| B3 | **Enregistrement/lecture** des sons d'événement | Choix du son | À ajouter |
| B4 | **Recherche globale** (un champ clients+canaux+fichiers) | Rechercher partout | À ajouter |
| B5 | **Sélecteur de micro natif** (liste de devices) | Choisir le micro | À ajouter |
| B6 | **Mute global d'une liste de clients** | Sélection multiple | À ajouter |
| B7 | **Vitesse/état** des transferts (dans le panneau Fichiers) | Info en temps réel | ✅ (progression) |
| B8 | **Menu « Tout déconnecter »** | Quitter tous les serveurs | ✅ (ajouté) |

---

## 7. Façon de les implémenter (mécanisme général)

Le moteur Rust (`tsclientlib`) expose déjà la **plupart des commandes** de la
couche SDK (elles ont été ajoutées au fil des phases). Pour chaque fonction
manquante :

1. **Côté Rust** : ajouter un `Command` (dans `lib.rs`) + son branchement dans la
   boucle d'événements (`api.rs`), en réutilisant les `Out*Message` du moteur
   déjà générés (`OutChannelSubscribeMessage`, `OutClientSetIsTalker…`, etc.).
2. **Côté FFI** : exporter un `ts_*` (dans `api.rs`) et le binder dans
   `ts_ffi.dart`.
3. **Côté état** : ajouter la méthode au `MultiServerNotifier` + façade
   `TsConnectionNotifier`.
4. **Côté UI** : ajouter le bouton/dialogue (sur un `bottomSheet` existant) +
   clés l10n EN/ZH.
5. **Valider** : `flutter analyze`, `flutter test`, `cargo test`, `cargo clippy`,
   `check_secrets.py` ; puis pousser → CI → APK.

---

## 8. Ce que je peux faire maintenant (serveur hors-ligne)

Dès que le tunnel est relancé, je pourrai confronter notre implémentation au
**code réel décompilé** (fonctions précises, chaînes de commandes, valeurs de
permissions) et affiner ce rapport. En attendant, **les fonctions à plus forte
valeur sont** :

- **S1 / CH1 / C1** : audit de permissions, abonnement canal, whisper incoming
  par UID — la **parité fonctionnelle** la plus visible.
- **F1 / F3** : gestionnaire de fichiers (lister/supprimer) — **confort**.
- **A5** : sons d'événement **associés** (`.wav`).

Veux-tu que je **relance le tunnel** et que tu me confirmes l'URL active, ou que
j'implémente directement les fonctions **S1 (permissions) + F1 (liste de
fichiers) + A5 (sons d'événement)** qui n'ont pas besoin du serveur pour être
écrites et validées ?
