# Correction garantie d'heures — Audit pré-implémentation

**Décision produit** : `net_a_payer = GREATEST(SUM PREVISIONNEL non-pause, SUM EFFECTIF fermés non-pause)`

Remplace la logique actuelle : `COALESCE(SUM EFFECTIF fermés, SUM PREVISIONNEL, 0)`.

Le soignant facture au minimum ses heures prévisionnelles (garantie plancher contractuelle). Si l'effectif pointé dépasse le prévisionnel (avec accord étab), l'effectif l'emporte.

---

## Section 1 — Diagnostic du code actuel

### 1.1 `fn_calculer_financier_mission` (trigger BEFORE sur `missions`)

- **Fichier canonique** : `supabase/migrations/20260416190300_cp5b_triggers_effectif_previsionnel.sql:12-87`
- **Trigger attaché** : `trg_calculer_financier BEFORE INSERT OR UPDATE OF taux_horaire_base, duree_heures, debut_le, fin_le, heures_nuit, heures_dimanche, heures_ferie, taux_ifm, taux_icp ON public.missions`
- **Ligne coupable** : lignes **28-36**

```sql
SELECT COALESCE(
  SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
    FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause),
  SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
    FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause),
  0
)
INTO v_duree
FROM mission_creneaux WHERE mission_id = NEW.id;
```

**Problème** : `COALESCE(eff_non_null_sum, prev_sum, 0)` — dès qu'UN créneau EFFECTIF fermé existe, la somme EFFECTIF (même minuscule, ex 1h) masque totalement le prévisionnel. Le soignant perd sa garantie.

Ligne **40-42** (fallback sans créneau) : `v_duree := COALESCE(NEW.duree_heures, EXTRACT(EPOCH ...))` — utilisé UNIQUEMENT si `NOT v_has_creneaux`. À conserver tel quel.

### 1.2 `fn_trg_auto_heures_majorees` (trigger BEFORE sur `missions`)

- **Fichier canonique** : `supabase/migrations/20260416190300_cp5b_triggers_effectif_previsionnel.sql:101-175`
- **Trigger attaché** : `trg_auto_heures_majorees BEFORE INSERT OR UPDATE OF debut_le, fin_le, duree_heures ON public.missions`
- **Logique coupable** : lignes **132-137**

```sql
IF EXISTS (SELECT 1 FROM mission_creneaux
           WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL) THEN
  v_type_source := 'EFFECTIF';
ELSE
  v_type_source := 'PREVISIONNEL';
END IF;
```

**Problème** : source identique à celle du bloc durée de la fct 1. Si on passe la durée en GREATEST, les majorations doivent être calculées sur le **même set de créneaux** que la durée gagnante — sinon incohérence entre `total_brut = taux × GREATEST(prev, eff)` et `heures_nuit` calculé sur l'autre ensemble.

### 1.3 `fn_verifier_pre_facturation(uuid)` (appelée par edge `generate-invoice` avant INSERT facture)

- **Fichier canonique** : `supabase/migrations/20260416190400_cp5b_garde_fous.sql:159-230`
- **Logique coupable** : ligne **214** (dans la version prod)

```sql
IF v_source = 'EFFECTIF' AND v_ecart_pourcent > 10 THEN
  RAISE EXCEPTION 'Facturation bloquée : écart prévisionnel/effectif de % pct (seuil 10 pct). ...';
END IF;
```

**Problème** : avec la règle GREATEST, un écart EFF < PREV est désormais **acceptable par conception** (garantie plancher). Bloquer à 10% d'écart devient incohérent.

### 1.4 Autres consommateurs COALESCE(EFFECTIF, PREVISIONNEL)

- `dec_verifier_plafond_48h()` (même migration `20260416190300:180+`) — plafond hebdomadaire. **Hors scope** facturation : cette fonction compte les heures travaillées pour le plafond URSSAF 48h/semaine. **Doit rester en EFFECTIF-si-existe-sinon-PREV** (on ne compte pas pour le plafond des heures non travaillées).
- `dec_verifier_repos_11h()` — idem, non lié à la facturation.

