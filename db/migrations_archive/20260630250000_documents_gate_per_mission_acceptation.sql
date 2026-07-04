-- Documents — étape 2a : gating PER-MISSION sur les chemins d'ACCEPTATION.
--
-- Le régime est une propriété de la MISSION, pas du soignant. Un flag global
-- `tous_documents_valides` (par soignant) ne peut pas représenter un Mixte qui a
-- les bons docs pour ses missions salariées mais pas encore pour les libérales.
-- On calcule donc les docs requis au check, à partir du type_contrat de la mission.
--
-- fn_documents_ok_pour_mission(soignant, type_contrat) : même cœur que
-- fn_calculer_tous_documents_valides (régime-aware + RPPS/ADELI court-circuite
-- DIPLOME/RPPS_ADELI) mais scopé au régime de LA mission. Ambigu (TOUS/NULL) →
-- sens le MOINS exigeant (salarié) : une mission polyvalente reste candidatable
-- avec des docs salariés, jamais bloquée faute de docs libéraux.
-- Le flag global reste un indicateur admin « prêt tous régimes » (non modifié).

CREATE OR REPLACE FUNCTION public.fn_documents_ok_pour_mission(p_soignant_id uuid, p_type_contrat text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_profession type_profession;
  v_identite_verifiee BOOLEAN;
  v_regime_liberal BOOLEAN;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN false; END IF;
  SELECT profession, (COALESCE(rpps_verifie, false) OR COALESCE(adeli_verifie, false))
    INTO v_profession, v_identite_verifiee
    FROM soignants WHERE id = p_soignant_id;

  -- Seul 'LIBERAL' exige les docs libéraux ; SALARIE/CDD/VACATION + ambigu (TOUS/NULL)
  -- → régime salarié (le moins exigeant).
  v_regime_liberal := (p_type_contrat = 'LIBERAL');

  RETURN NOT EXISTS(
    SELECT 1 FROM documents_requis_par_profession drp
    WHERE drp.profession = v_profession
      AND drp.est_critique = true
      AND (
          drp.type_exercice_requis = 'TOUS'
          OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_regime_liberal)
          OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND NOT v_regime_liberal)
      )
      AND NOT (v_identite_verifiee AND drp.type_document IN ('DIPLOME', 'RPPS_ADELI'))
      AND NOT EXISTS (
          SELECT 1 FROM documents_soignants ds
          WHERE ds.soignant_id = p_soignant_id
            AND ds.type_document = drp.type_document
            AND ds.statut_verification = 'VERIFIE'
            AND ds.supprime_le IS NULL
            AND (drp.a_expiration = false OR ds.valide_jusqua IS NULL OR ds.valide_jusqua > NOW())
      )
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_documents_ok_pour_mission(uuid, text) TO authenticated, service_role;

-- ── Trigger docs avant début (soignant assigné → EN_COURS) : per-mission.
CREATE OR REPLACE FUNCTION public.dec_verifier_docs_avant_debut()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_rcp_ok BOOLEAN;
BEGIN
    IF NEW.statut = 'EN_COURS' AND OLD.statut = 'ASSIGNEE' AND NEW.soignant_assigne_id IS NOT NULL THEN
        IF NOT fn_documents_ok_pour_mission(NEW.soignant_assigne_id, NEW.type_contrat_applique::text) THEN
            RAISE EXCEPTION 'Documents obligatoires non validés pour le régime de cette mission. Le soignant doit compléter son dossier avant le début.';
        END IF;

        -- RCP exigée uniquement pour une mission en LIBÉRAL.
        IF NEW.type_contrat_applique = 'LIBERAL' THEN
            SELECT EXISTS(
                SELECT 1 FROM documents_soignants
                WHERE soignant_id = NEW.soignant_assigne_id AND type_document = 'RCP_ASSURANCE'
                AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
                AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
            ) INTO v_rcp_ok;

            IF NOT v_rcp_ok THEN
                RAISE EXCEPTION 'Assurance RCP manquante ou expirée. Le soignant ne peut pas commencer la mission en libéral.';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

