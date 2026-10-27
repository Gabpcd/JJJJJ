# Jolene — migration React Native

Client mobile séparé de l’application Capacitor publiée. Les écrans utilisent les
composants React Native et une pile de navigation native : aucun écran WebView.
Le backend et les comptes existants ne sont pas réécrits.

## Périmètre

- Connexion email/mot de passe et résolution du compte **STAGING** : soignant,
  membre d’établissement avec son périmètre serveur, ou inscription à compléter.
- Création du compte, confirmation email, brouillon d’inscription et finalisation
  soignant/établissement. Médecine affiche les trois cycles, dont l’internat,
  sans déduire un droit de remplacement du seul cycle déclaré.
- Consultation des missions autorisées, filtres ville/contrat, détail et planning.
- Candidature avec planning confirmé, choix du contrat si demandé par le serveur,
  relecture après envoi et consultation de ses candidatures/missions.
- Profil soignant : lecture et modification des coordonnées, présentation,
  expérience et préférences géographiques. L’identité vérifiée reste verrouillée.
- Établissement : accueil, missions filtrées et paginées, détail du planning,
  profil et permissions réelles du membre. Les missions restent en lecture seule.
- Documents soignant : sélection de fichier, galerie ou caméra, ajout/remplacement,
  analyse, revue humaine, archivage et consultation de l’original privé. Un reçu
  local durable conserve les envois incertains pour les relire sans renvoyer le fichier.
- Contrats soignant/établissement : liste, lecture native du document serveur vérifié
  et signature OTP selon les permissions et l’admission TEST existantes. Le lecteur
  refuse un format qu’il ne sait pas restituer ; il ne régénère aucun contrat.
- Navigation à onglets avec une pile native par espace ; les pages conservent leur état.
- Retour par geste iOS / bouton système Android, conservation du défilement,
  clavier, actualisation et reprise après arrière-plan.
- Session dans le stockage sécurisé du système ; changement d’identité et
  déconnexion invalident les anciennes lectures.

Ce client ne remplace pas encore l’application publiée. La recette des nouveaux
parcours Documents et Contrats reste à exécuter en simulation puis en intégration
STAGING. Pointage, PSC, messagerie/push, revenus/facturation, préparation employeur,
publication et traitement des candidatures par l’établissement restent à porter. La récupération
du mot de passe et le challenge anti-bot natif restent à intégrer si requis par
la configuration Auth. Aucun parcours financier n’est exercé ici et le contenu
d’un contrat signé reste protégé. Voir [MIGRATION.md](MIGRATION.md) pour les limites de vérification.

## Exécuter le pilote

Depuis ce dossier :

    npm ci
    npm run ios

Expo Go SDK 57 sur simulateur suffit pour ce parcours. Le projet a son propre
lockfile (React 19 / React Native 0.86) ; ne pas installer ces dépendances à la
racine du web (React 18). Les identifiants d’un éventuel binaire de développement
sont distincts : app.jolene.nativepilot.

Le mode par défaut est **Démo · données fictives**, sans réseau ni identifiants :
30 missions locales pour vérifier l’interface. Ce n’est pas une preuve de
connexion Supabase ni de fonctionnement de ses permissions déployées.

Pour le parcours intégré, créer un fichier local ignoré .env.local :

    EXPO_PUBLIC_JOLENE_MODE=staging
    EXPO_PUBLIC_SUPABASE_URL=https://mejpriaetwgtcstbgfid.supabase.co
    EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<clé publique du projet STAGING>

Seul ce projet est autorisé, avec une clé sb_publishable_. Les clés secrètes, les
JWT de service et les URL de production sont refusés. Une configuration TEST
invalide affiche un écran bloquant ; elle ne bascule pas silencieusement en démo.
Ne jamais mettre un mot de passe, jeton utilisateur ou clé de service dans une
variable EXPO_PUBLIC. Saisir les identifiants du compte TEST dans l’interface.