**Conclusion** : seules les 3 fonctions citées (1.1, 1.2, 1.3) doivent être modifiées.

---

## Section 2 — Code modifié proposé

### 2.1 `fn_calculer_financier_mission` — GREATEST

**Remplace lignes 28-36** :

```sql
SELECT GREATEST(
  COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
    FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause), 0),
  COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
    FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause), 0)
)
INTO v_duree
FROM mission_creneaux WHERE mission_id = NEW.id;
```

**Pourquoi GREATEST et pas autre chose** :
- `GREATEST(a, NULL) = NULL` en PG (NULL propage) → on enveloppe chaque somme dans `COALESCE(..., 0)` pour neutraliser ce piège.
- `GREATEST(0, 0) = 0` → reste combiné au garde-fou ligne 38 (`v_has_creneaux`) : si aucune ligne dans mission_creneaux, on retombe sur `NEW.duree_heures` (fallback mission.duree_heures / fin_le - debut_le).
- Pas besoin de changer les lignes 38-42 (fallback sans créneau).

### 2.2 `fn_trg_auto_heures_majorees` — source aligne sur la durée gagnante

**Remplace lignes 132-137** :

```sql
DECLARE
  v_sum_prev numeric;
  v_sum_eff  numeric;
BEGIN
  ...
  SELECT
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause), 0),
    COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
      FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause), 0)
  INTO v_sum_prev, v_sum_eff
  FROM mission_creneaux WHERE mission_id = NEW.id;

  -- Source = jeu de créneaux qui porte la durée gagnante
  IF v_sum_eff > v_sum_prev THEN
    v_type_source := 'EFFECTIF';
  ELSE
    v_type_source := 'PREVISIONNEL';  -- inclut le cas d'égalité et le cas PREV > EFF
  END IF;
```

**Pourquoi** :
- Si EFF > PREV, les majorations comptent sur EFFECTIF (heures pointées réelles).
- Si PREV >= EFF, garantie plancher s'applique → on compte les majorations sur les créneaux PREVISIONNEL (cohérent avec `total_brut` qui utilisera la durée PREV).
- Égalité : on privilégie PREVISIONNEL (plus stable, défini à la création).

### 2.3 `fn_verifier_pre_facturation` — retirer le blocage 10% asymétrique

**Remplace lignes 194-215 (logique seuil)** par :

```sql
v_source := CASE WHEN v_nb_effectif_ferme > 0 THEN 'EFFECTIF_OU_PREV' ELSE 'PREVISIONNEL' END;

SELECT
  COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
           FILTER (WHERE type_creneau = 'PREVISIONNEL' AND NOT est_pause)::numeric, 2), 0),
  COALESCE(ROUND(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0)
           FILTER (WHERE type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause)::numeric, 2), 0)
INTO v_duree_previsionnelle, v_duree_effective
FROM mission_creneaux WHERE mission_id = p_mission_id;

-- Nouvelle règle : on bloque UNIQUEMENT si l'effectif dépasse le prévisionnel
-- de plus de 10% (dépassement suspect, validation admin requise).
-- EFFECTIF < PREV → garantie plancher applique → pas de blocage.
IF v_duree_previsionnelle > 0 AND v_duree_effective > v_duree_previsionnelle * 1.10 THEN
  RAISE EXCEPTION 'Facturation bloquée : effectif %h dépasse prévisionnel %h de plus de 10 pct. Contactez l''admin pour valider le dépassement.',
    v_duree_effective, v_duree_previsionnelle USING ERRCODE = 'check_violation';
END IF;
```

**Variante alternative (à valider)** : supprimer complètement le blocage 10% (tout écart accepté automatiquement, la garantie plancher gère à la hausse et à la baisse). À trancher avec Gabrielle selon la tolérance business.

---

## Section 3 — Impact sur les factures déjà en base

Simulation SQL pour comparer `net_a_payer` COALESCE (actuel) vs GREATEST (proposé), appliquée aux 11 factures actuellement en base (mix fixtures seed + organiques) :

