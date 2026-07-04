# Archive des migrations pré-squash (baseline 9.0)

Ce dossier contient les **644 migrations historiques** appliquées à la prod
avant le squash baseline du 2026-07-04. Elles ne sont **plus rejouées** : leur
effet cumulé est capturé dans l'unique migration initiale
`supabase/migrations/00000000000000_baseline_prod.sql` (dump du schéma `public`
de prod).

## Pourquoi ce squash ?

Le schéma initial de Jolene a été créé par Lovable **sans migration versionnée**.
Les 644 fichiers d'ici étaient des *patches* posés par-dessus ce socle jamais
versionné → un environnement neuf (branche preview, disaster recovery) ne pouvait
pas reconstruire le schéma à partir de zéro (`MIGRATIONS_FAILED`, 0 table). Le
squash fait de la définition **live** de prod la seule migration initiale.

## État post-squash

`supabase/migrations/` ne contient que :
1. `00000000000000_baseline_prod.sql` — dump complet du schéma `public` de prod.
2. `20260704180000_relancer_validation_presence.sql` — seule migration postérieure
   au snapshot baseline (RPC « Relancer l'établissement », gardée append-only).

Validé le 2026-07-04 : rejeu du baseline sur base Supabase neuve → 0 erreur ;
empreintes structurelles (colonnes, contraintes, enums, index, policies, triggers,
fonctions) `[baseline + 20260704180000]` **identiques** à la prod live.

## Rollback du registre

`db/registre_snapshot_pre_squash_2026-07-04.sql` restaure les 645 entrées
d'origine de `supabase_migrations.schema_migrations` (métadonnées uniquement,
aucun DDL) si la réparation du registre devait être annulée.

## Ne pas restaurer ces fichiers dans `supabase/migrations/`

Les y remettre ferait retenter `supabase db push` de les rejouer (non-idempotents,
déjà appliqués) → deploy rouge. Ils restent ici pour l'archéologie/historique
uniquement.
