-- Réconciliation après la migration historique 20260714154908, déjà
-- enregistrée en production depuis une branche parallèle. Cette version
-- historique corrigeait uniquement le GUC de pénalité et redéfinissait
-- l'ancienne RPC simplifiée. La migration canonique 20260714135000 apporte
-- les verrous, les garde-fous financiers, la mission de remplacement séparée
-- et la resynchronisation des compteurs ; elle doit rester la dernière
-- définition effective sur une base neuve comme sur la production.
CREATE OR REPLACE FUNCTION public.fn_declarer_empechement_imperieux(
  p_mission_id uuid, p_indispo_debut date, p_indispo_fin date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_m public.missions%ROWTYPE;
  v_escrow public.paiements_escrow%ROWTYPE;
  v_nb integer := 0;
  v_max integer := greatest(
    0, fn_param_num('annulations_justifiees_max_12m', 2)::integer
  );
  v_n12 integer;
  v_depasse boolean;
  v_admin uuid;
  v_soignant_id uuid := auth.uid();
  v_audit_result jsonb;
  v_refund_result jsonb;
  v_blocage_publication jsonb;
  v_notifications_avant integer := 0;
  v_rows integer := 0;
  v_context text;
  v_est_future boolean;
  v_originale_cloturee boolean := false;
  v_remplacement_en_revue boolean := false;
  v_finance_resolution text := 'AUCUNE';
  v_previous_empechement_context text := COALESCE(
    current_setting('jolene.empechement_mission_context', true), ''
  );
  v_previous_empechement_validated text := COALESCE(
    current_setting('jolene.empechement_mission_validated', true), ''
  );
  v_mission_diffusee_id uuid := p_mission_id;
  v_remplacement_id uuid;
  v_previous_system_update text := COALESCE(
    current_setting('jolene.system_update', true), ''
  );
BEGIN
  -- Un verrou par soignant sérialise le quota même si deux missions distinctes
  -- sont déclarées en parallèle. Le verrou de ligne empêche en plus une double
  -- déclaration de la même mission.
  IF v_soignant_id IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'jolene.empechement.' || v_soignant_id::text,
        0
      )
    );
  END IF;

  SELECT * INTO v_m
  FROM public.missions
  WHERE id = p_mission_id AND soignant_assigne_id = v_soignant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_m.est_arret_maladie THEN
    RETURN jsonb_build_object('error', 'Un empêchement est déjà déclaré sur cette mission.');
  END IF;
  IF v_m.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN
    RETURN jsonb_build_object('error', 'Cette mission n''est plus active.');
  END IF;
  IF p_indispo_debut IS NULL OR p_indispo_fin IS NULL OR p_indispo_fin < p_indispo_debut THEN
    RETURN jsonb_build_object('error', 'Dates d''indisponibilité invalides.');
  END IF;
  IF p_indispo_fin - p_indispo_debut > 90 THEN
    RETURN jsonb_build_object('error', 'Période d''indisponibilité trop longue (90 jours max).');
  END IF;
  IF p_indispo_fin < (v_m.debut_le AT TIME ZONE 'Europe/Paris')::date
     OR p_indispo_debut > (v_m.fin_le AT TIME ZONE 'Europe/Paris')::date THEN
    RETURN jsonb_build_object(
      'error_code', 'INDISPONIBILITE_HORS_MISSION',
      'error', 'La période d''indisponibilité doit chevaucher la mission.'
    );
  END IF;

  v_est_future := v_m.statut = 'ASSIGNEE' AND v_m.debut_le > now();

  -- Une mission future doit pouvoir être annulée sans jamais payer l'ancien
  -- soignant. Les situations déjà externalisées ou ambiguës sont arrêtées
  -- avant le moindre flag/audit : aucune demi-transaction n'est possible.
  IF v_est_future THEN
    IF EXISTS (
      SELECT 1 FROM public.stripe_transfers st
      WHERE st.mission_id = p_mission_id
        AND st.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
    ) OR EXISTS (
      SELECT 1 FROM public.paiements_soignant ps
      WHERE ps.mission_id = p_mission_id
    ) OR EXISTS (
      SELECT 1 FROM public.factures_honoraires fh
      WHERE fh.mission_id = p_mission_id
        AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    ) THEN
      RETURN jsonb_build_object(
        'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
        'error', 'Une opération financière existe déjà pour cette mission. Le support doit la rapprocher avant l''annulation.'
      );
    END IF;

    SELECT pe.* INTO v_escrow
    FROM public.paiements_escrow pe
    WHERE pe.mission_id = p_mission_id
    ORDER BY pe.cree_le DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      IF v_escrow.statut IN ('RELEASE_PLANIFIE', 'PAYE', 'DISPUTE')
         OR (
           v_escrow.statut = 'INITIE'
           AND (
             v_escrow.stripe_payment_intent_id IS NOT NULL
             OR v_escrow.stripe_charge_id IS NOT NULL
             OR v_escrow.stripe_payout_id IS NOT NULL
             OR COALESCE(v_escrow.tentatives_debit, 0) > 0
           )
         ) THEN
        RETURN jsonb_build_object(
          'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
          'error', 'Le paiement rapide est déjà en cours d''externalisation. Le support doit le rapprocher avant l''annulation.',
          'escrow_statut', v_escrow.statut
        );
      END IF;
    END IF;
  END IF;

  SELECT count(*) INTO v_n12
  FROM public.journaux_audit
  WHERE acteur_id = v_soignant_id
    AND action = 'ANNULATION_EMPECHEMENT_IMPERIEUX'
    AND cree_le > NOW() - INTERVAL '12 months';
  v_depasse := (v_n12 + 1) > v_max;

  -- Phase FLAG : le garde alphabétiquement premier vérifie que ces trois
  -- colonnes sont les seules mutées. La phase est nécessaire aussi pour un
  -- profil soignant qui possède parallèlement un rôle établissement faible.
  v_context := 'FLAG:' || p_mission_id::text || ':' || v_soignant_id::text;
  BEGIN
    PERFORM set_config(
      'jolene.empechement_mission_context', v_context, true
    );
    PERFORM set_config('jolene.empechement_mission_validated', '', true);
    UPDATE missions
    SET est_arret_maladie = TRUE,
        arret_maladie_declare_le = NOW(),
        modifie_le = NOW()
    WHERE id = p_mission_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1
       OR NOT EXISTS (
         SELECT 1
         FROM public.missions m_flag
         WHERE m_flag.id = p_mission_id
           AND m_flag.est_arret_maladie IS TRUE
           AND m_flag.arret_maladie_declare_le IS NOT NULL
       ) THEN
      RAISE EXCEPTION 'Phase interne FLAG incomplète.'
        USING ERRCODE = 'P0001';
    END IF;
    PERFORM set_config(
      'jolene.empechement_mission_validated',
      v_previous_empechement_validated,
      true
    );
    PERFORM set_config(
      'jolene.empechement_mission_context',
      v_previous_empechement_context,
      true
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config(
      'jolene.empechement_mission_validated',
      v_previous_empechement_validated,
      true
    );
    PERFORM set_config(
      'jolene.empechement_mission_context',
      v_previous_empechement_context,
      true
    );
    RAISE;
  END;

  v_audit_result := fn_ecrire_audit_safe(
    v_soignant_id, 'SOIGNANT', 'ANNULATION_EMPECHEMENT_IMPERIEUX',
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
  IF COALESCE((v_audit_result->>'success')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'La déclaration ne peut pas être journalisée.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Le compteur est intégralement dérivé de ses sources canoniques.
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant_id);

  IF v_depasse THEN
    BEGIN
      PERFORM set_config('jolene.system_update', 'true', true);
      UPDATE soignants
      SET score_fiabilite = GREATEST(
            0, COALESCE(score_fiabilite, 50) - 8
          ),
          modifie_le = NOW()
      WHERE id = v_soignant_id;
      PERFORM set_config(
        'jolene.system_update', v_previous_system_update, true
      );
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config(
        'jolene.system_update', v_previous_system_update, true
      );
      RAISE;
    END;

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

  -- Neutraliser l'ancien rail financier puis clôturer toute mission future,
  -- garantie ou non. L'originale conserve l'assigné pour la preuve et les
  -- compteurs ; le remplacement aura toujours un nouvel id.
  IF v_est_future THEN
    IF v_escrow.id IS NOT NULL THEN
      IF v_escrow.statut = 'INITIE' THEN
        UPDATE public.paiements_escrow
           SET statut = 'REMBOURSE',
               erreur = 'Annulé avant tout débit : empêchement impérieux',
               modifie_le = now()
         WHERE id = v_escrow.id
           AND statut = 'INITIE'
           AND stripe_payment_intent_id IS NULL
           AND stripe_charge_id IS NULL
           AND stripe_payout_id IS NULL
           AND tentatives_debit = 0;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'Neutralisation escrow concurrente refusée.'
            USING ERRCODE = 'P0001';
        END IF;
        UPDATE public.escrow_exposition_releases
           SET statut = 'REGLE'
         WHERE paiement_escrow_id = v_escrow.id AND statut = 'ACTIF';
        UPDATE public.escrow_release_queue
           SET statut = 'ECHEC',
               erreur = 'Mission annulée avant débit',
               traite_le = now()
         WHERE paiement_escrow_id = v_escrow.id
           AND statut IN ('EN_ATTENTE', 'EN_COURS');
        INSERT INTO public.journaux_audit (
          acteur_id, type_acteur, action, type_ressource, id_ressource,
          details, navigateur_acteur
        ) VALUES (
          '00000000-0000-0000-0000-000000000000'::uuid,
          'SYSTEME', 'ADMIN_ACTION', 'paiement_escrow', v_escrow.id,
          jsonb_build_object(
            'evenement', 'ESCROW_ANNULE_AVANT_DEBIT',
            'mission_id', p_mission_id,
            'motif', 'EMPECHEMENT_IMPERIEUX'
          ),
          'fn_declarer_empechement_imperieux'
        );
        v_finance_resolution := 'ESCROW_ANNULE_AVANT_DEBIT';
      ELSIF v_escrow.statut IN ('DEBITE', 'DISPONIBLE') THEN
        v_refund_result := public.fn_escrow_rembourser(
          v_escrow.id,
          v_escrow.honoraires_cents,
          true,
          'Empêchement impérieux avant mission'
        );
        IF COALESCE((v_refund_result->>'success')::boolean, false) IS NOT TRUE THEN
          RAISE EXCEPTION 'Remboursement escrow impossible: %', v_refund_result
            USING ERRCODE = 'P0001';
        END IF;
        v_finance_resolution := 'ESCROW_REMBOURSEMENT_ENFILE';
      ELSIF v_escrow.statut = 'REMBOURSE_EN_COURS' THEN
        v_finance_resolution := 'ESCROW_REMBOURSEMENT_DEJA_EN_COURS';
      ELSIF v_escrow.statut IN ('REMBOURSE', 'ECHOUE') THEN
        v_finance_resolution := 'ESCROW_TERMINAL';
      ELSE
        RAISE EXCEPTION 'Etat escrow non annulable: %', v_escrow.statut
          USING ERRCODE = 'P0001';
      END IF;
    END IF;

    v_context := 'CLOSE:' || p_mission_id::text || ':' || v_soignant_id::text;
    BEGIN
      PERFORM set_config('jolene.empechement_mission_context', v_context, true);
      PERFORM set_config('jolene.empechement_mission_validated', '', true);
      UPDATE public.missions
         SET statut = 'ANNULEE_PAR_SOIGNANT', modifie_le = now()
       WHERE id = p_mission_id;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 OR NOT EXISTS (
        SELECT 1 FROM public.missions m_close
        WHERE m_close.id = p_mission_id
          AND m_close.statut = 'ANNULEE_PAR_SOIGNANT'
          AND m_close.soignant_assigne_id = v_soignant_id
          AND m_close.est_arret_maladie IS TRUE
      ) THEN
        RAISE EXCEPTION 'Phase interne CLOSE incomplète.'
          USING ERRCODE = 'P0001';
      END IF;
      PERFORM set_config(
        'jolene.empechement_mission_validated',
        v_previous_empechement_validated, true
      );
      PERFORM set_config(
        'jolene.empechement_mission_context',
        v_previous_empechement_context, true
      );
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config(
        'jolene.empechement_mission_validated',
        v_previous_empechement_validated, true
      );
      PERFORM set_config(
        'jolene.empechement_mission_context',
        v_previous_empechement_context, true
      );
      RAISE;
    END;
    v_originale_cloturee := true;

    -- Le contrat signé reste une preuve immuable. Si une DPAE a été faite,
    -- on enfile explicitement son annulation au lieu de falsifier le contrat.
    INSERT INTO public.externalisation_actions (
      type_action, payload, source, source_id
    )
    SELECT 'DPAE_ANNULATION',
           jsonb_build_object(
             'contrat_id', cm.id,
             'mission_id', p_mission_id,
             'motif', 'EMPECHEMENT_IMPERIEUX',
             'echeance_legale_h', 48
           ),
           'ANNULATION_MISSION', p_mission_id
    FROM public.contrats_mission cm
    WHERE cm.mission_id = p_mission_id
      AND cm.statut = 'SIGNE_COMPLET'
      AND cm.type_contrat IN ('CDD', 'CDDU', 'VACATION')
      AND (
        COALESCE(cm.dpae_effectuee, false) IS TRUE
        OR NULLIF(btrim(COALESCE(cm.dpae_numero, '')), '') IS NOT NULL
      );
  END IF;

  INSERT INTO public.notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    v_m.etablissement_id,
    'SYSTEM',
    'Empêchement impérieux déclaré ⚠️',
    'Le soignant assigné à "' || fn_html_escape(v_m.intitule) ||
      '" atteste sur l''honneur d''un empêchement impérieux et sera indisponible du ' ||
      TO_CHAR(p_indispo_debut, 'DD/MM') || ' au ' || TO_CHAR(p_indispo_fin, 'DD/MM') || '.' ||
      CASE
        WHEN v_m.garantie_remplacement AND v_m.fin_le > now() + interval '1 hour'
          THEN ' Garantie remplacement : Jolene traite la demande. Vous serez informé dès sa diffusion.'
        WHEN v_est_future
          THEN ' La mission originale est clôturée. Publiez un remplacement depuis vos missions.'
        ELSE ' La mission est suspendue jusqu''à validation des heures réellement effectuées.'
      END,
    '/etablissement/missions/' || v_m.id,
    'ETABLISSEMENT'
  );

  INSERT INTO notifications (
    destinataire_id, type, titre, corps, lien, type_destinataire
  ) VALUES (
    v_soignant_id,
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

  IF v_m.garantie_remplacement AND v_m.fin_le > now() + interval '1 hour' THEN
    v_blocage_publication := public.fn_blocage_publication_etab(
      v_m.etablissement_id
    );
    IF v_blocage_publication IS NOT NULL THEN
      v_remplacement_en_revue := true;
      FOR v_admin IN
        SELECT user_id FROM public.equipe_admin
        WHERE actif AND user_id IS NOT NULL
      LOOP
        INSERT INTO public.notifications (
          destinataire_id, type_destinataire, type, titre, corps, lien,
          type_ressource, id_ressource
        ) VALUES (
          v_admin, 'ADMIN', 'SYSTEM',
          'Garantie remplacement à traiter manuellement ⚠️',
          'L''empêchement est enregistré mais la publication automatique est bloquée : '
            || COALESCE(
              v_blocage_publication->>'message',
              v_blocage_publication->>'error', 'gate établissement'
            ) || '.',
          '/admin/missions', 'mission', p_mission_id
        );
      END LOOP;
    ELSE
      v_context := 'REPLACEMENT:' || p_mission_id::text || ':'
        || v_soignant_id::text;
      BEGIN
        PERFORM set_config(
          'jolene.empechement_mission_context', v_context, true
        );
        PERFORM set_config('jolene.empechement_mission_validated', '', true);
        INSERT INTO public.missions (
          etablissement_id, intitule, description, service,
          profession_requise, specialite_medicale_requise,
          accepte_non_specialises, debut_le, fin_le, duree_heures,
          taux_horaire_base, type_contrat_recherche,
          mode_remuneration, retrocession_pct, mission_source, statut,
          mode_attribution, est_urgente, niveau_urgence,
          garantie_remplacement, remplacement_de_mission_id
        ) VALUES (
          v_m.etablissement_id,
          'REMPLACEMENT URGENT — ' || v_m.intitule,
          COALESCE(v_m.description, '')
            || E'\n\n[Mission de remplacement générée automatiquement — garantie Jolene]',
          v_m.service,
          v_m.profession_requise,
          v_m.specialite_medicale_requise,
          v_m.accepte_non_specialises,
          GREATEST(v_m.debut_le, now() + interval '15 minutes'),
          v_m.fin_le,
          round(extract(epoch FROM (
            v_m.fin_le - GREATEST(
              v_m.debut_le, now() + interval '15 minutes'
            )
          )) / 3600.0, 2),
          v_m.taux_horaire_base,
          v_m.type_contrat_recherche,
          v_m.mode_remuneration,
          v_m.retrocession_pct,
          'REMPLACEMENT',
          'OUVERTE',
          'PREMIER_ARRIVE',
          true,
          3,
          true,
          v_m.id
        ) RETURNING id INTO v_remplacement_id;
        IF NOT EXISTS (
          SELECT 1
          FROM public.missions m_replacement
          WHERE m_replacement.id = v_remplacement_id
            AND m_replacement.remplacement_de_mission_id = p_mission_id
            AND m_replacement.statut = 'OUVERTE'
            AND m_replacement.soignant_assigne_id IS NULL
            AND m_replacement.est_urgente IS TRUE
            AND m_replacement.niveau_urgence = 3
            AND m_replacement.mode_attribution = 'PREMIER_ARRIVE'
            AND m_replacement.debut_le > now()
        ) THEN
          RAISE EXCEPTION 'Phase interne REPLACEMENT incomplète.'
            USING ERRCODE = 'P0001';
        END IF;
        PERFORM set_config(
          'jolene.empechement_mission_validated',
          v_previous_empechement_validated,
          true
        );
        PERFORM set_config(
          'jolene.empechement_mission_context',
          v_previous_empechement_context,
          true
        );
      EXCEPTION WHEN OTHERS THEN
        PERFORM set_config(
          'jolene.empechement_mission_validated',
          v_previous_empechement_validated,
          true
        );
        PERFORM set_config(
          'jolene.empechement_mission_context',
          v_previous_empechement_context,
          true
        );
        RAISE;
      END;
      v_mission_diffusee_id := v_remplacement_id;

      INSERT INTO notifications (
        destinataire_id, type, titre, corps, lien, type_destinataire,
        type_ressource, id_ressource
      ) VALUES (
        v_m.etablissement_id,
        'SYSTEM',
        'Mission de remplacement urgente créée 🚨',
        'La mission de remplacement pour « '
          || fn_html_escape(v_m.intitule)
          || ' » est publiée pour le temps restant et le pool vient d''être alerté.',
        '/etablissement/missions/' || v_remplacement_id,
        'ETABLISSEMENT',
        'mission',
        v_remplacement_id
      );

      -- Le trigger urgent est l'unique fan-out externe.
      SELECT greatest(0, count(*)::integer - v_notifications_avant)
      INTO v_nb
      FROM public.notifications n
      WHERE n.type IN ('MISSION_URGENTE', 'POOL_URGENCE')
        AND n.type_ressource = 'mission'
        AND n.id_ressource = v_mission_diffusee_id;
    END IF;
  END IF;

  -- Les AFTER triggers historiques peuvent avoir touché les compteurs pendant
  -- CLOSE ; le résultat final est toujours recalé sur les sources canoniques.
  PERFORM private.fn_resynchroniser_compteurs_soignant(v_soignant_id);

  RETURN jsonb_build_object(
    'success', true,
    'pool_alerte', v_nb,
    'mission_diffusee_id', v_mission_diffusee_id,
    'mission_remplacement_id', v_remplacement_id,
    'mission_originale_cloturee', v_originale_cloturee,
    'remplacement_en_revue', v_remplacement_en_revue,
    'finance_resolution', v_finance_resolution,
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
