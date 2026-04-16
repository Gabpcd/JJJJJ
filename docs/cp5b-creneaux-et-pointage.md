# CP5b — Créneaux prévisionnels vs effectifs + système de pointage

> Date : 2026-04-16
> Statut : AUDIT — validation section par section avant implémentation
> Dépend de : CP5a (colonnes _fige, trigger gel, refonte 4 triggers)

---

## 1. Modifications du modèle `mission_creneaux`

### 1.1 Nouvelle colonne `type_creneau`

```sql
ALTER TABLE public.mission_creneaux
  ADD COLUMN IF NOT EXISTS type_creneau text NOT NULL DEFAULT 'PREVISIONNEL';

ALTER TABLE public.mission_creneaux
  ADD CONSTRAINT chk_type_creneau CHECK (type_creneau IN ('PREVISIONNEL', 'EFFECTIF'));
```

Pas d'enum Postgres (décision Gabrielle — trop rigide pour les migrations futures).

### 1.2 Migration des 265 créneaux existants

Tous les créneaux existants sont prévisionnels (saisis par étab ou migrés en CP3). Le `DEFAULT 'PREVISIONNEL'` couvre automatiquement les 265 rows existantes — pas de backfill UPDATE nécessaire.

**Vérification post-migration :**
```sql
SELECT type_creneau, COUNT(*) FROM mission_creneaux GROUP BY type_creneau;
-- Attendu : PREVISIONNEL = 265 (ou plus si créneaux ajoutés entre-temps)
```

### 1.3 Immutabilité des PREVISIONNEL après gel

Les créneaux PREVISIONNEL d'une mission gelée (`missions.fige_le IS NOT NULL`) sont protégés par le trigger `trg_protect_creneaux_facture` (CP3) qui bloque toute modification si une facture émise existe.

**Extension CP5b** : bloquer aussi les modifications des PREVISIONNEL si `fige_le IS NOT NULL` (même sans facture), sauf bypass admin tracé. Logique ajoutée dans `fn_protect_creneaux_si_facture` :

```sql
-- Après le check facture existant, ajouter :
IF v_type_creneau = 'PREVISIONNEL' THEN
  SELECT fige_le INTO v_fige_le FROM missions WHERE id = v_mission_id;
  IF v_fige_le IS NOT NULL THEN
    -- Bloqué sauf admin override (même pattern que fn_geler)
    IF current_setting('jolene.admin_override_gel', true) = v_mission_id::text
       AND COALESCE(current_setting('jolene.admin_override_reason', true), '') != '' THEN
      -- Audit + allow
    ELSE
      RAISE EXCEPTION 'Créneaux prévisionnels immutables après gel (fige_le=%)...', v_fige_le;
    END IF;
  END IF;
END IF;
```

Les créneaux EFFECTIF ne sont **pas** soumis à cette immutabilité — ils sont dynamiques jusqu'à validation.

### 1.4 Impact sur le sync trigger

`fn_sync_mission_creneaux` maintient `missions.debut_le/fin_le/duree_heures/nb_creneaux` à partir des créneaux. Avec deux types :

**Décision Q2 : le span (debut_le/fin_le) reste calé sur les PREVISIONNEL.**

Le sync trigger est modifié pour :

| Champ mission | Source | Filtre |
|---|---|---|
| `debut_le` | `MIN(debut)` | `WHERE type_creneau = 'PREVISIONNEL'` |
| `fin_le` | `MAX(fin)` | `WHERE type_creneau = 'PREVISIONNEL'` |
| `duree_heures` | `SUM(fin - debut) WHERE NOT est_pause` | `WHERE type_creneau = 'PREVISIONNEL'` |
| `nb_creneaux` | `COUNT(*)` | `WHERE type_creneau = 'PREVISIONNEL'` |
| `debut_effectif` | `MIN(debut)` | `WHERE type_creneau = 'EFFECTIF'` |
| `fin_effective` | `MAX(fin)` | `WHERE type_creneau = 'EFFECTIF'` |
| `duree_heures_effective` | `SUM(fin - debut) WHERE NOT est_pause` | `WHERE type_creneau = 'EFFECTIF'` |

**3 nouvelles colonnes sur `missions`** (décision Q2) :
```sql
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS debut_effectif timestamptz,
  ADD COLUMN IF NOT EXISTS fin_effective timestamptz,
  ADD COLUMN IF NOT EXISTS duree_heures_effective numeric;
```

