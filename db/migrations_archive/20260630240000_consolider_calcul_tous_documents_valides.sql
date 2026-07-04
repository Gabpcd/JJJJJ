-- Documents — consolidation de la source de vérité `tous_documents_valides`.
--
-- BUG : 3 triggers sur documents_soignants + 2 chemins inline (fn_admin_moderer_document,
-- cron fn_verifier_documents_expirants) calculaient le flag avec des logiques DIFFÉRENTES.
-- Le bon calcul (régime-aware par type_exercice_requis + RPPS/ADELI vérifié dispense de
-- DIPLOME/RPPS_ADELI) était écrasé par les calculs naïfs (comptent TOUS les docs requis,
-- sans régime ni court-circuit identité) → un Mixte / un RPPS-validé voyait son flag
-- repasser à false de façon « aléatoire » (selon le dernier chemin exécuté).
--
-- FIX étape 1 : UNE seule logique, dans fn_calculer_tous_documents_valides(soignant_id),
-- appelée par tous les chemins. (Étape 2 = rendre ce calcul per-mission au check
-- candidature/acceptation — séparée.)

-- 1) Source de vérité unique : le bon calcul, extrait en fonction appelable.
CREATE OR REPLACE FUNCTION public.fn_calculer_tous_documents_valides(p_soignant_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rpps_verifie BOOLEAN;
  v_adeli_verifie BOOLEAN;
  v_identite_verifiee BOOLEAN;
  v_est_liberal_pur BOOLEAN;
  v_est_salarie BOOLEAN;
BEGIN
  IF p_soignant_id IS NULL THEN RETURN; END IF;

  SELECT COALESCE(rpps_verifie, false),
         COALESCE(adeli_verifie, false),
         (type_exercice = 'LIBERAL'),
         (type_exercice IS DISTINCT FROM 'LIBERAL')
    INTO v_rpps_verifie, v_adeli_verifie, v_est_liberal_pur, v_est_salarie
    FROM soignants WHERE id = p_soignant_id;

  v_identite_verifiee := v_rpps_verifie OR v_adeli_verifie;

  UPDATE soignants SET tous_documents_valides = NOT EXISTS(
      SELECT 1 FROM documents_requis_par_profession drp
      WHERE drp.profession = (SELECT profession FROM soignants WHERE id = p_soignant_id)
        AND drp.est_critique = true
        AND (
            drp.type_exercice_requis = 'TOUS'
            OR (drp.type_exercice_requis = 'LIBERAL_ONLY' AND v_est_liberal_pur)
            OR (drp.type_exercice_requis = 'SALARIE_ONLY' AND v_est_salarie)
        )
        -- RPPS/ADELI vérifié = droit d'exercer prouvé → dispense DIPLOME + RPPS_ADELI.
        AND NOT (v_identite_verifiee AND drp.type_document IN ('DIPLOME', 'RPPS_ADELI'))
        AND NOT EXISTS (
            SELECT 1 FROM documents_soignants ds
            WHERE ds.soignant_id = p_soignant_id
              AND ds.type_document = drp.type_document
              AND ds.statut_verification = 'VERIFIE'
              AND ds.supprime_le IS NULL
              AND (drp.a_expiration = false OR ds.valide_jusqua IS NULL OR ds.valide_jusqua > NOW())
        )
  ), modifie_le = NOW() WHERE id = p_soignant_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_calculer_tous_documents_valides(uuid) TO authenticated, service_role;

-- 2) Les 3 fonctions trigger délèguent toutes à la source unique (plus de divergence).
CREATE OR REPLACE FUNCTION public.fn_recalculer_tous_documents_valides()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM fn_calculer_tous_documents_valides(COALESCE(NEW.soignant_id, OLD.soignant_id));
  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_maj_tous_documents_valides()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM fn_calculer_tous_documents_valides(COALESCE(NEW.soignant_id, OLD.soignant_id));
  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.dec_verifier_expiration_documents()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM fn_calculer_tous_documents_valides(NEW.soignant_id);
  RETURN NEW;
END;
$function$;

-- 3) Retire les 2 triggers redondants : un seul suffit (tous calculent désormais pareil).
DROP TRIGGER IF EXISTS dec_document_verification_expiration ON public.documents_soignants;
DROP TRIGGER IF EXISTS trg_maj_tous_documents_valides ON public.documents_soignants;

