BEGIN;
SET LOCAL lock_timeout = '5s';
-- Les délais de facture partent de leur échéance contractuelle. Les délais du
-- paiement salarial direct, distincts, restent inchangés. Aucun email ni
-- changement de facture existante n'est déclenché par cette migration.
CREATE OR REPLACE FUNCTION "public"."fn_alerter_paiements_retard"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_mission RECORD;
    v_facture RECORD;
    v_montant_estime NUMERIC;
    v_count_emails INT := 0;
    v_count_missions_j7 INT := 0;
    v_count_missions_j21 INT := 0;
    v_count_factures_j7 INT := 0;
    v_count_factures_j21 INT := 0;
BEGIN
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

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_mission.etablissement_id, 'SYSTEM',
                'Rappel paiement soignant',
                'Rappel : paiement de ' || v_montant_estime || ' EUR a declarer pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || ').',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_1_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j7 := v_count_missions_j7 + 1;
        END IF;

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
                'Paiement de ' || v_montant_estime || ' EUR toujours non declare pour "' || COALESCE(v_mission.intitule, 'Mission') || '" (' || v_mission.soignant_prenom || ' ' || v_mission.soignant_nom || '). Sans regularisation sous 24 jours la publication de nouvelles missions sera suspendue.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT', 'mission', v_mission.id);

            UPDATE public.missions SET relance_paiement_2_le = NOW() WHERE id = v_mission.id;
            v_count_missions_j21 := v_count_missions_j21 + 1;
        END IF;
    END LOOP;

    FOR v_facture IN
        SELECT f.id, f.numero_facture, f.montant_ttc, f.date_emission,
               COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30) AS date_echeance,
               f.relance_1_le, f.relance_2_le, f.etablissement_id,
               e.nom AS etab_nom, e.email_contact AS etab_email
        FROM public.factures f
        JOIN public.etablissements e ON e.id = f.etablissement_id
        WHERE f.statut IN ('EMISE', 'EN_RETARD')
        AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30) IS NOT NULL
        AND (f.relance_1_le IS NULL OR f.relance_2_le IS NULL)
    LOOP
        IF v_facture.date_echeance + 7 <= (NOW() AT TIME ZONE 'Europe/Paris')::date
           AND v_facture.relance_1_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('RAPPEL_PAIEMENT_J7', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'date_echeance', TO_CHAR(v_facture.date_echeance, 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Rappel facture commission',
                'Rappel : facture ' || COALESCE(v_facture.numero_facture, '-') || ' de ' || v_facture.montant_ttc || ' EUR en attente de reglement.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_1_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j7 := v_count_factures_j7 + 1;
        END IF;

        IF v_facture.date_echeance + 21 <= (NOW() AT TIME ZONE 'Europe/Paris')::date
           AND v_facture.relance_2_le IS NULL THEN

            IF v_facture.etab_email IS NOT NULL THEN
                INSERT INTO public.email_queue (type, destinataire_id, destinataire_email, data)
                VALUES ('PAIEMENT_RETARD_J21', v_facture.etablissement_id, v_facture.etab_email,
                    jsonb_build_object(
                        'type_obligation', 'FACTURE_COMMISSION',
                        'numero_facture', v_facture.numero_facture,
                        'montant_ttc', ROUND(v_facture.montant_ttc, 2),
                        'date_emission', TO_CHAR(v_facture.date_emission AT TIME ZONE 'Europe/Paris', 'DD/MM/YYYY'),
                        'date_echeance', TO_CHAR(v_facture.date_echeance, 'DD/MM/YYYY'),
                        'etablissement_nom', v_facture.etab_nom,
                        'jours_retard', 21,
                        'jours_avant_blocage', 24
                    ));
                v_count_emails := v_count_emails + 1;
            END IF;

            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire, type_ressource, id_ressource)
            VALUES (v_facture.etablissement_id, 'SYSTEM',
                'Facture en retard (21 jours)',
                'Facture ' || COALESCE(v_facture.numero_facture, '-') || ' de ' || v_facture.montant_ttc || ' EUR toujours impayee. Sans regularisation sous 24 jours la publication de nouvelles missions sera suspendue.',
                '/etablissement/facturation', 'ETABLISSEMENT', 'facture', v_facture.id);

            UPDATE public.factures SET relance_2_le = NOW() WHERE id = v_facture.id;
            v_count_factures_j21 := v_count_factures_j21 + 1;
        END IF;
    END LOOP;

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
            'L etablissement "' || COALESCE(v_mission.etab_nom, 'Etablissement') || '" a declare vous avoir paye ' || v_mission.montant_net || ' EUR pour "' || COALESCE(v_mission.intitule, 'Mission') || '". Merci de confirmer ou contester.',
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
$$;

CREATE OR REPLACE FUNCTION "public"."fn_gerer_blocage_etabs"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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
          AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30) IS NOT NULL
          AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30)
          < (NOW() AT TIME ZONE 'Europe/Paris')::date - v_seuil_j;

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
          AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30)
          < (NOW() AT TIME ZONE 'Europe/Paris')::date - v_seuil_j;

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
$$;