Si aucun créneau EFFECTIF n'existe, ces 3 colonnes restent NULL.

### 1.5 Impact sur `fn_calculer_financier_mission`

**Décision Q3 : EFFECTIF après validation étab, fallback PREVISIONNEL.**

Le calculateur financier lit actuellement `mission_creneaux WHERE NOT est_pause` sans filtre type. Il est modifié pour :

```sql
-- Priorité EFFECTIF validés, fallback PREVISIONNEL
SELECT COALESCE(
  SUM(EXTRACT(EPOCH FROM (mc.fin - mc.debut)) / 3600.0)
    FILTER (WHERE mc.type_creneau = 'EFFECTIF' AND NOT mc.est_pause),
  SUM(EXTRACT(EPOCH FROM (mc.fin - mc.debut)) / 3600.0)
    FILTER (WHERE mc.type_creneau = 'PREVISIONNEL' AND NOT mc.est_pause),
  0
) INTO v_duree
FROM mission_creneaux mc WHERE mc.mission_id = NEW.id;
```

**Même logique pour `fn_trg_auto_heures_majorees`** : itérer sur EFFECTIF si existent, sinon PREVISIONNEL.

**Condition "après validation"** : un créneau EFFECTIF est considéré "validé" quand tous les scans associés ont `valide_par_etab = true` OU quand `validation_etab_requise = false`. Pour V1, on utilise tous les EFFECTIF (fermés, ie `fin IS NOT NULL`), la validation étab est un garde-fou UI, pas un filtre SQL dans le calculateur.

### 1.6 Impact sur les 4 triggers CP5a

| Trigger | Filtre actuel | Changement CP5b |
|---|---|---|
| `fn_trg_auto_heures_majorees` | `WHERE NOT est_pause` | Ajouter priorité EFFECTIF/PREVISIONNEL (même COALESCE que 1.5) |
| `dec_verifier_plafond_48h` | `WHERE NOT est_pause` | Sommer les EFFECTIF si existent pour les missions EN_COURS/TERMINEE, PREVISIONNEL pour les ASSIGNEE (pas encore de pointage) |
| `dec_verifier_repos_11h` | `WHERE NOT est_pause` | Utiliser EFFECTIF si existent (repos réel), fallback PREVISIONNEL |
| `dec_refuser_chevauchement_soignant` | Span `debut_le/fin_le` | Inchangé (D1 : span = PREVISIONNEL) |

---

## 2. Modèle de pointage

### 2.1 Table `scans_pointage`

```sql
CREATE TABLE public.scans_pointage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL REFERENCES missions(id),
  soignant_id uuid NOT NULL REFERENCES auth.users(id),

  -- Code et scan
  code_saisi text NOT NULL,
  numero_scan smallint NOT NULL,
  type_scan text NOT NULL CHECK (type_scan IN ('OUVERTURE', 'FERMETURE')),
  scanne_le timestamptz NOT NULL DEFAULT now(),
  horodatage_arrondi timestamptz NOT NULL,

  -- Créneau effectif lié
  creneau_effectif_id uuid REFERENCES mission_creneaux(id) ON DELETE CASCADE,

  -- Validation
  est_en_avance boolean NOT NULL DEFAULT false,
  validation_etab_requise boolean NOT NULL DEFAULT false,
  valide_par_etab boolean NOT NULL DEFAULT false,
  valide_le timestamptz,
  valide_par uuid REFERENCES auth.users(id),

  -- Métadonnées géoloc (absorbées de presences)
  latitude numeric,
  longitude numeric,
  precision_gps_m numeric,
  id_terminal text,
  ip_address inet,
  distance_etablissement_m numeric,

  cree_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.scans_pointage ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_scans_pointage_mission ON scans_pointage(mission_id, numero_scan);
CREATE INDEX idx_scans_pointage_code ON scans_pointage(code_saisi);
```

**RLS :**
- INSERT : soignant assigné à la mission (`auth.uid() = soignant_id`)
- SELECT : soignant assigné OU admin_etablissement OU admin
- UPDATE (validation) : admin_etablissement OU admin

### 2.2 Colonnes ajoutées sur `missions`

```sql
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS code_pointage_actif text,
  ADD COLUMN IF NOT EXISTS code_pointage_hmac text,
  ADD COLUMN IF NOT EXISTS prochain_type_scan text DEFAULT 'OUVERTURE'
    CHECK (prochain_type_scan IN ('OUVERTURE', 'FERMETURE')),
  ADD COLUMN IF NOT EXISTS nb_scans smallint DEFAULT 0;
```

