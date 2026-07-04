-- PHASE 4 (point 4) — Revue admin des établissements à vérifier.
-- 1) fn_admin_valider_etablissement : la validation manuelle pose DÉSORMAIS aussi
--    finess_verifie + rattachement (méthode ADMIN). Sans cela, l'établissement
--    validé restait bloqué par le verrou de publication (fn_blocage_publication_etab
--    exige finess_verifie ET rattachement_verifie). Incohérence corrigée.
--    BUG LATENT corrigé : l'action d'audit 'VALIDATION_ETABLISSEMENT' n'était PAS
--    dans journaux_audit_action_check → la fonction échouait en usage réel.
--    Idem 'REJET_ETABLISSEMENT' (fn_admin_rejeter_etablissement). On bascule sur
--    l'action whitelistée 'ADMIN_ACTION' + sous_action dans details.
-- 2) fn_admin_lister_etablissements_a_verifier : file d'attente admin avec tout le
--    dossier de vérification (FINESS, représentant + pièce, dirigeants INSEE, e-mail).

CREATE OR REPLACE FUNCTION public.fn_admin_valider_etablissement(p_etablissement_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    SELECT id, nom, statut_verification, siret_verifie, contrat_valide
    INTO v_etab FROM etablissements WHERE id = p_etablissement_id AND supprime_le IS NULL;

    IF v_etab IS NULL THEN
        RETURN jsonb_build_object('error', 'Établissement introuvable');
    END IF;

    IF v_etab.statut_verification = 'VERIFIE' THEN
        RETURN jsonb_build_object('error', 'Cet établissement est déjà vérifié');
    END IF;

    UPDATE etablissements SET
        statut_verification = 'VERIFIE',
        peut_publier_missions = TRUE,
        verifie_le = NOW(),
        verifie_par = auth.uid(),
        -- Validation manuelle = rattachement par décision admin. On marque le socle
        -- de vérification du dispositif pour que le verrou de publication soit cohérent.
        finess_verifie = TRUE,
        finess_verifie_le = COALESCE(finess_verifie_le, NOW()),
        rattachement_methode = 'ADMIN',
        rattachement_verifie = TRUE,
        rattachement_verifie_le = NOW()
    WHERE id = p_etablissement_id;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'ADMIN_ACTION', 'etablissement', p_etablissement_id,
        jsonb_build_object('sous_action', 'VALIDATION_ETABLISSEMENT', 'nom', v_etab.nom, 'rattachement', 'ADMIN'));

    RETURN jsonb_build_object('success', true, 'nom', v_etab.nom);
END;
$function$;

-- Correction du même bug latent sur le rejet (action non whitelistée).
CREATE OR REPLACE FUNCTION public.fn_admin_rejeter_etablissement(p_etablissement_id uuid, p_motif text DEFAULT 'Non conforme aux critères de la plateforme'::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_nom TEXT;
    v_motif_safe TEXT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    v_motif_safe := LEFT(REGEXP_REPLACE(COALESCE(NULLIF(TRIM(p_motif), ''), 'Non conforme'), '<[^>]*>', '', 'g'), 500);

    UPDATE etablissements SET
        statut_verification = 'REJETE',
        peut_publier_missions = FALSE,
        motif_rejet = v_motif_safe
    WHERE id = p_etablissement_id;

    SELECT COALESCE(nom, 'Inconnu') INTO v_nom FROM etablissements WHERE id = p_etablissement_id;

    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'ADMIN_ACTION', 'etablissement', p_etablissement_id,
        jsonb_build_object('sous_action', 'REJET_ETABLISSEMENT', 'nom', v_nom, 'motif', v_motif_safe));

    RETURN jsonb_build_object('success', TRUE, 'message', 'Établissement rejeté : ' || v_nom);
END;
$function$;

-- File d'attente admin : établissements dont le rattachement n'est pas encore validé
-- (hors rejetés). Expose tout le dossier de vérification pour décision éclairée.
CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements_a_verifier(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_resultat jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_resultat
  FROM (
    SELECT id, nom, siret, siret_verifie, finess, finess_verifie, finess_raison_sociale,
           finess_categorie, finess_secteur, finess_est_public,
           representant_nom, representant_prenom, representant_identite_verifiee,
           representant_piece_s3_key, representant_piece_type_document,
           dirigeants, email_contact, email_contact_verifie,
           rattachement_methode, rattachement_verifie, statut_verification,
           contrat_valide, peut_publier_missions, motif_rejet, cree_le
    FROM etablissements
    WHERE supprime_le IS NULL
      AND COALESCE(rattachement_verifie, false) = false
      AND COALESCE(statut_verification, '') <> 'REJETE'
    ORDER BY cree_le DESC NULLS LAST
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  ) e;

  RETURN jsonb_build_object('success', true, 'etablissements', v_resultat);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_lister_etablissements_a_verifier(integer) TO authenticated;
