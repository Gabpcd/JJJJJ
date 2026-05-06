-- ============================================================
-- CP-C-2 C — Refonte fn_alerter_paiements_retard
-- ============================================================
-- Objectifs :
-- - Seuils J+7 / J+21 (anciens : J+30 / J+60)
-- - Retrait du blocage auto @ J+60 (déplacé vers CP-C-3 J+45)
-- - Ajout boucle factures commission (absente avant)
-- - Queuer emails via email_queue (pattern existant) en plus
--   des notifications in-app conservées
-- - Idempotence via guard relance_X_le IS NULL
-- Tickets résolus : E11 (cron J+7 implémenté), E2 complète
-- ============================================================

-- Ancienne signature retournait void → DROP obligatoire avant CREATE
DROP FUNCTION IF EXISTS public.fn_alerter_paiements_retard();

CREATE OR REPLACE FUNCTION public.fn_alerter_paiements_retard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_facture RECORD;
    v_etab_email TEXT;
    v_etab_nom TEXT;
    v_montant_estime NUMERIC;
    v_count_emails INT := 0;
    v_count_missions_j7 INT := 0;
    v_count_missions_j21 INT := 0;
    v_count_factures_j7 INT := 0;
    v_count_factures_j21 INT := 0;
BEGIN
    -- ──────────────────────────────────────────────────────
    -- Boucle A : missions SALARIE TERMINEE non déclarées
    -- ──────────────────────────────────────────────────────
    FOR v_mission IN
        SELECT m.id, m.intitule, m.fin_le, m.net_a_payer, m.total_brut,
               m.relance_paiement_1_le, m.relance_paiement_2_le,
               m.soignant_assigne_id, m.etablissement_id,
               e.nom AS etab_nom, e.email_contact AS etab_email,
               COALESCE(s.prenom, '') AS soignant_prenom,
               COALESCE(s.nom, '') AS soignant_nom
        FROM public.missions m
        JOIN public.etablissements e ON e.id = m.etablissement_id
        LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
        WHERE m.statut = 'TERMINEE'
        AND m.type_contrat_applique = 'SALARIE'
        AND m.fin_le IS NOT NULL
        AND m.soignant_assigne_id IS NOT NULL
        AND (m.relance_paiement_1_le IS NULL OR m.relance_paiement_2_le IS NULL)
        AND NOT EXISTS (
            SELECT 1 FROM public.paiements_soignant ps
            WHERE ps.mission_id = m.id AND ps.statut IN ('DECLARE', 'CONFIRME')
        )
    LOOP
        v_montant_estime := COALESCE(v_mission.net_a_payer, v_mission.total_brut, 0);

        -- Niveau J+7 : 1ère relance
        IF v_mission.fin_le + INTERVAL '7 days' <= NOW()
           AND v_mission.relance_paiement_1_le IS NULL THEN

            IF v_mission.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('RAPPEL_PAIEMENT_J7', v_mission.etablissement_id, v_mission.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'PAIEMENT_SOIGNANT',
                        'mission_id', v_mission.id,
                        'mission_intitule', v_mission.intitule,
                        'soignant_prenom', v_mission.soignant_prenom,
                        'soignant_nom', v_mission.soignant_nom,
                        'montant_estime', ROUND(v_montant_estime, 2),
                        'date_fin_mission', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_mission.etab_nom
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            -- Notification in-app étab (conservée)
            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_mission.etablissement_id, 'SYSTEM',
                'Rappel paiement soignant',
                'Rappel : paiement de ' || v_montant_estime || ' € à déclarer pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || ').',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_1_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j7 := v_count_missions_j7 + 1;
        END IF;

        -- Niveau J+21 : 2ème relance
        IF v_mission.fin_le + INTERVAL '21 days' <= NOW()
           AND v_mission.relance_paiement_2_le IS NULL THEN

            IF v_mission.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PAIEMENT_RETARD_J21', v_mission.etablissement_id, v_mission.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'PAIEMENT_SOIGNANT',
                        'mission_id', v_mission.id,
                        'mission_intitule', v_mission.intitule,
                        'soignant_prenom', v_mission.soignant_prenom,
                        'soignant_nom', v_mission.soignant_nom,
                        'montant_estime', ROUND(v_montant_estime, 2),
                        'date_fin_mission', TO_CHAR(v_mission.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_mission.etab_nom,
                        'jours_retard', 21,
                        'jours_avant_blocage', 24
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_mission.etablissement_id, 'SYSTEM',
                'Paiement en retard (21 jours)',
                'Paiement de ' || v_montant_estime || ' € toujours non déclaré pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || '). Sans régularisation sous 24 jours, la publication de nouvelles missions sera suspendue.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_2_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j21 := v_count_missions_j21 + 1;
        END IF;
    END LOOP;

    -- ──────────────────────────────────────────────────────
    -- Boucle B : factures commission non payées
    -- ──────────────────────────────────────────────────────
    FOR v_facture IN
        SELECT f.id, f.numero_facture, f.montant_ttc, f.date_emission,
               f.relance_1_le, f.relance_2_le, f.etablissement_id,
               e.nom AS etab_nom, e.email_contact AS etab_email
        FROM public.factures f
        JOIN public.etablissements e ON e.id = f.etablissement_id
        WHERE f.statut IN ('EMISE', 'EN_RETARD')
        AND f.date_emission IS NOT NULL
        AND (f.relance_1_le IS NULL OR f.relance_2_le IS NULL)
    LOOP
        -- Niveau J+7
        IF v_facture.date_emission + INTERVAL '7 days' <= NOW()
           AND v_facture.relance_1_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('RAPPEL_PAIEMENT_J7', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Rappel facture commission',
                'Rappel : facture ' || COALESCE(v_facture.numero_facture, '—') || ' de ' || v_facture.montant_ttc || ' € en attente de règlement.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_1_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j7 := v_count_factures_j7 + 1;
        END IF;

        -- Niveau J+21
        IF v_facture.date_emission + INTERVAL '21 days' <= NOW()
           AND v_facture.relance_2_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PAIEMENT_RETARD_J21', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom,
                        'jours_retard', 21,
                        'jours_avant_blocage', 24
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Facture en retard (21 jours)',
                'Facture ' || COALESCE(v_facture.numero_facture, '—') || ' de ' || v_facture.montant_ttc || ' € toujours impayée. Sans régularisation sous 24 jours, la publication de nouvelles missions sera suspendue.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_2_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j21 := v_count_factures_j21 + 1;
        END IF;
    END LOOP;

    -- ──────────────────────────────────────────────────────
    -- Boucle C (conservée) : paiements DECLARE non confirmés >15j
    -- ──────────────────────────────────────────────────────
    FOR v_mission IN
        SELECT p.id AS paiement_id, p.soignant_id, p.mission_id, p.montant_net,
               m.intitule, e.nom AS etab_nom
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.etablissements e ON e.id = p.etablissement_id
        WHERE p.statut = 'DECLARE'
        AND p.confirme_par_soignant = FALSE
        AND p.cree_le < NOW() - INTERVAL '15 days'
        AND p.relance_1_le IS NULL
    LOOP
        UPDATE public.paiements_soignant SET relance_1_le = NOW() WHERE id = v_mission.paiement_id;

        INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_mission.soignant_id, 'SYSTEM',
            'Rappel : confirmez la reception du paiement',
            'L etablissement "' || COALESCE(v_mission.etab_nom, 'Etablissement') || '" a declare vous avoir paye ' || v_mission.montant_net || ' € pour "' || COALESCE(v_mission.intitule, 'Mission') || '". Merci de confirmer ou contester.',
            '/soignant/mes-gains', 'SOIGNANT');
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'emails_queued', v_count_emails,
        'missions_j7', v_count_missions_j7,
        'missions_j21', v_count_missions_j21,
        'factures_j7', v_count_factures_j7,
        'factures_j21', v_count_factures_j21
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_alerter_paiements_retard() IS
  'CP-C-2 C refonte seuils J+7/J+21 + factures commission + email_queue. Cron jobid 11 @ 0 8 * * *. Blocage J+45 delegue a CP-C-3.';