| Numéro facture | prev_h | eff_h fermés | Durée utilisée (COALESCE) | Durée GREATEST | Delta durée | Impact |
|---|---|---|---|---|---|---|
| **FH-2026-04-0011** (organique) | 12.00 | **4.25** | **4.25** | **12.00** | **+7.75h** | 🔴 **Changement** — garantie plancher appliquerait |
| JOL-98765432-2026-00002 (organique) | 12.00 | 0 | 12.00 | 12.00 | 0 | ✅ Identique |
| JOL-98765432-2026-00001 (organique) | 12.00 | 0 | 12.00 | 12.00 | 0 | ✅ Identique |
| FH-2026-04-0007 (organique) | 6.00 | 0 | 6.00 | 6.00 | 0 | ✅ Identique |
| FH-2026-04-0008 (organique) | 8.00 | 0 | 8.00 | 8.00 | 0 | ✅ Identique |
| FH-2026-04-0001 à 0006 (fixtures seed) | 6→12 | 0 | prev | prev | 0 | ✅ Identique |

**Seul cas d'écart** : `FH-2026-04-0011` — mission pointée 4.25h réels pour 12h prévues. Actuel facture 367.51€ (sur 4.25h). Avec GREATEST, facturerait sur 12h → **total_brut passerait de 306.25€ → ~906€**, net_a_payer ~1090€.

**Verdict** : c'est une **CORRECTION**, pas une régression. La règle produit dit explicitement que le soignant doit facturer au moins le prévisionnel. L'ancien calcul violait cette règle (facturation 4.25h alors que garantie contractuelle = 12h).

**Facture déjà émise** : statut actuel de FH-2026-04-0011 à vérifier avant toute décision. Si `EMISE` ou `PAYEE`, les montants sont figés (factures immuables par design CP3) — **aucun impact rétroactif automatique**. Si `BROUILLON`, la régénération via `generate-invoice` recalculerait selon la nouvelle règle.

---

## Section 4 — Tests mentaux (7 scénarios)

| # | Scénario | Durée attendue | Source majorations | Verdict GREATEST |
|---|---|---|---|---|
| a | PREV=12h, EFF=10h fermé | **12h** (plancher) | PREVISIONNEL | ✅ Garantie applique |
| b | PREV=12h, EFF=14h fermé | **14h** (effectif) | EFFECTIF | ✅ Dépassement reconnu |
| c | PREV=12h, EFF=0 créneau | **12h** (plancher, `COALESCE(0)=0`) | PREVISIONNEL | ✅ Aucun pointage = fallback prev |
| d | PREV=0 créneau (exotique), EFF=5h fermé | **5h** | EFFECTIF | ⚠️ Tenable mais suspect (mission sans prévisionnel saisi) |
| e | PREV=12h, EFF=10h fermé + 1h ouvert | **12h** (ouvert filtré par `fin IS NOT NULL`) | PREVISIONNEL | ⚠️ `fn_verifier_pre_facturation` bloque encore pour créneau ouvert |
| f | PREV nuit 20h-8h (12h), EFF nuit 21h-7h (10h fermé) | **12h** → `heures_nuit` calculé sur PREVISIONNEL (12h) | PREVISIONNEL | ✅ Cohérence durée ↔ majorations |
| g | `fn_verifier_pre_facturation` : EFF < PREV (garantie plancher) | Plus de blocage 10% sur ce cas | n/a | ✅ Aucun blocage — cf. Section 2.3. Blocage conservé uniquement si EFF > PREV×1.10 |

### Détails sur (d) — cas exotique PREV=0
`GREATEST(0, 5) = 5h` → facture 5h. Ce cas ne devrait pas arriver dans le flux normal (`fn_creer_mission` pose toujours au moins un créneau prévisionnel). Ajout possible d'un garde-fou : `RAISE WARNING si v_sum_prev = 0 AND v_sum_eff > 0`. **À valider avec Gabrielle.**

