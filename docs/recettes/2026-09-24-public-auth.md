# Recette publique et authentification — 24 septembre 2026

Le frontend réel a été exécuté avec une API simulée stricte : **60/60 scénarios réussis**, 12 par format (iPad portrait WebKit 820×1180, iPad paysage WebKit 1180×820, iPhone WebKit 390×844, Android Chromium 412×839 et ordinateur Chromium 1440×900). Aucun retry ni scénario ignoré. Résultats locaux : `/private/tmp/jolene-recette-preuves-20260924/public-final/results.json`. Build statique `http://127.0.0.1:8891` ; les fichiers produit concernés sont identiques dans le build final.

## Parcours couverts

- Dix-neuf routes publiques, marketing et légales : titre attendu, absence de débordement horizontal, retour depuis une URL inconnue.
- Mission publique : description et rémunération, inscription au clic, distinction mission clôturée / indisponibilité réseau 503 et nouvelle tentative.
- Centre d’aide et trois alias : recherche, filtre de public, aucun résultat, article et retour ; erreurs de liste et d’article récupérables. Un compte connecté peut sélectionner « Tous » sans que son rôle reprenne la main.
- Connexion : erreurs françaises, affichage du mot de passe, lien de récupération, normalisation de l’email et délai avant nouvel envoi ; redirection des routes protégées sans session.
- Réinitialisation : lien valide et invalide, confirmation différente, correction du champ et mise à jour simulée, sortie de session. Confirmation email : retour effectif à la connexion ; statuts d’email établissement et retour Pro Santé Connect annulé.
- Inscription soignant et établissement : refus de mot de passe faible en français, conservation des champs. Les créations réussies et l’accès métier sont couverts dans les inventaires de chaque rôle.
- Contact : échec réseau, conservation de la saisie, réussite à la nouvelle tentative et nombre exact d’appels simulés.

## Défauts reproduits puis corrigés

1. Mission publique : une erreur serveur était présentée comme une mission clôturée. État d’erreur explicite, bouton de reprise, délai maximal et annulation des réponses obsolètes.
2. Aide : des échecs de chargement ressemblaient à une recherche vide ou à un article supprimé. Les erreurs deviennent visibles et récupérables.
3. Aide : la réponse d’une recherche tardive pouvait réécrire l’URL après l’ouverture d’un article et ramener l’utilisateur à la liste. La synchronisation de l’URL est indépendante de la réponse.
4. Aide connectée : le filtre « Tous » était réinitialisé au rôle du compte. Le rôle ne fournit maintenant que le choix initial.
5. Confirmation email : le bouton de retour déconnectait sans changer de page. Il ouvre maintenant la connexion.
6. Réinitialisation : l’erreur de confirmation modifiait le nom accessible du champ. Les libellés sont associés par identifiants stables ; les erreurs sont des descriptions accessibles distinctes.

## Preuves et limites

Les assertions portent sur le DOM, les transitions, les appels simulés et les instantanés ARIA attachés aux résultats. Les erreurs JavaScript et les API non prévues font échouer les tests. Les destinations externes et les WebSockets sont bloqués ; aucune inscription, aucun email, aucun contact réel n’a été envoyé. Les réponses d’authentification sont simulées : ces tests ne certifient ni la délivrance des emails, ni les fournisseurs PSC, ni les politiques SQL/RLS. Ils complètent les tests d’intégration existants.

Fichiers : `e2e/recette-complete-public.spec.ts` et `e2e/helpers/recette-complete-public.ts`. Les scénarios sont inclus dans la nouvelle matrice CI `Simulation interfaces`, séparée des E2E réels.
