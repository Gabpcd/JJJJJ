# Recette escrow 7b-D — rapport d'exécution (Lot 10 §3)

> 04/07/2026. Tentative d'exécution de la recette escrow sur environnement de
> test isolé (branche Supabase preview éphémère), conformément au choix §3.

## Verdict : STOP — recette NON exécutable en l'état

**La recette escrow ne peut pas être exécutée sur un environnement de test tant
que le squash baseline 9.0 n'est pas fait.** Conséquence directe (règle §6.2 de
Gabrielle) : **zéro scénario en PASS → aucun flip du flag `feature_paiement_rapide_actif`.**

## Ce qui a été tenté et observé

1. Création d'une branche Supabase preview (`recette-escrow-lot10`,
   ref `mufvsanasmpnnvachgaa`, 0,013 $/h). Une branche applique **toutes les
   migrations du repo** sur une base neuve.
2. Résultat : **`MIGRATIONS_FAILED`**. État de la branche :
   - `public` : **0 table** (aucun objet métier créé).
   - `supabase_migrations.schema_migrations` : 197 versions enregistrées,
     dernière = `20260417130723_fix_t20_audit_cloture_amiable`.
   - Aucune table escrow, aucune fonction `fn_escrow_*`.
3. Branche détruite immédiatement (coût arrêté).

## Cause racine — confirmation spectaculaire du diagnostic 9.0

Les migrations du repo sont des **patchs** (`fix_t20_*`, `fix_bonus_*`,
`ALTER TABLE`, `CREATE OR REPLACE FUNCTION`…) qui **présupposent un schéma
préexistant** — celui créé par Lovable **hors migrations** en avril, puis
seulement *enregistré* en bulk dans `schema_migrations` (cf. commentaire
`deploy-supabase.yml` : « les 141 versions Lovable insérées en bulk »). Sur une
base **vierge**, les tables de base n'existent jamais → les patchs échouent →
0 table.

C'est précisément ce que `docs/DRIFT_AUDIT.md` documentait (184 objets prod
absents du repo). La branche le **prouve** : **le repo ne reconstruit pas la
base depuis zéro.** Aucun environnement neuf (branche, nouveau projet, shadow DB
de CI) ne peut donc porter le schéma escrow aujourd'hui. Le seul environnement
qui a le schéma escrow est la **prod** (flag=0) — sur laquelle on ne crée pas de
flux financiers de test (garde-fou).

## Débloquer : le squash baseline 9.0 (étape 3, désormais PROUVÉE nécessaire)

Le plan 9.0 prévoyait déjà cette étape, non encore faite :

1. Faire du dump prod versionné `supabase/schema/public.sql` (déjà committé,
   #800) la **migration initiale** d'un repo squashé.
2. Déplacer les ~250 migrations historiques de patchs vers `_archive/`.
3. Enregistrer la migration initiale comme déjà-appliquée pour la prod
   (`schema_migrations`) pour que `deploy-supabase` reste un no-op sur prod.
4. Vérifier qu'une branche neuve applique la migration initiale et obtient un
   schéma **complet** (shadow DB diff vide).

Une fois squashé, une branche preview porte le schéma complet → cette recette
escrow devient exécutable (machine à états SQL + legs Stripe).

## Rappel du périmètre de la recette (pour quand l'env sera dispo)

- **Legs SQL** (déterministes, exécutables sur branche squashée) : création
  escrow à la confirmation, plafond §11.1, gel/déblocage, trigger de release,
  décisions de remboursement A5/A6, exposition. Cf. `scripts/recette-escrow.ts`.
- **Legs Stripe** (destination charge / payout / dispute / webhook round-trip) :
  nécessitent en plus les edge functions déployées sur la branche avec clés test
  + endpoint webhook de test. Reste à câbler.

## Décision produit ouverte

Le flip ⚡ n'est **pas** un prérequis de la soumission stores : le plan Lot 9
prévoyait explicitement « soumettre sans attendre l'escrow, ⚡ éteint ». Deux
chemins :

- **A. Squash baseline maintenant** → recette escrow → flip, puis stores.
- **B. Stores d'abord, ⚡ éteint** (flag=0) → squash + recette + flip post-launch.

Recommandation : **B** pour ne pas retarder la soumission (le flip est
réversible et gaté), en planifiant le squash 9.0 juste après. À trancher par
Gabrielle.
