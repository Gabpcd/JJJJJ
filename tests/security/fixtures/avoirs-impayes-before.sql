-- Corps LIVE avant correction, capturés le 17/10/2026, pour reproduire le défaut.
-- Fixture du seul banc avoirs-impayes-isolated.test.sql ; aucune donnée cliente.
DO $fixture_guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'avoirs_impayes'
  THEN RAISE EXCEPTION 'AVOIRS_FIXTURE_REQUIRES_ISOLATED_DATABASE'; END IF;
END $fixture_guard$;

CREATE OR REPLACE FUNCTION public.dec_bloquer_si_facture_impayee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_nb_impayees integer;
BEGIN
  IF TG_OP = 'INSERT' THEN
    SELECT count(*) INTO v_nb_impayees
    FROM public.factures
    WHERE etablissement_id = NEW.etablissement_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND date_echeance < current_date;

    IF v_nb_impayees > 0 AND NOT public.est_admin() THEN
      RAISE EXCEPTION
        'Vous avez % facture(s) échue(s) impayée(s) : les nouvelles publications sont suspendues (vos missions en cours ne sont pas affectées). Régularisez depuis Facturation pour republier.',
        v_nb_impayees;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.dec_bloquer_si_facture_impayee() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.dec_bloquer_si_facture_impayee() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_kpi()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
  debut_semaine timestamptz := date_trunc('week', now());
  debut_mois timestamptz := date_trunc('month', now());
  fin_mois timestamptz := date_trunc('month', now()) + interval '1 month';
BEGIN
  IF NOT public.est_admin() THEN
    RETURN '{"error":"Accès réservé aux administrateurs"}'::jsonb;
  END IF;

  WITH missions_reelles AS (
    SELECT m.*
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE e.est_compte_test IS FALSE
       AND COALESCE(s.est_compte_test, false) IS FALSE
  ),
  factures_reelles AS (
    SELECT f.*
      FROM public.factures f
      JOIN public.etablissements e ON e.id = f.etablissement_id
     WHERE e.est_compte_test IS FALSE
  )
  SELECT jsonb_build_object(
    'soignants_total', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
    ),
    'etablissements_total', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
    ),
    'missions_terminees_total', (
      SELECT count(*) FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'missions_terminees_mois', (
      SELECT count(*) FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'missions_ouvertes', (
      SELECT count(*) FROM missions_reelles
       WHERE statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS')
    ),
    'soignants_semaine', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= debut_semaine
    ),
    'etablissements_semaine', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= debut_semaine
    ),
    'litiges_ouverts', (
      SELECT count(*)
        FROM public.litiges l
        JOIN missions_reelles m ON m.id = l.mission_id
       WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE')
    ),
    'ca_commissions_ht_mois', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'ca_potentiel_mois', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles
       WHERE fin_le >= debut_mois AND fin_le < fin_mois
         AND statut IN ('TERMINEE', 'ASSIGNEE', 'EN_COURS')
    ),
    'ca_encaisse_total', (
      SELECT COALESCE(sum(montant_ht), 0)
        FROM factures_reelles WHERE statut = 'PAYEE'
    ),
    'ca_potentiel_total', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'gmv_mois', (
      SELECT COALESCE(sum(total_brut), 0)
        FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'gmv_total', (
      SELECT COALESCE(sum(total_brut), 0)
        FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'taux_acceptation_mois', (
      SELECT CASE
        WHEN count(*) FILTER (WHERE cree_le >= debut_mois) = 0 THEN 0
        ELSE round(
          100.0 * count(*) FILTER (
            WHERE statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
              AND cree_le >= debut_mois
          ) / NULLIF(count(*) FILTER (WHERE cree_le >= debut_mois), 0)
        )
      END
      FROM missions_reelles
    ),
    'factures_impayees', (
      SELECT count(*) FROM factures_reelles WHERE statut IN ('EMISE', 'EN_RETARD')
    ),
    'docs_en_attente', (
      SELECT count(*)
        FROM public.documents_soignants d
        JOIN public.soignants s ON s.id = d.soignant_id
       WHERE d.statut_verification = 'EN_ATTENTE'
         AND s.est_compte_test IS FALSE
    ),
    'etab_en_attente', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL
         AND est_compte_test IS FALSE
         AND COALESCE(rattachement_verifie, false) = false
         AND COALESCE(statut_verification, '') <> 'REJETE'
    )
  ) INTO result;

  RETURN result;
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_admin_kpi() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_kpi() TO authenticated, service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) VALUES ('fn_admin_kpi()', 'ADMIN_EST_ADMIN_VALIDE', '82b915c73d755d4102911edcd1ec19e6', 'RPC back-office: garde admin interne observée (est_admin().', now());

