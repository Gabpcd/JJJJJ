-- Lot 2 : câblage des leviers opérationnels sur fn_param_num.
-- Tous default-preserving (le défaut renvoyé = la valeur codée en dur d'origine).

-- Correction : le code bloque réellement à 45 jours (pas 15 comme seedé par erreur).
-- On aligne la valeur stockée sur la réalité du code avant de brancher.
UPDATE public.parametres_systeme
SET valeur = 45,
    description = 'Jours de retard de paiement avant blocage automatique de l''établissement (publication de missions suspendue).'
WHERE cle = 'seuil_blocage_retard_j';

UPDATE public.parametres_systeme SET cablee = true
WHERE cle IN ('delai_autovalidation_presence_h', 'seuil_blocage_retard_j', 'quota_superlikes_jour');

-- Le quota de super-likes devient configurable : la contrainte count<=5 figée
-- empêcherait de relever le quota. On garde le plancher (>=0), le plafond est
-- désormais géré côté fonction via fn_param_num.
ALTER TABLE public.super_swipes_quota DROP CONSTRAINT IF EXISTS super_swipes_quota_count_check;
ALTER TABLE public.super_swipes_quota ADD CONSTRAINT super_swipes_quota_count_check CHECK (count >= 0);

-- 1) Auto-validation des présences (72h par défaut).
CREATE OR REPLACE FUNCTION public.fn_valider_presences_72h_auto()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int;
  v_delai interval := ((public.fn_param_num('delai_autovalidation_presence_h', 72))::text || ' hours')::interval;
BEGIN
  UPDATE public.presences
  SET valide_auto_72h_le = NOW(), valide_par_etablissement = true,
      valide_le = COALESCE(valide_le, NOW()), modifie_le = NOW()
  WHERE pointage_depart_le IS NOT NULL
    AND pointage_depart_le < NOW() - v_delai
    AND COALESCE(valide_par_etablissement, false) = false
    AND motif_litige IS NULL
    AND valide_auto_72h_le IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'cron', NULL,
      jsonb_build_object('evenement', 'PRESENCES_VALIDEES_AUTO_72H', 'count', v_count, 'exec_le', NOW()));
  END IF;
  RETURN jsonb_build_object('success', true, 'count_validees', v_count);
END;
$function$;

-- 2) Blocage automatique des établissements en retard (45 jours par défaut).
CREATE OR REPLACE FUNCTION public.fn_gerer_blocage_etabs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_paiements_retard_nb INT;
    v_paiements_retard_montant NUMERIC;
    v_factures_retard_nb INT;
    v_factures_retard_montant NUMERIC;
    v_raisons JSONB;
    v_blocages INT := 0;
    v_deblocages INT := 0;
    v_seuil_j integer := (public.fn_param_num('seuil_blocage_retard_j', 45))::integer;
    v_seuil interval := (v_seuil_j::text || ' days')::interval;