Remplacement de `code_arrivee`/`code_depart` (gardés mais DEPRECATED — pas de DROP pour compat frontend existant).

### 2.3 RPC `fn_scanner_code_pointage(p_code text, p_metadata jsonb DEFAULT NULL)`

**SECURITY DEFINER SET search_path TO 'public'** — obligatoire car le soignant appelant n'a pas les droits RLS pour INSERT `mission_creneaux` ni UPDATE `missions` (protecteurs freeze). Le check `auth.uid() = soignant_assigne_id` est fait DANS la fonction (step 2), pas par RLS.

Flux :
```
1. SELECT mission WHERE code_pointage_actif = p_code
   → 404 si pas trouvé (code invalide/expiré)

2. Vérifier auth.uid() = soignant_assigne_id
   → 403 si soignant non assigné

3. Anti-doublon : dernier scan < 2 min → "scan déjà pris en compte"

4. Lire prochain_type_scan ('OUVERTURE' ou 'FERMETURE')

5. Si OUVERTURE :
   a. Vérifier fenêtre : scan > 15 min avant MIN(debut) PREVISIONNEL → bloquer
   b. Arrondir now() au quart d'heure le plus proche
   c. INSERT mission_creneaux (type='EFFECTIF', debut=arrondi, fin=NULL)
   d. INSERT scans_pointage (type='OUVERTURE', creneau_effectif_id=new)
   e. UPDATE mission SET prochain_type_scan='FERMETURE', nb_scans=nb_scans+1

6. Si FERMETURE :
   a. Arrondir now() au quart d'heure
   b. UPDATE mission_creneaux SET fin=arrondi WHERE type='EFFECTIF' AND fin IS NULL
   c. INSERT scans_pointage (type='FERMETURE', creneau_effectif_id=creneau)
   d. UPDATE mission SET prochain_type_scan='OUVERTURE', nb_scans=nb_scans+1

7. Dans tous les cas :
   a. Invalider code actuel
   b. Générer nouveau code + HMAC
   c. UPDATE mission SET code_pointage_actif=new, code_pointage_hmac=new_hmac

8. Retourner :
   { nouveau_code, nouveau_hmac, type_scan_effectue, prochain_type_scan,
     creneau_effectif_id, horodatage_arrondi }
```

**Arrondi au quart d'heure :**
```sql
-- Arrondi au quart d'heure le plus proche
v_arrondi := date_trunc('hour', v_now) + 
  INTERVAL '15 minutes' * ROUND(EXTRACT(MINUTE FROM v_now) / 15.0);
```

### 2.4 Marquage validation étab

| Condition | `validation_etab_requise` | Effet |
|---|---|---|
| Scan > 15 min avant premier créneau prévisionnel | `true` + `est_en_avance = true` | Créneau effectif créé mais flaggé, étab doit valider |
| Scan > 24h après dernier créneau prévisionnel | `true` | Idem |
| Scan dans fenêtre normale | `false` | Créneau effectif auto-validé |

### 2.5 Deprecation `presences`

La table `presences` est marquée DEPRECATED. Aucun DROP — le frontend existant peut la lire. Les nouvelles fonctionnalités passent par `scans_pointage` + `mission_creneaux EFFECTIF`.

Documenter dans `/docs/modules-futurs.md` : « Migration presences → scans_pointage, nettoyage post-lancement. »

---

## 3. Génération et affichage des codes

### 3.1 Génération initiale

Le premier code est généré lors de la transition `OUVERTE → ASSIGNEE`. Le trigger `fn_geler_mission_a_assignation` (CP5a, Bloc 1 GEL) est étendu :

```sql
-- À la fin du Bloc 1 GEL, après les _fige :
NEW.code_pointage_actif := lpad(floor(random() * 1000000)::text, 6, '0');
NEW.code_pointage_hmac := encode(
  hmac(NEW.id::text || ':' || NEW.code_pointage_actif, 
       current_setting('app.settings.hmac_secret', true), 'sha256'),
  'hex'
);
NEW.prochain_type_scan := 'OUVERTURE';
NEW.nb_scans := 0;
```

**Secret HMAC** : variable serveur `app.settings.hmac_secret` (à configurer dans Supabase → Project Settings → Database → Settings). Si absent, le HMAC est NULL et le QR ne contient que le code 6 chiffres (mode dégradé).

