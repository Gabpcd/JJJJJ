-- Définition LIVE OID 59809, relue le 30/09/2026.
-- Seul delta métier : l'auteur établissement d'une note est le tenant canonique,
-- également pour un membre prescripteur. Fenêtre de 60 jours et droits inchangés.
DO $preflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid =
    'public.fn_lister_missions_a_noter_etab()'::regprocedure;
  IF NOT FOUND OR md5(p.prosrc) NOT IN ('4feea9884817ca0d5a702700d6f36fbd', '0b3bff2c5588245287087d681698c2c9')
    OR p.prosecdef IS DISTINCT FROM true
    OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'::aclitem[] THEN
    RAISE EXCEPTION 'Liste notations : définition ou droits inattendus';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.security_definer_inventory
    WHERE signature='fn_lister_missions_a_noter_etab()'
      AND categorie='RPC_UTILISATEUR_AUTH_INTERNE'
      AND definition_md5 IN ('4feea9884817ca0d5a702700d6f36fbd', '0b3bff2c5588245287087d681698c2c9')) THEN
    RAISE EXCEPTION 'Liste notations : inventaire divergent';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_lister_missions_a_noter_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  v_etab_id := public.mon_etablissement_id();
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mission_id', m.id,
    'intitule', m.intitule,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'soignant_id', m.soignant_assigne_id,
    'soignant_prenom', s.prenom,
    'soignant_nom', s.nom,
    'soignant_profession', s.profession,
    'duree_heures', m.duree_heures,
    'taux_horaire_base', m.taux_horaire_base,
    'jours_depuis_fin', EXTRACT(DAY FROM NOW() - m.fin_le)::int
  ) ORDER BY m.fin_le DESC), '[]'::jsonb)
  INTO v_missions
  FROM public.missions m
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  WHERE m.etablissement_id = v_etab_id
    AND m.statut = 'TERMINEE'
    AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.notations_missions nm
      WHERE nm.mission_id = m.id
        AND nm.sens = 'ETAB_VERS_SOIGNANT'
        AND nm.notateur_id = v_etab_id
    )
    AND m.fin_le > NOW() - INTERVAL '60 days';

  RETURN jsonb_build_object('success', true, 'missions', v_missions);
END;
$function$;

DO $inventory$
BEGIN
  IF md5((SELECT prosrc FROM pg_catalog.pg_proc WHERE oid =
    'public.fn_lister_missions_a_noter_etab()'::regprocedure)) IS DISTINCT FROM '0b3bff2c5588245287087d681698c2c9' THEN
    RAISE EXCEPTION 'Liste notations canonique non installée';
  END IF;
  UPDATE private.security_definer_inventory
  SET definition_md5='0b3bff2c5588245287087d681698c2c9',
      justification='Identité requise et mon_etablissement_id() canonique ; liste filtrée par établissement, auteur canonique de la note et fenêtre de 60 jours inchangée. Source 20260930145933_aligner_liste_notations_etablissement_canonique.sql.',
      recense_le=now()
  WHERE signature='fn_lister_missions_a_noter_etab()'
    AND categorie='RPC_UTILISATEUR_AUTH_INTERNE'
    AND definition_md5 IN ('4feea9884817ca0d5a702700d6f36fbd', '0b3bff2c5588245287087d681698c2c9');
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventaire liste notations divergent'; END IF;
END;
$inventory$;
