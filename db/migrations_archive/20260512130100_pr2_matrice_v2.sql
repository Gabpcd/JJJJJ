-- PR 2 Sprint 1 v2 — Matrice compatibilité exercice × profession × type étab
-- (hotfix audit action constraint)
--
-- Contexte : empêcher le piège du salariat déguisé (Conseil d'Etat 11/02/2025
-- arrêt Mediflash + art. L8221-1 Code travail). Un IDE libéral en EHPAD privé
-- ou clinique privée serait juridiquement requalifiable.
--
-- HISTORIQUE :
-- - 20260512_pr2_*.sql : rejeté (format YYYYMMDD)
-- - 20260512120100_pr2_*.sql : rolled back par CHECK constraint
--   journaux_audit_action_check (action 'MATRICE_COMPATIBILITE_LIBERAL_
--   INSTALLED' pas dans la liste autorisée)
-- - Cette version v2 : action='SYSTEM' (autorisée) + contexte préservé.

-- 1. Ajouter les 8 nouveaux types d'établissement (cabinets libéraux)
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_MEDICAL';
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_DENTAIRE';
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_IDEL';
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_SAGE_FEMME';
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_KINE';
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_ORTHO';
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_ERGO';
ALTER TYPE public.type_etablissement ADD VALUE IF NOT EXISTS 'CABINET_PSYCHOMOT';

-- 2. RPC peut_exercer_liberal — matrice
CREATE OR REPLACE FUNCTION public.peut_exercer_liberal(
  p_profession text,
  p_type_etablissement text
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Matrice validée juridiquement par Gabrielle :
  --   MEDECIN libéral : cabinets, cliniques privées, EHPAD, SSIAD, HAD,
  --     centre de santé, MAS, FAM (CNOM art. R.4127-65).
  --   DENTISTE libéral : cabinet dentaire uniquement (CNOC art. R.4127-274).
  --   IDE libéral (IDEL) : cabinet IDEL UNIQUEMENT (R.4312-12 CSP).
  --     Tout autre = piège Mediflash requalifiable en travail dissimulé.
  --   SAGE_FEMME libérale : cabinet sage-femme, clinique privée (maternités),
  --     HAD, centre de santé.
  --   KINE libéral : cabinet kiné, clinique privée (rééducation), SSIAD,
  --     HAD, MAS, FAM.
  --   ORTHOPHONISTE libéral : cabinet ortho uniquement.
  --   ERGOTHERAPEUTE libéral : cabinet ergo ou HAD (intervention domicile).
  --   PSYCHOMOTRICIEN libéral : cabinet psychomot ou HAD.
  --   Toutes les autres professions : pas de libéral autorisé.
  RETURN CASE p_profession
    WHEN 'MEDECIN' THEN p_type_etablissement IN ('CABINET_MEDICAL', 'CLINIQUE_PRIVEE', 'EHPAD', 'SSIAD', 'HAD', 'CENTRE_SANTE', 'MAS', 'FAM')
    WHEN 'DENTISTE' THEN p_type_etablissement = 'CABINET_DENTAIRE'
    WHEN 'IDE' THEN p_type_etablissement = 'CABINET_IDEL'
    WHEN 'SAGE_FEMME' THEN p_type_etablissement IN ('CABINET_SAGE_FEMME', 'CLINIQUE_PRIVEE', 'HAD', 'CENTRE_SANTE')
    WHEN 'KINE' THEN p_type_etablissement IN ('CABINET_KINE', 'CLINIQUE_PRIVEE', 'SSIAD', 'HAD', 'MAS', 'FAM')
    WHEN 'ORTHOPHONISTE' THEN p_type_etablissement = 'CABINET_ORTHO'
    WHEN 'ERGOTHERAPEUTE' THEN p_type_etablissement IN ('CABINET_ERGO', 'HAD')
    WHEN 'PSYCHOMOTRICIEN' THEN p_type_etablissement IN ('CABINET_PSYCHOMOT', 'HAD')
    ELSE FALSE
  END;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.peut_exercer_liberal(text, text) TO anon, authenticated;

COMMENT ON FUNCTION public.peut_exercer_liberal IS
  'Matrice de compatibilité profession × type établissement pour le mode libéral. '
  'Renvoie FALSE pour les combinaisons non autorisées par la réglementation '
  '(évite le piège du salariat déguisé, cf Conseil d''Etat 11/02/2025).';

-- 3. RPC peut_exercer (wrapper salarié + libéral)
CREATE OR REPLACE FUNCTION public.peut_exercer(
  p_profession text,
  p_type_exercice text,
  p_type_etablissement text
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_type_exercice IN ('SALARIE', 'CDD', 'CDDU', 'VACATION') THEN
    RETURN TRUE;
  END IF;

  IF p_type_exercice IN ('LIBERAL', 'MIXTE') THEN
    RETURN public.peut_exercer_liberal(p_profession, p_type_etablissement);
  END IF;

  RETURN TRUE;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.peut_exercer(text, text, text) TO anon, authenticated;

-- 4. Trigger sur missions : refuser la publication d'une mission LIBERAL
-- pour un couple profession × type établissement incompatible.
CREATE OR REPLACE FUNCTION public.dec_valider_compatibilite_mission_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type_etab text;
BEGIN
  IF NEW.type_contrat_recherche IS DISTINCT FROM 'LIBERAL' THEN
    RETURN NEW;
  END IF;

  SELECT type::text INTO v_type_etab FROM public.etablissements
  WHERE id = NEW.etablissement_id;

  IF NEW.profession_requise IS NOT NULL AND v_type_etab IS NOT NULL THEN
    IF NOT public.peut_exercer_liberal(NEW.profession_requise, v_type_etab) THEN
      RAISE EXCEPTION
        '[CODE DU TRAVAIL] La profession % ne peut pas exercer en libéral en % '
        '(cas de salariat déguisé, art. L8221-1 Code travail + Conseil d''Etat 11/02/2025). '
        'Proposez la mission en CDD ou Vacation.',
        NEW.profession_requise, v_type_etab;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_valider_compatibilite_mission_liberal ON public.missions;
CREATE TRIGGER trg_dec_valider_compatibilite_mission_liberal
  BEFORE INSERT OR UPDATE OF type_contrat_recherche, profession_requise, etablissement_id
  ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.dec_valider_compatibilite_mission_liberal();

-- 5. Audit trail avec action='SYSTEM' (valeur autorisée)
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'MATRICE_COMPATIBILITE_LIBERAL_INSTALLED',
    'pr', 'PR 2 Sprint 1 révisé (v2 hotfix audit action)',
    'nouveaux_types_etab', ARRAY['CABINET_MEDICAL','CABINET_DENTAIRE','CABINET_IDEL','CABINET_SAGE_FEMME','CABINET_KINE','CABINET_ORTHO','CABINET_ERGO','CABINET_PSYCHOMOT'],
    'rpcs_creees', ARRAY['peut_exercer_liberal','peut_exercer'],
    'triggers_crees', ARRAY['trg_dec_valider_compatibilite_mission_liberal'],
    'reference_juridique', 'Conseil d''Etat 11/02/2025 (arrêt Mediflash) + art. L8221-1 Code travail'
  )
);
