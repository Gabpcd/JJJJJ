# CP5a — Refonte triggers et taux configurables

> Date : 2026-04-16
> Statut : AUDIT — validation partie par partie avant implémentation

---

## Partie 1 : Nouvelles colonnes

### 1.1 Colonnes ajoutées sur `etablissements`

Deux colonnes pour les bornes horaires de nuit configurables (D4). Les taux de majoration existent déjà.

| Colonne | Type | Default | CHECK | Raison |
|---|---|---|---|---|
| `heure_debut_nuit` | smallint | 21 | `BETWEEN 19 AND 23` | Art. L3122-2 : « tout travail entre 21h et 6h ». Conventions collectives permettent 19h–23h. |
| `heure_fin_nuit` | smallint | 6 | `BETWEEN 4 AND 8` | Idem, fin de nuit 4h–8h selon convention. |

**Colonnes existantes — ajout de planchers légaux (D7) :**

| Colonne existante | Default actuel | CHECK à ajouter | Justification légale |
|---|---|---|---|
| `taux_majoration_nuit_pourcent` | 25.00 | `>= 10` | Art. L3122-8 : minimum 10% pour travail de nuit habituel |
| `taux_majoration_dimanche_pourcent` | 50.00 | `>= 0` | Pas de minimum légal universel (dépend de la convention) |
| `taux_majoration_ferie_pourcent` | 100.00 | `>= 0` | Seul le 1er mai impose 100% (Art. L3133-6). Autres fériés : convention. |

**Pas de colonne ajoutée pour les taux de majoration eux-mêmes** — ils existent déjà :
- `taux_majoration_nuit_pourcent` (default 25)
- `taux_majoration_dimanche_pourcent` (default 50)
- `taux_majoration_ferie_pourcent` (default 100)
- `taux_commission_negocie` (default 15)
- `rist_taux_base_horaire` (default 25)

### 1.2 Colonnes snapshot ajoutées sur `missions`

Huit colonnes `*_fige` + un timestamp (D6). Toutes nullable, `NULL` = « pas encore figé » (mission OUVERTE).

| Colonne | Type | Source (copiée au gel) | Rôle |
|---|---|---|---|
| `taux_horaire_base_fige` | numeric | `missions.taux_horaire_base` | Taux horaire figé à l'assignation |
| `taux_majoration_nuit_fige` | numeric | `etablissements.taux_majoration_nuit_pourcent` | % majoration nuit figé |
| `taux_majoration_dimanche_fige` | numeric | `etablissements.taux_majoration_dimanche_pourcent` | % majoration dimanche figé |
| `taux_majoration_ferie_fige` | numeric | `etablissements.taux_majoration_ferie_pourcent` | % majoration férié figé |
| `heure_debut_nuit_fige` | smallint | `etablissements.heure_debut_nuit` | Borne début nuit figée |
| `heure_fin_nuit_fige` | smallint | `etablissements.heure_fin_nuit` | Borne fin nuit figée |
| `taux_commission_fige` | numeric | `etablissements.taux_commission_negocie` | % commission figé |
| `fige_le` | timestamptz | `now()` | Horodatage du gel |

**Sémantique COALESCE dans les triggers calculateurs :**
```
taux_effectif = COALESCE(_fige, valeur_etab, default_legal)
```
Tant que `_fige IS NULL`, les triggers utilisent les valeurs live de l'établissement (comportement actuel inchangé pour les missions OUVERTE).

### 1.3 Impact sur les protecteurs existants

Les 8 colonnes `*_fige` doivent être ajoutées aux listes de freeze dans :

| Protecteur | Contexte sync (`sync_in_progress=true`) | Contexte non-admin |
|---|---|---|
| `dec_proteger_mission_soignant` | Freeze `*_fige` à OLD (le sync ne les touche pas) | Freeze `*_fige` à OLD |
| `fn_protect_mission_financials` | Freeze `*_fige` à OLD | Freeze `*_fige` à OLD |

**Raison** : seul le trigger de gel (Partie 2) doit écrire les `*_fige`. Tout autre contexte (sync, soignant, même etab-admin hors transition de statut) doit les laisser intacts.

### 1.4 Migration des 268 missions existantes

| Statut | Nb missions | Action `*_fige` |
|---|---|---|
| `OUVERTE` | Variable | `NULL` (pas encore assignée — correct) |
| `ASSIGNEE`, `EN_COURS` | Variable | Backfill depuis l'établissement actuel |
| `TERMINEE` | Variable | Backfill depuis l'établissement actuel |
| `ANNULEE_*`, `ABSENCE`, `LITIGE` | Variable | Backfill depuis l'établissement actuel |

**Requête de backfill :**
```sql
UPDATE missions m SET
  taux_horaire_base_fige = m.taux_horaire_base,
  taux_majoration_nuit_fige = e.taux_majoration_nuit_pourcent,
  taux_majoration_dimanche_fige = e.taux_majoration_dimanche_pourcent,
  taux_majoration_ferie_fige = e.taux_majoration_ferie_pourcent,
  heure_debut_nuit_fige = COALESCE(e.heure_debut_nuit, 21),
  heure_fin_nuit_fige = COALESCE(e.heure_fin_nuit, 6),
  taux_commission_fige = COALESCE(m.taux_commission, e.taux_commission_negocie, 15),
  fige_le = m.modifie_le  -- approximation : date de dernière modif
FROM etablissements e
WHERE e.id = m.etablissement_id
  AND m.statut != 'OUVERTE';
```

**Risque du backfill** : les taux de l'établissement ont pu changer entre l'assignation et maintenant. Pour les 251 missions seeded, ce risque est nul (données test, bientôt purgées). Pour les 17 missions organiques, les taux étab n'ont jamais été modifiés depuis la création du compte → backfill exact.

**Pattern** : `DISABLE TRIGGER USER` + backfill + `ENABLE TRIGGER USER` (playbook standard, cf. `/docs/bulk-updates-playbook.md`).

### 1.5 SQL proposé (DDL)

```sql
-- ── etablissements : bornes nuit configurables ──
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS heure_debut_nuit smallint DEFAULT 21,
  ADD COLUMN IF NOT EXISTS heure_fin_nuit smallint DEFAULT 6;

ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_heure_debut_nuit CHECK (heure_debut_nuit BETWEEN 19 AND 23),
  ADD CONSTRAINT chk_heure_fin_nuit CHECK (heure_fin_nuit BETWEEN 4 AND 8);

-- ── etablissements : planchers légaux sur taux existants ──
ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_taux_maj_nuit_min CHECK (taux_majoration_nuit_pourcent >= 10),
  ADD CONSTRAINT chk_taux_maj_dim_min CHECK (taux_majoration_dimanche_pourcent >= 0),
  ADD CONSTRAINT chk_taux_maj_fer_min CHECK (taux_majoration_ferie_pourcent >= 0);

-- ── missions : colonnes snapshot ──
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS taux_horaire_base_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_nuit_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_dimanche_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_ferie_fige numeric,
  ADD COLUMN IF NOT EXISTS heure_debut_nuit_fige smallint,
  ADD COLUMN IF NOT EXISTS heure_fin_nuit_fige smallint,
  ADD COLUMN IF NOT EXISTS taux_commission_fige numeric,
  ADD COLUMN IF NOT EXISTS fige_le timestamptz;
```

---

*Partie 2 (trigger de gel) en attente de validation de la Partie 1.*
