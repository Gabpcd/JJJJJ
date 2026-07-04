-- ============================================================
-- CP-C-3 C — fn_gerer_blocage_etabs + schedule cron
-- ============================================================
-- Nouvelle fonction dédiée appelée par cron jobid 11 après
-- fn_alerter_paiements_retard pour :
-- - BLOCAGE : étabs non bloqués avec retard paiement >45j OR
--   facture commission >45j
-- - DÉBLOCAGE : étabs bloqués qui ont tout régularisé
-- Tickets : E1 (logique blocage cohérente) + E7 (unfreeze auto)
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_gerer_blocage_etabs()
RETURNS JSONB
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
BEGIN
    -- ──────────────────────────────────────────
    -- BOUCLE A : BLOCAGES (étabs non bloqués avec retards >45j)
    -- ──────────────────────────────────────────
    FOR v_etab IN
        SELECT id, nom, email_contact
        FROM public.etablissements
        WHERE bloque_auto_le IS NULL
          AND statut_verification = 'VERIFIE'
          AND supprime_le IS NULL
    LOOP
        -- Paiements soignants en retard >45j
        SELECT COUNT(*), COALESCE(SUM(COALESCE(m.net_a_payer, m.total_brut, 0)), 0)
        INTO v_paiements_retard_nb, v_paiements_retard_montant
        FROM public.missions m
        WHERE m.etablissement_id = v_etab.id
          AND m.type_contrat_applique = 'SALARIE'
          AND m.statut = 'TERMINEE'
          AND m.fin_le IS NOT NULL
          AND m.fin_le < NOW() - INTERVAL '45 days'
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        -- Factures commission en retard >45j
        SELECT COUNT(*), COALESCE(SUM(f.montant_ttc), 0)
        INTO v_factures_retard_nb, v_factures_retard_montant
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.date_emission IS NOT NULL
          AND f.date_emission < NOW() - INTERVAL '45 days';

        -- Déclencher blocage si au moins un critère
        IF v_paiements_retard_nb > 0 OR v_factures_retard_nb > 0 THEN
            v_raisons := jsonb_build_object(
                'paiements_retard_nb', v_paiements_retard_nb,
                'paiements_retard_montant', ROUND(v_paiements_retard_montant, 2),
                'factures_retard_nb', v_factures_retard_nb,
                'factures_retard_montant', ROUND(v_factures_retard_montant, 2),
                'seuil_jours', 45
            );

            UPDATE public.etablissements
            SET bloque_auto_le = NOW(),
                bloque_auto_raisons = v_raisons
            WHERE id = v_etab.id;

            INSERT INTO public.historique_blocages_etablissements (etablissement_id, action, raisons)
            VALUES (v_etab.id, 'BLOCAGE', v_raisons);

            -- Queue email PUBLICATION_SUSPENDUE
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

            -- Notification in-app
            INSERT INTO public.notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (v_etab.id, 'SYSTEM',
                'Publication de missions suspendue',
                'Regularisez vos obligations (paiements soignants et factures commission) pour reactiver votre compte.',
                '/etablissement/obligations-financieres', 'ETABLISSEMENT');

            v_blocages := v_blocages + 1;
        END IF;
    END LOOP;

    -- ──────────────────────────────────────────
    -- BOUCLE B : DÉBLOCAGES (étabs bloqués régularisés)
    -- ──────────────────────────────────────────
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
          AND m.fin_le < NOW() - INTERVAL '45 days'
          AND NOT EXISTS (
              SELECT 1 FROM public.paiements_soignant ps
              WHERE ps.mission_id = m.id
              AND ps.statut IN ('DECLARE', 'CONFIRME')
          );

        SELECT COUNT(*) INTO v_factures_retard_nb
        FROM public.factures f
        WHERE f.etablissement_id = v_etab.id
          AND f.statut IN ('EMISE', 'EN_RETARD')
          AND f.date_emission < NOW() - INTERVAL '45 days';

        -- Débloquer si plus rien en retard
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
                'Votre compte est a nouveau autorise a publier des missions. Maintenez vos paiements et factures a jour pour eviter une nouvelle suspension.',
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

COMMENT ON FUNCTION public.fn_gerer_blocage_etabs() IS
  'CP-C-3 : blocage auto J+45 (paiement soignant ou facture commission) et deblocage auto post-regularisation. Appelee par cron jobid 11 apres fn_alerter_paiements_retard.';
