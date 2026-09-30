# Garde initiale du résolveur — revue auteur

Défaut établi par catalogues LIVE, sans invocation métier : le résolveur intelligent lit le type du litige avant autorisation. Une requête AUCUNE par un utilisateur non administrateur distingue un litige salarié d'un litige libéral/absent grâce aux erreurs différentes des résolveurs. Aucune résolution non autorisée n'a été démontrée.

Le nouveau corps provient de `pg_get_functiondef` LIVE. Son unique différence est le refus `{success:false,error:"Administrateur requis."}` lorsque `auth.uid()` est NULL ou `est_admin()` n'est pas vrai, placé avant toute lecture métier et validation d'action. Le reste du corps est identique octet par octet. Les arguments, le routage, les résolveurs, leurs gardes (dont celles des branches financières), calculs et ACL restent inchangés. Le test reconstruit aussi le corps LIVE depuis les migrations du 08/08 et 03/09. Aucun contournement AAL2 n'est introduit, ni appel fournisseur.

La migration refuse toute empreinte, propriétaire, search_path ou ACL inattendus avant remplacement. L'inventaire n'accepte pas l'ancien corps vulnérable : il référence uniquement le corps corrigé `5a13493bf67426d968d0d75aad16b86c` et refuse un précédent inventaire divergent. Cette entrée reste distincte du premier commit portant sur onze métadonnées.

Contrôles de l'auteur : 17 tests Node réussis ; parsing complet SQL et PL/pgSQL des migrations et suites par pglast ; TypeScript sans émission réussi ; diff sans erreur d'espacement. Ce document ne constitue pas une revue indépendante.

Suite SQL ajoutée et raccordée à la CI : fixtures synthétiques salarié/libéral, trois statuts de litige, UUID absent, cinq identités (sans identité, soignant, établissement, claim admin sans équipe et équipe inactive), quatre actions dont une invalide. Tous les 140 appels doivent retourner exactement le même refus. L'admin valide traverse les deux routes mais s'arrête sur une résolution trop courte avant toute résolution ; une clé service sans identité reste refusée. Aucun litige ne doit changer et l'inventaire doit correspondre au nouveau corps. La transaction finale annule les fixtures. **Exécution réelle SQL encore attendue en staging CI**, pas de serveur PostgreSQL local disponible ; le parsing ne prouve pas les contraintes/triggers des fixtures.

Simulation frontend : dix scénarios réussis (salarié et libéral sur iPhone/WebKit, Android/Chrome, iPad portrait et paysage/WebKit, ordinateur/Chrome). Saisie, refus sans faux succès, conservation de la décision, réessai explicite, succès simulé puis onglet Résolus après rechargement ; exactement deux appels mock, aucun appel implicite au reload, aucune requête externe/inconnue ni erreur JS. Captures iPad inspectées. Les composants admin du build réutilisé sont identiques à la base de ce lot ; aucun code frontend modifié. Ce résultat ne prouve ni une résolution SQL réelle ni un mouvement financier, et ne représente pas des appareils physiques.

Première tentative ordinateur : deux échecs du sélecteur Fermer, qui désignait à la fois le bouton du formulaire et la croix du dialogue. Sélecteur précisé, sans changement produit ni attente artificielle ; les artefacts initiaux sont conservés dans `/private/tmp/jolene-litige-garde-recette-ordinateur`. Preuves finales : `/private/tmp/jolene-litige-garde-recette-5formats/results.json` et captures/ARIA voisines. Le binaire agent-browser étant absent, Playwright installé a effectué la vérification ; aucune dépendance installée.

À confirmer avant intégration validée : revue indépendante et CI SQL réelle (dont la création des fixtures sous les triggers actuels). Aucune modification distante, push, revue CLI, merge ou livraison mobile effectués dans ce lot.

Complément d’intégration : le run `36697713126` a validé les suites précédentes,
dont la clôture, puis refusé la fixture litige sur `chk_type_contrat_recherche`.
Le catalogue staging confirme `TOUS`, `SALARIE`, `LIBERAL` pour une mission ;
`MIXTE` décrit le profil, pas ce champ mission. Les six missions synthétiques
utilisent désormais le même mode recherché que leur mode appliqué. La contrainte
et le code produit restent inchangés. Les assertions de cette suite sont encore
à exécuter ; la transaction échouée a été annulée.