CREATE OR REPLACE FUNCTION public.fn_alerter_paiements_retard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public.fn_alerter_paiements_retard() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_alerter_paiements_retard() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_blocage_publication_etab(p_etab_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v record;
BEGIN
  IF public.est_admin() THEN RETURN NULL; END IF;
  IF p_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;

  SELECT peut_publier_missions, statut_verification, contrat_service_signe,
         bloque_auto_le, bloque_auto_raisons, finess_verifie,
         siret_verifie, representant_identite_verifiee, rattachement_verifie
    INTO v
  FROM public.etablissements
  WHERE id = p_etab_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;

  IF v.peut_publier_missions IS NOT TRUE OR v.statut_verification <> 'VERIFIE' THEN
    RETURN jsonb_build_object(
      'error', 'ETABLISSEMENT_NON_VERIFIE',
      'message', 'Votre établissement doit être vérifié avant de publier des missions.'
    );
  END IF;
  IF v.siret_verifie IS NOT TRUE OR v.finess_verifie IS NOT TRUE
     OR v.representant_identite_verifiee IS NOT TRUE
     OR v.rattachement_verifie IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'VERIFICATION_INCOMPLETE',
      'message', 'Les contrôles SIRET, FINESS, identité et habilitation du représentant doivent être validés.',
      'siret_verifie', COALESCE(v.siret_verifie, false),
      'finess_verifie', COALESCE(v.finess_verifie, false),
      'identite_verifiee', COALESCE(v.representant_identite_verifiee, false),
      'rattachement_verifie', COALESCE(v.rattachement_verifie, false)
    );
  END IF;
  IF v.contrat_service_signe IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'error', 'CONTRAT_SERVICE_REQUIS',
      'message', 'Le contrat de service Jolene doit être signé avant de publier des missions.'
    );
  END IF;
  IF v.bloque_auto_le IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', 'PUBLICATION_SUSPENDUE',
      'message', 'Publication suspendue en raison d obligations de paiement à régulariser.',
      'bloque_auto_le', v.bloque_auto_le,
      'raisons', v.bloque_auto_raisons
    );
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.factures
    WHERE etablissement_id = p_etab_id
      AND statut IN ('EMISE', 'EN_RETARD')
      AND date_echeance < current_date
  ) THEN
    RETURN jsonb_build_object('error', 'FACTURES_IMPAYEES', 'message', 'Vous avez des factures impayées à régulariser.');
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_blocage_publication_etab(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_blocage_publication_etab(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_email_factures_impayees()
 RETURNS TABLE(email text, nom_etablissement text, numero_facture text, montant_ttc text, jours_depuis integer, etablissement_id uuid)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    SELECT e.email_contact, e.nom, f.numero_facture,
        ROUND(f.montant_ttc, 2)::TEXT,
        (CURRENT_DATE - f.date_echeance)::INTEGER, e.id
    FROM factures f
    JOIN etablissements e ON e.id = f.etablissement_id
    WHERE f.statut IN ('EMISE', 'EN_RETARD')
      AND f.date_echeance < CURRENT_DATE
      AND e.email_contact IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM emails_envoyes ee
          WHERE ee.type = 'RAPPEL_FACTURE'
            AND ee.sujet LIKE '%' || f.numero_facture || '%'
            AND ee.cree_le > NOW() - INTERVAL '7 days'
      );
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_email_factures_impayees() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_email_factures_impayees() TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.fn_gerer_blocage_etabs() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_gerer_blocage_etabs() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_obligations_financieres_internal_20260801()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_total_soignants_du numeric := 0;
  v_total_commissions_du numeric := 0;
  v_lignes jsonb := '[]'::jsonb;
BEGIN
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Etablissement introuvable');
  END IF;

  WITH obligations AS (
    SELECT
      ('facture:' || fh.id::text) AS payment_key,
      m.id::text AS mission_id,
      fh.id::text AS facture_honoraires_id,
      m.intitule,
      m.debut_le,
      m.fin_le,
      fh.periode_debut,
      fh.periode_fin,
      fh.est_facture_finale_mission,
      fh.montant_ttc AS total_brut,
      fh.montant_ttc AS net_a_payer,
      COALESCE(fc.montant_ttc, 0) AS montant_commission_ttc,
      m.soignant_assigne_id::text AS soignant_id,
      GREATEST(0, EXTRACT(EPOCH FROM (
        LEAST(m.fin_le, (fh.periode_fin + 1)::timestamptz)
        - GREATEST(m.debut_le, fh.periode_debut::timestamptz)
      )) / 3600) AS heures,
      (CURRENT_DATE - fh.periode_fin)::integer AS jours_depuis_fin,
      COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
      s.profession::text AS soignant_profession,
      s.type_exercice AS soignant_type_exercice,
      m.type_contrat_applique::text AS type_contrat_applique,
      m.type_paiement_soignant AS type_paiement_soignant,
      COALESCE(m.mode_paiement_soignant, 'STRIPE_CONNECT') AS mode_paiement_soignant,
      (s.stripe_account_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.stripe_connect_onboarding sco
        WHERE sco.soignant_id = s.id
          AND sco.charges_enabled = true
          AND sco.payouts_enabled = true
      )) AS soignant_stripe_connect,
      EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
      ) AS a_paiement_conteste,
      (
        SELECT p.id::text FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
        ORDER BY p.cree_le DESC LIMIT 1
      ) AS paiement_conteste_id,
      fh.periode_fin::timestamptz AS ordre_fin
    FROM public.factures_honoraires fh
    JOIN public.missions m ON m.id = fh.mission_id
    JOIN public.soignants s ON s.id = fh.soignant_id
    LEFT JOIN public.factures fc
      ON fc.facture_honoraire_id = fh.id
     AND fc.type_document = 'FACTURE'
     AND fc.statut NOT IN ('ANNULEE', 'REMPLACEE', 'ERREUR_GENERATION')
    WHERE fh.etablissement_id = v_etab_id
      AND fh.type_document = 'FACTURE'
      AND fh.statut IN ('EMISE', 'EN_RETARD')
      AND m.type_contrat_applique = 'LIBERAL'
      AND m.statut IN ('EN_COURS', 'TERMINEE')
      AND (m.statut = 'TERMINEE' OR (NOT fh.est_facture_finale_mission AND fh.periode_fin < CURRENT_DATE))
      AND NOT EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.facture_honoraire_id = fh.id
          AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.stripe_transfers st
        WHERE st.facture_honoraire_id = fh.id
          AND st.statut IN ('TRANSFERE', 'CHARGE_REUSSI', 'PAYE')
      )

    UNION ALL

    SELECT
      ('mission:' || m.id::text), m.id::text, NULL::text, m.intitule,
      m.debut_le, m.fin_le, m.debut_le::date, m.fin_le::date, true,
      m.total_brut, m.net_a_payer, m.montant_commission_ttc,
      m.soignant_assigne_id::text,
      EXTRACT(EPOCH FROM (m.fin_le - m.debut_le)) / 3600,
      EXTRACT(DAY FROM now() - m.fin_le)::integer,
      COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, ''),
      s.profession::text, s.type_exercice,
      m.type_contrat_applique::text, m.type_paiement_soignant,
      m.mode_paiement_soignant, false,
      EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
      ),
      (
        SELECT p.id::text FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut = 'CONTESTE'
        ORDER BY p.cree_le DESC LIMIT 1
      ),
      m.fin_le
    FROM public.missions m
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    WHERE m.etablissement_id = v_etab_id
      AND m.statut = 'TERMINEE'
      AND m.type_contrat_applique = 'SALARIE'
      AND NOT EXISTS (
        SELECT 1 FROM public.paiements_soignant p
        WHERE p.mission_id = m.id AND p.statut IN ('DECLARE', 'CONFIRME', 'RESOLU')
      )
  )
  SELECT
    COALESCE(sum(o.net_a_payer), 0),
    COALESCE(jsonb_agg(to_jsonb(o) - 'ordre_fin' ORDER BY o.ordre_fin), '[]'::jsonb)
  INTO v_total_soignants_du, v_lignes
  FROM obligations o;

  SELECT COALESCE(sum(f.montant_ttc), 0)
  INTO v_total_commissions_du
  FROM public.factures f
  WHERE f.etablissement_id = v_etab_id
    AND f.statut IN ('EMISE', 'EN_RETARD');

  RETURN jsonb_build_object(
    'total_du', v_total_soignants_du + v_total_commissions_du,
    'total_soignants_du', v_total_soignants_du,
    'total_commissions_du', v_total_commissions_du,
    'nb_missions_non_payees', jsonb_array_length(v_lignes),
    'nb_paiements_en_attente', (
      SELECT count(*) FROM public.paiements_soignant
      WHERE etablissement_id = v_etab_id AND statut = 'DECLARE'
    ),
    'nb_factures_impayees', (
      SELECT count(*) FROM public.factures
      WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
    ),
    'nb_factures_commission_historique', (
      SELECT count(*) FROM public.factures
      WHERE etablissement_id = v_etab_id AND statut IN ('PAYEE', 'ANNULEE')
    ),
    'missions_non_payees', v_lignes,
    'paiements_soignants_en_attente', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT p.id::text AS paiement_id, p.mission_id::text, p.montant_net,
          p.methode, p.reference_virement, p.date_paiement, p.statut,
          m.intitule AS mission_intitule,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          s.profession::text AS soignant_profession,
          COALESCE(p.facture_honoraire_id::text, (
            SELECT fh.id::text FROM public.factures_honoraires fh
            WHERE fh.mission_id = m.id ORDER BY fh.date_emission DESC LIMIT 1
          )) AS facture_honoraires_id
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.soignants s ON s.id = p.soignant_id
        WHERE p.etablissement_id = v_etab_id AND p.statut = 'DECLARE'
        ORDER BY p.date_paiement DESC
      ) x
    ), '[]'::jsonb),
    'paiements_soignants_confirmes', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT p.id::text AS paiement_id, p.mission_id::text, p.montant_net,
          p.methode, p.reference_virement, p.date_paiement,
          p.confirme_par_soignant_le, m.intitule AS mission_intitule,
          COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
          p.facture_honoraire_id::text AS facture_honoraires_id
        FROM public.paiements_soignant p
        JOIN public.missions m ON m.id = p.mission_id
        JOIN public.soignants s ON s.id = p.soignant_id
        WHERE p.etablissement_id = v_etab_id AND p.statut = 'CONFIRME'
        ORDER BY p.confirme_par_soignant_le DESC LIMIT 10
      ) x
    ), '[]'::jsonb),
    'factures_impayees', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT f.id::text AS facture_id, f.numero_facture, f.montant_ht,
          f.montant_tva, f.montant_ttc, f.nombre_missions, f.date_echeance,
          f.statut, f.stripe_hosted_url, f.est_secteur_public,
          f.chorus_pro_statut, f.chorus_pro_numero_flux
        FROM public.factures f
        WHERE f.etablissement_id = v_etab_id
          AND f.statut IN ('EMISE', 'EN_RETARD', 'VIREMENT_DECLARE')
        ORDER BY f.date_echeance
      ) x
    ), '[]'::jsonb),
    'factures_commission_historique', COALESCE((
      SELECT jsonb_agg(row_to_json(x)) FROM (
        SELECT f.id::text AS facture_id, f.numero_facture, f.statut,
          f.montant_ttc, f.nombre_missions, f.date_emission, f.date_paiement,
          f.mode_paiement, f.virement_reference, f.stripe_payment_intent_id,
          f.mission_id::text AS mission_id, f.facture_honoraire_id::text,
          f.est_secteur_public, f.chorus_pro_statut
        FROM public.factures f
        WHERE f.etablissement_id = v_etab_id AND f.statut IN ('PAYEE', 'ANNULEE')
        ORDER BY f.date_paiement DESC NULLS LAST, f.date_emission DESC LIMIT 10
      ) x
    ), '[]'::jsonb),
    'missions_non_facturees', '[]'::jsonb
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_obligations_financieres_internal_20260801() FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_reverifier_blocage_etab()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public.fn_reverifier_blocage_etab() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_reverifier_blocage_etab() TO authenticated, service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) VALUES ('fn_reverifier_blocage_etab()', 'RPC_UTILISATEUR_AUTH_INTERNE', 'f1895c3507bf579b303d0bda285ba0b1', 'RPC authenticated: identité/tenancy interne observée (mon_etablissement_id).', now());

