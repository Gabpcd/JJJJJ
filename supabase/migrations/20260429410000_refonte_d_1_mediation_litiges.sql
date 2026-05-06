-- Refonte.D.1 — Médiation litiges (nouveaux statuts + accord mutuel + RPCs + cron 7j)
--
-- Anciens statuts conservés pour rétro-compat. Anciens RPCs (fn_resoudre_litige) toujours fonctionnels.
-- Nouveaux statuts : MEDIATION_EN_COURS, RESOLU_ACCORD_PARTIES, REVUE_ADMIN, RESOLU_FAVEUR_SOIGNANT, RESOLU_FAVEUR_ETAB, RESOLU_PARTAGE
-- Mécanique accord mutuel via colonnes accord_soignant_le + accord_etablissement_le (déjà présentes).

-- 1) Statuts étendus
ALTER TABLE public.litiges DROP CONSTRAINT IF EXISTS litiges_statut_check;
ALTER TABLE public.litiges ADD CONSTRAINT litiges_statut_check CHECK (statut = ANY (ARRAY[
  'OUVERT','EN_DISCUSSION','EN_MEDIATION','RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME',
  'MEDIATION_EN_COURS','RESOLU_ACCORD_PARTIES','REVUE_ADMIN','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE'
]));

-- 2) dec_proteger_resolution_litige étendu (autorise nouveaux statuts)
CREATE OR REPLACE FUNCTION public.dec_proteger_resolution_litige()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;

    IF NEW.statut IN ('FERME','RESOLU_ACCORD_PARTIES') AND NOT est_admin() THEN
        IF COALESCE(NEW.accord_soignant, FALSE) AND COALESCE(NEW.accord_etablissement, FALSE) THEN
            NEW.resolu_le := COALESCE(NEW.resolu_le, NOW());
            RETURN NEW;
        ELSE
            RAISE EXCEPTION 'Seul l''administrateur peut clôturer un litige sans accord mutuel.';
        END IF;
    END IF;

    IF NEW.statut IN ('RESOLU_ADMIN','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE','REVUE_ADMIN')
       AND NOT est_admin() THEN
        RAISE EXCEPTION 'Seul l''administrateur peut résoudre un litige (ou demander revue admin).';
    END IF;

    IF NOT est_admin() THEN
        NEW.resolu_par := OLD.resolu_par;
        IF NEW.statut NOT IN ('FERME','RESOLU_ACCORD_PARTIES') THEN
            NEW.resolution := OLD.resolution;
        END IF;
    END IF;

    IF NEW.statut IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME',
                      'RESOLU_ACCORD_PARTIES','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE')
       AND OLD.statut NOT IN ('RESOLU_SOIGNANT','RESOLU_ETABLISSEMENT','RESOLU_ADMIN','FERME',
                              'RESOLU_ACCORD_PARTIES','RESOLU_FAVEUR_SOIGNANT','RESOLU_FAVEUR_ETAB','RESOLU_PARTAGE') THEN
        NEW.resolu_le := COALESCE(NEW.resolu_le, NOW());
    END IF;

    RETURN NEW;
END;
$function$;

-- 3) Trigger accord mutuel : 2 accord_*_le set → RESOLU_ACCORD_PARTIES auto
CREATE OR REPLACE FUNCTION public.fn_trg_litige_accord_mutuel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.accord_soignant_le IS NOT NULL AND NEW.accord_etablissement_le IS NOT NULL
     AND NEW.statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS') THEN
    NEW.statut := 'RESOLU_ACCORD_PARTIES';
    NEW.resolu_le := COALESCE(NEW.resolu_le, NOW());
    NEW.accord_soignant := true;
    NEW.accord_etablissement := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_litige_accord_mutuel ON public.litiges;
CREATE TRIGGER trg_litige_accord_mutuel
  BEFORE UPDATE OF accord_soignant_le, accord_etablissement_le ON public.litiges
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_litige_accord_mutuel();