BEGIN
    FOR v_etab IN
        SELECT id, nom, email_contact
        FROM public.etablissements
        WHERE bloque_auto_le IS NULL
          AND statut_verification = 'VERIFIE'
          AND supprime_le IS NULL
    LOOP
        SELECT COUNT(*), COALESCE(SUM(COALESCE(m.net_a_payer, m.total_brut, 0)), 0)
        INTO v_paiements_retard_nb, v_paiements_retard_montant
        FROM public.missions m
        WHERE m.etablissement_id = v_etab.id
          AND m.type_contrat_applique = 'SALARIE'
          AND m.statut = 'TERMINEE'
          AND m.fin_le IS NOT NULL
          AND m.fin_le < NOW() - v_seuil
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        SELECT COUNT(*), COALESCE(SUM(f.montant_ttc), 0)
        INTO v_factures_retard_nb, v_factures_retard_montant
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.date_emission IS NOT NULL
          AND f.date_emission < NOW() - v_seuil;

        IF v_paiements_retard_nb > 0 OR v_factures_retard_nb > 0 THEN
            v_raisons := jsonb_build_object(
                'paiements_retard_nb', v_paiements_retard_nb,
                'paiements_retard_montant', ROUND(v_paiements_retard_montant, 2),
                'factures_retard_nb', v_factures_retard_nb,
                'factures_retard_montant', ROUND(v_factures_retard_montant, 2),
                'seuil_jours', v_seuil_j
            );

            UPDATE public.etablissements
            SET bloque_auto_le = NOW(),
                bloque_auto_raisons = v_raisons
            WHERE id = v_etab.id;

            INSERT INTO public.historique_blocages_etablissements (etablissement_id, action, raisons)
            VALUES (v_etab.id, 'BLOCAGE', v_raisons);

            IF v_etab.email_contact IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PUBLICATION_SUSPENDUE', v_etab.id, v_etab.email_contact,
                    jsonb_build_object(
                        'etablissement_nom', v_etab.nom,
                        'obligations_en_cours',
                          CASE WHEN v_paiements_retard_nb > 0 THEN v_paiements_retard_nb || ' paiement(s) soignant(s) en retard (' || ROUND(v_paiements_retard_montant, 2) || ' EUR)' ELSE '' END
                          || CASE WHEN v_paiements_retard_nb > 0 AND v_factures_retard_nb > 0 THEN '<br/>' ELSE '' END
                          || CASE WHEN v_factures_retard_nb > 0 THEN v_factures_retard_nb || ' facture(s) commission en retard (' || ROUND(v_factures_retard_montant, 2) || ' EUR)' ELSE '' END,
                        'total_montant_du', ROUND(v_paiements_retard_montant + v_factures_retard_montant, 2),
                        'date_blocage', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY')
                    ));
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_etab.id, 'SYSTEM',
                'Publication de missions suspendue',
                'Regularisez vos obligations (paiements soignants et factures commission) pour reactiver votre compte.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT');

            v_blocages := v_blocages + 1;
        END IF;
    END LOOP;

    FOR v_etab IN
        SELECT id, nom, email_contact
        FROM public.etablissements
        WHERE bloque_auto_le IS NOT NULL
          AND supprime_le IS NULL
    LOOP
        SELECT COUNT(*) INTO v_paiements_retard_nb
        FROM public.missions m
        WHERE m.etablissement_id = v_etab.id
          AND m.type_contrat_applique = 'SALARIE'
          AND m.statut = 'TERMINEE'
          AND m.fin_le < NOW() - v_seuil
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        SELECT COUNT(*) INTO v_factures_retard_nb
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.date_emission < NOW() - v_seuil;

        IF v_paiements_retard_nb = 0 AND v_factures_retard_nb = 0 THEN
            UPDATE public.etablissements
            SET bloque_auto_le = NULL,
                bloque_auto_raisons = NULL
            WHERE id = v_etab.id;

            INSERT INTO public.historique_blocages_etablissements (etablissement_id, action)
            VALUES (v_etab.id, 'DEBLOCAGE');

            IF v_etab.email_contact IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PUBLICATION_REACTIVEE', v_etab.id, v_etab.email_contact,
                    jsonb_build_object(
                        'etablissement_nom', v_etab.nom,
                        'debloque_le', TO_CHAR(NOW() AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY HH24:MI')
                    ));
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_etab.id, 'SYSTEM',
                'Publication de missions reactivee',
                'Votre compte est a nouveau autorise a publier des missions.',
                '/etablissement/dashboard', 'ETABLISSEMENT');

            v_deblocages := v_deblocages + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'blocages', v_blocages,
        'deblocages', v_deblocages
    );
END;
$function$;

-- 3) Quota de super-likes par jour (5 par défaut).
CREATE OR REPLACE FUNCTION public.fn_enregistrer_swipe(p_mission_id uuid, p_direction text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant_id uuid := auth.uid();
  v_direction swipe_direction;
  v_quota_count integer;
  v_swipe_id uuid;
  v_quota_max integer := (public.fn_param_num('quota_superlikes_jour', 5))::integer;
BEGIN
  IF v_soignant_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_direction NOT IN ('LIKE', 'DISLIKE', 'SUPER_LIKE') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'direction_invalide');
  END IF;

  v_direction := p_direction::swipe_direction;

  IF v_direction = 'SUPER_LIKE' THEN
    -- vérifier le quota AVANT d'incrémenter
    SELECT count INTO v_quota_count
      FROM public.super_swipes_quota
     WHERE soignant_id = v_soignant_id AND date = current_date;

    IF COALESCE(v_quota_count, 0) >= v_quota_max THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'quota_super_like_atteint',
        'quota_max', v_quota_max,
        'reset_le', (current_date + interval '1 day')::date
      );
    END IF;

    INSERT INTO public.super_swipes_quota (soignant_id, date, count)
      VALUES (v_soignant_id, current_date, 1)
      ON CONFLICT (soignant_id, date)
        DO UPDATE SET count = super_swipes_quota.count + 1
      RETURNING count INTO v_quota_count;
  END IF;

  INSERT INTO public.swipes (soignant_id, mission_id, direction)
    VALUES (v_soignant_id, p_mission_id, v_direction)
    ON CONFLICT (soignant_id, mission_id) DO NOTHING
    RETURNING id INTO v_swipe_id;

  IF v_swipe_id IS NULL THEN
    IF v_direction = 'SUPER_LIKE' THEN
      UPDATE public.super_swipes_quota
         SET count = count - 1
       WHERE soignant_id = v_soignant_id AND date = current_date;
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'mission_deja_swipee');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'swipe_id', v_swipe_id,
    'direction', p_direction,
    'quota_restant', CASE WHEN v_direction = 'SUPER_LIKE' THEN v_quota_max - v_quota_count ELSE NULL END
  );
END;
$function$;
