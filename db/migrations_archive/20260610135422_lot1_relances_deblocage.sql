-- Lot 1 launch blockers (2/3) — Liquidité marketplace :
-- ① Relance automatique des missions sans candidat (J+1 puis J+3) : alerte à
--    l'établissement (MISSION_NON_POURVUE) + notification aux soignants compatibles
--    (MISSION_A_POURVOIR, profession + type contrat + rayon).
-- ② Déblocage paiement réactif : fn_gerer_blocage_etabs passe en horaire (au lieu
--    de quotidien 8h) + RPC fn_reverifier_blocage_etab pour un déblocage immédiat
--    à la demande de l'établissement après régularisation.

-- ① Nouveau type de notification
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'CANDIDATURE_ACCEPTEE','CANDIDATURE_REFUSEE','CANDIDATURE_PROPOSEE','MISSION_ACCEPTEE','MISSION_ANNULEE',
  'MISSION_TERMINEE','MISSION_URGENTE','MISSION_NON_POURVUE','MISSION_ASSIGNEE','CONTRAT_A_SIGNER','CONTRAT_SIGNE',
  'FACTURE_EMISE','FACTURE_PAYEE','DOCUMENT_EXPIRANT','RAPPEL_DOCUMENTS','DOCUMENT_VERIFIE','DOCUMENT_REJETE',
  'MESSAGE_RECU','MESSAGE_ADMIN','POINTAGE_ARRIVEE','POINTAGE_DEPART','EVALUATION_RECUE','PARRAINAGE',
  'RAPPEL_MISSION','POOL_URGENCE','POOL_URGENCE_ACCEPTATION','SYSTEM','LITIGE_OUVERT','LITIGE_REPONSE',
  'LITIGE_RESOLU','LITIGE_MEDIATION','CHORUS_DEPOSEE','CHORUS_MISE_A_DISPOSITION','CHORUS_PAIEMENT_EN_COURS',
  'CHORUS_PAIEMENT_COMPTABILISE','CHORUS_REJETEE','FAVORI_NOUVELLE_MISSION','CREDIT_PARRAINAGE',
  'PARRAINAGE_PRIME_VERSEE','LITIGE_RESOLU_AJUSTE','AVOIR_EMIS','COMMISSION_AJUSTEE','LITIGE_ESCALADE_ADMIN',
  'LITIGE_MEDIATION_PRIORITAIRE','LITIGE_RAPPEL_J1','LITIGE_RAPPEL_J3','LITIGE_RAPPEL_J5',
  'REMBOURSEMENT_MANUEL_A_FAIRE','REMBOURSEMENT_CONFIRME','MISSION_A_POURVOIR'
]));

-- ① Suivi des relances par mission
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS relances_sans_candidat int NOT NULL DEFAULT 0;
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS derniere_relance_sans_candidat_le timestamptz;

-- ① Relance des missions ouvertes sans candidat (cron quotidien)
CREATE OR REPLACE FUNCTION public.fn_relancer_missions_sans_candidat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
    v_m RECORD;
    v_missions_relancees int := 0;
    v_soignants_notifies int := 0;
    v_nb int;