-- ── Acceptation directe (PREMIER_ARRIVE) : per-mission (régime résolu).
CREATE OR REPLACE FUNCTION public.fn_accepter_mission(p_mission_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_type_paiement TEXT;
    v_mode_paiement TEXT;
    v_type_contrat_gen TEXT;
    v_numero_contrat TEXT;
    v_contrat_id UUID;
    v_choix_effectif TEXT;
    v_rows INT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'PREMIER_ARRIVE' THEN RETURN jsonb_build_object('error', 'Cette mission nécessite une candidature'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    IF NOT fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
           v_mission.profession_requise, v_mission.specialite_medicale_requise, v_mission.accepte_non_specialises) THEN
        RETURN jsonb_build_object('error', 'Profession incompatible.');
    END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux salariés.');
    END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux libéraux.');
    END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Choisissez votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD / bulletin de paie)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    ELSE
        v_choix_effectif := p_choix_contrat;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    -- Docs requis selon le RÉGIME de la mission (résolu si Mixte), pas un flag global.
    IF NOT fn_documents_ok_pour_mission(auth.uid(), COALESCE(v_choix_effectif, v_mission.type_contrat_recherche::text)) THEN
        RETURN jsonb_build_object('error', 'Vos documents doivent être validés pour ce type de mission. Téléversez-les dans Mes documents — la vérification automatique prend quelques minutes.');
    END IF;

    IF v_soignant.type_exercice = 'LIBERAL' OR (v_soignant.type_exercice = 'MIXTE' AND (v_choix_effectif = 'LIBERAL' OR v_mission.type_contrat_recherche = 'LIBERAL')) THEN
        v_type_paiement := 'NOTE_HONORAIRES';
        v_mode_paiement := 'STRIPE_CONNECT';
        v_type_contrat_gen := 'LIBERAL';
    ELSE
        v_type_paiement := 'BULLETIN_PAIE';
        v_mode_paiement := 'DIRECT';
        v_type_contrat_gen := 'CDD';
    END IF;

    UPDATE missions SET
        soignant_assigne_id = auth.uid(), statut = 'ASSIGNEE',
        choix_contrat_soignant = v_choix_effectif,
        type_paiement_soignant = v_type_paiement,
        mode_paiement_soignant = v_mode_paiement,
        modifie_le = NOW()
    WHERE id = p_mission_id AND statut = 'OUVERTE';

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN
        RETURN jsonb_build_object('error', 'Cette mission vient d''être prise par un autre soignant (déjà prise).');
    END IF;

    v_numero_contrat := fn_generer_numero_contrat_safe(v_type_contrat_gen);

    INSERT INTO contrats_mission (
        mission_id, etablissement_id, soignant_id,
        type_contrat, numero_contrat, statut
    ) VALUES (
        p_mission_id, v_mission.etablissement_id, auth.uid(),
        v_type_contrat_gen, v_numero_contrat, 'EN_ATTENTE_SIGNATURES'
    )
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_contrat_id;

    IF v_contrat_id IS NULL THEN
        SELECT id INTO v_contrat_id FROM contrats_mission
        WHERE mission_id = p_mission_id
          AND soignant_id = auth.uid()
          AND statut <> 'ANNULE'
        ORDER BY cree_le DESC LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'contrat_id', v_contrat_id,
        'contrat_numero', v_numero_contrat,
        'type_paiement', v_type_paiement,
        'mode_paiement', v_mode_paiement
    );
END;
$function$;