CREATE OR REPLACE FUNCTION public.fn_stats_dashboard_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_stats JSONB;
    v_pool_urgence_count INT;
    v_messages_non_lus INT;
    v_missions_a_payer INT;
    v_debut_mois TIMESTAMPTZ;
    v_terminees_ce_mois INT;
    v_soignants_ce_mois INT;
    v_commissions_impayees NUMERIC;
    v_nb_factures_impayees INT;
    v_litiges_ouverts INT;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
    
    v_debut_mois := DATE_TRUNC('month', NOW());
    
    SELECT COUNT(*) INTO v_pool_urgence_count FROM fn_pool_urgence_etablissement(v_etab_id);
    
    SELECT COUNT(*) INTO v_messages_non_lus
    FROM messages_chat mc JOIN conversations c ON c.id = mc.conversation_id
    WHERE (c.participant_1_id = v_etab_id OR c.participant_2_id = v_etab_id)
    AND mc.auteur_id != v_etab_id AND mc.lu = FALSE;
    
    SELECT COUNT(*) INTO v_missions_a_payer
    FROM missions m WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME'));
    
    SELECT COUNT(*) INTO v_terminees_ce_mois
    FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE' AND fin_le >= v_debut_mois;
    
    SELECT COUNT(DISTINCT soignant_assigne_id) INTO v_soignants_ce_mois
    FROM missions WHERE etablissement_id = v_etab_id AND soignant_assigne_id IS NOT NULL
    AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE') AND debut_le >= v_debut_mois;
    
    SELECT COALESCE(SUM(montant_ttc), 0), COUNT(*)
    INTO v_commissions_impayees, v_nb_factures_impayees
    FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD');
    
    -- Litiges ouverts
    SELECT COUNT(*) INTO v_litiges_ouverts
    FROM litiges WHERE etablissement_id = v_etab_id 
    AND statut IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE');
    
    SELECT jsonb_build_object(
        'a_deja_publie', (SELECT COUNT(*) > 0 FROM missions WHERE etablissement_id = v_etab_id),
        'total_missions', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id),
        'missions_ouvertes', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'OUVERTE'),
        'missions_assignees', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'ASSIGNEE'),
        'missions_en_cours', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'EN_COURS'),
        'missions_terminees', (SELECT COUNT(*) FROM missions WHERE etablissement_id = v_etab_id AND statut = 'TERMINEE'),
        'missions_terminees_ce_mois', v_terminees_ce_mois,
        'soignants_ce_mois', v_soignants_ce_mois,
        'commissions_cumulees', COALESCE((SELECT SUM(montant_ht) FROM factures WHERE etablissement_id = v_etab_id AND statut != 'ANNULEE'), 0),
        'commissions_impayees', v_commissions_impayees,
        'nb_factures_impayees', v_nb_factures_impayees,
        'pool_urgence_count', v_pool_urgence_count,
        'messages_non_lus', v_messages_non_lus,
        'missions_a_payer', v_missions_a_payer,
        'litiges_ouverts', v_litiges_ouverts,
        'candidatures_en_attente', (
            SELECT COUNT(*) FROM candidatures c JOIN missions m ON m.id = c.mission_id
            WHERE m.etablissement_id = v_etab_id AND c.statut = 'EN_ATTENTE'
        ),
        'candidatures_recentes', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT c.id::TEXT AS candidature_id, m.intitule AS mission_intitule,
                    m.id::TEXT AS mission_id,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession,
                    s.score_fiabilite AS soignant_score, c.cree_le
                FROM candidatures c JOIN missions m ON m.id = c.mission_id JOIN soignants s ON s.id = c.soignant_id
                WHERE m.etablissement_id = v_etab_id AND c.statut = 'EN_ATTENTE'
                ORDER BY c.cree_le DESC LIMIT 5
            ) x
        ), '[]'::JSONB),
        'missions_assignees_detail', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession, s.score_fiabilite AS soignant_score
                FROM missions m JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'ASSIGNEE'
                ORDER BY m.debut_le ASC
            ) x
        ), '[]'::JSONB)
    ) INTO v_stats;
    
    RETURN v_stats;
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_stats_dashboard_etablissement() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_stats_dashboard_etablissement() TO authenticated, service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) VALUES ('fn_stats_dashboard_etablissement()', 'RPC_UTILISATEUR_AUTH_INTERNE', '7433f65f44fcbcad46551879a91251d3', 'RPC authenticated: identité/tenancy interne observée (mon_etablissement_id).', now());

