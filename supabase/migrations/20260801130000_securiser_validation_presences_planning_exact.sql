-- Une présence ne doit déclencher validation, facturation ou paiement qu'une
-- fois le planning contractuel entièrement terminé et tous les segments réels
-- fermés. Ce garde central couvre les validations unitaires, par lot, les
-- automatisations et toute écriture directe future.

BEGIN;

CREATE OR REPLACE FUNCTION public.dec_bloquer_validation_presence_avant_fin_planning()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_mission record;
  v_nb_previsionnels integer;
BEGIN
  SELECT m.id, m.debut_le, m.fin_le
    INTO v_mission
    FROM public.missions AS m
   WHERE m.id = NEW.mission_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '23503',
      MESSAGE = 'Mission introuvable pour cette présence.';
  END IF;

  SELECT pg_catalog.count(*)::integer
    INTO v_nb_previsionnels
    FROM public.mission_creneaux AS mc
   WHERE mc.mission_id = NEW.mission_id
     AND mc.type_creneau = 'PREVISIONNEL'
     AND mc.est_pause IS NOT TRUE;

  IF v_nb_previsionnels > 0 THEN
    IF EXISTS (
      SELECT 1
        FROM public.mission_creneaux AS mc
       WHERE mc.mission_id = NEW.mission_id
         AND mc.type_creneau = 'PREVISIONNEL'
         AND mc.est_pause IS NOT TRUE
         AND (
           mc.fin IS NULL
           OR mc.fin > pg_catalog.statement_timestamp()
         )
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'La présence ne peut être validée avant la fin du dernier créneau planifié.';
    END IF;
  ELSIF v_mission.debut_le IS NULL
        OR v_mission.fin_le IS NULL
        OR v_mission.fin_le <= v_mission.debut_le
        OR v_mission.fin_le > v_mission.debut_le + interval '24 hours'
        OR v_mission.fin_le > pg_catalog.statement_timestamp() THEN
    -- Compatibilité strictement limitée aux anciennes missions ponctuelles.
    -- Une mission longue sans détail n'est jamais interprétée comme continue.
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Le planning détaillé doit être terminé avant validation de la présence.';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.mission_creneaux AS mc
     WHERE mc.mission_id = NEW.mission_id
       AND mc.type_creneau = 'EFFECTIF'
       AND mc.est_pause IS NOT TRUE
       AND mc.fin IS NULL
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Un pointage est encore ouvert pour cette mission.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.mission_creneaux AS mc
     WHERE mc.mission_id = NEW.mission_id
       AND mc.type_creneau = 'EFFECTIF'
       AND mc.est_pause IS NOT TRUE
       AND mc.fin IS NOT NULL
       AND mc.fin > mc.debut
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Aucun pointage terminé ne permet de valider cette présence.';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_bloquer_validation_presence_avant_fin_planning()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_bloquer_validation_presence_avant_fin_planning()
  TO service_role;

DROP TRIGGER IF EXISTS trg_bloquer_validation_presence_avant_fin_planning
  ON public.presences;
CREATE TRIGGER trg_bloquer_validation_presence_avant_fin_planning
BEFORE UPDATE OF valide_par_etablissement
ON public.presences
FOR EACH ROW
WHEN (
  NEW.valide_par_etablissement IS TRUE
  AND OLD.valide_par_etablissement IS DISTINCT FROM TRUE
)
EXECUTE FUNCTION public.dec_bloquer_validation_presence_avant_fin_planning();

COMMIT;
