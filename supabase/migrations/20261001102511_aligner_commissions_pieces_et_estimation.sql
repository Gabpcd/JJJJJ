-- CANDIDAT LOCAL NON VALIDE : témoin rouge réel et revue fraîche requis.
-- Définitions LIVE staging du 01/10/2026 ; aucun recalcul de lignes existantes.
-- Les taux, la TVA 20 %, les droits et les pièces déjà émises restent inchangés.
DO $preflight$
DECLARE r record; p record;
BEGIN
  IF md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure))
    IS DISTINCT FROM 'c793ac81eaef0fe18fb5920c9264c675' THEN
    RAISE EXCEPTION 'Prérequis commission rectificative absent';
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('fn_preparer_facture_commission_periode(uuid)','e155d0232345adb95321d1e56f3c4cdd','8030a296741d5bfe6dad70edd4d8f20d','f26f4d29b77cb2be569c0db62c1fb4dc','fe01d207db4766c4246f641ba171a3e7','search_path=public, pg_temp'),
    ('dec_calculer_commission()','065286258fe7a131557692126c896b1a','2767aab47df4d531744cd751a4faed95','cdfa3faf225b0ac26b43db8a9ad8b41f','4c0238a79c1e54e0b17ad55f89e35104','search_path=public')
  ) AS attendu(signature, ancien_corps, nouveau_corps, ancienne_definition, nouvelle_definition, configuration) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF NOT FOUND OR md5(p.prosrc) NOT IN (r.ancien_corps,r.nouveau_corps)
      OR md5(pg_get_functiondef(p.oid)) NOT IN (r.ancienne_definition,r.nouvelle_definition)
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY[r.configuration]::text[]
      OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[]
      OR NOT EXISTS(SELECT 1 FROM private.security_definer_inventory WHERE signature=r.signature AND definition_md5=md5(p.prosrc)) THEN
      RAISE EXCEPTION 'Commission : corps, droits ou inventaire inattendus (%)',r.signature;
    END IF;
  END LOOP;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_preparer_facture_commission_periode(p_facture_honoraire_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_base_precedente numeric := 0;
  v_commission_precedente numeric := 0;
  v_nb_precedents integer := 0;
  v_taux_commission numeric;
  v_ht_piece numeric(10,2);
  v_ttc numeric(10,2);
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_numero text;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
    AND type_document = 'FACTURE'
    AND statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture d''honoraires introuvable ou non payable' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_fh.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true,
      'facture_id', v_existing.id,
      'numero_facture', v_existing.numero_facture,
      'montant_ttc', v_existing.montant_ttc,
      'existing', true
    );
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_fh.mission_id FOR UPDATE;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_fh.etablissement_id;
  IF NOT FOUND OR v_mission.id IS NULL OR v_etab.id IS NULL
     OR v_mission.type_contrat_applique <> 'LIBERAL'
     OR v_mission.soignant_assigne_id <> v_fh.soignant_id
     OR v_mission.etablissement_id <> v_fh.etablissement_id
     OR v_fh.montant_ht IS NULL OR v_fh.montant_ht <= 0
     OR v_fh.montant_ht::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'Mission incohérente pour la facture de commission' USING ERRCODE = '23514';
  END IF;

  -- La mission reste une estimation du planning. Les honoraires émis sont
  -- l'assiette de cette facture, y compris après un litige sur une autre période.
  -- Le repli historique conserve le taux déjà stocké, jamais le ratio des montants.
  v_taux_commission := COALESCE(v_mission.taux_commission_fige, v_mission.taux_commission);
  IF v_taux_commission IS NULL OR v_taux_commission <= 0 OR v_taux_commission > 100
     OR v_taux_commission::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'Taux de commission de mission absent ou incohérent' USING ERRCODE = '23514';
  END IF;
  v_ht_piece := round(v_fh.montant_ht * v_taux_commission / 100, 2);
  v_ht := v_ht_piece;

  IF v_fh.est_facture_finale_mission THEN
    -- La dernière pièce ne doit solder ni un budget prévisionnel ni une erreur
    -- historique. Les remplacements exclus et les avoirs signés restent liés
    -- à leurs propres commissions ; seuls les centimes d'arrondi sont lissés.
    IF EXISTS (
      SELECT 1 FROM public.factures_honoraires h
      WHERE h.mission_id = v_mission.id AND h.id <> v_fh.id
        AND h.statut IN ('EMISE', 'EN_RETARD', 'PAYEE', 'FACTORISEE', 'REMBOURSE')
        AND (h.soignant_id IS DISTINCT FROM v_fh.soignant_id
          OR h.etablissement_id IS DISTINCT FROM v_fh.etablissement_id
          OR h.montant_ht <= 0 OR h.montant_ht::text IN ('NaN', 'Infinity', '-Infinity')
          OR (SELECT count(*) FROM public.factures f WHERE f.facture_honoraire_id = h.id
            AND f.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')) <> 1
          OR NOT EXISTS (
            SELECT 1 FROM public.factures f
            WHERE f.facture_honoraire_id = h.id AND f.mission_id = v_mission.id
              AND f.etablissement_id = v_fh.etablissement_id
              AND f.type_document = h.type_document::text
              AND f.montant_ht > 0 AND f.montant_ht::text NOT IN ('NaN', 'Infinity', '-Infinity')
              AND f.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
          ))
    ) THEN
      RAISE EXCEPTION 'Commission antérieure absente, ambiguë ou incohérente : facture finale suspendue' USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(sum(CASE WHEN h.type_document = 'AVOIR' THEN -h.montant_ht ELSE h.montant_ht END), 0),
           COALESCE(sum(CASE WHEN f.type_document = 'AVOIR' THEN -f.montant_ht ELSE f.montant_ht END), 0),
           count(*)::integer
      INTO v_base_precedente, v_commission_precedente, v_nb_precedents
      FROM public.factures_honoraires h
      JOIN public.factures f ON f.facture_honoraire_id = h.id AND f.type_document = h.type_document::text
      WHERE h.mission_id = v_mission.id AND f.mission_id = v_mission.id AND h.id <> v_fh.id
        AND h.soignant_id = v_fh.soignant_id AND h.etablissement_id = v_fh.etablissement_id
        AND f.etablissement_id = v_fh.etablissement_id
        AND h.statut IN ('EMISE', 'EN_RETARD', 'PAYEE', 'FACTORISEE', 'REMBOURSE')
        AND f.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION');
    v_ht := round((v_base_precedente + v_fh.montant_ht) * v_taux_commission / 100, 2)
      - v_commission_precedente;
    IF abs(v_ht - v_ht_piece) > v_nb_precedents * 0.01 THEN
      RAISE EXCEPTION 'Historique de commission incohérent : écart hors arrondis' USING ERRCODE = '23514';
    END IF;
  END IF;
  IF v_ht <= 0 OR v_ht::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'Commission de période nulle ou négative' USING ERRCODE = '23514';
  END IF;
  -- Même calcul par pièce que les commissions de remplacement/complément.
  -- La TVA n'est pas compensée entre deux factures déjà émises.
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  v_numero := 'JOL-' || to_char(CURRENT_DATE, 'YYYY') || '-H-' || upper(left(replace(v_fh.id::text, '-', ''), 10));

  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id, numero_facture,
    periode_debut, periode_fin, montant_ht, taux_tva, montant_tva, montant_ttc,
    nombre_missions, statut, date_emission, date_echeance,
    est_secteur_public, mode_paiement, chorus_pro_statut, type_document
  ) VALUES (
    v_fh.etablissement_id, v_fh.mission_id, v_fh.id, v_numero,
    v_fh.periode_debut, v_fh.periode_fin, v_ht, 20, v_tva, v_ttc,
    1, 'EMISE', now(), CURRENT_DATE + 30,
    COALESCE(v_etab.est_secteur_public, false),
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'CHORUS_PRO' ELSE 'STRIPE' END,
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'A_DEPOSER' ELSE 'NON_APPLICABLE' END,
    'FACTURE'
  )
  RETURNING * INTO v_existing;

  IF v_fh.est_facture_finale_mission THEN
    UPDATE public.missions
    SET commission_facturee = true,
        facture_id = v_existing.id,
        modifie_le = now()
    WHERE id = v_mission.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'facture_id', v_existing.id,
    'numero_facture', v_existing.numero_facture,
    'montant_ttc', v_existing.montant_ttc,
    'est_secteur_public', v_existing.est_secteur_public,
    'existing', false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_calculer_commission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_taux NUMERIC;
