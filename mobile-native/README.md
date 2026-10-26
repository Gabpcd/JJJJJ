# Jolene — premier parcours React Native

Client mobile séparé de l’application Capacitor publiée. Les écrans utilisent les
composants React Native et une pile de navigation native : aucun écran WebView.
Le backend et les comptes existants ne sont pas réécrits.

## Périmètre

- Connexion email/mot de passe d’un **soignant existant de STAGING**.
- Consultation des missions autorisées, filtres ville/contrat, détail et planning.
- Retour par geste iOS / bouton système Android, conservation du défilement,
  clavier, actualisation et reprise après arrière-plan.
- Session dans le stockage sécurisé du système ; changement d’identité et
  déconnexion invalident les anciennes lectures.

Ce pilote ne remplace pas encore l’application publiée. Inscription, espace
établissement, candidature, documents, contrat, pointage, PSC, notifications et
paiements restent dans le client existant. Aucun parcours financier n’est exercé
ici et aucun contrat signé n’est modifié.

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

Un redémarrage Metro est nécessaire après un changement de configuration ou de
dépendances. Les scripts fixent la résolution IPv4 pour que le simulateur
rejoigne localhost. Aucun tunnel public n’est nécessaire.

## Validation

    npm run typecheck
    npm test
    npm run bundle

La CI native exécute types, logique et exports de vérification, puis les parcours
Maestro sur iPhone et Android, et XCTest sur iPad portrait et paysage. Les exports ne sont ni une livraison ni une
soumission. Les journaux et captures sont conservés dans les artefacts CI.

Le scénario maestro/consultation.yaml vérifie les filtres, l’état vide, le détail
d’une mission située loin dans la liste, le retour à sa position, l’arrière-plan
et la déconnexion. Les assertions de transport utilisent un client injecté et
des réponses fictives : elles ne prouvent pas la RLS du serveur.

Sur iPad, les tests UI Apple de `ios-ui-tests/` vérifient le parcours complet
en portrait, puis passent explicitement en paysage. Ils vérifient de nouveau l’entrée, la liste, le détail,
le geste de retour à la position précédente et la déconnexion. Il cible les
éléments avec XCTest, sans transformation tactile du driver Maestro.
Chaque orientation conserve quatre captures et un rapport XCTest distinct ; le runner
contrôle les dimensions affichées des images, en tenant compte de leur orientation EXIF. La présence
de ces scénarios ne vaut pas résultat : leur exécution CI doit être verte.
Android cible un unique émulateur prêt et refuse tout appareil USB ou non
autorisé ; Metro reste sur localhost via le port ADB inversé.

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

L’audit npm du 26/10/2026 signale deux dépendances transitives de l’outillage Expo
CLI : node-forge (GHSA-86w9-cpqp-85rv) et zod (GHSA-mrhx-c7xc-m3w5).
Le registre ne fournit pas de correction node-forge compatible publiée à cette
date ; ne pas appliquer la rétrogradation Expo 44 suggérée par npm audit fix
--force. Ces composants d’outillage ne sont pas importés par les écrans natifs ;
aucune signature OTA n’est utilisée. Réévaluer les versions avant une livraison.

Sources de l’architecture : [Expo SDK 57](https://docs.expo.dev/versions/v57.0.0/),
[React Native](https://reactnative.dev/docs/intro-react-native-components),
[Auth Supabase React Native](https://supabase.com/docs/guides/auth/quickstarts/react-native).