BEGIN
    FOR v_m IN
        SELECT m.id, m.intitule, m.profession_requise, m.type_contrat_recherche,
               m.taux_horaire_base, m.debut_le, m.etablissement_id,
               e.nom AS etab_nom, e.adresse_ville AS etab_ville,
               e.adresse_lat AS etab_lat, e.adresse_lng AS etab_lng
        FROM missions m
        JOIN etablissements e ON e.id = m.etablissement_id
        WHERE m.statut = 'OUVERTE'
          AND m.mode_attribution = 'CANDIDATURE'
          AND m.debut_le > NOW()
          AND m.cree_le < NOW() - INTERVAL '24 hours'
          AND COALESCE(m.relances_sans_candidat, 0) < 2
          AND (m.derniere_relance_sans_candidat_le IS NULL
               OR m.derniere_relance_sans_candidat_le < NOW() - INTERVAL '48 hours')
          AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = m.id AND c.statut = 'EN_ATTENTE')
        LIMIT 200
    LOOP
        -- Alerte établissement : 0 candidat + conseils actionnables
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        VALUES (v_m.etablissement_id, 'MISSION_NON_POURVUE',
            'Aucun candidat pour "' || fn_html_escape(v_m.intitule) || '"',
            'Votre mission du ' || TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') ||
            ' n''a pas encore de candidat. Les soignants compatibles viennent d''être notifiés. Conseils : vérifiez le taux horaire par rapport au marché, ou alertez le pool d''urgence en 1 clic.',
            '/etablissement/missions/' || v_m.id, 'ETABLISSEMENT');

        -- Notification aux soignants compatibles (profession + contrat + rayon), max 25
        WITH cibles AS (
            SELECT s.id
            FROM soignants s
            WHERE s.profession = v_m.profession_requise
              AND s.supprime_le IS NULL
              AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
              AND (v_m.type_contrat_recherche = 'TOUS'
                   OR (v_m.type_contrat_recherche = 'SALARIE' AND COALESCE(s.type_exercice,'SALARIE') IN ('SALARIE','MIXTE'))
                   OR (v_m.type_contrat_recherche = 'LIBERAL' AND COALESCE(s.type_exercice,'SALARIE') IN ('LIBERAL','MIXTE')))
              AND NOT fn_est_exclu(s.id, v_m.etablissement_id)
              AND NOT EXISTS (SELECT 1 FROM candidatures c WHERE c.mission_id = v_m.id AND c.soignant_id = s.id)
              AND NOT EXISTS (
                  SELECT 1 FROM notifications n
                  WHERE n.destinataire_id = s.id AND n.type = 'MISSION_A_POURVOIR'
                    AND n.lien = '/soignant/missions/' || v_m.id)
              AND (s.adresse_lat IS NULL OR v_m.etab_lat IS NULL
                   OR fn_haversine_distance_m(s.adresse_lat, s.adresse_lng, v_m.etab_lat, v_m.etab_lng)
                      <= COALESCE(s.rayon_deplacement_km, 50) * 1000)
            LIMIT 25
        )
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        SELECT id, 'MISSION_A_POURVOIR',
            'Mission ' || v_m.profession_requise::text || ' à pourvoir près de chez vous',
            fn_html_escape(v_m.intitule) || ' — ' || COALESCE(v_m.etab_ville, '') || ', le ' ||
            TO_CHAR(v_m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' à ' ||
            COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h. L''établissement cherche encore — postulez vite.',
            '/soignant/missions/' || v_m.id, 'SOIGNANT'
        FROM cibles;
        GET DIAGNOSTICS v_nb = ROW_COUNT;
        v_soignants_notifies := v_soignants_notifies + v_nb;

        UPDATE missions
        SET relances_sans_candidat = COALESCE(relances_sans_candidat, 0) + 1,
            derniere_relance_sans_candidat_le = NOW()
        WHERE id = v_m.id;

        v_missions_relancees := v_missions_relancees + 1;
    END LOOP;

    RETURN jsonb_build_object('success', TRUE,
        'missions_relancees', v_missions_relancees,
        'soignants_notifies', v_soignants_notifies);
END;
$body$;

-- ② Déblocage immédiat à la demande de l'établissement (après régularisation)
CREATE OR REPLACE FUNCTION public.fn_reverifier_blocage_etab()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $body$
DECLARE
    v_etab_id uuid := mon_etablissement_id();
    v_paiements_retard_nb int;
    v_factures_retard_nb int;
BEGIN
    IF v_etab_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM etablissements WHERE id = v_etab_id AND bloque_auto_le IS NOT NULL) THEN
        RETURN jsonb_build_object('success', TRUE, 'debloque', FALSE, 'message', 'Votre compte n''est pas bloqué.');
    END IF;

    -- Mêmes critères que fn_gerer_blocage_etabs (seuil 45 jours)
    SELECT COUNT(*) INTO v_paiements_retard_nb
    FROM missions m
    WHERE m.etablissement_id = v_etab_id
      AND m.type_contrat_applique = 'SALARIE'
      AND m.statut = 'TERMINEE'
      AND m.fin_le < NOW() - INTERVAL '45 days'
      AND NOT EXISTS (
          SELECT 1 FROM paiements_soignant ps
          WHERE ps.mission_id = m.id AND ps.statut IN ('DECLARE', 'CONFIRME'));

    SELECT COUNT(*) INTO v_factures_retard_nb
    FROM factures f
    WHERE f.etablissement_id = v_etab_id
      AND f.statut IN ('EMISE', 'EN_RETARD')
      AND f.date_emission < NOW() - INTERVAL '45 days';

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
$body$;
GRANT EXECUTE ON FUNCTION public.fn_reverifier_blocage_etab() TO authenticated;

-- Crons : relance quotidienne 8h30 + blocage/déblocage horaire
DO $cron$
BEGIN
  PERFORM cron.schedule('relance-missions-sans-candidat', '30 8 * * *',
    'SELECT fn_relancer_missions_sans_candidat()');
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron$;
DO $cron$
BEGIN
  PERFORM cron.schedule('gerer-blocage-etabs-hourly', '45 * * * *',
    'SELECT fn_gerer_blocage_etabs()');
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron$;
