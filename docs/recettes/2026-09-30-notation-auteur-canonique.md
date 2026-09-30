# Notation : identité canonique, liste et preuve transactionnelle

Lot issu de la lecture de `fn_creer_notation_mission` en production le 30 septembre 2026. Aucun appel métier ni SQL de mutation distant n'a servi au diagnostic.

## Défauts confirmés

La garde établissement utilisait `mission.etablissement_id <> mon_etablissement_id()`. Un utilisateur authentifié sans établissement obtenait NULL : le IF ne refusait pas, puis `COALESCE` attribuait la note à l'établissement de la mission. Le contrôle arrivait aussi après les lectures de statut, présence et litige. Le rôle admin reste celui validé par `est_admin()`/`est_admin_valide()`, jamais un simple claim.

La liste à noter comparait `notations_missions.notateur_id` à l'UID du membre, alors que l'auteur d'une note établissement est l'établissement canonique. Une mission déjà notée pouvait donc être proposée de nouveau au membre.

Les tests API historiques masquaient par un skip une erreur de colonne (`soignants.user_id`) et tentaient un seed partagé avec des champs de notation périmés. Le commentaire « rollback » désignait en réalité des DELETE, hors transaction.

## Périmètre du correctif

- `20260930145136` : compte actif, identité métier et tenant avant lecture de mission ; appartenance filtrée avec comparaisons NULL sûres ; refus uniforme mission tierce/absente ; auteur établissement égal à celui de la mission, y compris pour un admin valide sans tenant. Le sens NULL est refusé explicitement.
- `20260930145933` : exclusion des notes du tenant canonique dans la liste, fenêtre de 60 jours inchangée.
- Aucune modification de GRANT, des critères, du seuil tardif de 30 jours, de la publication réciproque ou du cron de publication différée. Aucun contrat, paiement, profil professionnel ou règle juridique modifié.
- Formulaire établissement : un refus reste annoncé dans le dialogue (`role=alert`), sans toast extérieur qui ferme la modale lors de son retrait. Les notes/commentaires sont conservés pour le réessai, les envois restent désactivés pendant la requête et le succès existant est conservé. Erreurs réseau et session expirée sont traduites, y compris lorsque Supabase les renvoie dans `error`.
- Les deux préflights refusent tout corps ou ACL inattendu. Seules les deux entrées exactes d'inventaire sont actualisées, avec des empreintes littérales.

| Fonction | OID LIVE observé | MD5 source LIVE | MD5 cible |
| --- | --- | --- | --- |
| `fn_creer_notation_mission(uuid,text,integer,integer,integer,integer,text)` | 58514 | `de8b4925694aa624a8e45c22e47416b0` | `430c4e6bb8dce83da949ba41642f3590` |
| `fn_lister_missions_a_noter_etab()` | 59809 | `4feea9884817ca0d5a702700d6f36fbd` | `0b3bff2c5588245287087d681698c2c9` |

ACL observée et conservée : propriétaire postgres ; EXECUTE postgres, authenticated, service_role ; ni PUBLIC ni anon. Les deux fonctions sont SECURITY DEFINER. L'OID est une preuve de lecture, pas un identifiant imposé à staging.

## Preuve métier préparée

`tests/security/notation-reverse-transactionnelle.test.sql` appelle les vraies RPC sous `SET LOCAL ROLE authenticated` avec des claims de fixtures : tiers soignant, membre d'autre établissement, profil absent avec rôle NULL, claim admin sans équipe, UID inexistant, UID NULL, propriétaire, membre RH et membre ayant aussi son propre établissement, admin réellement validé sans tenant. Le test conserve les triggers. Le membre RH représente le prescripteur existant ; aucune valeur « PRESCRIPTEUR » n'est ajoutée au schéma.

Les refus sont comparés sur mission terminée, en cours, ouverte, sans soignant, absente et NULL. Le test vérifie la liste avant/après notation, l'auteur et la cible, le doublon refusé, la note cachée au destinataire avant réciprocité (RLS et RPC), la publication simultanée, la lecture des deux côtés, le refus d'un tiers et le signalement par la cible. Fermeture publique, suspension Auth et révocation d'un membre restent refusées.

Les identifiants et emails `example.invalid` sont synthétiques. Les missions sont insérées directement avec des dates futures pour respecter le trigger interdisant la publication passée ; ce seed ne prétend pas représenter une clôture réelle. Aucune transition de statut, acceptation, contrat ou paiement n'est déclenchée. L'INSERT Auth n'a aucun trigger utilisateur LIVE ; son seul trigger observé est AFTER DELETE. Les profils sont marqués test. Les branches de notification urgente/absence ne s'appliquent pas ; aucun favori ne référence le nouveau tenant. Les triggers de notation recalculent seulement les scores/audits internes des fixtures. Le mandat SEPA reste NULL ; la branche du tripwire ne s'exécute pas.

Le sous-bloc finit par la seule sentinelle `ZN501` et annule fixtures, scores, audits et files dans la transaction. Toute autre erreur remonte. Des assertions après sentinelle vérifient l'absence des objets. Aucun DELETE de nettoyage ni purge d'audit. La publication globale à J+7 n'est pas invoquée par la recette.

## Niveaux de validation

