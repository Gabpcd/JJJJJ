# CP5a — Refonte triggers et taux configurables

> Date : 2026-04-16
> Statut : AUDIT — validation partie par partie avant implémentation

---

## Partie 1 : Nouvelles colonnes

### 1.1 Colonnes ajoutées sur `etablissements`

Deux colonnes pour les bornes horaires de nuit configurables (D4). Les taux de majoration existent déjà.

| Colonne | Type | Default | CHECK | Raison |
|---|---|---|---|---|
| `heure_debut_nuit` | time | `'21:00'` | `BETWEEN '19:00' AND '23:59'` | Art. L3122-2 : « tout travail entre 21h et 6h ». Conventions collectives permettent 19h–23h59. Type `time` pour supporter 21h30, 22h30 etc. |
| `heure_fin_nuit` | time | `'06:00'` | `BETWEEN '04:00' AND '08:00'` | Idem, fin de nuit 4h–8h selon convention. |

**Colonnes existantes — ajout de planchers légaux (D7) :**

| Colonne existante | Default actuel | CHECK à ajouter | Justification légale |
|---|---|---|---|
| `taux_majoration_nuit_pourcent` | 25.00 | `>= 25` | Plancher prudent au-dessus des minima CCN FHP n°2264 art. 82.1/82.2 pour couvrir FEHAP, CCU, Croix-Rouge, FPH. Ticket tech-debt T1 : validation avocat santé pré-lancement. |
| `taux_majoration_dimanche_pourcent` | 50.00 | `>= 25` | Idem — plancher prudent. CCN FHP art. 82.1 impose 20% min, relevé à 25% par précaution. |
| `taux_majoration_ferie_pourcent` | 100.00 | `>= 50` | CCN FHP art. 82.2 : 50% min hors 1er mai. Art. L3133-6 : 100% pour le 1er mai. Ticket tech-debt T1. |

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
| `heure_debut_nuit_fige` | time | `etablissements.heure_debut_nuit` | Borne début nuit figée |
| `heure_fin_nuit_fige` | time | `etablissements.heure_fin_nuit` | Borne fin nuit figée |
| `taux_commission_fige` | numeric | `etablissements.taux_commission_negocie` | % commission figé |
| `fige_le` | timestamptz | `now()` | Horodatage du gel |

**Sémantique COALESCE dans les triggers calculateurs :**
```
taux_effectif = COALESCE(_fige, valeur_etab, default_legal)
```
Tant que `_fige IS NULL`, les triggers utilisent les valeurs live de l'établissement (comportement actuel inchangé pour les missions OUVERTE).

### 1.2b Cycle de vie `taux_commission` et `taux_horaire_base` vs `*_fige`

**`taux_horaire_base`** (colonne existante sur `missions`) :
- Éditable uniquement tant que `fige_le IS NULL` (mission OUVERTE). Renseignée par l'étab à la création de la mission.
- `taux_horaire_base_fige` : snapshot de `taux_horaire_base` au moment de la transition OUVERTE → ASSIGNEE.
- **Après gel (`fige_le IS NOT NULL`) : `taux_horaire_base` est immutable.** Toute tentative de modification est bloquée par le trigger de gel (Partie 2). Exception : bypass admin tracé via session vars `jolene.admin_override_gel` + `jolene.admin_override_reason` avec audit dans `invoice_audit_log`.
- **Pas de deprecation** de `taux_horaire_base`. Elle reste utilisée en affichage, dans les RPCs, dans le frontend. `_fige` est interne aux triggers financiers.

