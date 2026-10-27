# État de la migration native

Ce registre sépare le code porté de sa validation. Le client Capacitor publié
reste distinct. Aucune modification de ce dossier n’effectue une livraison mobile.

## Lot en cours — 27 octobre 2026

| Domaine | Implémentation | Preuve requise avant conclusion |
| --- | --- | --- |
| Navigation et exploration | Onglets, piles natives, liste/détail, filtres | Simulations iPhone, Android, iPad portrait/paysage et captures relues |
| Inscription | Email, confirmation PKCE, reprise du brouillon, formulaires soignant/établissement | Simulation médecin/interne ; connexion et finalisation STAGING réelles encore à vérifier |
| Session et périmètres | SecureStore, rôle serveur, permissions établissement, invalidation à la déconnexion | Tests de concurrence ; vérification STAGING avec deux comptes et membre à accès réduit |
| Candidature | Planning confirmé, choix de contrat, refus et relecture ; mes missions | Simulation fictive ; mutation et conséquences backend STAGING encore à vérifier |
| Profil soignant | Lecture/édition limitée aux coordonnées et présentation ; identité vérifiée verrouillée | Simulation et relecture ; écriture STAGING encore à vérifier |
| Établissement | Profil, permissions, liste et détail des missions en lecture | Simulation et périmètre d’accès STAGING réel |

Le connecteur Supabase accessible au début de ce lot n’expose que le projet de
production. L’accès au projet STAGING doit être confirmé avant la recette
authentifiée. Il n’existe aucun repli automatique vers la production.

## Parcours restant à porter

- Vérification RPPS, documents privés, caméra, revue humaine et identité DPAE.
- Contrats, préparation employeur et signature OTP du document serveur.
- Pointage rotatif, GPS, interruptions, validation et contestation des présences.
- Revenus, factures/avoirs archivés, mandat, Stripe Connect et paiements établissement.
- Publication/modification des missions, sélection des candidatures et annulations.
- Messagerie, notifications, préférences et enregistrement des jetons push natifs.
- PSC, récupération du mot de passe, challenge anti-bot selon configuration Auth.
- Autres fonctions établissement (équipe, RH, réclamations, évaluations, export paie).

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