La confirmation utilise PKCE et `jolene-native-pilot://auth/confirm` : ce retour
doit être autorisé dans **Auth STAGING** avant la vérification intégrée. Expo Go
ne possède pas ce scheme ; la confirmation nécessite un binaire de développement
avec l’identifiant distinct du pilote. Ne pas utiliser une redirection production
pour contourner une configuration TEST absente.

Un redémarrage Metro est nécessaire après un changement de configuration ou de
dépendances. Les scripts fixent la résolution IPv4 pour que le simulateur
rejoigne localhost. Aucun tunnel public n’est nécessaire.

## Validation

    npm run typecheck
    npm test
    npm run bundle

La CI native exécute types, logique et exports de vérification, puis les parcours
Maestro sur Android et XCTest sur iPhone et iPad portrait et paysage. Les exports ne sont ni une livraison ni une
soumission. Les journaux et captures sont conservés dans les artefacts CI.

Le scénario maestro/consultation.yaml vérifie les filtres, l’état vide, le détail
d’une mission située loin dans la liste, le retour à sa position, l’arrière-plan
et la déconnexion, puis la candidature, la reprise du profil, la lecture établissement et l’inscription médecin/interne. Les assertions de transport utilisent un client injecté et
des réponses fictives : elles ne prouvent pas la RLS du serveur.

Sur iPhone et iPad, les tests UI Apple de `ios-ui-tests/` vérifient le parcours complet
en portrait. Sur iPad, ils passent ensuite explicitement en paysage et vérifient de nouveau l’entrée, la liste, le détail,
le geste de retour à la position précédente, la candidature, le profil, les écrans établissement, l’inscription et la déconnexion. Ils ciblent les
éléments avec XCTest, sans transformation tactile du driver Maestro.
Chaque orientation conserve seize captures et un rapport XCTest distinct ; le runner
contrôle les dimensions affichées des images, en tenant compte de leur orientation EXIF. La présence
de ces scénarios ne vaut pas résultat : leur exécution CI doit être verte.
Android cible un unique émulateur prêt et refuse tout appareil USB ou non
autorisé ; Metro reste sur localhost via le port ADB inversé.

Les workflows `native-documents.yml` et `native-contracts.yml` préparent chacun
quatre jobs distincts : iPhone, Android, iPad portrait et iPad paysage. Chaque job
utilise une démo neuve, sans credentials STAGING, et exige respectivement neuf
ou huit captures avec les assertions du scénario. Le runner refuse le croisement
des flags Documents/Contrats. Leur présence dans le dépôt ne prouve pas leur
réussite : les premières simulations de ce lot restent à exécuter et relire.

Les preuves doivent toujours distinguer : données fictives sur simulateur,
intégration STAGING avec compte réel de test, appareil physique et production.
Le passage au natif de l’ensemble de Jolene n’est pas validé par ce seul pilote.

## Livraison et dépendances

Aucun EAS Build, EAS Update, OTA, upload de binaire ou soumission store n’est
configuré. La livraison mobile reste une action manuelle distincte.

Expo SDK 57 est retenu pour la compatibilité du runtime Expo Go disponible lors
de cette première vérification. Xcode 26.4+ est nécessaire pour compiler un
binaire de développement correspondant ; le runtime simulateur évite une
installation supplémentaire de SDK sur le Mac.

Le correctif compatible node-forge 1.4.1 est appliqué le 27/10/2026. L’audit npm
signale encore zod 3, dépendance de l’outillage Expo CLI
(GHSA-mrhx-c7xc-m3w5), et ses deux dépendants. Ne pas appliquer la rétrogradation
Expo proposée par `npm audit fix --force`. Zod n’est pas importé par les écrans
natifs ; aucune signature OTA n’est utilisée. Réévaluer l’outillage avant livraison.

Sources de l’architecture : [Expo SDK 57](https://docs.expo.dev/versions/v57.0.0/),
[React Native](https://reactnative.dev/docs/intro-react-native-components),
[Auth Supabase React Native](https://supabase.com/docs/guides/auth/quickstarts/react-native).