### 3.2 Régénération à chaque scan

Dans `fn_scanner_code_pointage` (step 7), après chaque scan :
```sql
v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
-- S'assurer que le nouveau code est unique parmi les missions actives
WHILE EXISTS (
  SELECT 1 FROM missions 
  WHERE code_pointage_actif = v_new_code 
    AND id != p_mission_id
    AND statut IN ('ASSIGNEE', 'EN_COURS')
) LOOP
  v_new_code := lpad(floor(random() * 1000000)::text, 6, '0');
END LOOP;
```

**Unicité** : le code doit être unique parmi les missions actives (ASSIGNEE/EN_COURS). Avec 1M codes possibles et ~50 missions actives simultanées, la probabilité de collision est < 0.005%. Le WHILE LOOP est une sécurité.

### 3.3 Payload QR

```
jolene://pointage/{mission_id}/{code}?h={hmac_first_8_chars}
```

- `mission_id` : UUID de la mission (identifie automatiquement la mission dans l'app)
- `code` : 6 chiffres (saisie manuelle fallback)
- `h` : 8 premiers caractères du HMAC (vérification serveur anti-falsification)

Le serveur reconstruit le HMAC complet et compare :
```sql
IF left(encode(hmac(p_mission_id::text || ':' || p_code, secret, 'sha256'), 'hex'), 8) != p_hmac THEN
  RAISE EXCEPTION 'QR invalide';
END IF;
```

### 3.4 Affichage côté étab

**Option retenue : subscription Supabase Realtime.**

L'étab s'abonne aux changements de `missions.code_pointage_actif` via Realtime :
```typescript
supabase.channel('pointage')
  .on('postgres_changes', {
    event: 'UPDATE', schema: 'public', table: 'missions',
    filter: `id=eq.${missionId}`
  }, (payload) => {
    setCodeActif(payload.new.code_pointage_actif);
  })
  .subscribe();
```

Chaque scan régénère le code → l'étab voit le nouveau code en temps réel (~200ms de latence Realtime).

**Fallback** : RPC `fn_codes_pointage_mission(uuid)` existante, adaptée pour retourner `code_pointage_actif` au lieu de `code_arrivee/code_depart`.

---

## 4. Garde-fous

### 4.1 Fenêtre temporelle

| Moment | Règle | Action |
|---|---|---|
| > 15 min avant MIN(debut) PREVISIONNEL | **Bloqué** | RAISE EXCEPTION, pas de créneau EFFECTIF créé |
| 0-15 min avant debut prévisionnel | **Autorisé avec flag** | `est_en_avance = true`, `validation_etab_requise = true` |
| Dans la fenêtre prévisionnelle | **Autorisé** | Pas de flag |
| 0-24h après MAX(fin) PREVISIONNEL | **Autorisé** | Pas de flag |
| > 24h après MAX(fin) PREVISIONNEL | **Autorisé avec flag** | `validation_etab_requise = true` |

**Implémentation dans `fn_scanner_code_pointage`** (step 5a) :
```sql
SELECT MIN(debut) INTO v_premier_prevu
FROM mission_creneaux
WHERE mission_id = v_mission_id AND type_creneau = 'PREVISIONNEL';

IF v_now < v_premier_prevu - INTERVAL '15 minutes' THEN
  RAISE EXCEPTION 'Pointage trop tôt. La mission commence à %. Pointage possible à partir de %.',
    TO_CHAR(v_premier_prevu AT TIME ZONE 'Europe/Paris', 'HH24:MI'),
    TO_CHAR((v_premier_prevu - INTERVAL '15 minutes') AT TIME ZONE 'Europe/Paris', 'HH24:MI')
    USING ERRCODE = 'check_violation';
END IF;

v_est_en_avance := (v_now < v_premier_prevu);

SELECT MAX(fin) INTO v_dernier_prevu
FROM mission_creneaux
WHERE mission_id = v_mission_id AND type_creneau = 'PREVISIONNEL';

v_validation_requise := v_est_en_avance OR (v_now > v_dernier_prevu + INTERVAL '24 hours');
```

### 4.2 Arrondi au quart d'heure

Standard hospitalier. Fonction utilitaire :
```sql
CREATE OR REPLACE FUNCTION public.fn_arrondir_quart_heure(p_ts timestamptz)
RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
  SELECT date_trunc('hour', p_ts) +
    INTERVAL '15 minutes' * ROUND(EXTRACT(MINUTE FROM p_ts) / 15.0);
$$;
```

Exemples :
- 08:06 → 08:00
- 08:08 → 08:15
- 08:22 → 08:15
- 08:38 → 08:45

L'arrondi s'applique à l'horodatage qui sera écrit dans `mission_creneaux.debut` (OUVERTURE) ou `mission_creneaux.fin` (FERMETURE). L'horodatage exact est dans `scans_pointage.scanne_le`, l'arrondi dans `scans_pointage.horodatage_arrondi`.

### 4.3 Anti-doublon (scans rapprochés < 2 min)

```sql
SELECT scanne_le INTO v_dernier_scan
FROM scans_pointage
WHERE mission_id = v_mission_id
ORDER BY numero_scan DESC LIMIT 1;

IF v_dernier_scan IS NOT NULL AND v_now - v_dernier_scan < INTERVAL '2 minutes' THEN
  RAISE EXCEPTION 'Scan déjà pris en compte (il y a %). Prochain scan possible dans %.',
    TO_CHAR(v_now - v_dernier_scan, 'MI:SS'),
    TO_CHAR(v_dernier_scan + INTERVAL '2 minutes' - v_now, 'MI:SS')
    USING ERRCODE = 'check_violation';
END IF;
```

### 4.4 Oubli de scan fin

**Scénario** : le soignant oublie de scanner en partant. `prochain_type_scan = 'FERMETURE'` mais il est déjà parti. Le créneau EFFECTIF a `debut` mais `fin IS NULL`.

**Solution : RPC `fn_declarer_fin_retroactive`** :
```sql
fn_declarer_fin_retroactive(
  p_mission_id uuid,
  p_heure_fin timestamptz,    -- heure déclarée par le soignant
  p_raison text DEFAULT 'Oubli de scan'
)
```

Flux :
1. Vérifie qu'il existe un créneau EFFECTIF ouvert (`fin IS NULL`)
2. Vérifie que `p_heure_fin > debut` du créneau ouvert
3. Arrondit au quart d'heure
4. UPDATE créneau EFFECTIF `SET fin = arrondi`
5. INSERT scan_pointage fictif (`type = 'FERMETURE'`, `validation_etab_requise = true`)
6. UPDATE mission `SET prochain_type_scan = 'OUVERTURE'`
7. Régénère un nouveau code

Le créneau est **automatiquement flaggé** `validation_etab_requise = true`. L'étab doit confirmer dans les 48h (logique UI, pas SQL).

---

## 5. Impact sur `generate-invoice`

### 5.1 Sélection des créneaux pour facturation

La edge function `generate-invoice` lit actuellement `mission_creneaux WHERE NOT est_pause` sans filtre type. Modification :

```sql
-- Créneaux pour calcul facture
SELECT debut, fin, est_pause
FROM mission_creneaux
WHERE mission_id = p_mission_id
  AND NOT est_pause
  AND type_creneau = CASE
    WHEN EXISTS (
      SELECT 1 FROM mission_creneaux
      WHERE mission_id = p_mission_id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL
    ) THEN 'EFFECTIF'
    ELSE 'PREVISIONNEL'
  END;
```

**Règle** : si au moins un créneau EFFECTIF fermé existe → facturer sur EFFECTIF. Sinon → fallback PREVISIONNEL.

**Pas de mix** : on ne mélange pas EFFECTIF et PREVISIONNEL dans une même facture. C'est l'un ou l'autre.

### 5.2 Garde-fou pré-facturation

Avant d'émettre la facture, vérifier :
```sql
-- Alerte si écart > 10% entre prévisionnel et effectif
SELECT
  ABS(duree_heures - COALESCE(duree_heures_effective, duree_heures)) AS ecart_heures,
  CASE WHEN duree_heures > 0 THEN
    ABS(duree_heures - COALESCE(duree_heures_effective, duree_heures)) / duree_heures * 100
  ELSE 0 END AS ecart_pourcent
FROM missions WHERE id = p_mission_id;
```

**BLOQUANT** (décision C3) : si `ecart_pourcent > 10` ET facturation sur EFFECTIF → RAISE EXCEPTION. Le soignant ou l'étab doit compléter le pointage via `fn_declarer_fin_retroactive` avant facturation.

Vérification supplémentaire : si un créneau EFFECTIF est ouvert (`fin IS NULL`) → RAISE EXCEPTION. Pas de facturation tant qu'un créneau est en cours.

---

## 6. Impact sur les triggers existants

### 6.1 `fn_sync_mission_creneaux`

**Changement majeur** : le sync trigger doit maintenir 2 sets de colonnes dénormalisées.

```sql
-- Phase 1 (sync=true) : span PREVISIONNEL
SELECT MIN(debut), MAX(fin),
  COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0),
  COUNT(*)
INTO v_debut, v_fin, v_duree, v_nb
FROM mission_creneaux
WHERE mission_id = v_mission_id AND type_creneau = 'PREVISIONNEL';

-- Phase 2 (sync=false) : effectifs
SELECT MIN(debut), MAX(fin),
  COALESCE(SUM(CASE WHEN NOT est_pause THEN EXTRACT(EPOCH FROM (fin - debut)) / 3600.0 ELSE 0 END), 0)
INTO v_debut_eff, v_fin_eff, v_duree_eff
FROM mission_creneaux
WHERE mission_id = v_mission_id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL;
```

Le Phase 1 UPDATE écrit `debut_le/fin_le/duree_heures/nb_creneaux` (PREVISIONNEL).
Le Phase 2 UPDATE écrit `duree_heures` + `debut_effectif/fin_effective/duree_heures_effective` (EFFECTIF si existent, sinon NULL).

### 6.2 `fn_calculer_financier_mission`

Modifié pour utiliser le COALESCE EFFECTIF/PREVISIONNEL décrit en section 1.5. Le taux horaire et les majorations viennent toujours des `_fige` (CP5a).

### 6.3 `fn_trg_auto_heures_majorees`

Modifié pour itérer sur EFFECTIF (fermés) si existent, sinon PREVISIONNEL. Logique :
```sql
-- Choix du type de créneaux
IF EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL) THEN
  v_type_source := 'EFFECTIF';
ELSE
  v_type_source := 'PREVISIONNEL';
END IF;

FOR v_creneau IN
  SELECT debut, fin FROM mission_creneaux
  WHERE mission_id = NEW.id AND type_creneau = v_type_source AND NOT est_pause
LOOP ...
```

### 6.4 `dec_verifier_plafond_48h` et `dec_verifier_repos_11h`

Même logique : EFFECTIF si existent pour les missions EN_COURS/TERMINEE, PREVISIONNEL pour ASSIGNEE (pas encore de pointage). Le filtre :
```sql
AND type_creneau = CASE
  WHEN m.statut IN ('EN_COURS', 'TERMINEE') AND EXISTS (
    SELECT 1 FROM mission_creneaux mc2
    WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL
  ) THEN 'EFFECTIF'
  ELSE 'PREVISIONNEL'
END
```

### 6.5 `fn_geler_mission_a_assignation` (CP5a)

**Bloc 1 GEL** : étendu pour générer `code_pointage_actif` + HMAC (section 3.1). Ajoute aussi un INSERT `GEL_APPLIED` dans `journaux_audit` avec le snapshot complet (_fige + code initial). Décision Q1 : traçabilité complète du cycle gel/dégel.

**Bloc 2 DEGEL** : cleanup complet avec suppression sync re-entrance (décision C4) :
```sql
PERFORM set_config('jolene.sync_in_progress', 'true', true);
DELETE FROM mission_creneaux WHERE mission_id = OLD.id AND type_creneau = 'EFFECTIF';
-- CASCADE → scans_pointage auto-deleted via FK ON DELETE CASCADE
PERFORM set_config('jolene.sync_in_progress', 'false', true);

NEW.debut_effectif := NULL;
NEW.fin_effective := NULL;
NEW.duree_heures_effective := NULL;
NEW.code_pointage_actif := NULL;
NEW.code_pointage_hmac := NULL;
NEW.prochain_type_scan := NULL;
NEW.nb_scans := 0;
```

**Bloc 3 PROTECTION** : `code_pointage_actif` n'est PAS dans les champs bloqués — il change à chaque scan.

### 6.6 `trg_protect_creneaux_facture`

Étendu (section 1.3) : bloque aussi les PREVISIONNEL quand `fige_le IS NOT NULL`.
Les EFFECTIF ne sont PAS bloqués par ce trigger — ils sont créés/modifiés par le pointage.

---

## 7. Risques

### R1 — Race condition sur le code actif

**Scénario** : deux personnes scannent le même code en parallèle (< 2ms).

**Mitigation** : la RPC `fn_scanner_code_pointage` utilise `SELECT ... FOR UPDATE` sur la mission pour obtenir un lock exclusif :
```sql
SELECT code_pointage_actif, prochain_type_scan INTO v_mission
FROM missions WHERE id = v_mission_id FOR UPDATE;
```
Le deuxième scan attend le lock, puis trouve un code invalide (régénéré par le premier scan) → RAISE 'Code invalide'.

### R2 — Soignant non assigné scanne un code

**Mitigation** : step 2 de la RPC vérifie `auth.uid() = missions.soignant_assigne_id`. RAISE EXCEPTION 'Vous n\'êtes pas assigné à cette mission.'

### R3 — Brute force code 6 chiffres

**Analyse** : 1M combinaisons, code régénéré à chaque scan. Un attaquant devrait trouver LE code actif d'UNE mission spécifique. Avec rate limiting Supabase (100 req/min par IP), un brute force prendrait ~7 jours.

**Mitigations** :
1. Le code seul ne suffit pas — il faut aussi être `soignant_assigne_id` (auth JWT)
2. HMAC dans le QR empêche la génération de QR falsifiés
3. Rate limit sur l'edge function de scan (10 tentatives/min par soignant)
4. Log des tentatives échouées dans `journaux_audit`

### R4 — Créneau effectif jamais fermé

**Scénario** : soignant ouvre un créneau (OUVERTURE) puis ne scanne jamais la FERMETURE.

**Mitigation** :
1. `fn_declarer_fin_retroactive` (section 4.4) pour déclaration manuelle
2. Cron job (edge function schedulée) : détecter les créneaux EFFECTIF `WHERE fin IS NULL AND debut < now() - INTERVAL '24 hours'` → envoyer notification au soignant + flaguer `validation_etab_requise`
3. `generate-invoice` refuse de facturer si un créneau EFFECTIF est ouvert (`fin IS NULL`)

### R5 — Volume de données missions longues

**Scénario** : mission de 3 semaines, soignant scanne 4 fois/jour → 84 scans + 42 créneaux EFFECTIF.

**Analyse** : acceptable. La table `scans_pointage` aura ~100 rows par mission longue. Avec index sur `(mission_id, numero_scan)`, les queries sont O(log n). Pas de problème de perf avant ~100K missions actives.

### R6 — Interaction gel + pointage

**Scénario** : mission gelée (ASSIGNEE), le soignant scanne (OUVERTURE). Le gel bloque les _fige mais le pointage crée un créneau EFFECTIF.

**Analyse** : pas de conflit. Le créneau EFFECTIF est un INSERT dans `mission_creneaux`, pas un UPDATE des _fige. Le trigger `fn_protect_creneaux_si_facture` ne bloque pas les INSERT (seulement si facture émise). Le trigger `trg_zz_geler_mission` ne fire que sur UPDATE de missions (pas de mission_creneaux). Transparent.

### R7 — HMAC secret manquant

**Scénario** : `app.settings.hmac_secret` pas configuré dans Supabase.

**Mitigation** : dégradation gracieuse. Si `current_setting('app.settings.hmac_secret', true)` retourne NULL, le HMAC n'est pas généré, le QR ne contient que `jolene://pointage/{mission_id}/{code}`. La vérification HMAC est skippée si le paramètre `h` est absent du QR. Documenter dans les instructions de déploiement.

---

## Steps d'implémentation proposés

| Step | Contenu | Dépendances |
|---|---|---|
| **1** | DDL : colonne `type_creneau` + 3 colonnes missions + colonnes pointage + table `scans_pointage` | — |
| **2** | Sync trigger : filtrer par type_creneau, maintenir colonnes effectif | Step 1 |
| **3** | RPC `fn_scanner_code_pointage` + `fn_arrondir_quart_heure` + code gen dans gel trigger | Step 1, 2 |
| **4** | Mise à jour triggers CP5a : EFFECTIF/PREVISIONNEL COALESCE dans calculateur + heures majorées | Step 1, 2 |
| **5** | Garde-fous : fenêtre, anti-doublon, `fn_declarer_fin_retroactive` | Step 3 |
| **6** | Protection créneaux PREVISIONNEL post-gel + impact generate-invoice | Step 1 |
| **7** | Tests (objectif : 10+ scénarios) | All |

---

*Audit CP5b complet. En attente de validation Gabrielle avant implémentation.*