CREATE OR REPLACE FUNCTION public.fn_supprimer_mon_compte_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_etab_id uuid;
  v_missions_actives int;
  v_factures_impayees int;
  v_hash text;
  v_interne text := COALESCE(current_setting('app.internal_operation',true),'');
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT id INTO v_etab_id FROM etablissements WHERE id = v_uid FOR UPDATE;
  IF v_etab_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Aucun établissement lié à ce compte');
  END IF;

  IF private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN
    RETURN jsonb_build_object('success',true,'deja_anonymise',true);
  END IF;

  -- Garde-fou : missions actives
  SELECT count(*) INTO v_missions_actives FROM missions
   WHERE etablissement_id = v_etab_id
     AND statut IN ('OUVERTE','ASSIGNEE','EN_COURS','LITIGE')
     AND fin_le > NOW();
  IF v_missions_actives > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('Vous avez %s mission(s) ouverte(s) ou en cours.', v_missions_actives));
  END IF;

  -- Garde-fou : factures impayées (la suppression n'efface pas une dette)
  SELECT count(*) INTO v_factures_impayees FROM factures
   WHERE etablissement_id = v_etab_id AND statut IN ('EN_ATTENTE','EN_RETARD');
  IF v_factures_impayees > 0 THEN
    RETURN jsonb_build_object('success', false, 'error',
      format('%s facture(s) impayée(s). Réglez-les avant suppression.', v_factures_impayees));
  END IF;

  -- Bypass trigger fn_protect_etablissement_commercial pour anonymisation
  PERFORM set_config('app.internal_operation', 'true', true);
  v_hash := encode(extensions.digest(v_etab_id::text || NOW()::text, 'sha256'), 'hex');

  BEGIN
  INSERT INTO private.suppression_etablissement_context(backend_pid,transaction_id,utilisateur_id)
  VALUES(pg_backend_pid(),txid_current(),v_uid);
  -- Anonymisation établissement
  UPDATE etablissements SET
    nom = 'Établissement supprimé',
    siret = '99' || LPAD(LEFT(REGEXP_REPLACE(v_hash, '[^0-9]', '', 'g'), 12), 12, '0'),
    finess = NULL,
    email_contact = v_hash || '@supprime.jolene.app',
    telephone_contact = NULL,
    adresse_rue = '[SUPPRIMÉ]',
    adresse_ville = '[SUPPRIMÉ]',
    adresse_code_postal = '00000',
    adresse_departement = NULL, adresse_lat = NULL, adresse_lng = NULL,
    description = NULL, logo_url = NULL, horaires_ouverture = NULL,
    contrat_url = NULL,
    siret_raison_sociale = NULL, siret_categorie_juridique = NULL,
    siret_code_naf = NULL, siret_est_actif = false,
    chorus_pro_actif = false, chorus_pro_identifiant = NULL,
    sms_actif = false, sms_consent_le = NULL,
    peut_publier_missions = false,
    bloque_auto_le = NOW(),
    bloque_auto_raisons = jsonb_build_array('COMPTE_SUPPRIME_RGPD'),
    supprime_le = NOW(),
    stripe_sepa_payment_method_id = NULL
  WHERE id = v_etab_id;

  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.internal_operation',v_interne,true);
    RAISE;
  END;
  DELETE FROM private.suppression_etablissement_context
  WHERE backend_pid=pg_backend_pid() AND transaction_id=txid_current() AND utilisateur_id=v_uid;
  PERFORM set_config('app.internal_operation',v_interne,true);

  -- Tables liées
  DELETE FROM admins_groupe_sante WHERE utilisateur_id = v_uid;
  DELETE FROM tokens_push WHERE utilisateur_id = v_uid;
  DELETE FROM notifications WHERE destinataire_id = v_uid;

  UPDATE messages_chat SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_mission SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;
  UPDATE messages_litige SET contenu = '[Message supprimé]' WHERE auteur_id = v_uid;

  UPDATE evaluations SET commentaire = NULL
   WHERE evaluateur_id = v_uid OR evalue_id = v_uid;

  DELETE FROM exclusions WHERE exclu_par = v_uid OR exclu_id = v_uid;

  UPDATE partages_rib SET actif = false, expire_le = NOW()
   WHERE etablissement_id = v_etab_id;

  -- Contrats : on conserve (preuves légales) mais anonymise IP/UA
  UPDATE contrats_mission SET
    signature_ip_etablissement = NULL,
    signature_navigateur_etablissement = NULL,
    signature_image_etablissement = NULL
   WHERE etablissement_id = v_etab_id;

  DELETE FROM email_queue WHERE destinataire_id = v_uid;
  UPDATE sms_envoyes SET telephone = 'SUPPRIME', destinataire_id = NULL
   WHERE destinataire_id = v_uid;

  DELETE FROM calendar_events_sync WHERE connection_id IN
    (SELECT id FROM calendar_connections WHERE utilisateur_id = v_uid);
  DELETE FROM calendar_connections WHERE utilisateur_id = v_uid;
  DELETE FROM api_keys WHERE etablissement_id = v_etab_id;

  -- Audit (type_acteur ADMIN_ETABLISSEMENT, action RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT)
  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (v_uid, 'ADMIN_ETABLISSEMENT', 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT', 'etablissement', v_etab_id,
    jsonb_build_object('anonymise', true));

  INSERT INTO private.suppressions_compte_confirmees(utilisateur_id,type_profil,anonymise_le,email_anonymise)
  SELECT id,'ETABLISSEMENT',supprime_le,email_contact FROM public.etablissements WHERE id=v_etab_id
  ON CONFLICT(utilisateur_id,type_profil) DO UPDATE SET anonymise_le=excluded.anonymise_le,email_anonymise=excluded.email_anonymise;
  IF NOT private.fn_anonymisation_compte_confirmee(v_uid,'ETABLISSEMENT') THEN RAISE EXCEPTION 'Anonymisation établissement non confirmée'; END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Établissement anonymisé. Factures conservées 10 ans (LPF L102 B).',
    'etablissement_id', v_etab_id
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_supprimer_mon_compte_etablissement() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_supprimer_mon_compte_etablissement() TO authenticated, service_role;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) VALUES ('fn_supprimer_mon_compte_etablissement()', 'RPC_UTILISATEUR_AUTH_INTERNE', '8d1a6220cdc135d36d2d472fcde230ee', 'UID égal au propriétaire historique ciblé, pas un tenant arbitraire ; verrou, missions et impayés contrôlés ; preuve privée. Un simple membre ne supprime pas son employeur. Source : 20260925150546_suppression_compte_preuve_privee.sql', now());