-- 4) RPC fn_proposer_accord_partie : passe à MEDIATION_EN_COURS
CREATE OR REPLACE FUNCTION public.fn_proposer_accord_partie(p_litige_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_litige RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable'); END IF;

  IF NOT est_admin() AND v_litige.soignant_id <> v_uid AND v_litige.etablissement_id <> v_etab_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas partie au litige');
  END IF;

  IF v_litige.statut NOT IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige déjà en médiation ou résolu');
  END IF;

  UPDATE litiges SET statut = 'MEDIATION_EN_COURS' WHERE id = p_litige_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := CASE WHEN v_etab_id IS NOT NULL THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'MEDIATION_OUVERTE', p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('initie_par', CASE WHEN v_etab_id IS NOT NULL THEN 'etab' ELSE 'soignant' END)
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  SELECT
    CASE WHEN v_etab_id IS NOT NULL THEN v_litige.soignant_id ELSE v_litige.etablissement_id END,
    CASE WHEN v_etab_id IS NOT NULL THEN 'SOIGNANT' ELSE 'ETABLISSEMENT' END,
    'LITIGE_MEDIATION',
    'Médiation litige proposée',
    'L''autre partie propose une médiation amiable. Vous avez 7 jours pour discuter et confirmer un accord.',
    CASE WHEN v_etab_id IS NOT NULL THEN '/soignant/litiges' ELSE '/etablissement/litiges' END;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_proposer_accord_partie(UUID) TO authenticated;

-- 5) RPC fn_confirmer_accord_partie
CREATE OR REPLACE FUNCTION public.fn_confirmer_accord_partie(p_litige_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_litige RECORD;
  v_partie TEXT;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable'); END IF;

  IF v_litige.statut NOT IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige déjà résolu');
  END IF;

  IF v_etab_id IS NOT NULL AND v_litige.etablissement_id = v_etab_id THEN
    UPDATE litiges SET accord_etablissement = true, accord_etablissement_le = COALESCE(accord_etablissement_le, NOW())
    WHERE id = p_litige_id;
    v_partie := 'ETAB';
  ELSIF v_litige.soignant_id = v_uid THEN
    UPDATE litiges SET accord_soignant = true, accord_soignant_le = COALESCE(accord_soignant_le, NOW())
    WHERE id = p_litige_id;
    v_partie := 'SOIGNANT';
  ELSIF est_admin() THEN
    UPDATE litiges SET
      accord_soignant = true, accord_soignant_le = COALESCE(accord_soignant_le, NOW()),
      accord_etablissement = true, accord_etablissement_le = COALESCE(accord_etablissement_le, NOW())
    WHERE id = p_litige_id;
    v_partie := 'ADMIN';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas partie au litige');
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := CASE WHEN v_etab_id IS NOT NULL THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'MEDIATION_ACCORD_PARTIES',
    p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('partie', v_partie)
  );

  IF (SELECT statut FROM litiges WHERE id = p_litige_id) = 'RESOLU_ACCORD_PARTIES' THEN
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES
      (v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
       '✅ Litige résolu par accord mutuel',
       'Vous et l''établissement avez confirmé un accord. Aucune pénalité scoring.',
       '/soignant/litiges'),
      (v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
       '✅ Litige résolu par accord mutuel',
       'Vous et le soignant avez confirmé un accord. Aucune pénalité scoring.',
       '/etablissement/litiges');
  END IF;

  RETURN jsonb_build_object('success', true, 'partie', v_partie);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_confirmer_accord_partie(UUID) TO authenticated;

-- 6) RPC fn_admin_trancher_litige : décision admin RESOLU_FAVEUR_*/RESOLU_PARTAGE
CREATE OR REPLACE FUNCTION public.fn_admin_trancher_litige(p_litige_id UUID, p_decision TEXT, p_motif TEXT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_litige RECORD;
  v_decision_clean TEXT;
  v_statut_final TEXT;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seul l''administrateur peut trancher');
  END IF;

  v_decision_clean := UPPER(TRIM(p_decision));
  IF v_decision_clean NOT IN ('FAVEUR_SOIGNANT','FAVEUR_ETAB','PARTAGE') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Décision invalide (FAVEUR_SOIGNANT/FAVEUR_ETAB/PARTAGE)');
  END IF;

  v_statut_final := 'RESOLU_' || v_decision_clean;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable'); END IF;

  UPDATE litiges SET statut = v_statut_final, resolution = p_motif, resolu_par = v_uid, resolu_le = NOW()
  WHERE id = p_litige_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES
    (v_litige.soignant_id, 'SOIGNANT', 'LITIGE_RESOLU',
     CASE v_decision_clean
       WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en votre faveur ✅'
       WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en faveur de l''établissement'
       ELSE 'Litige tranché : décision partagée'
     END,
     COALESCE(p_motif, 'L''administrateur a tranché.'),
     '/soignant/litiges'),
    (v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_RESOLU',
     CASE v_decision_clean
       WHEN 'FAVEUR_SOIGNANT' THEN 'Litige tranché en faveur du soignant'
       WHEN 'FAVEUR_ETAB' THEN 'Litige tranché en votre faveur ✅'
       ELSE 'Litige tranché : décision partagée'
     END,
     COALESCE(p_motif, 'L''administrateur a tranché.'),
     '/etablissement/litiges');

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'MISSION_LITIGE',
    p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('decision', v_decision_clean, 'statut_final', v_statut_final, 'motif', p_motif)
  );

  RETURN jsonb_build_object('success', true, 'statut_final', v_statut_final);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_admin_trancher_litige(UUID, TEXT, TEXT) TO authenticated;

-- 7) RPC fn_basculer_litiges_revue_admin_timeout : appelée par cron daily
CREATE OR REPLACE FUNCTION public.fn_basculer_litiges_revue_admin_timeout()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_litige RECORD;
  v_count INT := 0;
BEGIN
  IF NOT (est_admin() OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  FOR v_litige IN
    SELECT id, soignant_id, etablissement_id FROM litiges
    WHERE statut = 'MEDIATION_EN_COURS'
      AND cree_le < NOW() - INTERVAL '7 days'
      AND (accord_soignant_le IS NULL OR accord_etablissement_le IS NULL)
  LOOP
    UPDATE litiges SET statut = 'REVUE_ADMIN' WHERE id = v_litige.id;

    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES
      (v_litige.soignant_id, 'SOIGNANT', 'LITIGE_MEDIATION',
       '⚠️ Litige basculé en revue admin',
       'La période de médiation de 7 jours est écoulée sans accord mutuel. Un administrateur va trancher.',
       '/soignant/litiges'),
      (v_litige.etablissement_id, 'ETABLISSEMENT', 'LITIGE_MEDIATION',
       '⚠️ Litige basculé en revue admin',
       'La période de médiation de 7 jours est écoulée sans accord mutuel. Un administrateur va trancher.',
       '/etablissement/litiges');

    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := v_litige.id, p_type_acteur := 'SYSTEME',
      p_action := 'MEDIATION_REVUE_ADMIN_DEMANDEE',
      p_type_ressource := 'litige', p_id_ressource := v_litige.id,
      p_details := jsonb_build_object('raison', 'timeout_7_jours_sans_accord')
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_basculer_litiges_revue_admin_timeout() TO service_role;

NOTIFY pgrst, 'reload schema';
