-- Lot 21 / D4 : la profession requise par la mission détermine le régime.
-- Une préférence LIBERAL ou TOUS ne doit jamais faire échouer la création ou
-- l'édition d'une mission dont la cellule n'est pas explicitement AUTORISEE :
-- la mission est proposée en SALARIE, conformément au défaut fermé C6.

CREATE OR REPLACE FUNCTION public.dec_valider_compatibilite_mission_liberal()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type_etab text;
  v_est_public boolean;
  v_mode jsonb;
BEGIN
  SELECT type::text, COALESCE(est_secteur_public, false)
    INTO v_type_etab, v_est_public
    FROM public.etablissements
   WHERE id = NEW.etablissement_id;

  IF NEW.profession_requise IS NULL OR v_type_etab IS NULL THEN
    RETURN NEW;
  END IF;

  v_mode := public.fn_mode_exercice(
    NEW.profession_requise::text,
    v_type_etab,
    CASE WHEN v_est_public THEN 'PUBLIC' ELSE NULL END
  );

  IF NEW.type_contrat_recherche IN ('LIBERAL', 'TOUS')
     AND v_mode->>'niveau' <> 'AUTORISE' THEN
    NEW.type_contrat_recherche := 'SALARIE';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_valider_compatibilite_mission_liberal()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_valider_compatibilite_mission_liberal()
  TO service_role;
