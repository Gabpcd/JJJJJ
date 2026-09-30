# Validation SQL des PR et état persistant du staging

Le job `Migrations + sécurité SQL (transaction annulée)` de `validate-pr.yml`
sépare deux opérations :

1. Synchroniser durablement le staging autorisé avec les migrations du commit
   `BASE_SHA` de main, depuis un worktree exact et non modifié.
2. Appliquer les migrations **ajoutées par la PR** et leurs régressions dans
   `BEGIN … ROLLBACK`, avec savepoints entre suites. Le succès vérifie ces
   opérations ; il ne déploie pas le schéma de la PR pour les autres clients.

Les fichiers de migration de la PR ne doivent jamais être copiés dans le
worktree du bootstrap. Sinon `supabase db push` les applique avant le rollback,
expose leurs nouvelles RPC et fait éventuellement échouer leur second passage
sur une création de table non idempotente.

Avant le bootstrap, le contrôle lit uniquement les versions du registre
staging. Si une version n'appartient pas à la base main, il s'arrête avant
`CREATE EXTENSION`, `supabase link` et `supabase db push`. Cela couvre une PR
déjà appliquée sur le staging et un staging avancé depuis la création du run.
Actualiser la base de la PR ou faire réconcilier l'environnement après revue :
ce contrôle ne supprime rien et n'exécute ni reset ni migration repair.

Le registre ne prouve pas, à lui seul, l'absence de DDL manuel non enregistré.
Les contrôles de drift existants et la revue du schéma restent distincts.

Les modifications/suppressions/renommages de migrations déjà présentes dans
main sont refusés. Il faut ajouter une nouvelle migration ; modifier un
fichier déjà suivi ne ferait pas rejouer son SQL et produirait une validation
incomplète. Les collisions de version sont également refusées.

`staging-comptes.yml` continue d'attendre le succès du job SQL avant ses parcours
via les services existants du staging. Cette attente confirme la validation
transactionnelle, pas la disponibilité durable des nouvelles RPC de la PR.
Un parcours dépendant d'un nouveau schéma ou une recette réellement concurrente
nécessite un environnement isolé ou un déploiement de test explicitement prévu.

## Vérification hors réseau

```sh
node --test tests/node/staging-migration-base.node.mjs
```

Les tests exécutent les blocs shell réels du workflow dans un dépôt Git
temporaire. Les transports Supabase/API sont simulés : la migration main en
attente seule est persistée par le faux CLI ; le `CREATE TABLE` non idempotent
de la PR est envoyé une fois dans la transaction annulée. Les tests vérifient
aussi l'arrêt sans écriture sur version distante hors base, historique modifié,
registre invalide, cible production, secret manquant et worktree contaminé.

Cette simulation ne prouve pas l'exécution du SQL sur PostgreSQL ou le résultat
de la CI distante. Le changement concerne la validation CI ; il ne modifie
aucun écran ni contrat produit et ne constitue pas une recette frontend.