- Parsing SQL **et PLpgSQL** complet des deux migrations et du test : vérifié localement avec pglast 7.10. Le parsing n'est pas une exécution PostgreSQL ; la relecture a notamment corrigé un cast explicite vers `public.statut_mission` dans le seed.
- `tsc -b` et typecheck isolé des deux specs notation : vérifiés localement. Neuf tests unitaires ciblés passent (six modale : refus/réessai, double clic, exception réseau, deux erreurs Supabase renvoyées, réponse vide ; trois tests existants BoutonNoterMission). Les warnings Radix de description absente, antérieurs au delta, restent visibles et non filtrés.
- Tests API partagés : trois contrôles sans mutation (refus sans UID de la liste, colonnes sur UUID sentinelle absent, refus du signalement sans UID avant lookup). Toute erreur SQL échoue. Le seul skip conservé est l'absence de credentials. Non exécutés localement sur la base partagée.
- SQL comportemental : à exécuter par la CI staging sous transaction annulée ; aucun résultat SQL vert revendiqué avant ce run.
- Simulation frontend : `e2e/recette-complete-notation-autorisation.spec.ts`, deux rôles, cinq formats, réponses fictives ; refus visible, formulaire conservé, réessai explicite, succès, état après rechargement et absence de double RPC. Matrice finale : **10/10**, sans skip ni retry, en 21,6 s (30/09/2026, démarrage 15:17:36 UTC), sur preview compilée loopback18464 ; `errors`, `unknown`, `external` et erreurs de console sont vides dans les dix journaux. Les profils frontend réutilisent la fixture médecin libéral, ceux du SQL sont salariés : aucun des deux niveaux ne prétend prouver un paiement ou une facture.

La simulation ne prouve pas les autorisations SQL ; la CI SQL ne prouve pas le rendu sur un appareil physique. Aucun appareil physique, fournisseur, SMS ou paiement n'est exercé dans ce lot.

## Incidents de recette conservés

Le premier lancement ordinateur en sandbox a échoué avant toute page : deux erreurs `MachPortRendezvous… Permission denied (1100)`, durée de test 0 ms. La reprise utilise les navigateurs locaux autorisés hors sandbox. Ce n'est pas un défaut applicatif.

La première matrice sur preview compilée a été arrêtée après quatre échecs et un test interrompu (cinq non exécutés). Deux échecs établissement sur iPad ont montré qu'un clic sur la fermeture du toast externe fermait aussi le dialogue, perdant la saisie. Deux échecs soignant provenaient de lectures mock manquantes (`fn_score_etab_public`, `fn_user_id_pour_etablissement`), avec erreurs 501 détectées par les contrôles conservés. Le parcours soignant lui-même avait atteint le succès et le rechargement. Aucun échec n'a été supprimé ni reclassé en succès ; aucun retry automatique ou filtre de console ajouté.

Preuves initiales conservées sous `/private/tmp/jolene-notation-ui-20260930/ordinateur` et `matrice-v1`. La deuxième matrice (`matrice-v2`) a terminé les actions des dix parcours, mais les dix tests sont restés rouges sur une CSS Google Fonts absente des mocks : les requêtes étaient bloquées avant réseau, avec erreurs de console sur Chromium. Une interception explicite renvoie désormais une CSS vide locale ; les gardes réseau/console restent inchangées. La matrice finale verte utilise `matrice-v3` et une nouvelle compilation de la source corrigée sur loopback18464. L'espace a été surveillé ; au constat 119 MiB, les navigateurs ont été suspendus jusqu'au rétablissement de la marge. Aucune erreur ENOSPC dans les essais de ce lot.

## Reproduire et consulter les preuves

```sh
node_modules/.bin/vitest run src/components/etablissement/ModaleEvaluerSoignant.test.tsx src/components/BoutonNoterMission.test.tsx
node_modules/.bin/tsc -b --pretty false
RECETTE_RESULTS_DIR=/private/tmp/notation-resultats PLAYWRIGHT_BASE_URL=http://127.0.0.1:18464 node_modules/.bin/playwright test --config=e2e/playwright.recette-complete.config.ts e2e/recette-complete-notation-autorisation.spec.ts
```

La preview doit être compilée avec API loopback et clés fictives ; cette configuration de simulation n'exécute aucun setup Auth distant. Le SQL est raccordé par `validate-pr.yml` au runner transactionnel staging, distinct de ces simulations.

Preuves durables compactes : workspace Jolene `audits/2026-09-30-preparation-nationale/preuves/notation-autorisation/` (reports, validation, captures représentatives, patch et manifeste SHA256). Les traces initiales restent dans `/private/tmp/jolene-notation-ui-20260930/` ; elles ne sont pas recopiées. Relecture croisée de l'agent `revue_export_201` : aucun P1/P2 restant sur migrations/SQL et interface, six tests modale rejoués verts ; cette lecture ne remplace pas la revue B8 à contexte vierge.

## Correction de fixture après exécution SQL réelle

Le run de validation `36741233648` sur `dc0457af` a refusé correctement l’appartenance d’un compte de famille ADMIN à un établissement (`23514`, `fn_protect_famille_compte_membre_etablissement`). Ce scénario de préparation était incompatible avec les gardes existantes, avant les assertions de notation. La fixture emploie désormais un vrai administrateur sans tenant, vérifie explicitement cet état et conserve l’assertion d’auteur canonique de la mission. Les membres RH, membre avec établissement propre, refus tiers et contrôles de rollback restent inchangés. Aucun trigger ni garde produit n’est modifié.