-- ── Acceptation rapide pool urgence : per-mission.
CREATE OR REPLACE FUNCTION public.fn_accepter_mission_urgence(p_mission_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_soignant RECORD;
  v_mission RECORD;
  v_existing UUID;
  v_candidature_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable');
  END IF;

  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;
  IF v_mission.statut <> 'OUVERTE' OR COALESCE(v_mission.est_urgente, false) = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission non disponible (non-urgente ou non-ouverte)');
  END IF;

  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profession ou spécialité incompatible');
  END IF;

  IF NOT fn_documents_ok_pour_mission(v_uid, v_mission.type_contrat_recherche::text) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vos documents ne sont pas validés pour ce type de mission');
  END IF;

  IF v_mission.type_contrat_recherche = 'LIBERAL' THEN
    IF NOT EXISTS (
      SELECT 1 FROM documents_soignants
      WHERE soignant_id = v_uid AND type_document = 'RCP_ASSURANCE'
      AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
      AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Assurance RCP obligatoire pour une mission urgente en libéral.');
    END IF;
  END IF;

  SELECT id INTO v_existing FROM candidatures
  WHERE mission_id = p_mission_id AND soignant_id = v_uid
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà candidaté à cette mission');
  END IF;

  INSERT INTO candidatures (mission_id, soignant_id, statut, message, cree_le)
  VALUES (
    p_mission_id, v_uid, 'EN_ATTENTE_VALIDATION_ETAB',
    'Acceptation rapide via pool urgence',
    NOW()
  )
  RETURNING id INTO v_candidature_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  VALUES (
    v_mission.etablissement_id, 'ETABLISSEMENT', 'POOL_URGENCE_ACCEPTATION',
    '🚨 Acceptation rapide pool urgence',
    v_soignant.prenom || ' ' || LEFT(v_soignant.nom, 1) || '. (' || v_soignant.profession::text
      || ') a accepté votre mission urgente. Validez ou refusez sous 1h.',
    '/etablissement/missions/' || p_mission_id::text,
    'candidature', v_candidature_id
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'POOL_URGENCE_ACCEPTATION_RAPIDE',
    p_type_ressource := 'candidature',
    p_id_ressource := v_candidature_id,
    p_details := jsonb_build_object('mission_id', p_mission_id)
  );

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'message', 'Acceptation enregistrée. Attente validation établissement.'
  );
END;
$function$;

-- ── Proposition étab → soignant : per-mission (régime de la mission, ambigu = salarié).
CREATE OR REPLACE FUNCTION public.fn_proposer_mission_soignant(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_soignant RECORD;
    v_choix_persiste TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;

    IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN
        RETURN '{"error":"Acces refuse"}'::JSONB;
    END IF;

    IF v_mission.statut != 'OUVERTE' THEN
        RETURN '{"error":"La mission n est plus ouverte"}'::JSONB;
    END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = p_soignant_id;
    IF v_soignant IS NULL THEN RETURN '{"error":"Soignant introuvable"}'::JSONB; END IF;

    IF v_soignant.profession != v_mission.profession_requise THEN
        RETURN jsonb_build_object('error', 'Ce soignant est ' || v_soignant.profession::TEXT || ', la mission requiert un(e) ' || v_mission.profession_requise::TEXT);
    END IF;

    IF v_mission.type_contrat_recherche IS NOT NULL AND v_mission.type_contrat_recherche != 'TOUS' THEN
        IF (v_mission.type_contrat_recherche = 'SALARIE' AND v_soignant.type_exercice = 'LIBERAL')
           OR (v_mission.type_contrat_recherche = 'LIBERAL' AND v_soignant.type_exercice = 'SALARIE') THEN
            RETURN jsonb_build_object('error', 'Type d exercice incompatible avec cette mission');
        END IF;
    END IF;

    IF NOT fn_documents_ok_pour_mission(p_soignant_id, v_mission.type_contrat_recherche::text) THEN
        RETURN jsonb_build_object('error', 'Ce soignant n a pas les documents requis pour ce type de mission.');
    END IF;

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = p_soignant_id AND statut IN ('EN_ATTENTE','PROPOSEE','ACCEPTEE')) THEN
        RETURN '{"error":"Deja propose a ce soignant"}'::JSONB;
    END IF;

    IF fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN
        RETURN '{"error":"Ce soignant est dans votre liste d exclusions."}'::JSONB;
    END IF;

    IF p_choix_contrat IS NOT NULL AND p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
        RETURN jsonb_build_object('error', 'p_choix_contrat invalide (attendu SALARIE ou LIBERAL).');
    END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL THEN
            RETURN jsonb_build_object(
                'error', 'E16_CHOIX_CONTRAT_REQUIS',
                'message', 'Ce soignant est MIXTE et la mission accepte les deux contrats. Specifiez p_choix_contrat SALARIE ou LIBERAL.',
                'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarie (CDD)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Liberal (note d honoraires)')
                )
            );
        END IF;
        v_choix_persiste := p_choix_contrat;
    ELSIF v_mission.type_contrat_recherche = 'SALARIE' THEN
        v_choix_persiste := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN
        v_choix_persiste := 'LIBERAL';
    ELSIF v_soignant.type_exercice IN ('SALARIE', 'LIBERAL') THEN
        v_choix_persiste := v_soignant.type_exercice;
    ELSE
        v_choix_persiste := NULL;
    END IF;

    INSERT INTO candidatures (mission_id, soignant_id, statut, proposee_par, type_contrat_choisi)
    VALUES (p_mission_id, p_soignant_id, 'PROPOSEE', auth.uid(), v_choix_persiste);

    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Mission proposee',
        'On vous propose la mission "' || fn_html_escape(v_mission.intitule) || '"',
        '/soignant/missions/' || p_mission_id, 'SOIGNANT');

    RETURN jsonb_build_object('success', TRUE, 'choix_persiste', v_choix_persiste);
END;
$function$;