CREATE OR REPLACE FUNCTION "public"."fn_reverifier_blocage_etab"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_etab_id uuid := mon_etablissement_id();
    v_paiements_retard_nb int;
    v_factures_retard_nb int;
    v_seuil_j integer := (public.fn_param_num('seuil_blocage_retard_j', 45))::integer;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM etablissements WHERE id = v_etab_id AND bloque_auto_le IS NOT NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'debloque', FALSE, 'message', 'Votre compte n''est pas bloqué.');
    END IF;

    -- Même seuil paramétré et même échéance que fn_gerer_blocage_etabs
    SELECT COUNT(*) INTO v_paiements_retard_nb
    FROM missions m
    WHERE m.etablissement_id = v_etab_id
      AND m.type_contrat_applique = 'SALARIE'
      AND m.statut = 'TERMINEE'
      AND m.fin_le < NOW() - make_interval(days => v_seuil_j)
      AND NOT EXISTS (
          SELECT 1 FROM paiements_soignant ps
          WHERE ps.mission_id = m.id AND ps.statut IN ('DECLARE', 'CONFIRME'));

    SELECT COUNT(*) INTO v_factures_retard_nb
    FROM factures f
    WHERE f.etablissement_id = v_etab_id
      AND f.statut IN ('EMISE', 'EN_RETARD')
      AND COALESCE(f.date_echeance, (f.date_emission AT TIME ZONE 'Europe/Paris')::date + 30)
          < (NOW() AT TIME ZONE 'Europe/Paris')::date - v_seuil_j;

    IF v_paiements_retard_nb = 0 AND v_factures_retard_nb = 0 THEN
        UPDATE etablissements SET bloque_auto_le = NULL, bloque_auto_raisons = NULL WHERE id = v_etab_id;
        INSERT INTO historique_blocages_etablissements (etablissement_id, action)
        VALUES (v_etab_id, 'DEBLOCAGE');
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_etab_id, 'SYSTEM', 'Publication de missions reactivee',
            'Vos obligations sont régularisées : votre compte est à nouveau autorisé à publier des missions.',
            '/etablissement/tableau-de-bord', 'ETABLISSEMENT');
        RETURN jsonb_build_object('success', TRUE, 'debloque', TRUE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'debloque', FALSE,
        'paiements_retard_nb', v_paiements_retard_nb,
        'factures_retard_nb', v_factures_retard_nb,
        'message', 'Des obligations restent en retard — régularisez-les puis réessayez.');
END;
$$;
-- Maintenir l'inventaire des fonctions modifiées, sans ajouter de droit client.
UPDATE private.security_definer_inventory i
SET definition_md5 = md5(p.prosrc), recense_le = now()
FROM pg_proc p
WHERE p.oid = to_regprocedure('public.' || i.signature)
  AND i.signature IN ('fn_alerter_paiements_retard()', 'fn_gerer_blocage_etabs()', 'fn_reverifier_blocage_etab()');
COMMENT ON FUNCTION public.fn_gerer_blocage_etabs() IS 'Blocage après 45 jours de retard : échéance facture commission, fin de mission pour paiement salarial direct. Réactivation après régularisation.';
COMMIT;