**Règle d'immutabilité post-gel** (implémentée dans le trigger de gel, Partie 2) :
```sql
-- Bloque toute modification de taux_horaire_base après gel
IF NEW.taux_horaire_base IS DISTINCT FROM OLD.taux_horaire_base
   AND OLD.fige_le IS NOT NULL THEN
  -- Bypass admin tracé
  IF current_setting('jolene.admin_override_gel', true) = NEW.id::text
     AND COALESCE(current_setting('jolene.admin_override_reason', true), '') != '' THEN
    INSERT INTO invoice_audit_log (invoice_id, action, performed_by, payload_before)
    SELECT fh.id, 'TAUX_HORAIRE_MODIFIED_POST_GEL', auth.uid(),
      jsonb_build_object(
        'reason', current_setting('jolene.admin_override_reason', true),
        'mission_id', NEW.id,
        'old_taux', OLD.taux_horaire_base,
        'new_taux', NEW.taux_horaire_base
      )
    FROM factures_honoraires fh
    WHERE fh.mission_id = NEW.id AND fh.statut NOT IN ('BROUILLON', 'ANNULEE')
    LIMIT 1;
    -- Si pas de facture, log dans une table d'audit directe
    IF NOT FOUND THEN
      INSERT INTO invoice_audit_log (action, performed_by, payload_before)
      VALUES ('TAUX_HORAIRE_MODIFIED_POST_GEL', auth.uid(),
        jsonb_build_object(
          'reason', current_setting('jolene.admin_override_reason', true),
          'mission_id', NEW.id,
          'old_taux', OLD.taux_horaire_base,
          'new_taux', NEW.taux_horaire_base
        ));
    END IF;
  ELSE
    RAISE EXCEPTION 'Modification de taux_horaire_base interdite après gel (fige_le=%). Pour corriger : annuler la mission et en créer une nouvelle, ou utiliser le bypass admin tracé (jolene.admin_override_gel + jolene.admin_override_reason).',
      OLD.fige_le USING ERRCODE = 'check_violation';
  END IF;
END IF;
```

**`taux_commission`** (colonne existante sur `missions`, default 15) :
- Initialisée par `fn_calculer_financier_mission` depuis `etablissements.taux_commission_negocie`.
- `taux_commission_fige` : snapshot au gel via `COALESCE(missions.taux_commission, etab.taux_commission_negocie, 15)`. Après gel, c'est `_fige` qui est lu par le calculateur financier.
- **Pas de deprecation** de `taux_commission`. Elle continue d'exister comme valeur "live" et reste utile pour l'affichage et les RPCs.
- **État actuel en base** (vérifié 2026-04-16) : 0 missions avec `taux_commission IS NULL`, 133 à 15%, 135 à un taux différent. Le COALESCE dans le backfill ne changera rien en pratique, mais reste en sécurité pour les futurs INSERT sans trigger.

**Lecture par `fn_calculer_financier_mission` :**

| Phase mission | `taux_horaire_base` lu depuis | Taux majorations lus depuis | Commission lue depuis |
|---|---|---|---|
| OUVERTE (`_fige IS NULL`) | `missions.taux_horaire_base` | `etablissements.taux_majoration_*_pourcent` | `COALESCE(missions.taux_commission, etab.taux_commission_negocie, 15)` |
| ASSIGNEE+ (`_fige NOT NULL`) | `missions.taux_horaire_base_fige` | `missions.taux_majoration_*_fige` | `missions.taux_commission_fige` |

**Backfill des 268 missions existantes** : `taux_commission_fige` est backfillé via `COALESCE(missions.taux_commission, etab.taux_commission_negocie, 15)` — cascade identique à la lecture OUVERTE pour cohérence. `taux_horaire_base_fige` depuis `missions.taux_horaire_base` (pas de COALESCE nécessaire, colonne NOT NULL).

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
  heure_debut_nuit_fige = COALESCE(e.heure_debut_nuit, '21:00'::time),
  heure_fin_nuit_fige = COALESCE(e.heure_fin_nuit, '06:00'::time),
  taux_commission_fige = COALESCE(m.taux_commission, e.taux_commission_negocie, 15),
  fige_le = NULL  -- gel rétroactif CP5a, date réelle de transition OUVERTE→ASSIGNEE inconnue
FROM etablissements e
WHERE e.id = m.etablissement_id
  AND m.statut != 'OUVERTE';
