# Recherche comportementale — client Windows, polling, PTT/VAD et chiffrement

## Polling

Le moteur réseau du client Windows est événementiel : callbacks de connexion, mises à jour client/canal, événements audio et signaux/slots Qt. Les chaînes `onConnectStatusChangeEvent`, `onUpdateClientEvent`, `onChannelMoveEvent`, `onTalkStatusChangeEvent` et les callbacks du SDK corroborent ce modèle.

Le moteur Rust de NEk0 est également événementiel (`con.events().next()` avec attente Tokio). Le polling de 200 ms était uniquement une limitation du pont Dart FFI, pas du protocole.

Modification appliquée :

- callback `NativeCallable.listener` enregistré auprès de Rust ;
- réveil edge-triggered envoyé à Dart dès qu’un événement est mis en file ;
- le callback ne transporte aucune donnée et ne manipule pas l’état sur le thread Rust ;
- Dart draine ensuite la file avec `ts_poll_events()` sur son isolate ;
- polling 50 ms conservé uniquement pendant capture/parole pour l’indicateur vocal ;
- garde-fou 1 s pendant connexion et 2 s au repos ;
- sérialisation complète du roster réduite à une réconciliation toutes les 2 secondes.

Le chemin normal des événements n’attend donc plus le timer FFI, ce qui rapproche le comportement du modèle callback du client Windows.

## Modes de transmission visibles dans Windows

Les ressources Windows décrivent :

- **Push-To-Talk** : micro actif seulement pendant l’appui ;
- **Continuous Transmission** ;
- **Automatic** : algorithme intelligent de présence vocale ;
- **Volume Gate** : transmission au-dessus d’un seuil ;
- **Hybrid** : combinaison volume gate + probabilité de présence vocale ;
- délai de relâchement PTT et VAD éventuellement actif au-dessus du PTT.

Le binaire contient des références à WebRTC Audio Processing, `MonoVad`, `RNN VAD`, AEC3 et Speex preprocess. Ces composants expliquent le comportement, mais leur code propriétaire/intégré n’est pas copié.

## Implémentation indépendante ajoutée

Le mode activation vocale de NEk0 utilise maintenant un détecteur hybride source-only :

- RMS et seuil configuré ;
- estimation lente du bruit ambiant ;
- seuil adaptatif limité ;
- taux de passages par zéro ;
- facteur de crête ;
- ouverture immédiate sur signal clairement supérieur au seuil ;
- hangover de 200 ms pour éviter de couper les fins de mots ;
- rejet des NaN/Inf et limitation des échantillons.

Ce détecteur n’est pas présenté comme identique au RNN WebRTC de TeamSpeak. Il reproduit la logique fonctionnelle « gate + forme vocale » sans binaire tiers précompilé. Le PTT existant reste prioritaire et coupe physiquement la capture lorsque le bouton n’est pas pressé.

## Serveurs privés et canaux protégés

Ajouts :

- mot de passe serveur séparé ;
- mot de passe canal séparé ;
- transmission des deux paramètres vers `ConnectOptions.password()` et `ConnectOptions.channel_password()` ;
- chiffrement au repos des deux secrets via Android Keystore ;
- suppression des mots de passe dans le JSON des favoris.

## Chiffrement TS3

Le moteur ReSpeak fournit :

- handshake cryptographique TS3 ;
- échange de clés et identité ;
- AES-EAX pour contrôle/authentification ;
- dérivation clé/nonce par sens, type, génération et ID paquet ;
- contrôle des flags `Unencrypted` ;
- rejet de voix non chiffrée quand le serveur/canal exige le chiffrement ;
- gestion de `virtualserver_codec_encryption_mode` et `channel_codec_is_unencrypted`.

Le transport de ce fork conserve le chiffrement vocal activé dans `ConnectedParams`. Aucun contournement de serveur privé, mot de passe ou permission n’est ajouté.

## Groupes et permissions

Les déclarations ReSpeak couvrent déjà :

- groupes serveur et canal ;
- `client_servergroups` et `client_channel_group_id` ;
- listes, ajout/retrait de clients et permissions ;
- permissions effectives, valeurs, skip et negate ;
- erreurs de permission ;
- Talk Power et permissions de forcer PTT.

Le moteur de base sait parser ces messages, mais NEk0 ne les expose pas encore dans son modèle/UI. La prochaine phase doit d’abord ajouter une vue lecture seule des groupes effectifs, puis les opérations administratives uniquement si le serveur confirme les permissions nécessaires.