-- 4) Modération admin : déléguer au calcul unique (au lieu du recalcul naïf inline).
CREATE OR REPLACE FUNCTION public.fn_admin_moderer_document(p_document_id uuid, p_action text, p_motif text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_doc RECORD;
BEGIN
    IF NOT est_admin() THEN
        RETURN '{"error":"Non autorisé"}'::JSONB;
    END IF;

    SELECT * INTO v_doc FROM documents_soignants WHERE id = p_document_id;
    IF NOT FOUND THEN
        RETURN '{"error":"Document non trouvé"}'::JSONB;
    END IF;

    IF p_action = 'VALIDER' THEN
        UPDATE documents_soignants SET statut_verification = 'VERIFIE', verifie_par = auth.uid(), verifie_le = NOW(), motif_rejet = NULL WHERE id = p_document_id;
    ELSIF p_action = 'REJETER' THEN
        UPDATE documents_soignants SET statut_verification = 'REJETE', verifie_par = auth.uid(), verifie_le = NOW(), motif_rejet = COALESCE(p_motif, 'Document non conforme') WHERE id = p_document_id;
    ELSE
        RETURN jsonb_build_object('error', 'Action invalide: ' || p_action);
    END IF;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'MODERATION_DOCUMENT', 'document', p_document_id,
        jsonb_build_object('action', p_action, 'type_document', v_doc.type_document, 'soignant_id', v_doc.soignant_id));

    PERFORM fn_calculer_tous_documents_valides(v_doc.soignant_id);

    RETURN jsonb_build_object('success', true, 'action', p_action);
END;
$function$;

-- 5) Cron d'expiration : conserve les notifications, recalcule le flag via la source unique.
CREATE OR REPLACE FUNCTION public.fn_verifier_documents_expirants()
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER := 0;
    v_doc RECORD;
    v_sid UUID;
BEGIN
    -- Documents qui expirent dans 30 jours
    FOR v_doc IN
        SELECT d.id, d.soignant_id, d.type_document, d.valide_jusqua, s.prenom, s.email
        FROM documents_soignants d
        JOIN soignants s ON s.id = d.soignant_id
        WHERE d.valide_jusqua IS NOT NULL
          AND d.valide_jusqua BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
          AND d.supprime_le IS NULL
          AND d.statut_verification = 'VERIFIE'
          AND d.rappel_j30_envoye = FALSE
    LOOP
        UPDATE documents_soignants SET rappel_j30_envoye = TRUE WHERE id = v_doc.id;
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_doc.soignant_id, 'DOCUMENT_EXPIRANT',
            'Document bientôt expiré ⚠️',
            'Votre ' || v_doc.type_document || ' expire le ' || v_doc.valide_jusqua,
            '/soignant/documents', 'SOIGNANT');
        v_count := v_count + 1;
    END LOOP;

    -- Documents qui expirent dans 7 jours
    FOR v_doc IN
        SELECT d.id, d.soignant_id, d.type_document, d.valide_jusqua
        FROM documents_soignants d
        WHERE d.valide_jusqua IS NOT NULL
          AND d.valide_jusqua BETWEEN CURRENT_DATE AND CURRENT_DATE + 7
          AND d.supprime_le IS NULL
          AND d.rappel_j7_envoye = FALSE
    LOOP
        UPDATE documents_soignants SET rappel_j7_envoye = TRUE WHERE id = v_doc.id;
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_doc.soignant_id, 'DOCUMENT_EXPIRANT',
            '⚠️ Document expire dans 7 jours',
            'Votre ' || v_doc.type_document || ' expire le ' || v_doc.valide_jusqua || '. Renouvelez-le maintenant.',
            '/soignant/documents', 'SOIGNANT');
        v_count := v_count + 1;
    END LOOP;

    -- Documents critiques expirés → recalcul du flag via la source unique
    -- (régime-aware + court-circuit identité), au lieu d'un FALSE naïf.
    FOR v_sid IN
        SELECT DISTINCT d.soignant_id FROM documents_soignants d
        JOIN documents_requis_par_profession r ON d.type_document = r.type_document
        JOIN soignants s ON s.id = d.soignant_id AND s.profession = r.profession
        WHERE d.valide_jusqua < CURRENT_DATE
          AND d.supprime_le IS NULL
          AND r.est_critique = TRUE
    LOOP
        PERFORM fn_calculer_tous_documents_valides(v_sid);
    END LOOP;

    RETURN v_count;
END;
$function$;