```

**`fige_le = NULL` pour les missions backfillées** : `modifie_le` reflète la dernière modification (pas la transition OUVERTE → ASSIGNEE). Plutôt que d'inventer une date fausse, on laisse `NULL` pour distinguer clairement les gels rétroactifs (CP5a) des gels traçables (post-CP5a, `fige_le = now()` au moment exact de la transition).

**Vérification pré-backfill : cohérence avec les factures existantes :**

Avant exécution du backfill, lancer cette vérification pour détecter toute divergence entre les taux backfillés et les montants déjà facturés :

```sql
-- Dry-run : détecter les missions TERMINEE facturées où le backfill
-- créerait une incohérence avec la facture émise
SELECT
  m.id AS mission_id,
  fh.numero AS facture_numero,
  m.total_brut AS total_brut_actuel,
  fh.montant_ht AS montant_ht_facture,
  m.taux_horaire_base AS taux_horaire_mission,
  e.taux_majoration_nuit_pourcent AS taux_nuit_etab_actuel,
  e.taux_majoration_dimanche_pourcent AS taux_dim_etab_actuel,
  e.taux_majoration_ferie_pourcent AS taux_fer_etab_actuel,
  e.taux_commission_negocie AS taux_comm_etab_actuel,
  m.taux_commission AS taux_comm_mission_actuel
FROM missions m
JOIN etablissements e ON e.id = m.etablissement_id
JOIN factures_honoraires fh ON fh.mission_id = m.id
  AND fh.statut NOT IN ('BROUILLON', 'ANNULEE')
WHERE m.statut = 'TERMINEE';
```

Si divergence détectée → rapport soumis pour validation avant exécution.
En pratique : 0 divergence attendue (taux étab jamais modifiés depuis création des comptes test).

**Risque du backfill** : les taux de l'établissement ont pu changer entre l'assignation et maintenant. Pour les 251 missions seeded, ce risque est nul (données test, bientôt purgées par CP6). Pour les 17 missions organiques, les taux étab n'ont jamais été modifiés depuis la création du compte → backfill exact.

**Pattern** : `DISABLE TRIGGER USER` + backfill + `ENABLE TRIGGER USER` (playbook standard, cf. `/docs/bulk-updates-playbook.md`).

### 1.5 SQL proposé (DDL)

```sql
-- ── etablissements : bornes nuit configurables ──
-- Type time pour supporter les demi-heures (21h30, 22h30 etc.)
ALTER TABLE public.etablissements
  ADD COLUMN IF NOT EXISTS heure_debut_nuit time DEFAULT '21:00',
  ADD COLUMN IF NOT EXISTS heure_fin_nuit time DEFAULT '06:00';

ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_heure_debut_nuit CHECK (heure_debut_nuit BETWEEN '19:00' AND '23:59'),
  ADD CONSTRAINT chk_heure_fin_nuit CHECK (heure_fin_nuit BETWEEN '04:00' AND '08:00');

-- ── etablissements : planchers légaux sur taux existants ──
-- Planchers calibrés au-dessus des minima CCN FHP n°2264 art. 82.1/82.2
-- pour couvrir également FEHAP, CCU, Croix-Rouge, FPH sans validation
-- juridique formelle à ce stade. Ticket tech-debt T1 : validation
-- avocat santé avant lancement public.
ALTER TABLE public.etablissements
  ADD CONSTRAINT chk_taux_maj_nuit_min CHECK (taux_majoration_nuit_pourcent >= 25),   -- Prudent > CCN FHP
  ADD CONSTRAINT chk_taux_maj_dim_min CHECK (taux_majoration_dimanche_pourcent >= 25), -- Prudent > CCN FHP art. 82.1 (20%)
  ADD CONSTRAINT chk_taux_maj_fer_min CHECK (taux_majoration_ferie_pourcent >= 50);    -- CCN FHP art. 82.2

-- ── missions : colonnes snapshot ──
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS taux_horaire_base_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_nuit_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_dimanche_fige numeric,
  ADD COLUMN IF NOT EXISTS taux_majoration_ferie_fige numeric,
  ADD COLUMN IF NOT EXISTS heure_debut_nuit_fige time,
  ADD COLUMN IF NOT EXISTS heure_fin_nuit_fige time,
  ADD COLUMN IF NOT EXISTS taux_commission_fige numeric,
  ADD COLUMN IF NOT EXISTS fige_le timestamptz;
```

---

*Partie 2 (trigger de gel) en attente de validation de la Partie 1.*
