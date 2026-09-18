-- Le compte Auth peut exister avant le profil professionnel. Ce brouillon
-- privé ne donne aucun rôle métier et ne crée aucune mission publiée.
CREATE TABLE public.parcours_inscription (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  type_compte text NOT NULL CHECK (type_compte IN ('SOIGNANT', 'ETABLISSEMENT')),
  donnees jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(donnees) = 'object' AND octet_length(donnees::text) <= 32768),
  consentement_cgu_le timestamptz NOT NULL DEFAULT now(),
  consentement_cgv_le timestamptz,
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now(),
  CHECK (type_compte <> 'ETABLISSEMENT' OR consentement_cgv_le IS NOT NULL)
);
ALTER TABLE public.parcours_inscription ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.parcours_inscription FROM anon, authenticated;
GRANT SELECT ON public.parcours_inscription TO authenticated;
GRANT ALL ON public.parcours_inscription TO service_role;
CREATE POLICY parcours_inscription_proprietaire ON public.parcours_inscription
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()) AND (SELECT public.fn_compte_auth_actif()));

CREATE FUNCTION public.fn_demarrer_inscription(p_type_compte text, p_profession text DEFAULT NULL,
  p_nom text DEFAULT NULL, p_cgu boolean DEFAULT false, p_cgv boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, auth
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_claim uuid := gen_random_uuid();
  v_reservation jsonb;
  v_parcours public.parcours_inscription;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Session invalide.' USING ERRCODE = '42501';
  END IF;
  IF p_type_compte NOT IN ('SOIGNANT', 'ETABLISSEMENT') OR p_type_compte IS NULL
    OR p_cgu IS NOT TRUE OR (p_type_compte = 'ETABLISSEMENT' AND p_cgv IS NOT TRUE) THEN
    RAISE EXCEPTION 'Vérifiez le type de compte et les conditions acceptées.' USING ERRCODE = '22023';
  END IF;
  IF p_type_compte = 'SOIGNANT' AND (p_profession IS NULL OR NOT EXISTS (
    SELECT 1 FROM unnest(enum_range(NULL::public.type_profession)) p WHERE p::text = p_profession
  )) THEN RAISE EXCEPTION 'Choisissez votre profession.' USING ERRCODE = '22023'; END IF;
  IF p_type_compte = 'ETABLISSEMENT' AND (length(btrim(COALESCE(p_nom, ''))) NOT BETWEEN 1 AND 200) THEN
    RAISE EXCEPTION 'Indiquez le nom de votre établissement.' USING ERRCODE = '22023';
  END IF;

  -- Même verrou/réservation que les endpoints historiques, y compris lors de
  -- deux créations concurrentes de rôles différents. Aucun rôle dans le JWT.
  v_reservation := public.fn_reserver_type_compte(v_uid, p_type_compte, v_claim);
  IF (v_reservation ->> 'allowed')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION '%', v_reservation ->> 'code' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.parcours_inscription(user_id, type_compte, donnees, consentement_cgv_le)
  VALUES (v_uid, p_type_compte,
    CASE WHEN p_type_compte = 'SOIGNANT' THEN jsonb_build_object('profession', p_profession)
      ELSE jsonb_build_object('nom', btrim(p_nom)) END,
    CASE WHEN p_type_compte = 'ETABLISSEMENT' THEN now() END)
  ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.types_comptes_auth SET claim_token = NULL, claim_expire_le = NULL
    WHERE user_id = v_uid AND claim_token = v_claim AND finalise_le IS NULL;
  SELECT * INTO v_parcours FROM public.parcours_inscription WHERE user_id = v_uid;
  RETURN to_jsonb(v_parcours);
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_demarrer_inscription(text,text,text,boolean,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_demarrer_inscription(text,text,text,boolean,boolean) TO authenticated;

CREATE FUNCTION public.fn_enregistrer_parcours_inscription(p_donnees jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, auth
AS $body$
DECLARE v_parcours public.parcours_inscription;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Session invalide.' USING ERRCODE = '42501';
  END IF;
  IF p_donnees IS NULL OR jsonb_typeof(p_donnees) <> 'object' OR octet_length(p_donnees::text) > 32768 THEN
    RAISE EXCEPTION 'Brouillon invalide.' USING ERRCODE = '22023';
  END IF;
  -- Aucun mot de passe, jeton, pièce ni état de vérification dans le brouillon.
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_donnees) k WHERE k NOT IN (
    'profession','prenom','nom','telephone','dateNaissance','typesContrat','rpps','rayon',
    'estSalarieEtablissement','estEtudiant','scolariteFormation','scolariteAnnee',
    'siret','finess','type','rue','ville','codePostal','departement','emailContact',
    'telephoneContact','numeroLicence','missionProfession','missionVille','missionDate',
    'missionDebut','missionFin','missionChoisie','brouillonMission'
  )) THEN RAISE EXCEPTION 'Champ non autorisé dans le brouillon.' USING ERRCODE = '22023'; END IF;
  UPDATE public.parcours_inscription SET donnees = donnees || p_donnees, modifie_le = now()
    WHERE user_id = auth.uid() RETURNING * INTO v_parcours;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inscription introuvable.' USING ERRCODE = 'P0002'; END IF;
  RETURN to_jsonb(v_parcours);
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_enregistrer_parcours_inscription(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_enregistrer_parcours_inscription(jsonb) TO authenticated;

-- Compensation d'un échec de complétion : garder le compte et son brouillon,
-- libérer uniquement la réservation détenue par cet appel pour une reprise.
CREATE FUNCTION public.fn_liberer_inscription_progressive(p_user_id uuid, p_claim_token uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public
AS $body$
  UPDATE public.types_comptes_auth t SET claim_token = NULL, claim_expire_le = NULL
  WHERE t.user_id = p_user_id AND t.claim_token = p_claim_token AND t.finalise_le IS NULL;
$body$;
REVOKE ALL ON FUNCTION public.fn_liberer_inscription_progressive(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_liberer_inscription_progressive(uuid,uuid) TO service_role;

-- Aperçu borné : critères de visibilité de fn_apercu_marche_profession,
-- sans identité d'établissement, contact, notes internes ou rémunération.
CREATE FUNCTION public.fn_missions_decouverte_inscription(p_ville text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $body$
DECLARE v_profession text; v_resultat jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RAISE EXCEPTION 'Session invalide.' USING ERRCODE = '42501';
  END IF;
  SELECT donnees ->> 'profession' INTO v_profession FROM public.parcours_inscription
    WHERE user_id = auth.uid() AND type_compte = 'SOIGNANT';
  IF NOT FOUND THEN RAISE EXCEPTION 'Espace soignant requis.' USING ERRCODE = '42501'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(mission)), '[]'::jsonb) INTO v_resultat FROM (
    SELECT m.id, m.profession_requise, e.adresse_ville AS ville, m.debut_le, m.fin_le
    FROM public.missions m JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE' AND m.debut_le > now() AND m.soignant_assigne_id IS NULL
      AND e.supprime_le IS NULL AND e.est_compte_test IS FALSE
      AND private.fn_mission_lie_compte_test(m.id) IS FALSE
      AND m.profession_requise::text = v_profession
      AND (nullif(btrim(p_ville), '') IS NULL OR e.adresse_ville ILIKE '%' || left(btrim(p_ville), 100) || '%')
    ORDER BY m.debut_le, m.id LIMIT 20
  ) mission;
  RETURN v_resultat;
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_missions_decouverte_inscription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_missions_decouverte_inscription(text) TO authenticated;

CREATE FUNCTION public.fn_accepter_cgu_decouverte_soignant()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, auth
AS $body$
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif()
     OR NOT EXISTS (SELECT 1 FROM public.soignants WHERE id = auth.uid() AND supprime_le IS NULL)
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = auth.uid() AND email_confirmed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Compte soignant confirmé requis.' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.journaux_audit(acteur_id,type_acteur,action,type_ressource,id_ressource,details)
  SELECT auth.uid(), 'SOIGNANT', 'RGPD_CONSENTEMENT_DONNE', 'soignant', auth.uid(),
    jsonb_build_object('type','psc_decouverte','cgu',true,'confidentialite',true)
  WHERE NOT EXISTS (SELECT 1 FROM public.journaux_audit WHERE acteur_id=auth.uid()
    AND action='RGPD_CONSENTEMENT_DONNE' AND details->>'type'='psc_decouverte');
END;
$body$;
REVOKE ALL ON FUNCTION public.fn_accepter_cgu_decouverte_soignant() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_accepter_cgu_decouverte_soignant() TO authenticated;

INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
SELECT p.oid::regprocedure::text,
  CASE WHEN p.proname = 'fn_liberer_inscription_progressive' THEN 'SERVICE_ONLY_REVOQUE' ELSE 'RPC_UTILISATEUR_AUTH_INTERNE' END,
  md5(p.prosrc), 'Inscription progressive : compte actif et propriétaire auth.uid(); aucune autorisation métier. Compensation réservée au service_role.', now()
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('fn_demarrer_inscription','fn_enregistrer_parcours_inscription','fn_liberer_inscription_progressive','fn_missions_decouverte_inscription','fn_accepter_cgu_decouverte_soignant')
ON CONFLICT(signature) DO UPDATE SET definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification,recense_le=EXCLUDED.recense_le;
