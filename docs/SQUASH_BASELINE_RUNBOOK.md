# Squash baseline 9.0 — runbook d'exécution coordonnée

> Objectif : rendre le repo capable de **reconstruire la base depuis zéro**
> (une branche Supabase neuve doit obtenir le schéma complet). Aujourd'hui
> impossible — les 645 migrations sont des patchs sur un schéma Lovable créé
> hors migrations (prouvé : branche preview 04/07 → `MIGRATIONS_FAILED`, 0 table).
>
> ⚠️ **Opération la plus sensible du repo.** Elle touche
> `supabase_migrations.schema_migrations` en prod — la zone exacte des deux
> incidents du 02/07. **Ne rien exécuter dans le désordre.** Chaque étape a une
> vérification de sortie ; si une vérif échoue, STOP.

## Principe

- `supabase/schema/public.sql` (dump prod versionné, #800) devient l'**unique
  migration initiale** `supabase/migrations/00000000000000_baseline_prod.sql`.
- Les 645 patchs historiques partent dans `db/migrations_archive/` (hors
  `supabase/migrations/`, invisibles du CLI).
- Sur **prod** : le registre est réparé pour ne contenir QUE la version baseline
  (marquée appliquée, sans la rejouer) → `deploy-supabase` reste un no-op.
- Sur une **branche neuve** : le CLI applique la baseline → schéma complet.

## Pré-requis

- Supabase CLI + `SUPABASE_DB_PASSWORD` + `SUPABASE_ACCESS_TOKEN` (je ne les ai
  pas ; cette exécution nécessite la CLI — côté Gabrielle ou CI dédiée).
- Une fenêtre sans autre merge sur `main` touchant `supabase/`.

## Étape 0 — produire le squash localement (sans risque)

```bash
scripts/squash-baseline.sh
```
Ce script (file-ops pures, ne touche aucune base) :
- crée `supabase/migrations/00000000000000_baseline_prod.sql` = copie de
  `supabase/schema/public.sql` ;
- déplace les 645 patchs vers `db/migrations_archive/` ;
- laisse un `db/migrations_archive/README.md` expliquant l'archive.

## Étape 1 — VALIDER la baseline sur une base neuve (AVANT toute prod)

**Le point d'incertitude** : un dump `pg_dump` contient des `ALTER … OWNER TO`,
des extensions, des GRANT qui peuvent échouer sur une base fraîche. Il faut le
prouver AVANT de toucher la prod.

Option A — reset local :
```bash
supabase db reset   # applique UNIQUEMENT la baseline sur la DB locale
```
Option B — branche preview sur la branche git du squash (si branching git actif).

✅ **Vérif de sortie** : `supabase db diff` (ou dump de la base de validation) ==
schéma prod, **0 objet manquant**. Si des `OWNER`/extensions/roles échouent →
sanitiser la baseline (retirer les `ALTER … OWNER TO postgres`, préfixer les
extensions par `IF NOT EXISTS`, retirer les GRANT vers des rôles absents) et
recommencer l'étape 1. **Ne pas passer à l'étape 2 tant que ce n'est pas vert.**

## Étape 2 — réparer le registre PROD (opération contrôlée, 1 fois)

Fenêtre de grâce : **désactiver temporairement** `deploy-supabase` (ou merger
hors de ses horaires) pour éviter tout `db push` pendant la manip.

Sur prod (`flripxtsyegjshnhzjkz`), en une transaction (registre uniquement,
AUCUN DDL sur le schéma) :

```sql
BEGIN;
-- 1. marquer la baseline comme déjà appliquée (le schéma existe déjà en prod)
INSERT INTO supabase_migrations.schema_migrations (version, name)
VALUES ('00000000000000', 'baseline_prod')
ON CONFLICT (version) DO NOTHING;
-- 2. purger l'historique des patchs (désormais archivés hors repo)
DELETE FROM supabase_migrations.schema_migrations WHERE version <> '00000000000000';
COMMIT;
```

✅ **Vérif de sortie** : `SELECT version FROM supabase_migrations.schema_migrations;`
→ **une seule ligne** `00000000000000`. Le schéma prod est **inchangé** (on n'a
touché que le registre).

## Étape 3 — merger le squash

Merger la PR du squash. `deploy-supabase` se relance :
- `Heal` : la seule version remote (`00000000000000`) est aussi locale → aucun
  orphelin → rien à purger.
- `db push` : la baseline est déjà enregistrée → **no-op**.

✅ **Vérif de sortie** : run `deploy-supabase` **vert**, job `Push pending
migrations` = « no new migrations ».

## Étape 4 — re-valider une branche neuve

Créer une branche preview → elle applique la baseline → **schéma complet**
(≠ le `MIGRATIONS_FAILED` du 04/07). Détruire la branche.

✅ **Vérif de sortie** : branche `MIGRATIONS_PASSED` + tables escrow présentes.

Après ça : la recette escrow (`docs/RECETTE_ESCROW.md`) devient exécutable, puis
le flip ⚡.

## Rollback

Tant que l'étape 2 n'est pas faite : `git revert` du squash suffit (le registre
prod n'a pas bougé). Après l'étape 2 : ré-insérer les versions archivées dans
`schema_migrations` depuis `db/migrations_archive/` (les noms de fichiers = les
versions) restaure l'ancien registre ; le schéma n'ayant jamais été touché, la
prod reste saine.

## Pourquoi je ne l'exécute pas seule

Je n'ai ni la CLI Supabase ni `SUPABASE_DB_PASSWORD` pour l'étape 1 (validation
`db reset`), et l'étape 2 est une écriture contrôlée sur le registre prod que je
ne fais pas sans ta présence (garde-fou 9.0 : SQL direct prod = hotfix documenté
uniquement). Je fournis le squash prêt + ce runbook ; on exécute les étapes 1→4
ensemble, dans l'ordre, avec les vérifs.