CREATE OR REPLACE FUNCTION public.fn_admin_suspendre_utilisateur(p_table text, p_id uuid, p_suspendre boolean DEFAULT true, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
DECLARE
  v_nom text;
  v_motif text := NULLIF(btrim(COALESCE(p_motif, '')), '');
  v_maintenant timestamptz := transaction_timestamp();
  v_membres integer := 0;
  v_auth_trouve boolean := false;
  v_auth_state_existe boolean := false;
  v_banned_until_courant timestamptz;
  v_banned_until_pose timestamptz;
  v_pose_precedente timestamptz;
  v_peut_publier_avant boolean := false;
  v_supprime_le timestamptz;
  v_est_suppression_rgpd boolean := false;
  v_provenance_suspension boolean := false;
BEGIN
  IF NOT public.est_admin_valide() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin AAL2 uniquement');
  END IF;
  IF p_table NOT IN ('soignants', 'etablissements') THEN
    RETURN jsonb_build_object('error', 'Table invalide');
  END IF;
  IF p_id IS NULL OR p_suspendre IS NULL THEN
    RETURN jsonb_build_object('error', 'Paramètres de suspension invalides');
  END IF;
  IF p_suspendre AND (v_motif IS NULL OR char_length(v_motif) < 3) THEN
    RETURN jsonb_build_object('error', 'Motif obligatoire (3 caractères minimum)');
  END IF;
  IF v_motif IS NOT NULL AND char_length(v_motif) > 1000 THEN
    RETURN jsonb_build_object('error', 'Motif trop long (1000 caractères maximum)');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_table || ':' || p_id::text, 0));

  IF p_table = 'soignants' THEN
    SELECT
      COALESCE(s.prenom || ' ' || s.nom, 'Inconnu'),
      s.supprime_le,
      (
        lower(COALESCE(s.email, '')) LIKE '%@supprime.jolene.app'
        OR EXISTS (
          SELECT 1 FROM public.journaux_audit j
          WHERE j.id_ressource = s.id
            AND j.action = 'RGPD_SUPPRESSION_COMPTE'
        )
      )
    INTO v_nom, v_supprime_le, v_est_suppression_rgpd
    FROM public.soignants s
    WHERE s.id = p_id
    FOR UPDATE;
  ELSE
    SELECT
      COALESCE(e.nom, 'Inconnu'),
      e.peut_publier_missions,
      e.supprime_le,
      (
        lower(COALESCE(e.email_contact, '')) LIKE '%@supprime.jolene.app'
        OR COALESCE(e.bloque_auto_raisons, '[]'::jsonb) ? 'COMPTE_SUPPRIME_RGPD'
        OR EXISTS (
          SELECT 1 FROM public.journaux_audit j
          WHERE j.id_ressource = e.id
            AND j.action = 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'
        )
      )
    INTO v_nom, v_peut_publier_avant, v_supprime_le, v_est_suppression_rgpd
    FROM public.etablissements e
    WHERE e.id = p_id
    FOR UPDATE;
  END IF;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Compte introuvable');
  END IF;

  SELECT u.banned_until
  INTO v_banned_until_courant
  FROM auth.users u
  WHERE u.id = p_id AND u.deleted_at IS NULL
  FOR UPDATE;
  v_auth_trouve := FOUND;

  SELECT EXISTS (
    SELECT 1 FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = p_table AND sp.id_ressource = p_id
  ) INTO v_provenance_suspension;

  IF v_est_suppression_rgpd THEN
    RETURN jsonb_build_object(
      'error',
      'Compte supprimé au titre du RGPD : suspension et réactivation interdites'
    );
  END IF;

  IF p_suspendre THEN
    IF v_supprime_le IS NOT NULL AND NOT v_provenance_suspension THEN
      RETURN jsonb_build_object(
        'error',
        'Compte déjà supprimé sans provenance de suspension réversible'
      );
    END IF;

    INSERT INTO public.suspensions_profils_admin (
      type_ressource, id_ressource, supprime_le_avant,
      suspendu_le, suspendu_par, motif
    ) VALUES (
      p_table, p_id, v_supprime_le, v_maintenant, auth.uid(), v_motif
    )
    ON CONFLICT (type_ressource, id_ressource) DO UPDATE
      SET suspendu_par = EXCLUDED.suspendu_par,
          motif = EXCLUDED.motif;

    IF v_auth_trouve THEN
      SELECT sa.banned_until_pose
      INTO v_pose_precedente
      FROM public.suspensions_auth_admin sa
      WHERE sa.type_ressource = p_table
        AND sa.id_ressource = p_id
        AND sa.user_id = p_id
      FOR UPDATE;
      v_auth_state_existe := FOUND;

      IF NOT v_auth_state_existe THEN
        v_banned_until_pose := GREATEST(
          COALESCE(v_banned_until_courant, v_maintenant),
          v_maintenant + interval '100 years'
        );

        INSERT INTO public.suspensions_auth_admin (
          type_ressource, id_ressource, user_id,
          banned_until_avant, banned_until_pose,
          suspendu_le, suspendu_par, motif
        ) VALUES (
          p_table, p_id, p_id,
          v_banned_until_courant, v_banned_until_pose,
          v_maintenant, auth.uid(), v_motif
        );

        UPDATE auth.users
        SET banned_until = v_banned_until_pose,
            updated_at = v_maintenant
        WHERE id = p_id
          AND banned_until IS NOT DISTINCT FROM v_banned_until_courant;
      ELSIF v_banned_until_courant IS NOT DISTINCT FROM v_pose_precedente THEN
        -- Suspension répétée : conserver l'état antérieur, mais faire suivre
        -- la valeur CAS réellement posée. Un ban externe divergent est intact.
        v_banned_until_pose := GREATEST(
          COALESCE(v_banned_until_courant, v_maintenant),
          v_maintenant + interval '100 years'
        );

        UPDATE auth.users
        SET banned_until = v_banned_until_pose,
            updated_at = v_maintenant
        WHERE id = p_id
          AND banned_until IS NOT DISTINCT FROM v_pose_precedente;

        UPDATE public.suspensions_auth_admin
        SET banned_until_pose = v_banned_until_pose,
            suspendu_par = auth.uid(),
            motif = v_motif
        WHERE type_ressource = p_table
          AND id_ressource = p_id
          AND user_id = p_id;
      END IF;
    END IF;

    IF p_table = 'soignants' THEN
      UPDATE public.soignants
      SET supprime_le = COALESCE(supprime_le, v_maintenant),
          modifie_le = v_maintenant
      WHERE id = p_id;
    ELSE
      INSERT INTO public.suspensions_etablissement_admin (
        etablissement_id, peut_publier_avant, suspendu_le, suspendu_par, motif
      ) VALUES (
        p_id, v_peut_publier_avant, v_maintenant, auth.uid(), v_motif
      )
      ON CONFLICT (etablissement_id) DO NOTHING;

      INSERT INTO public.suspensions_membres_etablissement_admin (
        etablissement_id, membre_id, user_id, actif_avant, desactive_le,
        suspendu_par, motif
      )
      SELECT p_id, m.id, m.user_id, m.actif, v_maintenant, auth.uid(), v_motif
      FROM public.membres_etablissement m
      WHERE m.etablissement_id = p_id
        AND m.actif IS TRUE
      ON CONFLICT (etablissement_id, membre_id) DO UPDATE
        SET desactive_le = EXCLUDED.desactive_le,
            suspendu_par = EXCLUDED.suspendu_par,
            motif = EXCLUDED.motif;

      UPDATE public.membres_etablissement m
      SET actif = false,
          maj_le = v_maintenant
      WHERE m.etablissement_id = p_id
        AND m.actif IS TRUE;
      GET DIAGNOSTICS v_membres = ROW_COUNT;

      UPDATE public.etablissements
      SET supprime_le = COALESCE(supprime_le, v_maintenant),
          peut_publier_missions = false,
          modifie_le = v_maintenant
      WHERE id = p_id;
    END IF;
  ELSE
    IF NOT v_provenance_suspension THEN
      RETURN jsonb_build_object(
        'error',
        'Aucune suspension administrateur réversible pour ce compte'
      );
    END IF;

    IF p_table = 'soignants' THEN
      UPDATE public.soignants s
      SET supprime_le = sp.supprime_le_avant,
          modifie_le = v_maintenant
      FROM public.suspensions_profils_admin sp
      WHERE s.id = p_id
        AND sp.type_ressource = 'soignants'
        AND sp.id_ressource = s.id;
    ELSE
      DELETE FROM public.suspensions_etablissement_admin se
      WHERE se.etablissement_id = p_id
      RETURNING se.peut_publier_avant INTO v_peut_publier_avant;

      UPDATE public.etablissements e
      SET supprime_le = sp.supprime_le_avant,
          peut_publier_missions = (
            COALESCE(v_peut_publier_avant, false)
            AND e.statut_verification = 'VERIFIE'
            AND e.siret_verifie IS TRUE
            AND e.finess_verifie IS TRUE
            AND e.representant_identite_verifiee IS TRUE
            AND e.rattachement_verifie IS TRUE
            AND e.contrat_service_signe IS TRUE
            AND e.bloque_auto_le IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM public.factures f
              WHERE f.etablissement_id = e.id
                AND f.statut IN ('EMISE', 'EN_RETARD')
                AND f.date_echeance < current_date
            )
          ),
          modifie_le = v_maintenant
      FROM public.suspensions_profils_admin sp
      WHERE e.id = p_id
        AND sp.type_ressource = 'etablissements'
        AND sp.id_ressource = e.id;

      UPDATE public.membres_etablissement m
      SET actif = sm.actif_avant,
          maj_le = v_maintenant
      FROM public.suspensions_membres_etablissement_admin sm
      WHERE sm.etablissement_id = p_id
        AND sm.membre_id = m.id
        AND m.etablissement_id = sm.etablissement_id
        AND m.user_id = sm.user_id
        AND m.actif IS FALSE
        AND m.maj_le = sm.desactive_le;
      GET DIAGNOSTICS v_membres = ROW_COUNT;

      DELETE FROM public.suspensions_membres_etablissement_admin sm
      WHERE sm.etablissement_id = p_id;
    END IF;

    UPDATE auth.users u
    SET banned_until = sa.banned_until_avant,
        updated_at = v_maintenant
    FROM public.suspensions_auth_admin sa
    WHERE sa.type_ressource = p_table
      AND sa.id_ressource = p_id
      AND sa.user_id = u.id
      AND u.banned_until IS NOT DISTINCT FROM sa.banned_until_pose;

    DELETE FROM public.suspensions_auth_admin sa
    WHERE sa.type_ressource = p_table
      AND sa.id_ressource = p_id;

    DELETE FROM public.suspensions_profils_admin sp
    WHERE sp.type_ressource = p_table
      AND sp.id_ressource = p_id;
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    auth.uid(), 'ADMIN',
    CASE WHEN p_suspendre THEN 'SUSPENSION_COMPTE' ELSE 'REACTIVATION_COMPTE' END,
    p_table, p_id,
    jsonb_build_object(
      'nom', v_nom,
      'table', p_table,
      'action', CASE WHEN p_suspendre THEN 'suspendre' ELSE 'réactiver' END,
      'motif', v_motif,
      'auth_synchronise', v_auth_trouve,
      'membres_affectes', v_membres
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'message', CASE WHEN p_suspendre THEN 'Compte suspendu : ' ELSE 'Compte réactivé : ' END || v_nom,
    'auth_synchronise', v_auth_trouve,
    'membres_affectes', v_membres
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.fn_admin_suspendre_utilisateur(text,uuid,boolean,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_suspendre_utilisateur(text,uuid,boolean,text) TO service_role, authenticated;
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le) VALUES ('fn_admin_suspendre_utilisateur(text,uuid,boolean,text)', 'ADMIN_EST_ADMIN_VALIDE', '3d2c664564c6dca5bb6602b187f9739a', 'RPC back-office: garde admin interne observée (est_admin_valide).', now());
