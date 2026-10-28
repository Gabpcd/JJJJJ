# État de la migration native

Ce registre sépare le code porté de sa validation. Le client Capacitor publié
reste distinct. Aucune modification de ce dossier n’effectue une livraison mobile.

## Premier lot intégré — PR #1091

Les parcours synthétiques ci-dessous ont passé les simulations iPhone, Android,
iPad portrait et paysage du [run 40494914146](https://github.com/Gabpcd/JJJJJ/actions/runs/40494914146)
sur le commit `7e7439c`, fusionné dans `main` par `3e02d55`. Les captures et arbres
d’accessibilité ont été relus. Cette preuve appartient à ce commit ; elle ne vaut
pas recette des ajouts Documents et Contrats.

| Domaine | Implémentation | Preuve requise avant conclusion |
| --- | --- | --- |
| Navigation et exploration | Onglets, piles natives, liste/détail, filtres | Simulation acquise ; non-régression à rejouer à chaque nouveau lot |
| Inscription | Email, confirmation PKCE, reprise du brouillon, formulaires soignant/établissement | Simulation médecin/interne acquise ; connexion et finalisation STAGING réelles encore à vérifier |
| Session et périmètres | SecureStore, rôle serveur, permissions établissement, invalidation à la déconnexion | Tests de concurrence ; vérification STAGING avec deux comptes et membre à accès réduit |
| Candidature | Planning confirmé, choix de contrat, refus et relecture ; mes missions | Simulation fictive acquise ; mutation et conséquences backend STAGING encore à vérifier |
| Profil soignant | Lecture/édition limitée aux coordonnées et présentation ; identité vérifiée verrouillée | Simulation et relecture acquises ; écriture STAGING encore à vérifier |
| Établissement | Profil, permissions, liste et détail des missions en lecture | Simulation acquise ; périmètre d’accès STAGING réel encore à vérifier |

Des essais iPhone antérieurs ont échoué sur le retour et le passage en arrière-plan.
Le run final franchit ces étapes sans retrait d’assertion. La collecte de diagnostics
est conservée ; ce passage ne démontre pas à lui seul la cause de ces échecs intermittents.

## Lot Documents et Contrats en préparation — 27 octobre 2026

| Domaine | Implémentation intégrée | Preuve encore requise |
| --- | --- | --- |
| Documents soignant | Dossier, exigences existantes, fichier/galerie/caméra, ajout/remplacement, analyse, revue humaine, archivage et original privé | Simulations des quatre formats ; permissions système et fichiers natifs réels ; opérations Storage/RPC STAGING et conséquences relues |
| Reprise documentaire | Reçu SecureStore avant envoi, confirmation par relecture, réconciliation sans renvoi, invalidation et purge des copies à la fin de session | Scénario synthétique d’envoi incertain ; redémarrage et changement de compte en intégration STAGING |
| Contrats soignant/établissement | Liste selon le périmètre serveur ; original HTML comparé à Storage et à son empreinte ; rendu natif strict, sans WebView ni régénération | Simulations des quatre formats ; originaux réels STAGING et refus des formats non pris en charge |
| Signature du contrat | Consentement lié à la révision affichée, OTP et signature via les RPC existantes, admission TEST, relecture après résultat incertain | Scénario synthétique ; droits réduits STAGING ; demande et validation du SMS chez le fournisseur TEST et preuve de signature serveur |

Deux workflows distincts préparent quatre jobs frais chacun (iPhone, Android,
iPad portrait et paysage). Documents exige neuf captures par format, Contrats
huit (neuf sur iOS avec la preuve Home). Sur `9de851f`, Consultation et tous
les contrôles web passent ; Documents et Contrats passent sur Android.
Les trois formats iOS Contrats échouent à la saisie : six événements de touche,
un seul changement du texte et un chiffre conservé. Le champ reste actif et
modifiable. La sonde, exécutée seulement après avoir enregistré l’échec, obtient
six chiffres par six appuis visibles ; elle ne valide pas le scénario et ne signe
rien. La cause de cette différence reste à déterminer.

Documents iOS a subi deux annulations du contact par BackBoard (« digitizer did
disappear », iPhone et iPad portrait) et un téléchargement Expo Go interrompu
avant installation (iPad paysage). Une reprise ciblée à code inchangé est en cours.
Aucun changement du bouton ni assouplissement de ses assertions n’est justifié par
ces interruptions système. Les preuves initiales restent conservées.

Ce lot reste non validé. Une comparaison avec le même parcours dans le client
compilé pour simulateur est en préparation, sans remplacer les contrôles Expo Go.
Les diagnostics opt-in ne capturent que longueurs, positions et états ; ils ne
constituent pas une correction. Ces résultats de PR ne signifient pas que `main`
est vert ni que le client publié a changé.
Les tests purs utilisent des transports injectés.
Les scénarios n’envoient aucun fichier réel ni SMS et ne signent aucun contrat réel.
Les diagnostics de navigation et d’échec iOS du premier lot restent actifs en CI démo.

L’intégration authentifiée vise uniquement le projet STAGING autorisé. Il n’existe
aucun repli automatique vers la production. Les autorisations et l’admission TEST
du backend restent nécessaires ; leur vérification réelle est distincte de la démo.

## Parcours restant à porter

- Vérification RPPS et identité DPAE ; écrans de revue documentaire réservés aux gestionnaires.
- Préparation employeur et génération du contrat ; les originaux signés ne sont pas réécrits par le client natif.
- Pointage rotatif, GPS, interruptions, validation et contestation des présences.
- Revenus, factures/avoirs archivés, mandat, Stripe Connect et paiements établissement.
- Publication/modification des missions, sélection des candidatures et annulations.
- Messagerie, notifications, préférences et enregistrement des jetons push natifs.
- PSC, récupération/modification du mot de passe, gestion et suppression du compte,
  challenge anti-bot selon configuration Auth.
- Autres fonctions établissement (équipe, RH, réclamations, évaluations, export paie).

Aucun code Pointage préparé séparément n’est intégré à ce lot.

Le parcours interne reste à compléter : spécialité de licence vérifiée, matching
exclusif, acceptation explicite des internes par l’établissement et présentation
de cette preuve dans la candidature. Sa préparation séparée n’est pas intégrée.

Le pilote accepte seulement les modes démo et STAGING et utilise l’identifiant
`app.jolene.nativepilot`. Le raccordement contrôlé à la production et la transition
vers l’identité de l’app publiée restent à préparer après la recette, avant une
livraison mobile distincte.

Les outils d’administration restent accessibles sur le web ; ils ne sont pas
représentés par des boutons natifs non fonctionnels. Les calculs de paie,
commissions, droits et vérifications restent ceux du backend existant.

## Niveaux de preuve

1. Les tests de logique utilisent des réponses injectées et ne prouvent pas les RPC déployées.
2. Les simulations Expo Go utilisent exclusivement des données fictives.
3. L’intégration STAGING doit relier les actions natives aux objets réellement persistés.
4. Les signatures SMS, emails et mouvements Stripe se vérifient avec les fournisseurs TEST.
5. Le contrôle physique utilise l’iPhone uniquement quand le parcours est prêt à essayer.

La réussite d’un lot ne signifie pas que tous les parcours natifs sont terminés.


La reprise des envois Documents conserve désormais un reçu versionné : phase
avant enregistrement, arguments exacts et justificatif antérieur. La relecture
cherche aussi les versions archivées. Un envoi prouvé sans enregistrement peut
être clos localement, sans supprimer son objet privé. Un enregistrement incertain
n’est jamais renvoyé automatiquement ; sa reprise explicite réutilise la même clé
et vérifie la classe de justificatif courante. La RPC existante ne fournit pas de
comparaison atomique avec le justificatif antérieur : un changement concurrent
ultérieur à la dernière lecture reste soumis aux règles de remplacement serveur.
Les anciens reçus sans métadonnées ne permettent pas cette reprise. La consultation
et les demandes de revue restent accessibles pendant cette vérification.

Le scénario Contrats conserve le contrôle d’un établissement en lecture seule,
puis fait signer un établissement autorisé après le soignant. Les deux signatures
synthétiques sont relues sur le même original ; huit captures sont attendues par
format. Ces prolongements nécessitent encore leur simulation CI sur ce commit.

Le scénario Documents inclut aussi l’arrêt synthétique avant enregistrement :
la relecture clôture le reçu, conserve le justificatif courant et réactive son
remplacement (neuvième capture). La reprise RPC explicite demeure couverte par
les transports injectés ; sa vérification authentifiée STAGING reste requise.
