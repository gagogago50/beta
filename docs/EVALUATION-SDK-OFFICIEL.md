# Évaluation du SDK TeamSpeak officiel 3.5.2

**Source officielle :** `https://files.teamspeak-services.com/releases/sdk/3.5.2/teamspeak-sdk-3.5.2.tar.gz`  
**SHA-256 observé :** `9eabe05abebf949e288553c6646abb4ef3854b6d196118c2ae87eb2436644865`  
**Version :** 3.5.2, 17 juin 2026.

## Contenu Android constaté

Le paquet officiel fournit des bibliothèques clientes précompilées pour :

- Android `arm64-v8a` ;
- Android `x86_64`.

Il inclut également des en-têtes C/C++, de la documentation et des exemples source. Le changelog indique Android API 21 minimum et recommande un backend audio Java/Kotlin sur Android.

## Décision d’intégration

**Le binaire SDK n’est pas intégré dans ce prototype.**

Raisons :

1. la licence fournie est propriétaire, non transférable et non sublicenciable ;
2. elle interdit la distribution à des tiers sans accord spécifique ;
3. elle ne convient donc pas à un APK open source redistribuable par défaut ;
4. `libteamspeak_sdk_client.so` est un binaire fermé précompilé, contraire à la règle de ce prototype qui compile son moteur depuis les sources ;
5. une utilisation distribuée doit être négociée avec TeamSpeak/Sales et documentée par écrit.

Pour un usage strictement personnel, le texte semble autoriser une utilisation sur les appareils de l’utilisateur, mais cela ne donne pas le droit de publier l’APK ou le dépôt avec la bibliothèque.

## Utilisation faite dans cette phase

Le SDK a seulement servi à vérifier des choix d’architecture déjà implémentés indépendamment :

- callbacks asynchrones plutôt qu’un polling réseau ;
- états connexion séparés ;
- audio interne 48 kHz ;
- périphériques audio personnalisés avec capture fournie régulièrement ;
- PTT via activation/désactivation de l’entrée ;
- erreurs distinctes pour mot de passe serveur et permissions ;
- modes de chiffrement vocal par canal, forcé actif ou forcé inactif ;
- événements de parole, déplacement, canaux et erreurs serveur ;
- messages privés, canal et serveur ;
- groupes/permissions et whisper.

Aucun fichier, en-tête, exemple ou binaire du SDK n’a été copié dans le projet `nek0-personal`.

## Quand utiliser le SDK officiel

Il pourra remplacer ReSpeak uniquement si :

- TeamSpeak accorde une licence écrite adaptée au projet et à sa distribution ;
- l’application accepte d’intégrer une bibliothèque propriétaire ;
- les binaires officiels sont vérifiés par hash/signature ;
- une couche JNI dédiée est créée ;
- les notices et restrictions de redistribution sont respectées.

Sans ces conditions, le moteur ReSpeak source-only reste le choix retenu.