### Détails sur (f) — cohérence durée ↔ majorations
Exemple : PREV = 20h lundi → 8h mardi (12h dont 11h nuit = 21h-8h + 20h-21h non nuit = en fait tout est nuit). EFF = 21h → 7h mardi = 10h toutes de nuit.
- `total_brut` : GREATEST(12, 10) × taux = 12 × taux
- `heures_nuit` : source = PREVISIONNEL (plus grand) → 11h (selon seuil nuit étab)
- `majoration_nuit` : 11h × taux × 25%
- **Correct** : la majoration porte sur les créneaux prévisionnels qui fournissent la durée plancher.

### Détails sur (g) — fn_verifier_pre_facturation
Nouveau comportement :
- **BLOQUE** si créneau EFFECTIF ouvert (fin IS NULL) — inchangé.
- **BLOQUE** si `EFF > PREV × 1.10` (dépassement > 10% suspect, admin valide).
- **N'Alerte pas** si EFF < PREV (garantie plancher = cas normal).
- Valeurs de retour enrichies : ajouter `duree_effective` dans le JSONB retour (aujourd'hui partiellement présent).

---

## Section 5 — Risques

### 5.1 Factures déjà émises
**Aucun impact rétroactif** : `factures_honoraires` est gelée par CP3 (`fn_bloquer_update_facture_honoraire_figee`). Les montants déjà posés en `montant_ht/ttc` sont figés. Seule `FH-2026-04-0011` diffère entre ancien et nouveau calcul — à retraiter manuellement si business le juge nécessaire (avoir + refacturation).

### 5.2 Missions futures
- Augmentation potentielle des `net_a_payer` sur les missions où l'effectif pointé < prévisionnel.
- **Commission Jolene** : calculée sur `total_brut` (même formule, ligne 78 de la fct 1.1) → la commission profite aussi de la garantie plancher. **À valider** : est-ce voulu ? (soignant reçoit 12h, Jolene commissionne sur 12h, étab paie 12h).
- **Cotisations sociales** (`cotisations_sociales` table) : calculées sur `net_a_payer` en aval → monteront aussi mécaniquement.

### 5.3 Edge cases découverts
1. **PREV = 0 + EFF > 0** (cas d) : accepté par GREATEST, mais signe un parcours de création cassé. Proposition : RAISE WARNING dans `fn_calculer_financier_mission` si `v_sum_prev = 0 AND v_has_creneaux`.
2. **Mission sans créneau du tout** (cas fallback `NOT v_has_creneaux`) : utilise `NEW.duree_heures` / `fin_le - debut_le`. Ce chemin n'est pas impacté par GREATEST (aucun créneau ni PREV ni EFF). Reste identique.
3. **`dec_verifier_plafond_48h`** conserve `COALESCE(eff, prev)` : plafond URSSAF compte les heures **travaillées**, pas contractuelles. Ne pas aligner sur GREATEST sous peine de sur-plafonner artificiellement.
4. **Commission étab vs net soignant** : si décision finale = "établissement paie la garantie plancher", alors commission Jolene sur total_brut est cohérent. Si décision = "Jolene absorbe la différence", il faudra découpler : `total_brut_facture_etab = taux × EFF` et `total_brut_paiement_soignant = taux × GREATEST(prev, eff)`. **Question à trancher avec Gabrielle avant implémentation.**

### 5.4 Tests à ajouter post-implémentation
- Test GREATEST sur 7 scénarios (a-g) → `tests/missions/garantie-heures.test.sql`
- Test régression factures gelées (pas de recalcul sur factures `EMISE`)
- Test idempotence : UPDATE mission → total_brut inchangé si créneaux inchangés

---

## Prochaines étapes (après validation Gabrielle)

1. Clarifier : commission Jolene sur GREATEST ou sur EFFECTIF uniquement ?
2. Clarifier : conserver blocage 10% asymétrique (EFF > PREV×1.10 uniquement) ou supprimer totalement ?
3. Implémentation (1 migration unique) : `20260417120000_garantie_heures_greatest.sql`
4. Tests SQL (`tests/missions/garantie-heures.test.sql`)
5. Revue manuelle : régénérer `FH-2026-04-0011` en mode simulation pour confirmer le delta chiffré.

**STOP** — audit terminé. En attente décision pour questions §5.4 (1-2) avant GO implémentation.
