-- La protection d'identité soignant ajoutée le 13/07 bloque légitimement les
-- mutations directes du score par un utilisateur. Elle neutralisait toutefois
-- aussi la pénalité interne de fn_declarer_empechement_imperieux, exécutée sous
-- le JWT du soignant malgré son SECURITY DEFINER : depassement=true était bien
-- renvoyé, mais le score restait inchangé.
--
-- La mutation métier est désormais entourée du contexte interne transactionnel
-- déjà reconnu par fn_protect_soignant_verification. La fenêtre est limitée à
-- l'unique UPDATE de pénalité et refermée immédiatement après.

CREATE OR REPLACE FUNCTION public.fn_declarer_empechement_imperieux(
  p_mission_id uuid, p_indispo_debut date, p_indispo_fin date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_m RECORD;
  v_nb int := 0;
  v_max int := GREATEST(0, fn_param_num('annulations_justifiees_max_12m', 2)::int);
  v_n12 int;
  v_depasse boolean;
  v_admin uuid;
BEGIN
  SELECT * INTO v_m
  FROM missions
  WHERE id = p_mission_id AND soignant_assigne_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus active.');
  END IF;
  IF v_m.est_arret_maladie THEN
    RETURN jsonb_build_object('error', 'Un empêchement est déjà déclaré sur cette mission.');
  END IF;
  IF p_indispo_debut IS NULL OR p_indispo_fin IS NULL OR p_indispo_fin < p_indispo_debut THEN
    RETURN jsonb_build_object('error', 'Dates d''indisponibilité invalides.');
  END IF;
  IF p_indispo_fin - p_indispo_debut > 90 THEN
    RETURN jsonb_build_object('error', 'Période d''indisponibilité trop longue (90 jours max).');
  END IF;

  SELECT count(*) INTO v_n12
  FROM journaux_audit
  WHERE acteur_id = auth.uid()
    AND action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
    AND cree_le > NOW() - INTERVAL '12 months';
  v_depasse := (v_n12 + 1) > v_max;

  UPDATE missions
  SET est_arret_maladie = TRUE,
      arret_maladie_declare_le = NOW(),
      modifie_le = NOW()
  WHERE id = p_mission_id;

  PERFORM fn_ecrire_audit_safe(
    auth.uid(), 'SOIGNANT', 'ANNULATION_EMPECHEMENT_IMPERIEUX',
    'mission', p_mission_id, NULL,
    jsonb_build_object(
      'sur_honneur', true,
      'indispo_debut', p_indispo_debut,
      'indispo_fin', p_indispo_fin,
      'n_12_mois', v_n12 + 1,
      'max_12_mois', v_max,
      'depassement', v_depasse
    )
  );

  IF v_depasse THEN
    PERFORM set_config('jolene.system_update', 'true', true);
    UPDATE soignants
    SET total_missions_annulees = COALESCE(total_missions_annulees, 0) + 1,
        score_fiabilite = GREATEST(0, COALESCE(score_fiabilite, 50) - 8),
        modifie_le = NOW()
    WHERE id = auth.uid();
    PERFORM set_config('jolene.system_update', '', true);

    FOR v_admin IN
      SELECT user_id FROM equipe_admin WHERE actif AND user_id IS NOT NULL
    LOOP
      INSERT INTO notifications (
        destinataire_id, type, titre, corps, lien, type_destinataire
      ) VALUES (
        v_admin,
        'SYSTEM',
        'Empêchements répétés — revue soignant ⚠️',
        'Un soignant vient de déclarer son ' || (v_n12 + 1) ||
          'e empêchement impérieux sur 12 mois (max toléré : ' || v_max ||
          '). Pénalité de score appliquée. Détails dans le journal d''audit ' ||
          '(action ANNULATION_EMPECHEMENT_IMPERIEUX).',
        '/admin/audit',
        'ADMIN'
      );
    END LOOP;
  END IF;

  INSERT INTO notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    v_m.etablissement_id,
    'SYSTEM',
    'Empêchement impérieux déclaré ⚠️',
    'Le soignant assigné à "' || fn_html_escape(v_m.intitule) ||
      '" atteste sur l''honneur d''un empêchement impérieux et sera indisponible du ' ||
      TO_CHAR(p_indispo_debut, 'DD/MM') || ' au ' || TO_CHAR(p_indispo_fin, 'DD/MM') || '.' ||
      CASE
        WHEN v_m.garantie_remplacement
          THEN ' Garantie remplacement : le pool d''urgence est alerté automatiquement.'
        ELSE ' Vous pouvez alerter le pool d''urgence depuis la mission.'
      END,
    '/etablissement/missions/' || v_m.id,
    'ETABLISSEMENT'
  );

  INSERT INTO notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    auth.uid(),
    'SYSTEM',
    'Empêchement enregistré',
    'Votre attestation sur l''honneur est enregistrée — aucun justificatif à fournir.' ||
      CASE
        WHEN v_depasse
          THEN ' Attention : au-delà de ' || v_max ||
            ' empêchements sur 12 mois, la pénalité de score s''applique (c''est le cas ici).'
        ELSE ' Aucune pénalité de score.'
      END ||
      ' Une fausse déclaration engage votre responsabilité (CGU).',
    '/soignant/missions/' || v_m.id,
    'SOIGNANT'
  );

  IF v_m.garantie_remplacement AND v_m.fin_le > NOW() + INTERVAL '1 hour' THEN
    UPDATE missions
    SET statut = 'OUVERTE',
        soignant_assigne_id = NULL,
        mode_attribution = 'PREMIER_ARRIVE',
        est_urgente = TRUE,
        niveau_urgence = 3,
        presence_confirmee_le = NULL,
        debut_le = GREATEST(debut_le, NOW() + INTERVAL '15 minutes'),
        modifie_le = NOW()
    WHERE id = p_mission_id;
    v_nb := fn_diffuser_pool_urgence(p_mission_id);
  END IF;

  RETURN jsonb_build_object(
    'success', TRUE,
    'pool_alerte', v_nb,
    'depassement', v_depasse,
    'n_12_mois', v_n12 + 1,
    'max_12_mois', v_max
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_declarer_empechement_imperieux(uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_declarer_empechement_imperieux(uuid, date, date)
  TO authenticated, service_role;