BEGIN
    -- Après dec_mission_z_finance, les colonnes mission décrivent le même
    -- planning. Un delta de facture ne peut modifier uniquement sa commission.
    -- Les pièces comptables restent calculées et payées indépendamment.
    IF (NEW.statut = 'TERMINEE'
        OR (NEW.statut = 'EN_COURS' AND NEW.type_contrat_applique = 'LIBERAL'))
       AND NEW.net_a_payer IS NOT NULL THEN
        v_taux := COALESCE(
            NEW.taux_commission_fige,
            CASE WHEN NEW.statut = 'EN_COURS' THEN NEW.taux_commission ELSE NULL END,
            (SELECT e.taux_commission_negocie FROM etablissements e WHERE e.id = NEW.etablissement_id),
            public.fn_param_num('commission_defaut_pct', 15)
        );

        NEW.taux_commission := v_taux;
        NEW.montant_commission_ht := ROUND(NEW.net_a_payer * (v_taux / 100.0), 2);
        NEW.montant_commission_tva := ROUND(NEW.montant_commission_ht * 0.20, 2);
        NEW.montant_commission_ttc := NEW.montant_commission_ht + NEW.montant_commission_tva;
    END IF;
    RETURN NEW;
END;
$function$;

DO $inventory$
DECLARE r record; p record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('fn_preparer_facture_commission_periode(uuid)','e155d0232345adb95321d1e56f3c4cdd','8030a296741d5bfe6dad70edd4d8f20d','f26f4d29b77cb2be569c0db62c1fb4dc','fe01d207db4766c4246f641ba171a3e7','search_path=public, pg_temp'),
    ('dec_calculer_commission()','065286258fe7a131557692126c896b1a','2767aab47df4d531744cd751a4faed95','cdfa3faf225b0ac26b43db8a9ad8b41f','4c0238a79c1e54e0b17ad55f89e35104','search_path=public')
  ) AS attendu(signature, ancien_corps, nouveau_corps, ancienne_definition, nouvelle_definition, configuration) LOOP
    SELECT * INTO p FROM pg_catalog.pg_proc WHERE oid=('public.'||r.signature)::regprocedure;
    IF NOT FOUND OR md5(p.prosrc) IS DISTINCT FROM r.nouveau_corps
      OR md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM r.nouvelle_definition
      OR p.prosecdef IS DISTINCT FROM true OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
      OR p.proconfig IS DISTINCT FROM ARRAY[r.configuration]::text[]
      OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[] THEN
      RAISE EXCEPTION 'Commission : installation ou droits inattendus (%)',r.signature;
    END IF;
    UPDATE private.security_definer_inventory SET definition_md5=md5(p.prosrc),recense_le=now()
      WHERE signature=r.signature AND definition_md5 IN(r.ancien_corps,r.nouveau_corps);
    IF NOT FOUND THEN RAISE EXCEPTION 'Commission : inventaire non actualisé (%)',r.signature; END IF;
  END LOOP;
END;
$inventory$;
