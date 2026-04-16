# Bulk Updates Playbook — Jolene

> Date : 2026-04-16
> Contexte : post-mortem CP3 (incident recalcul financier lors de migration)

## Le problème

La table `missions` a 30+ triggers BEFORE UPDATE. Tout UPDATE — même sur une seule colonne — déclenche l'ensemble de la cascade. Les triggers financiers recalculent, les protecteurs revertent, et l'ordre d'exécution détermine le résultat final.

En fonctionnement normal, ce système est auto-cohérent. Mais lors d'opérations en masse (migration, correction, recalcul batch), il peut produire des effets de bord : recalculs financiers non désirés, violations de contraintes, performance dégradée.

## Quand utiliser `ALTER TABLE DISABLE TRIGGER USER`

| Situation | Méthode | Exemple |
|---|---|---|
| Migration de données (INSERT/UPDATE en masse sur missions) | DISABLE TRIGGER USER | CP3 : `SET nb_creneaux = 1` |
| Restauration de snapshot | DISABLE TRIGGER USER | CP3 : restore après incident |
| Recalcul batch de colonnes dénormalisées | DISABLE TRIGGER USER | Futur : backfill heures_majorees |
| Correction de données admin | DISABLE TRIGGER USER dans un script dédié | Fixe d'un montant incorrect |

## Quand NE PAS utiliser

| Situation | Méthode correcte |
|---|---|
| Opération unitaire (1 mission) | Laisser les triggers faire leur travail |
| Flow utilisateur (frontend/RPC) | RPC avec auth context |
| Edge function (generate-invoice, etc.) | service_role avec context |
| Sync trigger (mission_creneaux → missions) | `jolene.sync_in_progress` (ciblé) |

## Template de migration avec DISABLE TRIGGER

```sql
-- ============================================================
-- Migration : [description]
-- Colonnes modifiées : [liste]
-- Triggers impactés : [tous les BEFORE UPDATE — désactivés]
-- Vérification : snapshot diff sur [colonnes financières]
-- ============================================================

-- 1. Snapshot
CREATE TABLE [table]_snapshot_[date] AS SELECT * FROM [table];

-- 2. Disable triggers
ALTER TABLE [table] DISABLE TRIGGER USER;

-- 3. Bulk operation
UPDATE [table] SET [colonne] = [valeur] WHERE [condition];

-- 4. Re-enable triggers
ALTER TABLE [table] ENABLE TRIGGER USER;

-- 5. Verify non-regression
SELECT COUNT(*) FROM [table] t
JOIN [table]_snapshot_[date] s ON t.id = s.id
WHERE t.[colonne_financiere] IS DISTINCT FROM s.[colonne_financiere];
-- MUST be 0 for financial columns not intentionally modified

-- 6. Cleanup (after validation)
-- DROP TABLE [table]_snapshot_[date];
```

## Règles strictes

1. **DISABLE et ENABLE dans le même script** — ne jamais laisser les triggers désactivés
2. **Snapshot AVANT** — toujours créer une table de backup
3. **Vérification APRÈS** — comparer les colonnes financières avec le snapshot
4. **Logger le scope** — nombre de rows, colonnes touchées
5. **Documenter dans le header** — raison, colonnes, triggers, vérification
6. **Ne PAS utiliser `jolene.sync_in_progress` pour des UPDATEs directs sur missions** — le bypass est trop permissif (voir postmortem-cp3.md)

## Anti-pattern : `jolene.sync_in_progress` pour des bulk updates

Le bypass `sync_in_progress` a été conçu pour le trigger de sync (`mission_creneaux → missions`). Il désactive 3 triggers de protection qui normalement revertent les modifications aux champs financiers.

Si on utilise ce bypass pour un UPDATE direct sur missions, les triggers financiers recalculent ET les protections sont bypassées → les recalculs persistent → **données financières corrompues**.

**Règle** : `sync_in_progress` = RÉSERVÉ au trigger `fn_sync_mission_creneaux`. Pour tout autre cas, utiliser `DISABLE TRIGGER USER`.
