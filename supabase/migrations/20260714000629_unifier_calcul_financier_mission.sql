-- Unifie le calcul financier d'une mission.
--
-- Le trigger historique trg_calculer_financier s'exécutait après
-- dec_mission_z_finance et réécrivait les montants avec le plafond Rist
-- générique de l'établissement. Il plafonnait ainsi, entre autres, une mission
-- MEDECIN libérale affichée à 90 €/h sur une base de 30 €/h.
--
-- dec_mission_z_finance (dec_calculer_finance_mission) reste l'unique moteur de
-- rémunération. dec_net_estime ne fait ensuite que convertir son net à payer en
-- estimation nette ; dec_mission_commission conserve son rôle à la clôture.

DROP TRIGGER IF EXISTS trg_calculer_financier ON public.missions;
DROP FUNCTION IF EXISTS public.fn_calculer_financier_mission();

-- Le plafond éventuel suit la profession REQUISE PAR LA MISSION. Le diplôme ou
-- la spécialisation supplémentaire du soignant assigné ne change jamais le
-- taux applicable à la mission.
CREATE OR REPLACE FUNCTION public.dec_appliquer_plafond_rist()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_plafond numeric;
  v_est_secteur_public boolean;
  v_regime_effectif text;
BEGIN
  -- Avant assignation, le taux publié est le taux réellement utilisé pour
  -- l'estimation. Le plafond ne peut être figé qu'avec un contrat salarié.
  IF NEW.soignant_assigne_id IS NULL THEN
    NEW.taux_rist_plafonne := NEW.taux_horaire_base;
    NEW.rist_plafond_applique := false;
    RETURN NEW;
  END IF;

  SELECT e.est_secteur_public
    INTO v_est_secteur_public
    FROM public.etablissements e
   WHERE e.id = NEW.etablissement_id;

  -- Après assignation, le choix réellement figé prime toujours sur le filtre
  -- de recherche. Une mission publiée « TOUS » puis attribuée en LIBERAL ne
  -- doit notamment jamais recevoir un plafond salarié.
  v_regime_effectif := COALESCE(
    NEW.type_contrat_applique::text,
    NULLIF(upper(btrim(NEW.choix_contrat_soignant)), ''),
    CASE WHEN NEW.type_contrat_recherche = 'SALARIE' THEN 'SALARIE' ELSE NULL END
  );

  IF NOT COALESCE(v_est_secteur_public, false)
     OR v_regime_effectif IS DISTINCT FROM 'SALARIE' THEN
    NEW.taux_rist_plafonne := NEW.taux_horaire_base;
    NEW.rist_plafond_applique := false;
    RETURN NEW;
  END IF;

  SELECT rp.plafond_calcule
    INTO v_plafond
    FROM public.rist_plafonds rp
   WHERE rp.profession = NEW.profession_requise
     AND rp.type_contrat IN ('CDD', 'SALARIE', 'VACATION')
     AND rp.en_vigueur_depuis <= CURRENT_DATE
     AND (rp.en_vigueur_jusqua IS NULL OR rp.en_vigueur_jusqua >= CURRENT_DATE)
   ORDER BY rp.en_vigueur_depuis DESC
   LIMIT 1;

  IF v_plafond IS NOT NULL AND NEW.taux_horaire_base > v_plafond THEN
    NEW.taux_rist_plafonne := v_plafond;
    NEW.rist_plafond_applique := true;
  ELSE
    NEW.taux_rist_plafonne := NEW.taux_horaire_base;
    NEW.rist_plafond_applique := false;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_appliquer_plafond_rist() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_appliquer_plafond_rist() TO service_role;

COMMENT ON FUNCTION public.dec_appliquer_plafond_rist() IS
  'Détermine le taux Rist depuis la profession requise par la mission, uniquement après assignation salariée dans le secteur public.';

DO $verification$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM pg_trigger
     WHERE tgrelid = 'public.missions'::regclass
       AND tgname = 'trg_calculer_financier'
       AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Le trigger financier historique trg_calculer_financier est encore actif';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_trigger t
      JOIN pg_proc p ON p.oid = t.tgfoid
     WHERE t.tgrelid = 'public.missions'::regclass
       AND t.tgname = 'dec_mission_z_finance'
       AND p.proname = 'dec_calculer_finance_mission'
       AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Le moteur financier canonique dec_mission_z_finance est absent';
  END IF;
END;
$verification$;
