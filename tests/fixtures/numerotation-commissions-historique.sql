-- Corps précédents exacts, réservés au PostgreSQL CI éphémère.
CREATE OR REPLACE FUNCTION "public"."fn_preparer_facture_commission_periode"("p_facture_honoraire_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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
$$;


ALTER FUNCTION "public"."fn_preparer_facture_commission_periode"("p_facture_honoraire_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_preparer_commission_complement_honoraires"("p_facture_honoraire_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_origine_honoraires public.factures_honoraires%ROWTYPE;
  v_origine_commission public.factures%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_taux_commission numeric;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_numero text;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
    AND type_document = 'FACTURE'
    AND nature_correction = 'COMPLEMENT'
    AND statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Facture complémentaire d''honoraires introuvable ou non émise';
  END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_fh.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'facture_id', v_existing.id,
      'numero_facture', v_existing.numero_facture,
      'montant_ttc', v_existing.montant_ttc, 'existing', true
    );
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_fh.mission_id FOR UPDATE;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_fh.etablissement_id;
  IF v_mission.id IS NULL OR v_etab.id IS NULL
     OR v_mission.type_contrat_applique <> 'LIBERAL'
     OR v_mission.soignant_assigne_id IS DISTINCT FROM v_fh.soignant_id
     OR v_mission.etablissement_id IS DISTINCT FROM v_fh.etablissement_id THEN
    RAISE EXCEPTION 'Mission incohérente pour la commission complémentaire';
  END IF;

  SELECT * INTO v_origine_honoraires
  FROM public.factures_honoraires
  WHERE id = v_fh.facture_precedente_id;
  SELECT * INTO v_origine_commission
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_honoraires.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1;
  v_taux_commission := CASE
    WHEN v_origine_honoraires.montant_ht > 0 AND v_origine_commission.montant_ht > 0
      THEN v_origine_commission.montant_ht / v_origine_honoraires.montant_ht
    ELSE COALESCE(v_mission.taux_commission, 15) / 100
  END;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;

  v_ht := round(v_fh.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  IF v_ht <= 0 OR v_ttc <= 0 THEN
    RAISE EXCEPTION 'Commission complémentaire nulle ou négative';
  END IF;

  v_numero := 'JOL-' || to_char(CURRENT_DATE, 'YYYY') || '-HC-'
    || upper(left(replace(v_fh.id::text, '-', ''), 10));
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id, numero_facture,
    facture_precedente_id, periode_debut, periode_fin,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, est_secteur_public,
    mode_paiement, chorus_pro_statut, type_document
  ) VALUES (
    v_fh.etablissement_id, v_fh.mission_id, v_fh.id, v_numero,
    v_origine_commission.id, v_fh.periode_debut, v_fh.periode_fin,
    v_ht, 20, v_tva, v_ttc, 1, 'EMISE', now(), CURRENT_DATE + 30,
    COALESCE(v_etab.est_secteur_public, false),
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'CHORUS_PRO' ELSE 'STRIPE' END,
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'A_DEPOSER' ELSE 'NON_APPLICABLE' END,
    'FACTURE'
  ) RETURNING * INTO v_existing;

  UPDATE public.missions
  SET total_brut = round(COALESCE(total_brut, 0) + v_fh.montant_ht, 2),
      net_a_payer = round(COALESCE(net_a_payer, 0) + v_fh.montant_ttc, 2),
      montant_commission_ht = round(COALESCE(montant_commission_ht, 0) + v_ht, 2),
      montant_commission_tva = round(COALESCE(montant_commission_tva, 0) + v_tva, 2),
      montant_commission_ttc = round(COALESCE(montant_commission_ttc, 0) + v_ttc, 2),
      commission_a_recalculer = false,
      commission_facturee = true,
      modifie_le = now()
  WHERE id = v_mission.id;

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_existing.id,
    'numero_facture', v_existing.numero_facture,
    'montant_ttc', v_existing.montant_ttc, 'existing', false
  );
END;
$$;


ALTER FUNCTION "public"."fn_preparer_commission_complement_honoraires"("p_facture_honoraire_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_preparer_commission_remplacement_honoraires"("p_facture_honoraire_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_fh public.factures_honoraires%ROWTYPE;
  v_origine_honoraires public.factures_honoraires%ROWTYPE;
  v_mission public.missions%ROWTYPE;
  v_etab public.etablissements%ROWTYPE;
  v_origine_commission public.factures%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_delta_ht numeric(10,2);
  v_delta_tva numeric(10,2);
  v_delta_ttc numeric(10,2);
  v_taux_commission numeric;
  v_numero text;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_fh
  FROM public.factures_honoraires
  WHERE id = p_facture_honoraire_id
    AND type_document = 'FACTURE'
    AND nature_correction = 'REMPLACEMENT'
    AND statut IN ('EMISE', 'EN_RETARD', 'PAYEE')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Facture rectificative introuvable ou non émise'; END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_fh.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('success', true, 'facture_id', v_existing.id, 'existing', true);
  END IF;

  SELECT * INTO v_origine_honoraires
  FROM public.factures_honoraires
  WHERE id = v_fh.facture_precedente_id
  FOR UPDATE;
  SELECT * INTO v_mission FROM public.missions WHERE id = v_fh.mission_id FOR UPDATE;
  SELECT * INTO v_etab FROM public.etablissements WHERE id = v_fh.etablissement_id;
  IF v_origine_honoraires.id IS NULL OR v_mission.id IS NULL OR v_etab.id IS NULL THEN
    RAISE EXCEPTION 'Chaîne de rectification incomplète';
  END IF;

  SELECT * INTO v_origine_commission
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_honoraires.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF FOUND AND v_origine_commission.statut NOT IN ('BROUILLON', 'EMISE', 'EN_RETARD') THEN
    RAISE EXCEPTION 'La facture de services d''origine est déjà payée : un avoir est requis';
  END IF;

  v_taux_commission := CASE
    WHEN v_origine_honoraires.montant_ht > 0 AND v_origine_commission.montant_ht > 0
      THEN v_origine_commission.montant_ht / v_origine_honoraires.montant_ht
    ELSE COALESCE(v_mission.taux_commission, 15) / 100
  END;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;
  v_ht := round(v_fh.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  v_delta_ht := v_ht - COALESCE(v_origine_commission.montant_ht, 0);
  v_delta_tva := v_tva - COALESCE(v_origine_commission.montant_tva, 0);
  v_delta_ttc := v_ttc - COALESCE(v_origine_commission.montant_ttc, 0);

  IF v_origine_commission.id IS NOT NULL THEN
    UPDATE public.factures
    SET statut = 'REMPLACEE', modifie_le = now()
    WHERE id = v_origine_commission.id
      AND statut IN ('BROUILLON', 'EMISE', 'EN_RETARD');
  END IF;

  v_numero := 'JOL-' || to_char(CURRENT_DATE, 'YYYY') || '-HR-'
    || upper(left(replace(v_fh.id::text, '-', ''), 10));
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id, numero_facture,
    facture_precedente_id, periode_debut, periode_fin,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, est_secteur_public,
    mode_paiement, chorus_pro_statut, type_document
  ) VALUES (
    v_fh.etablissement_id, v_fh.mission_id, v_fh.id, v_numero,
    v_origine_commission.id, v_fh.periode_debut, v_fh.periode_fin,
    v_ht, 20, v_tva, v_ttc, 1, 'EMISE', now(), CURRENT_DATE + 30,
    COALESCE(v_etab.est_secteur_public, false),
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'CHORUS_PRO' ELSE 'STRIPE' END,
    CASE WHEN COALESCE(v_etab.est_secteur_public, false) THEN 'A_DEPOSER' ELSE 'NON_APPLICABLE' END,
    'FACTURE'
  ) RETURNING * INTO v_existing;

  -- Cas reproduit : taux corrigé, quantité facturée inchangée sur une mission
  -- EN_COURS. Le moteur de mission a déjà recalculé ses agrégats au nouveau
  -- taux ; le delta de cette période ne doit pas être appliqué une seconde fois.
  -- Les autres corrections conservent le chemin historique (notamment heures
  -- seules et finale), sans prétendre corriger leurs propres écarts financiers.
  IF v_mission.statut = 'EN_COURS'
     AND v_fh.quantite_heures_snapshot > 0
     AND v_fh.quantite_heures_snapshot::text NOT IN ('NaN', 'Infinity', '-Infinity')
     AND v_fh.quantite_heures_snapshot = v_origine_honoraires.quantite_heures_snapshot
     AND v_fh.taux_horaire_snapshot > 0
     AND v_origine_honoraires.taux_horaire_snapshot > 0
     AND v_fh.taux_horaire_snapshot::text NOT IN ('NaN', 'Infinity', '-Infinity')
     AND v_origine_honoraires.taux_horaire_snapshot::text NOT IN ('NaN', 'Infinity', '-Infinity')
     AND v_fh.taux_horaire_snapshot <> v_origine_honoraires.taux_horaire_snapshot
     AND v_mission.taux_horaire_base = v_fh.taux_horaire_snapshot THEN
    UPDATE public.missions
    SET commission_a_recalculer = false,
        modifie_le = now()
    WHERE id = v_mission.id;
  ELSE
    UPDATE public.missions
    SET total_brut = round(
          COALESCE(total_brut, 0)
            + v_fh.montant_ht - v_origine_honoraires.montant_ht,
          2
        ),
        net_a_payer = round(
          COALESCE(net_a_payer, 0)
            + v_fh.montant_ttc - v_origine_honoraires.montant_ttc,
          2
        ),
        montant_commission_ht = round(COALESCE(montant_commission_ht, 0) + v_delta_ht, 2),
        montant_commission_tva = round(COALESCE(montant_commission_tva, 0) + v_delta_tva, 2),
        montant_commission_ttc = round(COALESCE(montant_commission_ttc, 0) + v_delta_ttc, 2),
        commission_a_recalculer = false,
        modifie_le = now()
    WHERE id = v_mission.id;
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_existing.id,
    'numero_facture', v_existing.numero_facture,
    'montant_ttc', v_existing.montant_ttc, 'existing', false
  );
END;
$$;


ALTER FUNCTION "public"."fn_preparer_commission_remplacement_honoraires"("p_facture_honoraire_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."fn_preparer_avoir_commission_honoraires"("p_avoir_honoraires_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_avoir_h public.factures_honoraires%ROWTYPE;
  v_origine_h public.factures_honoraires%ROWTYPE;
  v_origine_c public.factures%ROWTYPE;
  v_existing public.factures%ROWTYPE;
  v_taux_commission numeric;
  v_ht numeric(10,2);
  v_tva numeric(10,2);
  v_ttc numeric(10,2);
  v_numero text;
  v_avoir_c_id uuid;
BEGIN
  IF COALESCE(auth.jwt()->>'role', current_setting('request.jwt.claim.role', true), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_avoir_h
  FROM public.factures_honoraires
  WHERE id = p_avoir_honoraires_id
    AND type_document = 'AVOIR'
    AND nature_correction = 'AVOIR'
    AND statut IN ('EMISE', 'REMBOURSE')
  FOR UPDATE;
  IF NOT FOUND OR v_avoir_h.facture_precedente_id IS NULL THEN
    RAISE EXCEPTION 'Avoir d''honoraires introuvable ou non émis';
  END IF;

  SELECT * INTO v_existing
  FROM public.factures
  WHERE facture_honoraire_id = v_avoir_h.id
    AND type_document = 'AVOIR'
    AND statut NOT IN ('ANNULEE', 'ERREUR_GENERATION')
  FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', true, 'facture_id', v_existing.id,
      'numero_facture', v_existing.numero_facture,
      'montant_ttc', v_existing.montant_ttc, 'existing', true
    );
  END IF;

  SELECT * INTO v_origine_h
  FROM public.factures_honoraires
  WHERE id = v_avoir_h.facture_precedente_id
  FOR UPDATE;
  IF NOT FOUND OR v_origine_h.montant_ht <= 0 THEN
    RAISE EXCEPTION 'Facture d''honoraires d''origine incohérente';
  END IF;

  SELECT * INTO v_origine_c
  FROM public.factures
  WHERE facture_honoraire_id = v_origine_h.id
    AND type_document = 'FACTURE'
    AND statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
  ORDER BY cree_le DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND OR v_origine_c.montant_ht <= 0 THEN
    RAISE EXCEPTION 'Facture Jolene d''origine introuvable';
  END IF;

  v_taux_commission := v_origine_c.montant_ht / v_origine_h.montant_ht;
  IF v_taux_commission <= 0 OR v_taux_commission > 1 THEN
    RAISE EXCEPTION 'Taux de commission historique incohérent';
  END IF;
  v_ht := round(v_avoir_h.montant_ht * v_taux_commission, 2);
  v_tva := round(v_ht * 0.20, 2);
  v_ttc := v_ht + v_tva;
  IF v_ht <= 0 OR v_ttc <= 0 THEN
    RAISE EXCEPTION 'Montant de l''avoir Jolene incohérent';
  END IF;

  v_numero := public.next_avoir_commission_number(v_avoir_h.etablissement_id);
  INSERT INTO public.factures (
    etablissement_id, mission_id, facture_honoraire_id,
    numero_facture, type_document, facture_precedente_id,
    montant_ht, taux_tva, montant_tva, montant_ttc, nombre_missions,
    statut, date_emission, date_echeance, periode_debut, periode_fin,
    est_secteur_public, mode_paiement
  ) VALUES (
    v_avoir_h.etablissement_id, v_avoir_h.mission_id, v_avoir_h.id,
    v_numero, 'AVOIR', v_origine_c.id,
    v_ht, 20, v_tva, v_ttc, 1,
    'EMISE', now(), CURRENT_DATE,
    v_origine_c.periode_debut, v_origine_c.periode_fin,
    v_origine_c.est_secteur_public, v_origine_c.mode_paiement
  ) RETURNING id INTO v_avoir_c_id;

  UPDATE public.missions
  SET total_brut = GREATEST(0, COALESCE(total_brut, 0) - v_avoir_h.montant_ht),
      net_a_payer = GREATEST(0, COALESCE(net_a_payer, 0) - v_avoir_h.montant_ttc),
      montant_commission_ht = GREATEST(0, COALESCE(montant_commission_ht, 0) - v_ht),
      montant_commission_tva = GREATEST(0, COALESCE(montant_commission_tva, 0) - v_tva),
      montant_commission_ttc = GREATEST(0, COALESCE(montant_commission_ttc, 0) - v_ttc),
      commission_a_recalculer = false,
      modifie_le = now()
  WHERE id = v_avoir_h.mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_avoir_h.etablissement_id,
    p_type_acteur := 'SYSTEME',
    p_action := 'FACTURATION',
    p_type_ressource := 'facture',
    p_id_ressource := v_avoir_c_id,
    p_details := jsonb_build_object(
      'evenement', 'AVOIR_COMMISSION_APRES_LITIGE',
      'avoir_honoraires_id', v_avoir_h.id,
      'facture_commission_origine_id', v_origine_c.id,
      'taux_commission_historique', v_taux_commission,
      'montant_ht', v_ht,
      'montant_tva', v_tva,
      'montant_ttc', v_ttc
    )
  );

  RETURN jsonb_build_object(
    'success', true, 'facture_id', v_avoir_c_id,
    'numero_facture', v_numero,
    'montant_ht', v_ht, 'montant_tva', v_tva,
    'montant_ttc', v_ttc, 'existing', false
  );
END;
$$;


ALTER FUNCTION "public"."fn_preparer_avoir_commission_honoraires"("p_avoir_honoraires_id" "uuid") OWNER TO "postgres";
