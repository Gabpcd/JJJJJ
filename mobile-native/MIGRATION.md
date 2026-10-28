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

### Stabilisation iOS — 28 octobre 2026

Les derniers contrôles produit sur `9d311d8` comptent 52 succès, six échecs et
quatre contrôles sautés. Consultation native et les simulations web passent ;
Documents et Contrats passent sur Android, Documents aussi sur iPad paysage.
Les captures de ces réussites ont été relues. Ce commit n'est pas validé ni fusionné.

Les échecs restants sont conservés : entrée démo annulée par BackBoard sur
Documents iPad portrait et Contrats iPhone Expo ; retour Documents→Profil annulé
sur iPhone ; saisie de six chiffres réduite à un sur Contrats iPad portrait et
client iPhone compilé, à trois sur iPad paysage. La cause des interruptions de
navigation reste ouverte. La sonde de clavier exécutée après un échec ne valide
jamais le scénario et ne poursuit pas vers la signature.

Le témoin UIKit sans React Native conserve les six chiffres. Une comparaison
React Native compilée depuis les sources, avec la même entrée, le même XCTest et
le même verrou, a ensuite été exécutée dans le
[run 40692122474](https://github.com/Gabpcd/JJJJJ/actions/runs/40692122474),
SHA diagnostic `5cd1676` :

| Variante iPhone | Champs contrôlé stylé / non contrôlé stylé / contrôlé simple | Verdict |
| --- | --- | --- |
| RN0.86.3 original | 6 / 2 / 6 chiffres conservés | 1 échec réel, sans expiration |
| RN0.86.3 avec correctif épinglé | 6 / 6 / 6 chiffres conservés | 1 réussite |

Les douze captures avant/après et leurs arbres d'accessibilité ont été relus.
Les champs sont visibles au-dessus du clavier. Le run diagnostic reste rouge
parce que le témoin original échoue ; ce témoin ne fait pas partie de la CI produit.

Le client applique maintenant les trois sources du
[correctif RN59197](https://github.com/react/react-native/pull/59197), révision
`a91468ffe62122bc49d964a08b493374f0af4775`. Cette proposition upstream reste ouverte,
non fusionnée : ce n'est pas une version officielle corrigée. Le postinstall
vérifie les versions verrouillées et les empreintes originales/corrigées ; le
plugin Expo impose une compilation RN depuis les sources. La CI refuse un cœur
précompilé, une autre SHA de checkout ou l'absence des deux objets natifs attendus.

Les trois workflows produit iOS utilisent désormais ce client Debug non signé
sur iPhone et iPad, avec les mêmes scénarios, rôles, assertions et délais par écran.
Le doublon de comparaison iPhone est remplacé par la même exécution dans la
matrice Contrats. La préparation froide du simulateur et l'inventaire Xcode ont
leurs propres plafonds et reçus d'échec. Aucun retry ni délai par écran accru.
Android conserve son hôte existant.

Validation locale de ce delta : 279 tests de logique et TypeScript réussis ; revues
indépendantes favorables du patch, du plugin et de leur composition avec la CI.
Les simulations complètes produit sur la nouvelle révision restent à réussir,
avec relecture des captures, avant de valider ou fusionner ce lot. L'A/B ne prouve
pas IME/AutoFill/secureTextEntry, les signatures réelles ou le bon fonctionnement
de toutes les saisies de l'app. `main` doit être contrôlé séparément après fusion.

Sur `0c93075`, Documents passe aussi sur iPhone et sur les deux orientations iPad.
La consultation iPad échoue encore sur l'ouverture du détail. Une collecte
`sample` a tourné quinze secondes pendant cette transition ; cet outil suspend
le processus échantillonné et peut donc perturber la mesure. Il est retiré de
l'exécution UI. Les événements natifs, captures et diagnostics après échec sont
conservés ; ce retrait ne démontre pas que tout ralentissement est corrigé.

La consultation iPhone a exécuté toutes ses étapes en 654 secondes, mais XCTest
l'a rejetée pour dépassement du plafond global de 600 secondes. Le précédent
passage réussi prenait déjà 592 secondes. Ce scénario regroupant les deux rôles,
la candidature, le profil et l'inscription reçoit un budget global de 900 secondes,
plus 300 secondes pour la finalisation de xcodebuild. Les délais de chaque écran
restent à 15 secondes et Documents/Contrats conservent leurs budgets antérieurs.
Les résultats expirés, incomplets, sautés ou repris après échec restent refusés.

Validation locale de ce dernier ajustement : 273 tests de logique natifs réussis.
Les 11 tests supprimés appartenaient uniquement au collecteur `sample` retiré ;
aucune assertion de parcours n'est supprimée. Les simulations et la revue
indépendante du dernier ajustement restent requises avant fusion.

Les tests purs utilisent des transports injectés. Les scénarios démo n'envoient
aucun fichier réel ni SMS et ne signent aucun contrat réel. Documents exige neuf
captures par format ; Contrats huit sur Android et neuf sur iOS avec la preuve
Home. Les diagnostics opt-in restent bornés et ne conservent pas les codes saisis.

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
2. Les simulations démo (client iOS compilé et Expo Go Android) utilisent exclusivement des données fictives.
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
