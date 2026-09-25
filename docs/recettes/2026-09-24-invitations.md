# Invitation d'équipe — 24 septembre 2026

Les deux scénarios passent sur chacun des cinq formats : **10/10**, sans retry automatique, dans le build statique8897 qui inclut les corrections définitives. Résultat local : `/private/tmp/jolene-invitation-final-v2/results.json`. Le complément ajoute une route publique authentifiée `/etab/invitation/:token` aux31 routes sous `/etablissement` déjà inventoriées.

## Parcours et défauts corrigés

1. Ouvrir une invitation sans session, se connecter, retrouver l'invitation et l'accepter explicitement. Avant correction, la connexion ouvrait directement le tableau de bord et perdait le lien. Le paramètre de retour accepte uniquement la route interne d'invitation, jamais une URL arbitraire.
2. Un nouvel invité ne possède initialement ni rôle métier, ni établissement, ni brouillon d'inscription. Le serveur simulé lui accorde un rôle seulement après l'acceptation. Le cache du rôle est invalidé avant la navigation pour que le rattachement soit relu immédiatement ; aucune permission n'est créée par le frontend.
3. Les refus expiration, adresse email différente, jeton invalide et invitation déjà traitée donnent leur message français. Une panne503 affichait `Service Unavailable` ; elle donne désormais un message français et permet de réessayer sans quitter le lien.
4. Le résultat d'une demande ne doit plus afficher un succès ou ramener au tableau de bord si l'utilisateur a quitté la page, changé de compte ou ouvert une autre invitation. Les réponses et minuteurs obsolètes sont ignorés ; le double clic n'émet pas deux demandes simultanées.

Les deux premiers défauts ont été reproduits avec les scénarios navigateur avant correction. La première recette corrigée utilisait un compte déjà professionnel ; elle a été renforcée pour exercer la transition effective de rôle décrite au point2, puis rejouée10/10.

## Vérifications ciblées

- `PageConnexion.role-resolution.test.tsx` :9 tests verts, dont conservation de l'invitation pour un compte sans rôle et refus de quatre destinations arbitraires.
- `AccepterInvitationEtab.test.tsx` :9 tests verts sur attente Auth, invalidation du cache, double clic, succès/rejet après départ, changement de jeton/compte et annulation de redirection.
- Instantanés ARIA de la confirmation, des quatre refus et de la panne récupérable ; captures iPad incluses dans les résultats Playwright.

L'invitation, la session et l'acceptation sont simulées. Aucun email n'est envoyé, aucun membre réel n'est ajouté. Les contrôles serveur existants de destinataire, expiration et autorisation sont conservés ; leur exécution réelle n'est pas prouvée par ce lot.
