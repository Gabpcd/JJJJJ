CREATE OR REPLACE FUNCTION public.fn_notifier_documents_expirants()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_doc RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_doc IN
        SELECT ds.soignant_id, ds.type_document, ds.valide_jusqua,
               s.prenom, s.nom
        FROM documents_soignants ds
        JOIN soignants s ON s.id = ds.soignant_id
        WHERE ds.valide_jusqua BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
          AND ds.statut_verification = 'VERIFIE'
          AND ds.supprime_le IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM notifications n
              WHERE n.destinataire_id = ds.soignant_id
                AND n.type = 'DOCUMENT_EXPIRANT'
                AND n.id_ressource = ds.id
                AND n.cree_le > NOW() - INTERVAL '7 days'
          )
    LOOP
        PERFORM fn_creer_notification(
            v_doc.soignant_id, 'SOIGNANT', 'DOCUMENT_EXPIRANT',
            'Document bientôt expiré',
            'Votre ' || v_doc.type_document || ' expire le ' || TO_CHAR(v_doc.valide_jusqua, 'DD/MM/YYYY') || '. Pensez à le renouveler.',
            '/soignant/documents',
            'document', v_doc.soignant_id
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_note_moyenne(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_moyenne NUMERIC;
    v_total INTEGER;
BEGIN
    SELECT ROUND(AVG(note), 1), COUNT(*)
    INTO v_moyenne, v_total
    FROM evaluations
    WHERE evalue_id = p_user_id;

    RETURN jsonb_build_object(
        'moyenne', COALESCE(v_moyenne, 0),
        'total_evaluations', COALESCE(v_total, 0)
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_obligations_financieres()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_total_soignants_du NUMERIC;
    v_total_commissions_du NUMERIC;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Etablissement introuvable'); END IF;

    v_total_soignants_du := COALESCE((
        SELECT SUM(m.net_a_payer) FROM missions m
        WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME','RESOLU'))
        AND NOT EXISTS (SELECT 1 FROM stripe_transfers st WHERE st.mission_id = m.id AND st.statut IN ('TRANSFERE','CHARGE_REUSSI','PAYE'))
    ), 0);

    v_total_commissions_du := COALESCE((
        SELECT SUM(montant_ttc) FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')
    ), 0);

    RETURN jsonb_build_object(
        'total_du', v_total_soignants_du + v_total_commissions_du,
        'total_soignants_du', v_total_soignants_du,
        'total_commissions_du', v_total_commissions_du,
        'nb_missions_non_payees', (SELECT COUNT(*) FROM missions m WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME','RESOLU'))
            AND NOT EXISTS (SELECT 1 FROM stripe_transfers st WHERE st.mission_id = m.id AND st.statut IN ('TRANSFERE','CHARGE_REUSSI','PAYE'))),
        'nb_paiements_en_attente', (SELECT COUNT(*) FROM paiements_soignant WHERE etablissement_id = v_etab_id AND statut = 'DECLARE'),
        'nb_factures_impayees', (SELECT COUNT(*) FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('EMISE', 'EN_RETARD')),
        'nb_factures_commission_historique', (SELECT COUNT(*) FROM factures WHERE etablissement_id = v_etab_id AND statut IN ('PAYEE', 'ANNULEE')),
        'missions_non_payees', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.debut_le, m.fin_le,
                    m.total_brut, m.net_a_payer, m.montant_commission_ttc,
                    m.soignant_assigne_id::TEXT AS soignant_id,
                    EXTRACT(EPOCH FROM (m.fin_le - m.debut_le))/3600 AS heures,
                    EXTRACT(DAY FROM NOW() - m.fin_le)::INT AS jours_depuis_fin,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession,
                    s.type_exercice AS soignant_type_exercice,
                    m.type_contrat_applique::TEXT AS type_contrat_applique,
                    m.type_paiement_soignant AS type_paiement_soignant,
                    m.mode_paiement_soignant AS mode_paiement_soignant,
                    (s.stripe_account_id IS NOT NULL AND EXISTS(
                        SELECT 1 FROM stripe_connect_onboarding sco
                        WHERE sco.soignant_id = s.id AND sco.charges_enabled = TRUE AND sco.payouts_enabled = TRUE
                    )) AS soignant_stripe_connect,
                    EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut = 'CONTESTE') AS a_paiement_conteste,
                    (SELECT p.id::TEXT FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut = 'CONTESTE' ORDER BY p.cree_le DESC LIMIT 1) AS paiement_conteste_id
                FROM missions m
                JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.soignant_assigne_id IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM paiements_soignant p WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME','RESOLU'))
                AND NOT EXISTS (SELECT 1 FROM stripe_transfers st WHERE st.mission_id = m.id AND st.statut IN ('TRANSFERE','CHARGE_REUSSI','PAYE'))
                ORDER BY m.fin_le ASC
            ) x
        ), '[]'::JSONB),
        'paiements_soignants_en_attente', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT p.id::TEXT AS paiement_id, p.mission_id::TEXT, p.montant_net, p.methode,
                    p.reference_virement, p.date_paiement, p.statut,
                    m.intitule AS mission_intitule,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.profession::TEXT AS soignant_profession,
                    (SELECT fh.id::TEXT FROM factures_honoraires fh WHERE fh.mission_id = m.id ORDER BY fh.date_emission DESC LIMIT 1) AS facture_honoraires_id
                FROM paiements_soignant p
                JOIN missions m ON m.id = p.mission_id
                JOIN soignants s ON s.id = p.soignant_id
                WHERE p.etablissement_id = v_etab_id AND p.statut = 'DECLARE'
                ORDER BY p.date_paiement DESC
            ) x
        ), '[]'::JSONB),
        'paiements_soignants_confirmes', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT p.id::TEXT AS paiement_id, p.mission_id::TEXT, p.montant_net, p.methode, p.reference_virement,
                    p.date_paiement, p.confirme_par_soignant_le,
                    m.intitule AS mission_intitule,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    (SELECT fh.id::TEXT FROM factures_honoraires fh WHERE fh.mission_id = m.id ORDER BY fh.date_emission DESC LIMIT 1) AS facture_honoraires_id
                FROM paiements_soignant p
                JOIN missions m ON m.id = p.mission_id
                JOIN soignants s ON s.id = p.soignant_id
                WHERE p.etablissement_id = v_etab_id AND p.statut = 'CONFIRME'
                ORDER BY p.confirme_par_soignant_le DESC LIMIT 10
            ) x
        ), '[]'::JSONB),
        'factures_impayees', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT f.id::TEXT AS facture_id, f.numero_facture, f.montant_ht, f.montant_tva, f.montant_ttc,
                    f.nombre_missions, f.date_echeance, f.statut,
                    f.stripe_hosted_url,
                    f.est_secteur_public,
                    f.chorus_pro_statut,
                    f.chorus_pro_numero_flux
                FROM factures f
                WHERE f.etablissement_id = v_etab_id AND f.statut IN ('EMISE', 'EN_RETARD', 'VIREMENT_DECLARE')
                ORDER BY f.date_echeance ASC
            ) x
        ), '[]'::JSONB),
        'factures_commission_historique', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT f.id::TEXT AS facture_id, f.numero_facture, f.statut,
                    f.montant_ttc, f.nombre_missions,
                    f.date_emission, f.date_paiement,
                    f.mode_paiement, f.virement_reference, f.stripe_payment_intent_id,
                    f.mission_id::TEXT AS mission_id,
                    f.est_secteur_public,
                    f.chorus_pro_statut
                FROM factures f
                WHERE f.etablissement_id = v_etab_id
                  AND f.statut IN ('PAYEE', 'ANNULEE')
                ORDER BY f.date_paiement DESC NULLS LAST, f.date_emission DESC
                LIMIT 10
            ) x
        ), '[]'::JSONB),
        'missions_non_facturees', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.fin_le,
                    m.montant_commission_ht, m.montant_commission_ttc
                FROM missions m
                WHERE m.etablissement_id = v_etab_id AND m.statut = 'TERMINEE' AND m.commission_facturee = FALSE
                  AND NOT EXISTS (SELECT 1 FROM factures f WHERE f.mission_id = m.id)
                ORDER BY m.fin_le DESC
            ) x
        ), '[]'::JSONB)
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_no_overlap_creneaux()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1 FROM mission_creneaux
    WHERE mission_id = NEW.mission_id
      AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      AND type_creneau = NEW.type_creneau
      AND NEW.debut < fin AND NEW.fin > debut
  ) THEN
    RAISE EXCEPTION 'Chevauchement de créneaux dans la même mission (type=%)', NEW.type_creneau
      USING ERRCODE = 'exclusion_violation';
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_next_bulletin_paie_number(p_soignant_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_siret text;
  v_annee text := to_char(CURRENT_DATE, 'YYYY');
  v_seq int;
  v_lock_key bigint;
BEGIN
  -- Advisory lock par soignant pour éviter les collisions de séquence
  v_lock_key := ('x' || substring(md5(p_soignant_id::text || ':bp') from 1 for 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT COALESCE(siret_liberal, '') INTO v_siret FROM soignants WHERE id = p_soignant_id;
  IF v_siret IS NULL OR length(v_siret) < 8 THEN
    v_siret := substring(p_soignant_id::text from 1 for 8);
  ELSE
    v_siret := substring(v_siret from 1 for 8);
  END IF;

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(numero_bulletin, '^BP-[^-]+-[0-9]{4}-', ''), '')::int
  ), 0) + 1
  INTO v_seq
  FROM bulletins_paie
  WHERE soignant_id = p_soignant_id
    AND numero_bulletin LIKE 'BP-' || v_siret || '-' || v_annee || '-%';

  RETURN format('BP-%s-%s-%s', v_siret, v_annee, lpad(v_seq::text, 5, '0'));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_obtenir_apercu_filtre(p_filtre_id uuid, p_since timestamp with time zone, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filtre RECORD;
  v_result jsonb;
  v_profession text;
  v_taux_min numeric;
  v_urgentes_only boolean;
BEGIN
  SELECT * INTO v_filtre FROM filtres_sauvegardes WHERE id = p_filtre_id;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  IF v_filtre.audience = 'SOIGNANT_RECHERCHE_MISSIONS' THEN
    v_profession := v_filtre.filtres->>'profession';
    v_taux_min := COALESCE((v_filtre.filtres->>'tauxMin')::numeric, 0);
    v_urgentes_only := COALESCE((v_filtre.filtres->>'urgentesOnly')::boolean, false);
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'intitule', m.intitule, 'profession', m.profession_requise::text,
      'etablissement', e.nom, 'ville', e.adresse_ville,
      'taux_horaire', m.taux_horaire_base,
      'debut_le', m.debut_le, 'fin_le', m.fin_le,
      'urgente', COALESCE(m.est_urgente, false)
    ) ORDER BY m.cree_le DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT * FROM missions m2
      WHERE m2.statut = 'OUVERTE' AND m2.cree_le > p_since
        AND (v_profession IS NULL OR v_profession = '' OR m2.profession_requise::text = v_profession)
        AND COALESCE(m2.taux_horaire_base, 0) >= v_taux_min
        AND (NOT v_urgentes_only OR COALESCE(m2.est_urgente, false) = true)
      ORDER BY m2.cree_le DESC LIMIT p_limit
    ) m
    LEFT JOIN etablissements e ON e.id = m.etablissement_id;
  ELSIF v_filtre.audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    v_profession := v_filtre.filtres->>'profession';
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', s.id, 'prenom', s.prenom,
      'nom_initiale', LEFT(s.nom, 1) || '.',
      'profession', s.profession::text,
      'note_moyenne', s.note_moyenne
    ) ORDER BY s.cree_le DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT * FROM soignants s2
      WHERE s2.cree_le > p_since
        AND COALESCE(s2.tous_documents_valides, false) = true
        AND (v_profession IS NULL OR v_profession = '' OR s2.profession::text = v_profession)
      ORDER BY s2.cree_le DESC LIMIT p_limit
    ) s;
  ELSE
    v_result := '[]'::jsonb;
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_normaliser_nom(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT btrim(lower(translate(
    coalesce(p, ''),
    'àâäáãéèêëíìîïóòôöõúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  )));
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_notifier_favoris_expirants()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_nb integer := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT ms.id AS sauvegarde_id, ms.soignant_id, m.id AS mission_id, m.intitule,
           to_char(m.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24hMI') AS debut_txt
    FROM missions_sauvegardees ms
    JOIN missions m ON m.id = ms.mission_id
    WHERE ms.notifie_expiration = false
      AND m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND m.debut_le <= now() + interval '48 hours'
      AND NOT EXISTS (
        SELECT 1 FROM candidatures c
        WHERE c.mission_id = m.id AND c.soignant_id = ms.soignant_id
      )
  LOOP
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES (
      r.soignant_id, 'SOIGNANT', 'FAVORI_MISSION_EXPIRE',
      '⭐ Ta mission sauvegardée démarre bientôt',
      '« ' || r.intitule || ' » démarre le ' || r.debut_txt || ' — postule avant qu''elle ne parte.',
      '/soignant/missions/' || r.mission_id
    );
    UPDATE missions_sauvegardees SET notifie_expiration = true WHERE id = r.sauvegarde_id;
    v_nb := v_nb + 1;
  END LOOP;
  RETURN v_nb;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_obtenir_conversation(p_autre_id uuid, p_mission_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_conv_id UUID;
    v_mon_id UUID := auth.uid();
BEGIN
    -- Chercher une conversation existante
    SELECT id INTO v_conv_id FROM conversations
    WHERE (
        (participant_1_id = v_mon_id AND participant_2_id = p_autre_id)
        OR (participant_1_id = p_autre_id AND participant_2_id = v_mon_id)
    )
    AND (p_mission_id IS NULL OR mission_id = p_mission_id OR mission_id IS NULL)
    LIMIT 1;

    IF v_conv_id IS NULL THEN
        -- Vérifier que l'utilisateur a le droit de créer cette conversation
        -- Admin peut contacter n'importe qui
        -- Soignant/Établissement uniquement si mission assignée entre eux
        IF NOT est_admin() THEN
            IF p_mission_id IS NULL THEN
                -- Sans mission, vérifier qu'il y a au moins une mission partagée
                IF NOT EXISTS (
                    SELECT 1 FROM missions
                    WHERE (soignant_assigne_id = v_mon_id AND etablissement_id = p_autre_id)
                       OR (soignant_assigne_id = p_autre_id AND etablissement_id IN (SELECT id FROM etablissements WHERE id = v_mon_id))
                ) THEN
                    RAISE EXCEPTION 'Vous ne pouvez contacter que les utilisateurs avec qui vous avez une mission.';
                END IF;
            END IF;
        END IF;

        INSERT INTO conversations (participant_1_id, participant_2_id, mission_id)
        VALUES (v_mon_id, p_autre_id, p_mission_id)
        RETURNING id INTO v_conv_id;
    END IF;

    RETURN v_conv_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(p_mission_id uuid, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  RAISE WARNING 'fn_ouvrir_litige_rate_limited(UUID, TEXT) is DEPRECATED since CP-LITIGES-2. Use 3-arg signature with type_litige.';

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'DEPRECATED_CALLER', 'LITIGE_OUVERTURE_LEGACY',
    'mission', p_mission_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'motif', left(p_motif, 200),
      'info', 'Appel via wrapper 2-arg DEPRECATED — migration UI incomplète'
    ),
    NULL, NULL
  );

  RETURN public.fn_ouvrir_litige_rate_limited(
    p_mission_id,
    'AUTRE'::public.type_litige,
    p_motif
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_paiements_etablissement()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_result JSONB;
BEGIN
    IF v_etab_id IS NULL THEN RETURN jsonb_build_object('error', 'Établissement introuvable'); END IF;
    
    SELECT jsonb_build_object(
        'total_paye', COALESCE((SELECT SUM(montant_net) FROM paiements_soignant WHERE etablissement_id = v_etab_id AND statut IN ('DECLARE','CONFIRME')), 0),
        'total_en_attente', COALESCE((SELECT SUM(montant_net) FROM paiements_soignant WHERE etablissement_id = v_etab_id AND statut = 'DECLARE'), 0),
        'total_confirme', COALESCE((SELECT SUM(montant_net) FROM paiements_soignant WHERE etablissement_id = v_etab_id AND statut = 'CONFIRME'), 0),
        'total_conteste', COALESCE((SELECT SUM(montant_net) FROM paiements_soignant WHERE etablissement_id = v_etab_id AND statut = 'CONTESTE'), 0),
        'nb_paiements', (SELECT COUNT(*) FROM paiements_soignant WHERE etablissement_id = v_etab_id),
        'commissions_ht', COALESCE((SELECT SUM(montant_ht) FROM factures WHERE etablissement_id = v_etab_id AND statut != 'ANNULEE'), 0),
        'commissions_ttc', COALESCE((SELECT SUM(montant_ttc) FROM factures WHERE etablissement_id = v_etab_id AND statut != 'ANNULEE'), 0),
        'missions_a_payer', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT m.id::TEXT AS mission_id, m.intitule, m.fin_le, m.total_brut,
                    m.type_paiement_soignant, m.net_a_payer, m.mode_paiement_soignant,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom,
                    s.type_exercice AS soignant_type_exercice,
                    -- ★ Vérifier que le Stripe Connect est COMPLÈTEMENT opérationnel
                    (s.stripe_account_id IS NOT NULL AND EXISTS(
                        SELECT 1 FROM stripe_connect_onboarding sco
                        WHERE sco.soignant_id = s.id 
                        AND sco.charges_enabled = TRUE 
                        AND sco.payouts_enabled = TRUE
                    )) AS soignant_stripe_connect,
                    EXTRACT(DAY FROM NOW() - m.fin_le)::INT AS jours_depuis_fin
                FROM missions m
                JOIN soignants s ON s.id = m.soignant_assigne_id
                WHERE m.etablissement_id = v_etab_id
                AND m.statut = 'TERMINEE'
                AND m.soignant_assigne_id IS NOT NULL
                AND NOT EXISTS (
                    SELECT 1 FROM paiements_soignant p
                    WHERE p.mission_id = m.id AND p.statut IN ('DECLARE','CONFIRME')
                )
                ORDER BY m.fin_le ASC
            ) x
        ), '[]'::JSONB),
        'paiements_recents', COALESCE((
            SELECT jsonb_agg(row_to_json(x)) FROM (
                SELECT p.id::TEXT AS paiement_id, p.mission_id::TEXT, p.montant_net, p.methode, 
                    p.statut, p.date_paiement, p.reference_virement,
                    p.confirme_par_soignant, p.confirme_par_soignant_le, p.conteste, p.motif_contestation,
                    p.echeance_le,
                    m.intitule AS mission_intitule,
                    COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, '') AS soignant_nom
                FROM paiements_soignant p
                JOIN missions m ON m.id = p.mission_id
                JOIN soignants s ON s.id = p.soignant_id
                WHERE p.etablissement_id = v_etab_id
                ORDER BY p.cree_le DESC LIMIT 20
            ) x
        ), '[]'::JSONB)
    ) INTO v_result;
    
    RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_ouvrir_litige_rate_limited(p_mission_id uuid, p_type_litige type_litige, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id    UUID := auth.uid();
  v_mission    RECORD;
  v_existing   INT;
  v_recent     INT;
  v_initie_par TEXT;
  v_etab_id    UUID;
  v_soignant_id UUID;
  v_presence_id UUID;
  v_rate_limit INT;
  v_litige_id  UUID;
  v_est_informatif BOOLEAN;
  v_fenetre_ouverte BOOLEAN;
  v_facture_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  IF length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id, statut
    INTO v_mission
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF v_mission.soignant_assigne_id = v_user_id THEN
    v_initie_par  := 'SOIGNANT';
    v_etab_id     := v_mission.etablissement_id;
    v_soignant_id := v_user_id;
  ELSIF v_mission.etablissement_id = public.mon_etablissement_id() THEN
    v_initie_par  := 'ETABLISSEMENT';
    v_etab_id     := v_mission.etablissement_id;
    v_soignant_id := v_mission.soignant_assigne_id;
  ELSE
    RETURN jsonb_build_object('error', 'Vous n''êtes pas partie prenante de cette mission.');
  END IF;

  SELECT COUNT(*) INTO v_existing
    FROM public.litiges
   WHERE mission_id = p_mission_id
     AND type_litige = p_type_litige
     AND statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION');
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('error', 'Un litige de ce type est déjà ouvert pour cette mission.');
  END IF;

  v_rate_limit := COALESCE(
    (SELECT valeur::INT FROM public.parametres_litiges WHERE cle = 'rate_limit_litiges_par_heure'),
    3
  );
  SELECT COUNT(*) INTO v_recent
    FROM public.litiges
   WHERE (soignant_id = v_user_id OR etablissement_id = public.mon_etablissement_id())
     AND cree_le > NOW() - INTERVAL '1 hour';
  IF v_recent >= v_rate_limit THEN
    RETURN jsonb_build_object('error', 'Trop de litiges ouverts récemment. Réessayez plus tard.');
  END IF;

  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'NON_PAIEMENT', 'FRAIS_COMPLEMENTAIRES') THEN
    SELECT id INTO v_facture_id
      FROM public.factures_honoraires
     WHERE mission_id = p_mission_id AND statut <> 'BROUILLON'
     ORDER BY date_emission DESC NULLS LAST
     LIMIT 1;
    IF v_facture_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Aucune facture trouvée pour cette mission, contestation impossible.');
    END IF;
  END IF;

  v_fenetre_ouverte := public.fn_fenetre_contestation_ouverte(p_type_litige, p_mission_id, v_facture_id);
  v_est_informatif := NOT v_fenetre_ouverte;

  IF v_est_informatif
     AND p_type_litige NOT IN ('COMPORTEMENT_SOIGNANT', 'COMPORTEMENT_ETABLISSEMENT', 'CONDITIONS_MISSION_NON_RESPECTEES')
  THEN
    RETURN jsonb_build_object(
      'error', 'Fenêtre de contestation fermée pour ce type de litige. Contactez le support.'
    );
  END IF;

  SELECT id INTO v_presence_id
    FROM public.presences WHERE mission_id = p_mission_id
   ORDER BY cree_le DESC LIMIT 1;

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, presence_id, facture_id,
    initie_par, motif, statut, type_litige, est_informatif
  )
  VALUES (
    p_mission_id, v_soignant_id, v_etab_id, v_presence_id, v_facture_id,
    v_initie_par, trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif
  )
  RETURNING id INTO v_litige_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, v_initie_par, 'LITIGE_OUVERTURE',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'initie_par', v_initie_par,
      'est_informatif', v_est_informatif,
      'facture_id', v_facture_id
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif,
    'facture_id', v_facture_id
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_obtenir_mes_preferences_notifications()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_global jsonb;
  v_par_evenement jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;

  SELECT to_jsonb(p) - 'utilisateur_id' INTO v_global
  FROM preferences_notifications p WHERE utilisateur_id = v_uid;

  -- Si pas de row, créer la row default
  IF v_global IS NULL THEN
    INSERT INTO preferences_notifications (utilisateur_id) VALUES (v_uid)
    ON CONFLICT (utilisateur_id) DO NOTHING;
    SELECT to_jsonb(p) - 'utilisateur_id' INTO v_global
    FROM preferences_notifications p WHERE utilisateur_id = v_uid;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'type_evenement', type_evenement,
    'canal', canal,
    'actif', actif
  )), '[]'::jsonb) INTO v_par_evenement
  FROM preferences_notifications_par_evenement WHERE utilisateur_id = v_uid;

  RETURN jsonb_build_object('global', v_global, 'par_evenement', v_par_evenement);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_obtenir_donnees_template_serie(p_envoi_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_envoi RECORD;
  v_data jsonb := '{}'::jsonb;
  v_count integer;
BEGIN
  SELECT * INTO v_envoi FROM serie_email_envois WHERE id = p_envoi_id;
  IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;

  IF v_envoi.serie = 'SOIGNANT_ONBOARDING' THEN
    SELECT jsonb_build_object(
      'prenom', s.prenom, 'nom', s.nom, 'profession', s.profession,
      'lien_dashboard', 'https://jolene.app/soignant'
    ) INTO v_data FROM soignants s WHERE s.id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J3' THEN
      SELECT count(*) INTO v_count FROM missions WHERE statut = 'OUVERTE';
      v_data := v_data || jsonb_build_object('nb_missions_actives', v_count);
    END IF;
    IF v_envoi.etape = 'J7' THEN
      SELECT count(*) INTO v_count FROM candidatures WHERE soignant_id = v_envoi.utilisateur_id;
      v_data := v_data || jsonb_build_object('nb_candidatures', v_count);
    END IF;
  ELSIF v_envoi.serie = 'ETAB_ONBOARDING' THEN
    SELECT jsonb_build_object(
      'nom_etablissement', e.nom, 'type_etablissement', e.type::text,
      'contrat_signe', e.contrat_service_signe,
      'lien_dashboard', 'https://jolene.app/etablissement'
    ) INTO v_data FROM etablissements e WHERE e.id = v_envoi.utilisateur_id;

    IF v_envoi.etape = 'J3' OR v_envoi.etape = 'J7' THEN
      SELECT count(*) INTO v_count FROM missions WHERE etablissement_id = v_envoi.utilisateur_id;
      v_data := v_data || jsonb_build_object('nb_missions_publiees', v_count);
    END IF;
    IF v_envoi.etape = 'J7' THEN
      SELECT count(*) INTO v_count FROM candidatures c
      JOIN missions m ON m.id = c.mission_id
      WHERE m.etablissement_id = v_envoi.utilisateur_id;
      v_data := v_data || jsonb_build_object('nb_candidatures_recues', v_count);
    END IF;
  END IF;

  RETURN v_data;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_obtenir_missions_swipe(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_soignant_id uuid := auth.uid(); v_sg soignants%ROWTYPE; v_missions jsonb;
        v_flag_pr boolean := (public.fn_param_num('feature_paiement_rapide_actif', 0) = 1);
BEGIN
  IF v_soignant_id IS NULL THEN RETURN jsonb_build_object('missions', '[]'::jsonb, 'error', 'auth_required'); END IF;
  SELECT * INTO v_sg FROM soignants WHERE id = v_soignant_id;
  -- 7d-A2 : tri = score + jitter aléatoire 0-12 pts → les meilleures restent
  -- devant, mais 10-15 % de missions à score moyen remontent (exploration).
  SELECT COALESCE(jsonb_agg(payload ORDER BY tri DESC), '[]'::jsonb) INTO v_missions
  FROM (
    SELECT (COALESCE(ms.score_global, 0) + floor(random() * 13))::int AS tri,
      jsonb_build_object(
      'mission_id', m.id, 'intitule', m.intitule, 'profession_requise', m.profession_requise,
      'etablissement_id', m.etablissement_id, 'etablissement_nom', e.nom, 'etablissement_ville', e.adresse_ville,
      'etablissement_code_postal', e.adresse_code_postal, 'etablissement_logo_url', e.logo_url,
      'etablissement_score', e.score_qualite, 'taux_horaire_base', m.taux_horaire_base, 'duree_heures', m.duree_heures,
      'debut_le', m.debut_le, 'fin_le', m.fin_le, 'est_urgente', m.est_urgente, 'service', m.service,
      'type_contrat_applique', m.type_contrat_applique, 'type_contrat_recherche', m.type_contrat_recherche,
      'nb_creneaux', m.nb_creneaux, 'total_brut', m.total_brut, 'net_a_payer', m.net_a_payer,
      'net_estime', m.net_estime, 'montant_ifm', COALESCE(m.montant_ifm, 0), 'montant_icp', COALESCE(m.montant_icp, 0),
      'montant_majoration_nuit', COALESCE(m.montant_majoration_nuit, 0), 'montant_majoration_dimanche', COALESCE(m.montant_majoration_dimanche, 0),
      'montant_majoration_ferie', COALESCE(m.montant_majoration_ferie, 0), 'score', COALESCE(ms.score_global, 0),
      'breakdown', COALESCE(ms.breakdown, '{}'::jsonb),
      'paiement_rapide', (
        v_flag_pr
        AND m.type_contrat_recherche = 'LIBERAL'
        AND e.mode_paiement_commission = 'SEPA_DEBIT'
        AND e.stripe_sepa_payment_method_id IS NOT NULL
      ),
      'distance_km', CASE
        WHEN v_sg.adresse_lat IS NOT NULL AND v_sg.adresse_lng IS NOT NULL
         AND e.adresse_lat IS NOT NULL AND e.adresse_lng IS NOT NULL
        THEN ROUND((fn_haversine_distance_m(v_sg.adresse_lat, v_sg.adresse_lng, e.adresse_lat, e.adresse_lng) / 1000.0)::numeric, 1)
        ELSE NULL END
    ) AS payload
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.matching_scores ms ON ms.mission_id = m.id AND ms.soignant_id = v_soignant_id
     WHERE m.statut = 'OUVERTE'
       AND (m.intitule NOT LIKE '[%' OR v_sg.email LIKE 'playwright-%')
       AND fn_soignant_compatible_mission(
             v_sg.profession, v_sg.specialite_medicale,
             m.profession_requise, m.specialite_medicale_requise, m.accepte_non_specialises)
       AND (m.type_contrat_recherche = 'TOUS' OR v_sg.type_exercice IS NULL OR v_sg.type_exercice = 'MIXTE'
            OR (m.type_contrat_recherche = 'SALARIE' AND v_sg.type_exercice IN ('SALARIE', 'MIXTE'))
            OR (m.type_contrat_recherche = 'LIBERAL' AND v_sg.type_exercice IN ('LIBERAL', 'MIXTE')))
       AND (v_sg.taux_horaire_minimum IS NULL OR m.taux_horaire_base IS NULL
            OR m.taux_horaire_base >= v_sg.taux_horaire_minimum)
       AND m.id NOT IN (SELECT s.mission_id FROM public.swipes s WHERE s.soignant_id = v_soignant_id)
     ORDER BY COALESCE(ms.score_global, 0) DESC, m.est_urgente DESC, m.cree_le DESC
     LIMIT p_limit
  ) t;
  RETURN jsonb_build_object('missions', v_missions);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_obtenir_mes_parrainages()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_filleuls JSONB; v_parrain_info JSONB; v_total_gains NUMERIC; v_nb_primes_versees INT;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 25))::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',p.id,'filleul_id',p.filleul_id,'prenom',s.prenom,'statut',p.statut,'cree_le',p.cree_le,
    'filleul_active_le',p.filleul_active_le,
    'commission_cumulee_filleul',COALESCE(p.commission_cumulee_filleul,0),
    'gmv_cumule_filleul',COALESCE(p.gmv_cumule_filleul,0),
    'reste_gmv_avant_prime',GREATEST(0, v_seuil_gmv - COALESCE(p.gmv_cumule_filleul,0)),
    'seuil_gmv',v_seuil_gmv,
    'seuil_atteint',(COALESCE(p.gmv_cumule_filleul,0) >= v_seuil_gmv
                     AND COALESCE(p.commission_cumulee_filleul,0) >= 4 * v_prime),
    'prime_versee_le',p.prime_versee_le,'premiere_mission_le',s.premiere_mission_le,
    'bonus_heures',COALESCE(p.bonus_heures_parrain,0)
  ) ORDER BY p.cree_le DESC), '[]'::jsonb)
  INTO v_filleuls
  FROM parrainages p JOIN soignants s ON s.id = p.filleul_id WHERE p.parrain_id = v_uid;
  SELECT COUNT(*), COALESCE(SUM(v_prime),0) INTO v_nb_primes_versees, v_total_gains
    FROM parrainages WHERE parrain_id = v_uid AND statut = 'PRIME_VERSEE';
  SELECT jsonb_build_object('parrain_prenom',sp.prenom,'statut',p.statut,'prime_versee_le',p.prime_versee_le)
    INTO v_parrain_info FROM parrainages p JOIN soignants sp ON sp.id = p.parrain_id WHERE p.filleul_id = v_uid LIMIT 1;
  RETURN jsonb_build_object('filleuls',v_filleuls,'total_gains_eur',v_total_gains,
    'nb_primes_versees',v_nb_primes_versees,'prime_eur',v_prime,'seuil_gmv_eur',v_seuil_gmv,
    'mon_parrain',COALESCE(v_parrain_info,'null'::jsonb));
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_pointer_arrivee(p_mission_id uuid, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_precision numeric DEFAULT NULL::numeric, p_terminal_id text DEFAULT NULL::text, p_modele text DEFAULT NULL::text, p_code_arrivee text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission RECORD;
  v_contrat RECORD;
  v_etab RECORD;
  v_distance_m numeric;
  v_perimetre_ok boolean;
  v_methode text;
  v_warnings jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
  IF v_mission.soignant_assigne_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
  IF v_mission.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN '{"error":"Mission non active"}'::JSONB; END IF;

  SELECT * INTO v_contrat FROM contrats_mission WHERE mission_id = p_mission_id AND statut = 'SIGNE_COMPLET';
  IF v_contrat IS NULL THEN RETURN '{"error":"Le contrat doit être signé avant le pointage."}'::JSONB; END IF;

  IF EXISTS (SELECT 1 FROM presences WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
    RETURN '{"error":"Vous avez déjà pointé votre arrivée."}'::JSONB;
  END IF;

  SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 500) AS tolerance_m
    INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;

  IF p_code_arrivee IS NOT NULL THEN
    IF p_code_arrivee != v_mission.code_arrivee THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT', 'error', 'Code de pointage incorrect.');
    END IF;
    v_methode := 'CODE';
    v_perimetre_ok := true;
    v_distance_m := NULL;
  ELSE
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'GPS_MANQUANT',
        'error', 'Coordonnées GPS requises (ou utilisez le code de secours).');
    END IF;
    IF v_etab.adresse_lat IS NULL OR v_etab.adresse_lng IS NULL THEN
      v_distance_m := NULL;
      v_perimetre_ok := false;
    ELSE
      v_distance_m := public.fn_haversine_distance_m(p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= v_etab.tolerance_m;
      IF NOT v_perimetre_ok THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'HORS_PERIMETRE',
          'error', 'Vous êtes à ' || v_distance_m::int || 'm de l''établissement (tolérance ' || v_etab.tolerance_m || 'm). Utilisez le code fourni par l''établissement.',
          'distance_m', v_distance_m, 'tolerance_m', v_etab.tolerance_m);
      END IF;
    END IF;
    v_methode := 'GPS';
  END IF;

  IF v_contrat.type_contrat IN ('CDD', 'CDD', 'SALARIE')
     AND COALESCE(v_contrat.dpae_numero, '') = '' THEN
    v_warnings := v_warnings || jsonb_build_object(
      'code', 'DPAE_NON_REGULARISEE',
      'message', 'Votre DPAE URSSAF n''est pas encore enregistrée dans Jolene. L''établissement doit régulariser la déclaration auprès de l''URSSAF et saisir le numéro dans la plateforme.',
      'severite', 'warning'
    );

    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object(
          'destinataire_id', v_mission.etablissement_id,
          'type_evenement', 'DPAE_NON_REGULARISEE_POINTAGE',
          'titre', '⚠️ DPAE à régulariser',
          'corps', 'Le soignant vient de pointer sur le contrat ' || COALESCE(v_contrat.numero_contrat, '') || ' mais le numéro URSSAF n''est pas saisi. À régulariser sous 24h.',
          'data', jsonb_build_object('contrat_id', v_contrat.id::text, 'mission_id', p_mission_id::text)
        )
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  INSERT INTO presences (
    mission_id, soignant_id, pointage_arrivee_le,
    arrivee_lat, arrivee_lng, arrivee_precision_gps_m,
    arrivee_id_terminal, arrivee_modele_terminal,
    methode_pointage_arrivee, distance_etablissement_m, perimetre_gps_valide
  ) VALUES (
    p_mission_id, auth.uid(), NOW(), p_lat, p_lng, p_precision,
    p_terminal_id, p_modele, v_methode, v_distance_m, v_perimetre_ok
  );

  UPDATE missions SET statut = 'EN_COURS', modifie_le = NOW()
   WHERE id = p_mission_id AND statut = 'ASSIGNEE';

  RETURN jsonb_build_object(
    'success', true,
    'methode', v_methode,
    'distance_m', v_distance_m,
    'perimetre_valide', v_perimetre_ok,
    'warnings', v_warnings
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_pointer_depart(p_presence_id uuid, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_precision numeric DEFAULT NULL::numeric, p_terminal_id text DEFAULT NULL::text, p_modele text DEFAULT NULL::text, p_code_depart text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_presence RECORD; v_mission RECORD; v_etab RECORD;
  v_distance_m numeric; v_perimetre_ok boolean; v_methode text;
BEGIN
  SELECT * INTO v_presence FROM presences WHERE id = p_presence_id;
  IF v_presence IS NULL THEN RETURN '{"error":"Présence introuvable"}'::JSONB; END IF;
  IF v_presence.soignant_id != auth.uid() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;
  IF v_presence.pointage_depart_le IS NOT NULL THEN RETURN '{"error":"Départ déjà pointé"}'::JSONB; END IF;
  SELECT * INTO v_mission FROM missions WHERE id = v_presence.mission_id;
  SELECT adresse_lat, adresse_lng, COALESCE(tolerance_pointage_m, 500) AS tolerance_m
  INTO v_etab FROM etablissements WHERE id = v_mission.etablissement_id;
  IF p_code_depart IS NOT NULL THEN
    IF p_code_depart != v_mission.code_depart THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'CODE_INCORRECT', 'error', 'Code de départ incorrect.');
    END IF;
    v_methode := 'CODE'; v_perimetre_ok := true; v_distance_m := NULL;
  ELSE
    IF p_lat IS NULL OR p_lng IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error_code', 'GPS_MANQUANT',
        'error', 'Coordonnées GPS requises (ou utilisez le code de secours).');
    END IF;
    IF v_etab.adresse_lat IS NULL OR v_etab.adresse_lng IS NULL THEN
      v_distance_m := NULL; v_perimetre_ok := false;
    ELSE
      v_distance_m := public.fn_haversine_distance_m(p_lat, p_lng, v_etab.adresse_lat::numeric, v_etab.adresse_lng::numeric);
      v_perimetre_ok := v_distance_m <= v_etab.tolerance_m;
      IF NOT v_perimetre_ok THEN
        RETURN jsonb_build_object('success', false, 'error_code', 'HORS_PERIMETRE',
          'error', 'Vous êtes à ' || v_distance_m::int || 'm de l''établissement (tolérance ' || v_etab.tolerance_m || 'm). Utilisez le code fourni par l''établissement.',
          'distance_m', v_distance_m, 'tolerance_m', v_etab.tolerance_m);
      END IF;
    END IF;
    v_methode := 'GPS';
  END IF;
  UPDATE presences SET
    pointage_depart_le = NOW(),
    depart_lat = p_lat, depart_lng = p_lng,
    depart_precision_gps_m = p_precision,
    depart_id_terminal = p_terminal_id,
    depart_modele_terminal = p_modele,
    methode_pointage_depart = v_methode,
    distance_etablissement_m = COALESCE(distance_etablissement_m, v_distance_m),
    perimetre_gps_valide = CASE WHEN perimetre_gps_valide IS NOT TRUE THEN v_perimetre_ok ELSE perimetre_gps_valide END
  WHERE id = p_presence_id;
  RETURN jsonb_build_object('success', true, 'methode', v_methode,
    'distance_m', v_distance_m, 'perimetre_valide', v_perimetre_ok);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_pointer_fin_pause(p_presence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_presence RECORD;
    v_pause RECORD;
    v_duree NUMERIC;
    v_total_pauses NUMERIC;
BEGIN
    SELECT * INTO v_presence FROM presences WHERE id = p_presence_id;
    IF v_presence IS NULL THEN RETURN jsonb_build_object('error', 'Présence introuvable'); END IF;
    IF v_presence.soignant_id != auth.uid() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;

    -- Trouver la pause en cours
    SELECT * INTO v_pause FROM pauses_presence 
    WHERE presence_id = p_presence_id AND fin_le IS NULL;
    IF v_pause IS NULL THEN
        RETURN jsonb_build_object('error', 'Aucune pause en cours');
    END IF;

    -- Fermer la pause
    UPDATE pauses_presence SET fin_le = NOW() WHERE id = v_pause.id;

    v_duree := ROUND(EXTRACT(EPOCH FROM (NOW() - v_pause.debut_le)) / 60, 2);

    -- Calculer le total des pauses pour cette présence
    SELECT COALESCE(SUM(
        CASE WHEN fin_le IS NOT NULL THEN EXTRACT(EPOCH FROM (fin_le - debut_le)) / 60
        ELSE EXTRACT(EPOCH FROM (NOW() - debut_le)) / 60 END
    ), 0) INTO v_total_pauses FROM pauses_presence WHERE presence_id = p_presence_id;

    -- Mettre à jour le total sur la présence
    UPDATE presences SET 
        duree_pause_min = ROUND(v_total_pauses, 2),
        modifie_le = NOW()
    WHERE id = p_presence_id;

    RETURN jsonb_build_object('success', true, 'duree_cette_pause_min', v_duree, 'total_pauses_min', ROUND(v_total_pauses, 2));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_pointer_debut_pause(p_presence_id uuid, p_motif text DEFAULT 'DEJEUNER'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_presence RECORD;
    v_pause_en_cours RECORD;
    v_pause_id UUID;
BEGIN
    SELECT * INTO v_presence FROM presences WHERE id = p_presence_id;
    IF v_presence IS NULL THEN RETURN jsonb_build_object('error', 'Présence introuvable'); END IF;
    IF v_presence.soignant_id != auth.uid() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
    IF v_presence.pointage_arrivee_le IS NULL THEN RETURN jsonb_build_object('error', 'Vous devez d''abord pointer votre arrivée'); END IF;
    IF v_presence.pointage_depart_le IS NOT NULL THEN RETURN jsonb_build_object('error', 'La mission est déjà terminée'); END IF;

    -- Vérifier pas de pause déjà en cours
    SELECT * INTO v_pause_en_cours FROM pauses_presence 
    WHERE presence_id = p_presence_id AND fin_le IS NULL;
    IF v_pause_en_cours.id IS NOT NULL THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà une pause en cours. Terminez-la avant d''en commencer une autre.');
    END IF;

    INSERT INTO pauses_presence (presence_id, soignant_id, motif)
    VALUES (p_presence_id, auth.uid(), COALESCE(p_motif, 'DEJEUNER'))
    RETURNING id INTO v_pause_id;

    RETURN jsonb_build_object('success', true, 'pause_id', v_pause_id, 'debut', NOW());
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_planifier_serie_onboarding(p_utilisateur_id uuid, p_serie serie_onboarding_type)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  -- J0 retiré : BIENVENUE_SOIGNANT/BIENVENUE_ETABLISSEMENT envoyé immédiatement
  -- par register-soignant/register-etablissement remplit ce rôle. La série
  -- de relances commence à J+1.
  INSERT INTO serie_email_envois (utilisateur_id, serie, etape, planifie_le, statut)
  VALUES
    (p_utilisateur_id, p_serie, 'J1', now() + INTERVAL '1 day', 'PLANIFIE'),
    (p_utilisateur_id, p_serie, 'J3', now() + INTERVAL '3 days', 'PLANIFIE'),
    (p_utilisateur_id, p_serie, 'J7', now() + INTERVAL '7 days', 'PLANIFIE')
  ON CONFLICT (utilisateur_id, serie, etape) DO NOTHING;
  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_param_num(p_cle text, p_defaut numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT valeur FROM public.parametres_systeme WHERE cle = p_cle), p_defaut);
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_param_bool(p_cle text, p_defaut boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT valeur <> 0 FROM public.parametres_systeme WHERE cle = p_cle), p_defaut);
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_parrainage_verifier_seuils(p_parrainage_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p RECORD;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 25))::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
  v_nb_fraude_signals INT;
BEGIN
  SELECT * INTO v_p FROM parrainages WHERE id = p_parrainage_id;
  IF v_p.id IS NULL OR v_p.statut <> 'FILLEUL_ACTIF' THEN RETURN; END IF;

  -- Double condition : GMV encaissé ≥ seuil ET commission encaissée ≥ 4× prime
  -- (prime totale 2×prime ≤ 50 % de la commission — règle d'or §5).
  IF COALESCE(v_p.gmv_cumule_filleul, 0) < v_seuil_gmv
     OR COALESCE(v_p.commission_cumulee_filleul, 0) < 4 * v_prime THEN
    RETURN;
  END IF;

  SELECT COUNT(*) INTO v_nb_fraude_signals FROM parrainage_fraude_signals
  WHERE parrainage_id = v_p.id AND type = 'MEME_IP';
  IF v_nb_fraude_signals > 0 THEN
    UPDATE parrainages SET statut = 'FRAUDE' WHERE id = v_p.id;
    PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_p.parrain_id, p_type_acteur := 'SYSTEME',
      p_action := 'PARRAINAGE_SOIGNANT_FRAUDE', p_type_ressource := 'parrainage', p_id_ressource := v_p.id,
      p_details := jsonb_build_object('filleul_id', v_p.filleul_id, 'commission_cumulee', v_p.commission_cumulee_filleul, 'gmv_cumule', v_p.gmv_cumule_filleul, 'raison', 'MEME_IP détectée à inscription'));
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    SELECT id, 'ADMIN_PLATEFORME', 'SYSTEM', 'Parrainage fraude détectée',
      'Parrainage ' || v_p.id::text || ' : même IP parrain/filleul. Versement bloqué.', '/admin/utilisateurs'
    FROM soignants WHERE role = 'ADMIN_PLATEFORME' LIMIT 3;
    RETURN;
  END IF;

  UPDATE parrainages SET statut = 'VALIDE_EN_ATTENTE_SEUIL' WHERE id = v_p.id;
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_p.parrain_id, p_type_acteur := 'SYSTEME',
    p_action := 'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT', p_type_ressource := 'parrainage', p_id_ressource := v_p.id,
    p_details := jsonb_build_object('filleul_id', v_p.filleul_id, 'commission_cumulee', v_p.commission_cumulee_filleul, 'gmv_cumule', v_p.gmv_cumule_filleul));
  INSERT INTO public.externalisation_actions (type_action, payload, source, source_id)
  VALUES ('RECOMPENSE_PARRAINAGE_SOIGNANT', jsonb_build_object(
    'parrainage_id', v_p.id, 'parrain_id', v_p.parrain_id, 'filleul_id', v_p.filleul_id,
    'montant_parrain', v_prime, 'montant_filleul', v_prime,
    'commission_cumulee', v_p.commission_cumulee_filleul, 'gmv_cumule', v_p.gmv_cumule_filleul),
    'parrainage_soignant', v_p.id);
  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien) VALUES
    (v_p.parrain_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE', 'Prime de parrainage de ' || v_prime || '€ !',
     'Ton filleul a atteint ' || v_seuil_gmv || '€ de missions encaissées. ' || v_prime || '€ arrivent sur ton compte.', '/soignant/parrainage'),
    (v_p.filleul_id, 'SOIGNANT', 'PARRAINAGE_PRIME_VERSEE', 'Prime de parrainage de ' || v_prime || '€ !',
     'Félicitations ! ' || v_prime || '€ de prime de parrainage arrivent sur ton compte.', '/soignant/parrainage');
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_presences_detail_mission(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_presence RECORD;
    v_pauses JSONB;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;

    IF v_mission.etablissement_id != mon_etablissement_id() AND NOT est_admin() 
       AND v_mission.soignant_assigne_id != auth.uid() THEN
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;

    SELECT * INTO v_presence FROM presences WHERE mission_id = p_mission_id LIMIT 1;

    IF v_presence IS NULL THEN
        RETURN jsonb_build_object('pointage_effectue', false, 'heures_planifiees', v_mission.duree_heures);
    END IF;

    -- Récupérer les pauses détaillées
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', pp.id, 'debut', pp.debut_le, 'fin', pp.fin_le, 
        'duree_min', pp.duree_min, 'motif', pp.motif, 'en_cours', pp.fin_le IS NULL
    ) ORDER BY pp.debut_le), '[]'::JSONB) INTO v_pauses
    FROM pauses_presence pp WHERE pp.presence_id = v_presence.id;

    RETURN jsonb_build_object(
        'pointage_effectue', true,
        'heures_planifiees', v_mission.duree_heures,
        'heures_reelles', v_presence.heures_reelles,
        'pointage_arrivee', v_presence.pointage_arrivee_le,
        'pointage_depart', v_presence.pointage_depart_le,
        'methode_arrivee', v_presence.methode_pointage_arrivee,
        'methode_depart', v_presence.methode_pointage_depart,
        'retard_min', v_presence.retard_min,
        'depart_anticipe_min', v_presence.depart_anticipe_min,
        'duree_brute_min', v_presence.duree_brute_min,
        'duree_pause_min', v_presence.duree_pause_min,
        'duree_nette_min', v_presence.duree_nette_min,
        'nb_pauses', jsonb_array_length(v_pauses),
        'pauses', v_pauses,
        'distance_m', v_presence.distance_etablissement_m,
        'perimetre_valide', v_presence.perimetre_gps_valide,
        'alerte_teleportation', v_presence.alerte_teleportation,
        'alertes', v_presence.alertes_fraude,
        'valide', v_presence.valide_par_etablissement
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
 RETURNS TABLE(soignant_id uuid, prenom text, nom text, profession text, score_fiabilite integer, pool_urgence_rayon_km integer, distance_km numeric, missions_urgence_terminees bigint, en_mission_maintenant boolean, derniere_mission_chez_nous timestamp with time zone, bio text, avatar_url text, est_favori boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_etab RECORD;
BEGIN
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM p_etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : pool urgence réservé à l''établissement' USING ERRCODE = '42501';
    END IF;
    SELECT e.id, e.adresse_lat, e.adresse_lng INTO v_etab FROM etablissements e WHERE e.id = p_etablissement_id;
    IF NOT FOUND THEN RETURN; END IF;
    RETURN QUERY
    SELECT
        s.id AS soignant_id,
        s.prenom::TEXT, s.nom::TEXT, s.profession::TEXT,
        CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite::INTEGER ELSE NULL END AS score_fiabilite,
        COALESCE(s.urgence_rayon_km, 15)::INTEGER AS pool_urgence_rayon_km,
        CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            ROUND((6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(v_etab.adresse_lat)) * COS(RADIANS(s.adresse_lat)) *
                COS(RADIANS(s.adresse_lng) - RADIANS(v_etab.adresse_lng)) +
                SIN(RADIANS(v_etab.adresse_lat)) * SIN(RADIANS(s.adresse_lat))
            ))))::NUMERIC, 1)
        ELSE NULL END AS distance_km,
        (SELECT COUNT(*)::BIGINT FROM missions m WHERE m.soignant_assigne_id = s.id AND COALESCE(m.est_urgente, FALSE) = TRUE AND m.statut = 'TERMINEE') AS missions_urgence_terminees,
        EXISTS(SELECT 1 FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut = 'EN_COURS' AND NOW() BETWEEN m.debut_le AND m.fin_le) AS en_mission_maintenant,
        (SELECT MAX(m2.fin_le) FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = p_etablissement_id AND m2.statut = 'TERMINEE') AS derniere_mission_chez_nous,
        s.bio::TEXT, s.avatar_url::TEXT,
        EXISTS(SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = p_etablissement_id) AS est_favori
    FROM soignants s
    WHERE COALESCE(s.disponible_urgence, FALSE) = TRUE
      AND s.supprime_le IS NULL
      AND fn_documents_ok_pour_mission(s.id, 'TOUS')
      AND NOT fn_est_exclu(s.id, p_etablissement_id)
      AND (
          s.profession IN (
              SELECT DISTINCT m.profession_requise FROM missions m
              WHERE m.etablissement_id = p_etablissement_id
              AND m.statut IN ('OUVERTE','ASSIGNEE','EN_COURS','ABSENCE','LITIGE')
          )
          OR NOT EXISTS (
              SELECT 1 FROM missions m WHERE m.etablissement_id = p_etablissement_id
              AND m.statut IN ('OUVERTE','ASSIGNEE','EN_COURS','ABSENCE','LITIGE')
          )
      )
    ORDER BY score_fiabilite DESC NULLS LAST, distance_km NULLS LAST;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_postuler_mission(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD; v_soignant RECORD; v_rcp_valide BOOLEAN; v_choix_final TEXT;
    v_compatible BOOLEAN; v_specialite_label TEXT; v_choix_effectif TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'CANDIDATURE' THEN RETURN jsonb_build_object('error', 'Cette mission n''accepte pas les candidatures'); END IF;

    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;

    IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
      RETURN jsonb_build_object('error',
        'Votre compte est ' || v_soignant.statut_compte::text || '. Vous ne pouvez plus candidater. Pour faire un recours, écrivez à bonjour@jolene.app.');
    END IF;

    v_compatible := fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
      v_mission.profession_requise, v_mission.specialite_medicale_requise, v_mission.accepte_non_specialises);

    IF NOT v_compatible THEN
      IF v_mission.profession_requise = 'MEDECIN' AND v_mission.specialite_medicale_requise IS NOT NULL
         AND v_soignant.profession = 'MEDECIN' THEN
        SELECT label INTO v_specialite_label FROM specialites_medicales WHERE code = v_mission.specialite_medicale_requise;
        RETURN jsonb_build_object('error', 'Cette mission requiert la spécialité ' ||
          COALESCE(v_specialite_label, v_mission.specialite_medicale_requise) || '.');
      ELSIF v_mission.profession_requise IN ('IBODE', 'IADE') AND v_soignant.profession = 'IDE'
            AND COALESCE(v_mission.accepte_non_specialises, true) = false THEN
        RETURN jsonb_build_object('error', 'Cette mission ' || v_mission.profession_requise::text || ' n''accepte pas les IDE non spécialisés.');
      ELSE
        RETURN jsonb_build_object('error', 'Votre profession ne correspond pas à la mission requise (' || v_mission.profession_requise::text || ').');
      END IF;
    END IF;

    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux salariés.'); END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Cette mission est réservée aux libéraux.'); END IF;

    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Veuillez choisir votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    END IF;

    IF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_final := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_final := 'LIBERAL';
    ELSIF v_soignant.type_exercice = 'MIXTE' THEN v_choix_final := v_choix_effectif;
    ELSE v_choix_final := COALESCE(v_soignant.type_exercice, 'SALARIE'); END IF;

    IF v_choix_final = 'LIBERAL' THEN
        SELECT EXISTS(SELECT 1 FROM documents_soignants WHERE soignant_id = auth.uid() AND type_document = 'RCP_ASSURANCE'
            AND statut_verification = 'VERIFIE' AND supprime_le IS NULL
            AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) INTO v_rcp_valide;
        IF NOT v_rcp_valide THEN
            RETURN jsonb_build_object('error', 'Assurance Responsabilité Civile Professionnelle (RCP) manquante ou expirée — obligatoire pour candidater en libéral. Téléversez-la dans vos documents (ou candidatez en salarié si la mission le permet).');
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = auth.uid()) THEN
        RETURN jsonb_build_object('error', 'Vous avez déjà postulé à cette mission'); END IF;

    INSERT INTO candidatures (mission_id, soignant_id, message, statut, type_contrat_choisi)
    VALUES (p_mission_id, auth.uid(), fn_html_escape(p_message), 'EN_ATTENTE', v_choix_final);

    -- Notifier l'établissement (parité avec le chemin swipe : auparavant seul le swipe
    -- insérait CANDIDATURE_RECUE → les candidatures via le bouton "Postuler" étaient muettes).
    INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
    VALUES (v_mission.etablissement_id, 'ETABLISSEMENT', 'CANDIDATURE_RECUE',
      '📋 Nouvelle candidature reçue',
      COALESCE(v_soignant.prenom, 'Un soignant') || ' a postulé à votre mission « ' || v_mission.intitule || ' ».',
      '/etablissement/missions/' || p_mission_id);

    IF v_soignant.tous_documents_valides IS NOT TRUE THEN
        IF NOT EXISTS (
            SELECT 1 FROM notifications
            WHERE destinataire_id = auth.uid() AND type = 'RAPPEL_DOCUMENTS'
              AND cree_le > NOW() - INTERVAL '24 hours'
        ) THEN
            INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
            VALUES (auth.uid(), 'RAPPEL_DOCUMENTS', 'Validez vos documents pour être accepté',
                'Votre candidature est envoyée ! Pour que l''établissement puisse vous accepter, vos documents doivent être validés (vérification automatique en quelques minutes).',
                '/soignant/mes-documents', 'SOIGNANT');
        END IF;
        RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final, 'docs_a_completer', TRUE);
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'choix_contrat', v_choix_final);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_profession_peut_etre_liberal(p_profession text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN p_profession IN (
        'IDE', 'IADE', 'IBODE', 'SAGE_FEMME', 'KINE', 'MEDECIN',
        'PHARMACIEN', 'ORTHOPHONISTE', 'DIETETICIEN',
        'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'MANIPULATEUR_RADIO',
        'DENTISTE'
    );
    -- SALARIÉES UNIQUEMENT : AS, AES, AUXILIAIRE_PUERICULTURE (DEAP, sous
    -- supervision, pas d'autonomie d'exercice), PREPARATEUR_PHARMA.
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_professions_liberales()
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN '[
        {"code": "IDE", "label": "Infirmier(ère) Diplômé(e) d''État", "liberal": true},
        {"code": "IADE", "label": "Infirmier(ère) Anesthésiste", "liberal": true},
        {"code": "SAGE_FEMME", "label": "Sage-Femme", "liberal": true},
        {"code": "KINE", "label": "Kinésithérapeute", "liberal": true},
        {"code": "MEDECIN", "label": "Médecin", "liberal": true},
        {"code": "PHARMACIEN", "label": "Pharmacien(ne)", "liberal": true},
        {"code": "ORTHOPHONISTE", "label": "Orthophoniste", "liberal": true},
        {"code": "DIETETICIEN", "label": "Diététicien(ne)", "liberal": true},
        {"code": "ERGOTHERAPEUTE", "label": "Ergothérapeute", "liberal": true},
        {"code": "PSYCHOMOTRICIEN", "label": "Psychomotricien(ne)", "liberal": true},
        {"code": "AS", "label": "Aide-Soignant(e)", "liberal": false},
        {"code": "AES", "label": "Accompagnant Éducatif et Social", "liberal": false},
        {"code": "IBODE", "label": "Infirmier(ère) de Bloc Opératoire", "liberal": false},
        {"code": "MANIPULATEUR_RADIO", "label": "Manipulateur Radio", "liberal": false},
        {"code": "PREPARATEUR_PHARMA", "label": "Préparateur en Pharmacie", "liberal": false}
    ]'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_pool_urgence_missions_pour_soignant()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_soignant RECORD;
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', m.id,
    'intitule', m.intitule,
    'profession_requise', m.profession_requise::text,
    'specialite_medicale_requise', m.specialite_medicale_requise,
    'taux_horaire_base', m.taux_horaire_base,
    'debut_le', m.debut_le,
    'fin_le', m.fin_le,
    'service', m.service,
    'etablissement_nom', e.nom,
    'etablissement_ville', e.adresse_ville,
    'distance_km',
      CASE
        WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL THEN
          ROUND((6371 * 2 * asin(sqrt(
            power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
            cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
            power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
          )))::NUMERIC, 1)
        ELSE NULL
      END,
    'deja_candidate', EXISTS (
      SELECT 1 FROM candidatures c
      WHERE c.mission_id = m.id AND c.soignant_id = v_uid
    ),
    'statut_candidature', (
      SELECT statut FROM candidatures c
      WHERE c.mission_id = m.id AND c.soignant_id = v_uid
      LIMIT 1
    )
  ) ORDER BY
    CASE
      WHEN e.adresse_lat IS NOT NULL AND v_soignant.adresse_lat IS NOT NULL THEN
        (6371 * 2 * asin(sqrt(
          power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
          cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
          power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
        )))
      ELSE 9999
    END ASC,
    m.debut_le ASC
  ), '[]'::jsonb)
  INTO v_result
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE'
    AND COALESCE(m.est_urgente, false) = true
    AND m.debut_le > NOW()
    AND public.fn_soignant_compatible_mission(
      v_soignant.profession, v_soignant.specialite_medicale,
      m.profession_requise, m.specialite_medicale_requise,
      COALESCE(m.accepte_non_specialises, true)
    ) = true
    AND (
      e.adresse_lat IS NULL OR v_soignant.adresse_lat IS NULL OR
      (6371 * 2 * asin(sqrt(
        power(sin(radians(v_soignant.adresse_lat - e.adresse_lat) / 2), 2) +
        cos(radians(e.adresse_lat)) * cos(radians(v_soignant.adresse_lat)) *
        power(sin(radians(v_soignant.adresse_lng - e.adresse_lng) / 2), 2)
      ))) <= COALESCE(v_soignant.urgence_rayon_km, 30)
    );

  RETURN jsonb_build_object(
    'missions', v_result,
    'pool_actif', COALESCE(v_soignant.disponible_urgence, false),
    'rayon_km', COALESCE(v_soignant.urgence_rayon_km, 30),
    'sms_opt_in', COALESCE(v_soignant.pool_urgence_sms_opt_in, false)
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_postuler_mission_rate_limited(p_mission_id uuid, p_message text DEFAULT NULL::text, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;
  -- 20 candidatures / heure / utilisateur (même seuil que l'ancien wrapper).
  IF NOT fn_verifier_rate_limit(v_user_id::text, 'candidature', 20, 3600) THEN
    RETURN jsonb_build_object('error', 'Trop de candidatures en peu de temps. Réessayez plus tard.');
  END IF;
  RETURN fn_postuler_mission(p_mission_id, p_message, p_choix_contrat);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_professions_autorisees_scolarite(p_formation text, p_annee_validee integer)
 RETURNS SETOF type_profession
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT e.profession_autorisee
  FROM public.equivalences_scolarite e
  WHERE e.actif = true
    AND lower(e.formation) = lower(p_formation)
    AND p_annee_validee >= e.annee_validee_min;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_contrat_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Si le caller est le soignant, on ne laisse passer que ses propres champs de signature
  IF OLD.soignant_id = auth.uid()
     AND NOT public.est_admin()
     AND NOT public.est_admin_etablissement() THEN
    NEW.signature_etablissement := OLD.signature_etablissement;
    NEW.signature_etablissement_le := OLD.signature_etablissement_le;
    NEW.signature_image_etablissement := OLD.signature_image_etablissement;
    NEW.signature_ip_etablissement := OLD.signature_ip_etablissement;
    NEW.signature_navigateur_etablissement := OLD.signature_navigateur_etablissement;
    NEW.contenu_html := OLD.contenu_html;
    -- Statut : verrouillé SAUF transition de signature légitime déclenchée par
    -- fn_signer_contrat_soignant (drapeau de session, non posable côté client).
    IF NOT (current_setting('jolene.signature_soignant_en_cours', true) = '1'
            AND NEW.statut IN ('SIGNE_SOIGNANT', 'SIGNE_COMPLET')) THEN
      NEW.statut := OLD.statut;
    END IF;
    NEW.numero_contrat := OLD.numero_contrat;
    NEW.type_contrat := OLD.type_contrat;
    NEW.etablissement_id := OLD.etablissement_id;
    NEW.mission_id := OLD.mission_id;
    NEW.pdf_cle_s3 := OLD.pdf_cle_s3;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_api_key_secrets()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.cle_api IS DISTINCT FROM OLD.cle_api THEN
    RAISE EXCEPTION 'La clé API ne peut pas être modifiée après création';
  END IF;
  IF NEW.cle_secret IS DISTINCT FROM OLD.cle_secret THEN
    RAISE EXCEPTION 'Le secret API ne peut pas être modifié après création';
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_proposer_cloture_litige(p_litige_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_litige RECORD;
    v_user_id UUID := auth.uid();
BEGIN
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    IF v_litige IS NULL THEN RETURN jsonb_build_object('error', 'Litige introuvable'); END IF;
    
    IF v_litige.statut NOT IN ('OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'CONTESTEE', 'EN_MEDIATION') THEN
        RETURN jsonb_build_object('error', 'Ce litige ne peut plus être modifié');
    END IF;
    
    IF v_litige.soignant_id = v_user_id THEN
        UPDATE litiges SET accord_soignant = TRUE, accord_soignant_le = NOW() WHERE id = p_litige_id;
    ELSIF mon_etablissement_id() = v_litige.etablissement_id THEN
        UPDATE litiges SET accord_etablissement = TRUE, accord_etablissement_le = NOW() WHERE id = p_litige_id;
    ELSE
        RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
    
    -- Recharger après update
    SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
    
    IF COALESCE(v_litige.accord_soignant, FALSE) AND COALESCE(v_litige.accord_etablissement, FALSE) THEN
        -- Les deux parties sont d'accord → passer en EN_MEDIATION pour validation admin
        UPDATE litiges SET statut = 'EN_MEDIATION' WHERE id = p_litige_id AND statut != 'EN_MEDIATION';
        
        -- Notifier l'admin
        INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
        SELECT id, 'SYSTEM', 'Accord mutuel sur litige',
            'Les deux parties sont d''accord pour clôturer le litige. Validation admin requise.',
            '/admin/moderation', 'ADMIN'
        FROM auth.users WHERE raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME' LIMIT 1;
        
        RETURN jsonb_build_object('statut', 'accord_mutuel_en_attente_admin',
            'message', 'Les deux parties sont d''accord. L''admin Jolene validera la clôture.');
    END IF;
    
    RETURN jsonb_build_object('statut', 'en_attente', 
        'accord_soignant', v_litige.accord_soignant, 'accord_etablissement', v_litige.accord_etablissement);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_candidature_statut()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    IF auth.uid() = OLD.soignant_id THEN
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
        IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

        IF NEW.statut IS DISTINCT FROM OLD.statut THEN
            IF OLD.statut = 'EN_ATTENTE' AND NEW.statut = 'ANNULEE' THEN
                RETURN NEW;
            ELSIF OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut = 'ANNULEE' THEN
                RETURN NEW;
            ELSIF OLD.statut = 'ACCEPTEE' AND NEW.statut = 'ANNULEE'
                  AND COALESCE(current_setting('jolene.annulation_soignant_ctx', true), '') = 'true' THEN
                RETURN NEW;
            ELSE
                RAISE EXCEPTION 'Vous ne pouvez pas modifier le statut de votre candidature (% → %)', OLD.statut, NEW.statut;
            END IF;
        END IF;

        IF NEW.message IS DISTINCT FROM OLD.message AND OLD.statut != 'EN_ATTENTE' THEN
            RAISE EXCEPTION 'Vous ne pouvez plus modifier votre message';
        END IF;

        NEW.motif_refus := OLD.motif_refus;
        NEW.traite_le := OLD.traite_le;
        RETURN NEW;
    END IF;

    IF mon_etablissement_id() IS NOT NULL THEN
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;
        IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification interdite'; END IF;

        IF NEW.statut IS DISTINCT FROM OLD.statut THEN
            IF NOT (
                (OLD.statut = 'EN_ATTENTE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
                OR (OLD.statut = 'EN_ATTENTE_VALIDATION_ETAB' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE'))
                OR (OLD.statut = 'PROPOSEE' AND NEW.statut IN ('ACCEPTEE', 'REFUSEE', 'EXPIREE'))
            ) THEN
                RAISE EXCEPTION 'Transition de statut candidature non autorisée: % → %', OLD.statut, NEW.statut;
            END IF;
        END IF;

        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Accès refusé à cette candidature';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_proposer_mission_soignant(p_mission_id uuid, p_soignant_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mission RECORD; v_soignant RECORD; v_choix_persiste TEXT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF v_mission IS NULL THEN RETURN '{"error":"Mission introuvable"}'::JSONB; END IF;
    IF NOT est_admin() AND v_mission.etablissement_id != mon_etablissement_id() THEN RETURN '{"error":"Acces refuse"}'::JSONB; END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN '{"error":"La mission n est plus ouverte"}'::JSONB; END IF;
    SELECT * INTO v_soignant FROM soignants WHERE id = p_soignant_id;
    IF v_soignant IS NULL THEN RETURN '{"error":"Soignant introuvable"}'::JSONB; END IF;
    IF v_soignant.profession != v_mission.profession_requise THEN
        RETURN jsonb_build_object('error', 'Ce soignant est ' || v_soignant.profession::TEXT || ', la mission requiert un(e) ' || v_mission.profession_requise::TEXT);
    END IF;
    IF v_mission.type_contrat_recherche IS NOT NULL AND v_mission.type_contrat_recherche != 'TOUS' THEN
        IF (v_mission.type_contrat_recherche = 'SALARIE' AND v_soignant.type_exercice = 'LIBERAL')
           OR (v_mission.type_contrat_recherche = 'LIBERAL' AND v_soignant.type_exercice = 'SALARIE') THEN
            RETURN jsonb_build_object('error', 'Type d exercice incompatible avec cette mission');
        END IF;
    END IF;
    IF NOT fn_documents_ok_pour_mission(p_soignant_id, v_mission.type_contrat_recherche::text) THEN
        RETURN jsonb_build_object('error', 'Ce soignant n a pas les documents requis pour ce type de mission.');
    END IF;
    IF EXISTS (SELECT 1 FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = p_soignant_id AND statut IN ('EN_ATTENTE','PROPOSEE','ACCEPTEE')) THEN
        RETURN '{"error":"Deja propose a ce soignant"}'::JSONB;
    END IF;
    IF fn_est_exclu(p_soignant_id, v_mission.etablissement_id) THEN RETURN '{"error":"Ce soignant est dans votre liste d exclusions."}'::JSONB; END IF;
    IF p_choix_contrat IS NOT NULL AND p_choix_contrat NOT IN ('SALARIE', 'LIBERAL') THEN
        RETURN jsonb_build_object('error', 'p_choix_contrat invalide (attendu SALARIE ou LIBERAL).');
    END IF;
    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        IF p_choix_contrat IS NULL THEN
            RETURN jsonb_build_object('error', 'E16_CHOIX_CONTRAT_REQUIS',
                'message', 'Ce soignant est MIXTE et la mission accepte les deux contrats. Specifiez p_choix_contrat SALARIE ou LIBERAL.',
                'choix_requis', TRUE,
                'options', jsonb_build_array(jsonb_build_object('value', 'SALARIE', 'label', 'Salarie (CDD)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Liberal (note d honoraires)')));
        END IF;
        v_choix_persiste := p_choix_contrat;
    ELSIF v_mission.type_contrat_recherche = 'SALARIE' THEN v_choix_persiste := 'SALARIE';
    ELSIF v_mission.type_contrat_recherche = 'LIBERAL' THEN v_choix_persiste := 'LIBERAL';
    ELSIF v_soignant.type_exercice IN ('SALARIE', 'LIBERAL') THEN v_choix_persiste := v_soignant.type_exercice;
    ELSE v_choix_persiste := NULL;
    END IF;
    INSERT INTO candidatures (mission_id, soignant_id, statut, proposee_par, type_contrat_choisi)
    VALUES (p_mission_id, p_soignant_id, 'PROPOSEE', auth.uid(), v_choix_persiste);
    INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
    VALUES (p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Mission proposee',
        'On vous propose la mission "' || fn_html_escape(v_mission.intitule) || '"',
        '/soignant/missions/' || p_mission_id, 'SOIGNANT');
    RETURN jsonb_build_object('success', TRUE, 'choix_persiste', v_choix_persiste);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_bulletin_paie_immutability()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_role text := current_setting('role', true);
  v_is_admin boolean;
BEGIN
  -- Bypass : service_role et admins peuvent tout
  v_is_admin := COALESCE((SELECT public.est_admin()), false);
  IF v_role = 'service_role' OR v_is_admin THEN
    NEW.modifie_le := now();
    RETURN NEW;
  END IF;

  IF OLD.statut = 'EMIS' OR OLD.statut = 'PAYE' THEN
    IF NEW.numero_bulletin IS DISTINCT FROM OLD.numero_bulletin
       OR NEW.salaire_brut IS DISTINCT FROM OLD.salaire_brut
       OR NEW.total_cotisations_salariales IS DISTINCT FROM OLD.total_cotisations_salariales
       OR NEW.net_avant_impot IS DISTINCT FROM OLD.net_avant_impot
       OR NEW.periode_debut IS DISTINCT FROM OLD.periode_debut
       OR NEW.periode_fin IS DISTINCT FROM OLD.periode_fin
       OR NEW.soignant_id IS DISTINCT FROM OLD.soignant_id
       OR NEW.mission_id IS DISTINCT FROM OLD.mission_id
       OR NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id
       OR NEW.date_emission IS DISTINCT FROM OLD.date_emission
    THEN
      RAISE EXCEPTION 'Bulletin de paie % : modification interdite après émission (art. L3243-4 CTW). Champs verrouillés : numero, montants, dates, identités.',
        OLD.numero_bulletin;
    END IF;
  END IF;

  NEW.modifie_le := now();
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_propage_stripe_payment_intent_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.mission_id IS NOT NULL AND NEW.stripe_payment_intent_id IS NOT NULL
     AND NEW.stripe_payment_intent_id <> '' THEN
    UPDATE public.factures_honoraires
    SET stripe_payment_intent_id = NEW.stripe_payment_intent_id
    WHERE mission_id = NEW.mission_id
      AND COALESCE(type_document, 'FACTURE') = 'FACTURE'
      AND (stripe_payment_intent_id IS NULL
           OR stripe_payment_intent_id <> NEW.stripe_payment_intent_id);
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_proposer_accord_partie(p_litige_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_id UUID := mon_etablissement_id();
  v_litige RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;

  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF v_litige IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Litige introuvable'); END IF;

  IF NOT est_admin() AND v_litige.soignant_id <> v_uid AND v_litige.etablissement_id <> v_etab_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vous n''êtes pas partie au litige');
  END IF;

  IF v_litige.statut NOT IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Litige déjà en médiation ou résolu');
  END IF;

  UPDATE litiges SET statut = 'MEDIATION_EN_COURS' WHERE id = p_litige_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := CASE WHEN v_etab_id IS NOT NULL THEN 'ADMIN_ETABLISSEMENT' ELSE 'SOIGNANT' END,
    p_action := 'MEDIATION_OUVERTE', p_type_ressource := 'litige', p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('initie_par', CASE WHEN v_etab_id IS NOT NULL THEN 'etab' ELSE 'soignant' END)
  );

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  SELECT
    CASE WHEN v_etab_id IS NOT NULL THEN v_litige.soignant_id ELSE v_litige.etablissement_id END,
    CASE WHEN v_etab_id IS NOT NULL THEN 'SOIGNANT' ELSE 'ETABLISSEMENT' END,
    'LITIGE_MEDIATION',
    'Médiation litige proposée',
    'L''autre partie propose une médiation amiable. Vous avez 7 jours pour discuter et confirmer un accord.',
    CASE WHEN v_etab_id IS NOT NULL THEN '/soignant/litiges' ELSE '/etablissement/litiges' END;

  RETURN jsonb_build_object('success', true);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_mission_financials()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF current_setting('jolene.sync_in_progress', true) = 'true' THEN
        NEW.taux_horaire_base := OLD.taux_horaire_base;
        NEW.total_brut := OLD.total_brut;
        NEW.net_a_payer := OLD.net_a_payer;
        NEW.net_estime := OLD.net_estime;
        NEW.montant_ifm := OLD.montant_ifm;
        NEW.montant_icp := OLD.montant_icp;
        NEW.taux_ifm := OLD.taux_ifm;
        NEW.taux_icp := OLD.taux_icp;
        NEW.montant_majoration_nuit := OLD.montant_majoration_nuit;
        NEW.montant_majoration_dimanche := OLD.montant_majoration_dimanche;
        NEW.montant_majoration_ferie := OLD.montant_majoration_ferie;
        NEW.heures_nuit := OLD.heures_nuit;
        NEW.heures_dimanche := OLD.heures_dimanche;
        NEW.heures_ferie := OLD.heures_ferie;
        NEW.taux_commission := OLD.taux_commission;
        NEW.montant_commission_ht := OLD.montant_commission_ht;
        NEW.montant_commission_tva := OLD.montant_commission_tva;
        NEW.montant_commission_ttc := OLD.montant_commission_ttc;
        NEW.taux_rist_plafonne := OLD.taux_rist_plafonne;
        NEW.rist_plafond_applique := OLD.rist_plafond_applique;
        NEW.commission_facturee := OLD.commission_facturee;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.profession_requise := OLD.profession_requise;
        NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
        NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
        NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
        NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
        NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
        NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
        NEW.taux_commission_fige := OLD.taux_commission_fige;
        NEW.fige_le := OLD.fige_le;
        RETURN NEW;
    END IF;

    IF OLD.soignant_assigne_id = auth.uid()
       AND NOT public.est_admin()
       AND NOT public.est_admin_etablissement() THEN
        NEW.taux_horaire_base := OLD.taux_horaire_base;
        NEW.total_brut := OLD.total_brut;
        NEW.net_a_payer := OLD.net_a_payer;
        NEW.montant_ifm := OLD.montant_ifm;
        NEW.montant_icp := OLD.montant_icp;
        NEW.taux_ifm := OLD.taux_ifm;
        NEW.taux_icp := OLD.taux_icp;
        NEW.montant_majoration_nuit := OLD.montant_majoration_nuit;
        NEW.montant_majoration_dimanche := OLD.montant_majoration_dimanche;
        NEW.montant_majoration_ferie := OLD.montant_majoration_ferie;
        NEW.heures_nuit := OLD.heures_nuit;
        NEW.heures_dimanche := OLD.heures_dimanche;
        NEW.heures_ferie := OLD.heures_ferie;
        NEW.taux_commission := OLD.taux_commission;
        NEW.montant_commission_ht := OLD.montant_commission_ht;
        NEW.montant_commission_tva := OLD.montant_commission_tva;
        NEW.montant_commission_ttc := OLD.montant_commission_ttc;
        NEW.taux_rist_plafonne := OLD.taux_rist_plafonne;
        NEW.rist_plafond_applique := OLD.rist_plafond_applique;
        NEW.etablissement_id := OLD.etablissement_id;
        NEW.profession_requise := OLD.profession_requise;
        NEW.duree_heures := OLD.duree_heures;
        NEW.debut_le := OLD.debut_le;
        NEW.fin_le := OLD.fin_le;
        NEW.taux_horaire_base_fige := OLD.taux_horaire_base_fige;
        NEW.taux_majoration_nuit_fige := OLD.taux_majoration_nuit_fige;
        NEW.taux_majoration_dimanche_fige := OLD.taux_majoration_dimanche_fige;
        NEW.taux_majoration_ferie_fige := OLD.taux_majoration_ferie_fige;
        NEW.heure_debut_nuit_fige := OLD.heure_debut_nuit_fige;
        NEW.heure_fin_nuit_fige := OLD.heure_fin_nuit_fige;
        NEW.taux_commission_fige := OLD.taux_commission_fige;
        NEW.fige_le := OLD.fige_le;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_etablissement_commercial()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_is_service_role BOOLEAN;
    v_is_internal BOOLEAN;
BEGIN
    IF est_admin() THEN RETURN NEW; END IF;
    
    -- Service role (Edge Functions, cron, webhooks)
    v_is_service_role := COALESCE(
        current_setting('request.jwt.claim.role', true) = 'service_role',
        auth.uid() IS NULL
    );
    IF v_is_service_role THEN RETURN NEW; END IF;

    -- ★ Opérations internes (recalcul palier, BFA, etc.)
    v_is_internal := COALESCE(current_setting('app.internal_operation', true), '') = 'true';
    IF v_is_internal THEN RETURN NEW; END IF;

    -- Champs FINANCIERS
    IF NEW.taux_commission_negocie IS DISTINCT FROM OLD.taux_commission_negocie THEN RAISE EXCEPTION 'Modification du taux de commission non autorisée'; END IF;
    IF NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id THEN RAISE EXCEPTION 'Modification du Stripe ID non autorisée'; END IF;
    IF NEW.palier_commission_id IS DISTINCT FROM OLD.palier_commission_id THEN RAISE EXCEPTION 'Modification du palier non autorisée'; END IF;
    IF NEW.formule_abonnement IS DISTINCT FROM OLD.formule_abonnement THEN RAISE EXCEPTION 'Modification de la formule non autorisée'; END IF;
    IF NEW.mode_facturation IS DISTINCT FROM OLD.mode_facturation THEN RAISE EXCEPTION 'Modification du mode de facturation non autorisée'; END IF;
    IF NEW.chorus_pro_actif IS DISTINCT FROM OLD.chorus_pro_actif THEN RAISE EXCEPTION 'Modification Chorus Pro non autorisée'; END IF;
    IF NEW.chorus_pro_identifiant IS DISTINCT FROM OLD.chorus_pro_identifiant THEN RAISE EXCEPTION 'Modification Chorus Pro non autorisée'; END IF;
    IF NEW.delai_paiement_jours IS DISTINCT FROM OLD.delai_paiement_jours THEN RAISE EXCEPTION 'Modification du délai non autorisée'; END IF;
    IF NEW.missions_mois_precedent IS DISTINCT FROM OLD.missions_mois_precedent THEN RAISE EXCEPTION 'Modification compteur non autorisée'; END IF;
    IF NEW.palier_recalcule_le IS DISTINCT FROM OLD.palier_recalcule_le THEN RAISE EXCEPTION 'Modification date recalcul non autorisée'; END IF;
    IF NEW.groupe_sante_id IS DISTINCT FROM OLD.groupe_sante_id THEN RAISE EXCEPTION 'Modification du groupe non autorisée'; END IF;

    -- Champs VÉRIFICATION
    IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification THEN RAISE EXCEPTION 'Modification du statut de vérification non autorisée'; END IF;
    IF NEW.peut_publier_missions IS DISTINCT FROM OLD.peut_publier_missions THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.siret_verifie IS DISTINCT FROM OLD.siret_verifie THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.note_moyenne IS DISTINCT FROM OLD.note_moyenne THEN RAISE EXCEPTION 'Modification de la note non autorisée'; END IF;
    IF NEW.contrat_valide IS DISTINCT FROM OLD.contrat_valide THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.est_secteur_public IS DISTINCT FROM OLD.est_secteur_public THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.verifie_par IS DISTINCT FROM OLD.verifie_par THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.verifie_le IS DISTINCT FROM OLD.verifie_le THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.mode_paiement_commission IS DISTINCT FROM OLD.mode_paiement_commission THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_document_verification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification THEN
      RAISE EXCEPTION 'Modification du statut de vérification interdite';
    END IF;
    IF NEW.verifie_par IS DISTINCT FROM OLD.verifie_par THEN
      RAISE EXCEPTION 'Modification du vérificateur interdite';
    END IF;
    IF NEW.verifie_le IS DISTINCT FROM OLD.verifie_le THEN
      RAISE EXCEPTION 'Modification de la date de vérification interdite';
    END IF;
    IF NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet THEN
      RAISE EXCEPTION 'Modification du motif de rejet interdite';
    END IF;
    IF NEW.est_critique IS DISTINCT FROM OLD.est_critique THEN
      RAISE EXCEPTION 'Modification du caractère critique interdite';
    END IF;
    IF NEW.rappel_j7_envoye IS DISTINCT FROM OLD.rappel_j7_envoye
       OR NEW.rappel_j30_envoye IS DISTINCT FROM OLD.rappel_j30_envoye
       OR NEW.rappel_expire_envoye IS DISTINCT FROM OLD.rappel_expire_envoye THEN
      RAISE EXCEPTION 'Modification des rappels interdite';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_facture_montants()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    -- Un étab ne peut JAMAIS modifier les montants ou le numéro de facture
    IF NEW.montant_ht IS DISTINCT FROM OLD.montant_ht THEN RAISE EXCEPTION 'Modification du montant non autorisée'; END IF;
    IF NEW.montant_tva IS DISTINCT FROM OLD.montant_tva THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.montant_ttc IS DISTINCT FROM OLD.montant_ttc THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.numero_facture IS DISTINCT FROM OLD.numero_facture THEN RAISE EXCEPTION 'Modification du numéro non autorisée'; END IF;
    IF NEW.nombre_missions IS DISTINCT FROM OLD.nombre_missions THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.taux_tva IS DISTINCT FROM OLD.taux_tva THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.date_emission IS DISTINCT FROM OLD.date_emission THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_message_mission_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    -- Seul le champ 'lu' est modifiable
    NEW.mission_id := OLD.mission_id;
    NEW.auteur_id := OLD.auteur_id;
    NEW.type_auteur := OLD.type_auteur;
    NEW.contenu := OLD.contenu;
    NEW.cree_le := OLD.cree_le;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_message_chat_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    -- Seul le champ 'lu' est modifiable
    NEW.conversation_id := OLD.conversation_id;
    NEW.auteur_id := OLD.auteur_id;
    NEW.contenu := OLD.contenu;
    NEW.est_admin := OLD.est_admin;
    NEW.cree_le := OLD.cree_le;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_facture_honoraire_immutability()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN
    RETURN NEW;
  END IF;
  IF est_admin() THEN RETURN NEW; END IF;
  IF OLD.statut = 'BROUILLON' THEN RETURN NEW; END IF;

  IF NEW.montant_ht IS DISTINCT FROM OLD.montant_ht THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_ht verrouillé';
  END IF;
  IF NEW.montant_ttc IS DISTINCT FROM OLD.montant_ttc THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_ttc verrouillé';
  END IF;
  IF NEW.montant_tva IS DISTINCT FROM OLD.montant_tva THEN
    RAISE EXCEPTION 'Facture honoraire émise : montant_tva verrouillé';
  END IF;
  IF NEW.taux_tva IS DISTINCT FROM OLD.taux_tva THEN
    RAISE EXCEPTION 'Facture honoraire émise : taux_tva verrouillé';
  END IF;
  IF NEW.numero_facture IS DISTINCT FROM OLD.numero_facture THEN
    RAISE EXCEPTION 'Facture honoraire émise : numero_facture verrouillé';
  END IF;
  IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : soignant_id verrouillé';
  END IF;
  IF NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : etablissement_id verrouillé';
  END IF;
  IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : mission_id verrouillé';
  END IF;
  IF NEW.date_emission IS DISTINCT FROM OLD.date_emission THEN
    RAISE EXCEPTION 'Facture honoraire émise : date_emission verrouillée';
  END IF;
  IF NEW.type_document IS DISTINCT FROM OLD.type_document THEN
    RAISE EXCEPTION 'Facture honoraire émise : type_document verrouillé';
  END IF;
  IF NEW.facture_precedente_id IS DISTINCT FROM OLD.facture_precedente_id THEN
    RAISE EXCEPTION 'Facture honoraire émise : facture_precedente_id verrouillé';
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_creneaux_si_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission_id uuid;
  v_type_creneau text;
  v_has_facture boolean;
  v_correction_mission uuid;
  v_correction_reason text;
  v_fige_le timestamptz;
  v_override_gel_mission uuid;
  v_override_gel_reason text;
BEGIN
  v_mission_id := COALESCE(NEW.mission_id, OLD.mission_id);
  v_type_creneau := COALESCE(NEW.type_creneau, OLD.type_creneau);

  -- CHECK 1 (CP5b): PREVISIONNEL immutables après gel
  IF v_type_creneau = 'PREVISIONNEL' THEN
    SELECT fige_le INTO v_fige_le FROM missions WHERE id = v_mission_id;

    IF v_fige_le IS NOT NULL THEN
      v_override_gel_mission := NULLIF(current_setting('jolene.admin_override_gel', true), '')::uuid;
      v_override_gel_reason := NULLIF(current_setting('jolene.admin_override_reason', true), '');

      IF v_override_gel_mission = v_mission_id AND v_override_gel_reason IS NOT NULL THEN
        INSERT INTO journaux_audit
          (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
        VALUES (
          auth.uid(), 'ADMIN_PLATEFORME', 'OVERRIDE_CHAMP_POST_GEL', 'mission_creneaux',
          COALESCE(NEW.id, OLD.id),
          jsonb_build_object(
            'reason', v_override_gel_reason,
            'mission_id', v_mission_id,
            'operation', TG_OP,
            'type_creneau', 'PREVISIONNEL'
          )
        );
      ELSE
        RAISE EXCEPTION 'Créneaux PREVISIONNEL immutables après gel (mission gelée le %). Les créneaux prévisionnels ne peuvent pas être modifiés après assignation. Pour corriger, un admin doit définir jolene.admin_override_gel et jolene.admin_override_reason.',
          v_fige_le USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  -- CHECK 2 (CP3): Facture émise bloque TOUS les créneaux
  SELECT EXISTS (
    SELECT 1 FROM factures_honoraires
    WHERE mission_id = v_mission_id
      AND statut NOT IN ('BROUILLON', 'ANNULEE')
  ) INTO v_has_facture;

  IF NOT v_has_facture THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  v_correction_mission := NULLIF(current_setting('jolene.admin_correction_mission_id', true), '')::uuid;
  v_correction_reason := NULLIF(current_setting('jolene.admin_correction_reason', true), '');

  IF v_correction_mission = v_mission_id AND v_correction_reason IS NOT NULL THEN
    INSERT INTO invoice_audit_log (invoice_id, action, performed_by, payload_before)
    SELECT fh.id, 'CRENEAUX_MODIFIED_POST_FACTURE', auth.uid(),
      jsonb_build_object(
        'reason', v_correction_reason,
        'mission_id', v_mission_id,
        'operation', TG_OP,
        'creneau_id', COALESCE(NEW.id, OLD.id)
      )
    FROM factures_honoraires fh
    WHERE fh.mission_id = v_mission_id AND fh.statut NOT IN ('BROUILLON', 'ANNULEE')
    LIMIT 1;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  RAISE EXCEPTION 'Impossible de modifier les créneaux : une facture émise existe pour cette mission (mission_id=%). Pour corriger, un admin doit définir jolene.admin_correction_mission_id et jolene.admin_correction_reason.',
    v_mission_id USING ERRCODE = 'check_violation';
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_presence_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- If caller is the soignant (not admin/etablissement), block changes to integrity fields
  IF OLD.soignant_id = auth.uid() 
     AND NOT public.est_admin() 
     AND NOT public.est_admin_etablissement() THEN
    -- Prevent tampering with fraud/validation fields
    NEW.alerte_teleportation := OLD.alerte_teleportation;
    NEW.alertes_fraude := OLD.alertes_fraude;
    NEW.perimetre_gps_valide := OLD.perimetre_gps_valide;
    NEW.distance_etablissement_m := OLD.distance_etablissement_m;
    NEW.valide_par_etablissement := OLD.valide_par_etablissement;
    NEW.valide_le := OLD.valide_le;
    NEW.motif_litige := OLD.motif_litige;
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_soignant_verification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;
    IF COALESCE(current_setting('jolene.system_update', true), '') = 'true' THEN RETURN NEW; END IF;

    IF COALESCE(current_setting('jolene.rpc_update', true), '') = 'true' THEN
        IF OLD.id = auth.uid() THEN
            NEW.diplome_verifie := OLD.diplome_verifie;
            NEW.identite_verifiee := OLD.identite_verifiee;
            NEW.tous_documents_valides := OLD.tous_documents_valides;
            NEW.rpps_verifie := OLD.rpps_verifie;
            NEW.rpps_verifie_le := OLD.rpps_verifie_le;
            NEW.rpps_nom_api := OLD.rpps_nom_api;
            NEW.rpps_prenom_api := OLD.rpps_prenom_api;
            NEW.rpps_profession_api := OLD.rpps_profession_api;
            NEW.statut_verification_aria := OLD.statut_verification_aria;
            NEW.coherence_identite := OLD.coherence_identite;
            NEW.coherence_details := OLD.coherence_details;
            IF OLD.profession IS NOT NULL THEN NEW.profession := OLD.profession; END IF;
            NEW.score_fiabilite := OLD.score_fiabilite;
            NEW.note_moyenne := OLD.note_moyenne;
            NEW.total_absences := OLD.total_absences;
            NEW.total_retards_pointage := OLD.total_retards_pointage;
            NEW.total_missions_annulees := OLD.total_missions_annulees;
            NEW.total_missions_terminees := OLD.total_missions_terminees;
            NEW.heures_cumulees := OLD.heures_cumulees;
            NEW.heures_plateforme := OLD.heures_plateforme;
            NEW.stripe_account_id := OLD.stripe_account_id;
            NEW.supprime_le := OLD.supprime_le;
            NEW.parraine_par := OLD.parraine_par;
            IF OLD.rpps_verifie = TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
            IF OLD.identite_verifiee = TRUE THEN NEW.nom := OLD.nom; NEW.prenom := OLD.prenom; END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.id = auth.uid() THEN
        NEW.diplome_verifie := OLD.diplome_verifie;
        NEW.identite_verifiee := OLD.identite_verifiee;
        NEW.tous_documents_valides := OLD.tous_documents_valides;
        NEW.rpps_verifie := OLD.rpps_verifie;
        NEW.rpps_verifie_le := OLD.rpps_verifie_le;
        NEW.rpps_nom_api := OLD.rpps_nom_api;
        NEW.rpps_prenom_api := OLD.rpps_prenom_api;
        NEW.rpps_profession_api := OLD.rpps_profession_api;
        NEW.statut_verification_aria := OLD.statut_verification_aria;
        NEW.coherence_identite := OLD.coherence_identite;
        NEW.coherence_details := OLD.coherence_details;
        IF OLD.rpps_verifie = TRUE THEN NEW.numero_rpps := OLD.numero_rpps; END IF;
        IF OLD.identite_verifiee = TRUE THEN NEW.nom := OLD.nom; NEW.prenom := OLD.prenom; END IF;
        IF OLD.profession IS NOT NULL THEN NEW.profession := OLD.profession; END IF;
        NEW.type_exercice := OLD.type_exercice;
        NEW.statut_liberal := OLD.statut_liberal;
        NEW.score_fiabilite := OLD.score_fiabilite;
        NEW.note_moyenne := OLD.note_moyenne;
        NEW.total_absences := OLD.total_absences;
        NEW.total_retards_pointage := OLD.total_retards_pointage;
        NEW.total_missions_annulees := OLD.total_missions_annulees;
        NEW.total_missions_terminees := OLD.total_missions_terminees;
        NEW.heures_cumulees := OLD.heures_cumulees;
        NEW.heures_plateforme := OLD.heures_plateforme;
        NEW.eligible_conversion_3200h := OLD.eligible_conversion_3200h;
        NEW.validation_3200h_statut := OLD.validation_3200h_statut;
        NEW.stripe_account_id := OLD.stripe_account_id;
        NEW.supprime_le := OLD.supprime_le;
        NEW.parraine_par := OLD.parraine_par;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_notification_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- ★ Service role → passthrough (Edge Functions email-cron, send-push, send-email)
  IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN
    RETURN NEW;
  END IF;
  -- ★ Pas d'auth → passthrough (cron/triggers internes)
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  -- ★ Admin → passthrough
  IF est_admin() THEN
    RETURN NEW;
  END IF;

  -- Le destinataire ne peut modifier QUE lue + lue_le
  IF NEW.titre IS DISTINCT FROM OLD.titre
    OR NEW.corps IS DISTINCT FROM OLD.corps
    OR NEW.type IS DISTINCT FROM OLD.type
    OR NEW.lien IS DISTINCT FROM OLD.lien
    OR NEW.destinataire_id IS DISTINCT FROM OLD.destinataire_id
    OR NEW.type_destinataire IS DISTINCT FROM OLD.type_destinataire
    OR NEW.id_ressource IS DISTINCT FROM OLD.id_ressource
    OR NEW.type_ressource IS DISTINCT FROM OLD.type_ressource
    OR NEW.email_envoye IS DISTINCT FROM OLD.email_envoye
    OR NEW.email_envoye_le IS DISTINCT FROM OLD.email_envoye_le
    OR NEW.push_envoyee IS DISTINCT FROM OLD.push_envoyee
    OR NEW.push_envoyee_le IS DISTINCT FROM OLD.push_envoyee_le
    OR NEW.cree_le IS DISTINCT FROM OLD.cree_le
  THEN
    RAISE EXCEPTION 'Seuls les champs lue et lue_le peuvent être modifiés';
  END IF;
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_proteger_document_verification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Service role → passthrough (Edge Functions, cron)
    IF COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role' THEN RETURN NEW; END IF;
    IF auth.uid() IS NULL THEN RETURN NEW; END IF;
    
    -- Admin → passthrough
    IF est_admin() THEN RETURN NEW; END IF;

    -- Block soignants from modifying verification fields
    IF NEW.statut_verification IS DISTINCT FROM OLD.statut_verification
       OR NEW.verifie_par IS DISTINCT FROM OLD.verifie_par
       OR NEW.verifie_le IS DISTINCT FROM OLD.verifie_le
       OR NEW.valide_depuis IS DISTINCT FROM OLD.valide_depuis
       OR NEW.valide_jusqua IS DISTINCT FROM OLD.valide_jusqua
       OR NEW.motif_rejet IS DISTINCT FROM OLD.motif_rejet
       OR NEW.est_critique IS DISTINCT FROM OLD.est_critique
       OR NEW.resultat_ia IS DISTINCT FROM OLD.resultat_ia
       OR NEW.score_confiance_ia IS DISTINCT FROM OLD.score_confiance_ia
       OR NEW.nom_extrait_ia IS DISTINCT FROM OLD.nom_extrait_ia
       OR NEW.prenom_extrait_ia IS DISTINCT FROM OLD.prenom_extrait_ia
       OR NEW.coherence_nom IS DISTINCT FROM OLD.coherence_nom
    THEN
        RAISE EXCEPTION 'Modification des champs de vérification interdite'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Block soignant from changing document to another soignant
    IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN
        RAISE EXCEPTION 'Modification du propriétaire interdite';
    END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_paiement_soignant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Service role (Edge Functions) peut tout modifier
    IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN
        RETURN NEW;
    END IF;
    -- Admin peut tout modifier
    IF est_admin() THEN RETURN NEW; END IF;

    -- Soignant: ne peut modifier que confirme_par_soignant, conteste, motif_contestation, et statut vers CONFIRME/CONTESTE
    IF auth.uid() = OLD.soignant_id THEN
        IF NEW.montant_net IS DISTINCT FROM OLD.montant_net THEN RAISE EXCEPTION 'Modification du montant non autorisée'; END IF;
        IF NEW.statut IS DISTINCT FROM OLD.statut AND NEW.statut NOT IN ('CONFIRME', 'CONTESTE') THEN RAISE EXCEPTION 'Modification du statut non autorisée'; END IF;
        IF NEW.methode IS DISTINCT FROM OLD.methode THEN RAISE EXCEPTION 'Modification de la méthode non autorisée'; END IF;
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification de la mission non autorisée'; END IF;
        IF NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
        RETURN NEW;
    END IF;

    -- Établissement: peut confirmer mais pas modifier les montants
    IF mon_etablissement_id() = OLD.etablissement_id THEN
        IF NEW.montant_net IS DISTINCT FROM OLD.montant_net THEN RAISE EXCEPTION 'Modification du montant non autorisée'; END IF;
        IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification de la mission non autorisée'; END IF;
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Accès refusé';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_paiement_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    -- Personne ne peut modifier les montants des paiements mission
    IF NEW.montant_ht IS DISTINCT FROM OLD.montant_ht THEN RAISE EXCEPTION 'Modification du montant non autorisée'; END IF;
    IF NEW.montant_tva IS DISTINCT FROM OLD.montant_tva THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.montant_ttc IS DISTINCT FROM OLD.montant_ttc THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.mission_id IS DISTINCT FROM OLD.mission_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.etablissement_id IS DISTINCT FROM OLD.etablissement_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.stripe_payment_intent_id IS DISTINCT FROM OLD.stripe_payment_intent_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_stripe_transfer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN RETURN NEW; END IF;
    IF est_admin() THEN RETURN NEW; END IF;

    -- Aucun user ne peut modifier les transfers Stripe
    RAISE EXCEPTION 'Modification des transferts Stripe non autorisée. Seul le système peut modifier ces enregistrements.';
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_protect_stripe_connect_onboarding()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Service role peut tout modifier
    IF COALESCE(current_setting('request.jwt.claim.role', true) = 'service_role', auth.uid() IS NULL) THEN
        RETURN NEW;
    END IF;
    IF est_admin() THEN RETURN NEW; END IF;
    
    -- Le soignant ne peut PAS modifier ces champs
    IF NEW.stripe_account_id IS DISTINCT FROM OLD.stripe_account_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.statut IS DISTINCT FROM OLD.statut THEN RAISE EXCEPTION 'Modification du statut non autorisée'; END IF;
    IF NEW.onboarding_complete IS DISTINCT FROM OLD.onboarding_complete THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.charges_enabled IS DISTINCT FROM OLD.charges_enabled THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.payouts_enabled IS DISTINCT FROM OLD.payouts_enabled THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.details_submitted IS DISTINCT FROM OLD.details_submitted THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.iban_last4 IS DISTINCT FROM OLD.iban_last4 THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    IF NEW.soignant_id IS DISTINCT FROM OLD.soignant_id THEN RAISE EXCEPTION 'Modification non autorisée'; END IF;
    
    RETURN NEW;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_purger_gps_ancien()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE presences SET
        arrivee_lat = NULL, arrivee_lng = NULL,
        depart_lat = NULL, depart_lng = NULL,
        arrivee_precision_gps_m = NULL, depart_precision_gps_m = NULL,
        arrivee_id_terminal = NULL, depart_id_terminal = NULL,
        arrivee_modele_terminal = NULL, depart_modele_terminal = NULL
    WHERE pointage_arrivee_le < NOW() - INTERVAL '1 year'
      AND arrivee_lat IS NOT NULL;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_purger_audit_ancien()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    -- Supprimer les logs d'accès > 1 an (pas les logs financiers)
    DELETE FROM journaux_audit
    WHERE cree_le < NOW() - INTERVAL '5 years';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_purger_demo()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN '{"error":"Accès refusé"}'::JSONB; END IF;

    DELETE FROM missions WHERE etablissement_id IN (
        SELECT id FROM etablissements WHERE email_contact LIKE '%demo%' OR nom LIKE '%Pharmacie du Centre%' OR nom LIKE '%Clinique des Lilas%' OR nom LIKE '%EHPAD Résidence Soleil%' OR nom LIKE '%Leader Santé Bastille%'
    );
    DELETE FROM etablissements WHERE nom IN ('Pharmacie du Centre', 'Clinique des Lilas', 'EHPAD Résidence Soleil', 'Pharmacie Leader Santé Bastille');
    DELETE FROM soignants WHERE email LIKE 'demo.soignant.%@jolene.app';

    RETURN '{"success":true}'::JSONB;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rappel_dpae_quotidien()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_contrat RECORD; v_count int := 0;
BEGIN
  FOR v_contrat IN
    SELECT cm.id, cm.numero_contrat, cm.etablissement_id
    FROM public.contrats_mission cm
    WHERE cm.statut = 'SIGNE_COMPLET' AND cm.type_contrat IN ('CDD', 'CDD', 'SALARIE')
      AND COALESCE(cm.dpae_effectuee, false) = false
      AND cm.signature_soignant_le > NOW() - INTERVAL '7 days'
      AND cm.signature_soignant_le < NOW() - INTERVAL '1 day'
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
        body := jsonb_build_object('destinataire_id', v_contrat.etablissement_id,
          'type_evenement', 'DPAE_RAPPEL', 'titre', 'Rappel DPAE',
          'corps', 'Contrat ' || COALESCE(v_contrat.numero_contrat, '') ||
                   ' : la DPAE URSSAF doit être déclarée avant la prise de poste.',
          'data', jsonb_build_object('contrat_id', v_contrat.id,
            'lien', 'https://app.jolene.app/contrat/' || v_contrat.id::text))
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    v_count := v_count + 1;
  END LOOP;
  IF v_count > 0 THEN
    INSERT INTO public.journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES ('00000000-0000-0000-0000-000000000000', 'SYSTEME', 'SYSTEM', 'cron', NULL,
      jsonb_build_object('evenement', 'DPAE_RAPPEL_QUOTIDIEN', 'count', v_count, 'exec_le', NOW()));
  END IF;
  RETURN jsonb_build_object('success', true, 'count', v_count);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rappel_pointage_arrivee()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_mission RECORD; v_count int := 0;
BEGIN
  FOR v_mission IN
    SELECT m.id, m.intitule, m.soignant_assigne_id FROM public.missions m
    WHERE m.statut IN ('ASSIGNEE','EN_COURS')
      AND m.debut_le > NOW() - INTERVAL '2 hours'
      AND m.debut_le < NOW() - INTERVAL '30 minutes'
      AND m.soignant_assigne_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.presences p WHERE p.mission_id = m.id AND p.soignant_id = m.soignant_assigne_id)
  LOOP
    BEGIN
      PERFORM net.http_post(
        url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)),
        body := jsonb_build_object('destinataire_id', v_mission.soignant_assigne_id,
          'type_evenement', 'POINTAGE_MANQUANT',
          'titre', 'Pointez votre arrivée 📍',
          'corps', 'Mission ' || COALESCE(v_mission.intitule, '') ||
                   ' : pensez à pointer votre arrivée dans l''application.',
          'data', jsonb_build_object('mission_id', v_mission.id,
            'lien', 'https://app.jolene.app/soignant/missions/' || v_mission.id::text))
      );
    EXCEPTION WHEN OTHERS THEN NULL; END;
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('success', true, 'count', v_count);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_purger_pings_gps_anciens()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_deleted integer;
BEGIN
  DELETE FROM public.pings_gps_mission WHERE recu_le < now() - INTERVAL '30 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted > 0 THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', 'SYSTEME',
      'SYSTEM', 'fonction', NULL,
      jsonb_build_object(
        'evenement', 'PURGE_PINGS_GPS',
        'lignes_supprimees', v_deleted,
        'horodatage', now()
      )
    );
  END IF;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rebooker_soignant(p_soignant_id uuid, p_mission_modele_id uuid, p_debut timestamp with time zone, p_fin timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD; v_s RECORD; v_new_id uuid;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_modele_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission modèle introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF p_debut IS NULL OR p_fin IS NULL OR p_fin <= p_debut OR p_debut < NOW() THEN
    RETURN jsonb_build_object('error', 'Dates invalides (le début doit être dans le futur).');
  END IF;
  SELECT * INTO v_s FROM soignants WHERE id = p_soignant_id AND supprime_le IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Soignant introuvable'); END IF;
  IF v_s.profession != v_m.profession_requise THEN
    RETURN jsonb_build_object('error', 'La profession du soignant ne correspond pas à la mission modèle.');
  END IF;
  IF fn_est_exclu(p_soignant_id, v_m.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Ce soignant est dans votre liste d''exclusions.');
  END IF;

  INSERT INTO missions (
    etablissement_id, intitule, description, service,
    profession_requise, specialite_medicale_requise, accepte_non_specialises,
    debut_le, fin_le, duree_heures, taux_horaire_base,
    type_contrat_recherche, statut, mode_attribution, est_urgente, garantie_remplacement,
    mission_source
  ) VALUES (
    v_m.etablissement_id, v_m.intitule, v_m.description, v_m.service,
    v_m.profession_requise, v_m.specialite_medicale_requise, v_m.accepte_non_specialises,
    p_debut, p_fin, ROUND(EXTRACT(EPOCH FROM (p_fin - p_debut)) / 3600.0, 2), v_m.taux_horaire_base,
    v_m.type_contrat_recherche, 'OUVERTE', 'CANDIDATURE', FALSE, COALESCE(v_m.garantie_remplacement, FALSE),
    'REBOOK'
  ) RETURNING id INTO v_new_id;

  INSERT INTO notifications (destinataire_id, type, titre, corps, lien, type_destinataire)
  VALUES (p_soignant_id, 'CANDIDATURE_PROPOSEE', 'Un établissement veut retravailler avec vous ⭐',
    fn_html_escape(v_m.intitule) || ' du ' || TO_CHAR(p_debut AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
    ' au ' || TO_CHAR(p_fin AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24:MI') ||
    ' à ' || COALESCE(v_m.taux_horaire_base::text, '?') || ' €/h — vous êtes leur premier choix, postulez en 1 clic.',
    '/soignant/missions/' || v_new_id, 'SOIGNANT');

  RETURN jsonb_build_object('success', TRUE, 'mission_id', v_new_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rafraichir_donnees_matching()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Médiane des taux par profession sur les missions des 90 derniers jours.
  INSERT INTO public.marche_taux_medians (profession, taux_median, nb_missions, calcule_le)
  SELECT m.profession_requise::text,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.taux_horaire_base),
         COUNT(*)::integer,
         now()
    FROM public.missions m
   WHERE m.taux_horaire_base IS NOT NULL
     AND m.profession_requise IS NOT NULL
     AND m.cree_le > now() - interval '90 days'
   GROUP BY m.profession_requise
  HAVING COUNT(*) >= 3
  ON CONFLICT (profession) DO UPDATE SET
    taux_median = EXCLUDED.taux_median,
    nb_missions = EXCLUDED.nb_missions,
    calcule_le = EXCLUDED.calcule_le;

  -- Pattern horaire appris : ratio de likes par tranche (nuit 20h-7h / jour,
  -- weekend / semaine), lissage de Laplace (+1/+2) — neutre 0,5 sans signal.
  INSERT INTO public.matching_preferences_soignant
    (soignant_id, pref_nuit, pref_jour, pref_weekend, pref_semaine, nb_signaux, maj_le)
  SELECT agg.sid,
         (agg.likes_nuit + 1.0) / (agg.tot_nuit + 2.0),
         (agg.likes_jour + 1.0) / (agg.tot_jour + 2.0),
         (agg.likes_we   + 1.0) / (agg.tot_we   + 2.0),
         (agg.likes_sem  + 1.0) / (agg.tot_sem  + 2.0),
         agg.total::integer,
         now()
  FROM (
    SELECT b.sid,
           COUNT(*) FILTER (WHERE b.est_nuit)              AS tot_nuit,
           COUNT(*) FILTER (WHERE b.est_nuit AND b.aime)   AS likes_nuit,
           COUNT(*) FILTER (WHERE NOT b.est_nuit)           AS tot_jour,
           COUNT(*) FILTER (WHERE NOT b.est_nuit AND b.aime) AS likes_jour,
           COUNT(*) FILTER (WHERE b.est_we)                 AS tot_we,
           COUNT(*) FILTER (WHERE b.est_we AND b.aime)      AS likes_we,
           COUNT(*) FILTER (WHERE NOT b.est_we)             AS tot_sem,
           COUNT(*) FILTER (WHERE NOT b.est_we AND b.aime)  AS likes_sem,
           COUNT(*) AS total
    FROM (
      SELECT sw.soignant_id AS sid,
             (EXTRACT(HOUR FROM m.debut_le AT TIME ZONE 'Europe/Paris') >= 20
              OR EXTRACT(HOUR FROM m.debut_le AT TIME ZONE 'Europe/Paris') < 7) AS est_nuit,
             (EXTRACT(DOW FROM m.debut_le AT TIME ZONE 'Europe/Paris') IN (0, 6)) AS est_we,
             (sw.direction::text IN ('LIKE', 'SUPER_LIKE', 'FAVORI')) AS aime
        FROM public.swipes sw
        JOIN public.missions m ON m.id = sw.mission_id
       WHERE sw.created_at > now() - interval '90 days'
         AND m.debut_le IS NOT NULL
    ) b
    GROUP BY b.sid
  ) agg
  ON CONFLICT (soignant_id) DO UPDATE SET
    pref_nuit = EXCLUDED.pref_nuit,
    pref_jour = EXCLUDED.pref_jour,
    pref_weekend = EXCLUDED.pref_weekend,
    pref_semaine = EXCLUDED.pref_semaine,
    nb_signaux = EXCLUDED.nb_signaux,
    maj_le = EXCLUDED.maj_le;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recalculer_palier_commission(p_etablissement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_count INTEGER; v_groupe_id UUID; v_palier RECORD;
    v_ancien_taux NUMERIC; v_nouveau_taux NUMERIC; v_remise_groupe NUMERIC := 0;
BEGIN
    SELECT COALESCE(taux_commission_negocie, 15.00) INTO v_ancien_taux FROM etablissements WHERE id = p_etablissement_id;
    SELECT groupe_sante_id INTO v_groupe_id FROM etablissements WHERE id = p_etablissement_id;

    IF v_groupe_id IS NOT NULL THEN
        SELECT COALESCE(remise_groupe_pourcent, 0) INTO v_remise_groupe FROM groupes_sante WHERE id = v_groupe_id;
        SELECT COUNT(*) INTO v_count FROM missions m JOIN etablissements e ON e.id = m.etablissement_id
        WHERE e.groupe_sante_id = v_groupe_id AND m.statut = 'TERMINEE'
          AND m.fin_le >= date_trunc('month', NOW()) - INTERVAL '1 month' AND m.fin_le < date_trunc('month', NOW());
    ELSE
        SELECT COUNT(*) INTO v_count FROM missions m
        WHERE m.etablissement_id = p_etablissement_id AND m.statut = 'TERMINEE'
          AND m.fin_le >= date_trunc('month', NOW()) - INTERVAL '1 month' AND m.fin_le < date_trunc('month', NOW());
    END IF;

    SELECT * INTO v_palier FROM paliers_commission
    WHERE est_actif = TRUE AND missions_min <= v_count AND (missions_max IS NULL OR missions_max >= v_count)
    ORDER BY ordre DESC LIMIT 1;

    IF FOUND AND v_palier.id IS NOT NULL THEN
        v_nouveau_taux := GREATEST(5.00, v_palier.taux_commission - v_remise_groupe);

        -- Bypass trigger fn_protect_etablissement_commercial via session GUC
        -- (l'ancienne version utilisait ALTER TABLE DISABLE TRIGGER mais
        -- celui-ci provoque "cannot ALTER TABLE because it is being used
        -- by active queries" quand on est dans une boucle qui scanne la
        -- même table — cas de fn_recalculer_tous_paliers).
        PERFORM set_config('app.internal_operation', 'true', true);

        UPDATE etablissements SET taux_commission_negocie = v_nouveau_taux, palier_commission_id = v_palier.id,
            missions_mois_precedent = v_count, palier_recalcule_le = CURRENT_DATE, modifie_le = NOW()
        WHERE id = p_etablissement_id;

        IF v_groupe_id IS NOT NULL THEN
            UPDATE etablissements SET taux_commission_negocie = v_nouveau_taux, palier_commission_id = v_palier.id,
                missions_mois_precedent = v_count, palier_recalcule_le = CURRENT_DATE, modifie_le = NOW()
            WHERE groupe_sante_id = v_groupe_id;
        END IF;

        PERFORM set_config('app.internal_operation', 'false', true);
    END IF;

    RETURN jsonb_build_object('etablissement_id', p_etablissement_id, 'missions_mois_precedent', v_count,
        'ancien_taux', v_ancien_taux, 'nouveau_taux', COALESCE(v_nouveau_taux, v_ancien_taux),
        'palier', COALESCE(v_palier.nom, 'Découverte'), 'remise_groupe', v_remise_groupe, 'groupe_cumul', v_groupe_id IS NOT NULL);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recalculer_tous_paliers()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_etab IN
        SELECT DISTINCT COALESCE(groupe_sante_id::TEXT, id::TEXT) AS cle_unique, id
        FROM etablissements
        WHERE supprime_le IS NULL
    LOOP
        PERFORM fn_recalculer_palier_commission(v_etab.id);
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recalculer_tresorerie_bloquee(p_litige_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total NUMERIC(12,2);
BEGIN
  IF p_litige_id IS NULL THEN
    RETURN;
  END IF;

  SELECT COALESCE(SUM(montant_ht), 0)
    INTO v_total
    FROM public.factures_honoraires
   WHERE litige_id = p_litige_id
     AND statut_litige = 'EN_ATTENTE_LITIGE';

  UPDATE public.litiges
     SET montant_tresorerie_bloquee = v_total
   WHERE id = p_litige_id;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recalculer_commissions_post_litige()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mission            RECORD;
  v_new_brut           NUMERIC(12,2);
  v_new_commission_ht  NUMERIC(12,2);
  v_new_commission_tva NUMERIC(12,2);
  v_new_commission_ttc NUMERIC(12,2);
  v_delta_ht           NUMERIC(12,2);
  v_delta_tva          NUMERIC(12,2);
  v_delta_ttc          NUMERIC(12,2);
  v_doc_number         TEXT;
  v_doc_type           TEXT;
  v_processed_unbilled INT := 0;
  v_avoirs_emis        INT := 0;
  v_fc_emises          INT := 0;
  v_notifs_envoyees    INT := 0;
  v_mission_intitule   TEXT;
  v_litige_id          UUID;
BEGIN
  FOR v_mission IN
    SELECT id, taux_commission, facture_id, commission_facturee,
           montant_commission_ht, etablissement_id, intitule
      FROM public.missions
     WHERE commission_a_recalculer = TRUE
  LOOP
    SELECT COALESCE(SUM(fh.montant_signe), 0) INTO v_new_brut
      FROM public.factures_honoraires fh
     WHERE fh.mission_id = v_mission.id
       AND fh.statut NOT IN ('ANNULEE', 'REMPLACEE')
       AND fh.statut_litige <> 'EN_ATTENTE_LITIGE';

    v_new_commission_ht  := ROUND(v_new_brut * COALESCE(v_mission.taux_commission, 15) / 100.0, 2);
    v_new_commission_tva := ROUND(v_new_commission_ht * 0.20, 2);
    v_new_commission_ttc := v_new_commission_ht + v_new_commission_tva;

    IF v_mission.facture_id IS NULL
       AND COALESCE(v_mission.commission_facturee, FALSE) = FALSE THEN
      UPDATE public.missions
         SET montant_commission_ht  = v_new_commission_ht,
             montant_commission_tva = v_new_commission_tva,
             montant_commission_ttc = v_new_commission_ttc,
             commission_a_recalculer = FALSE
       WHERE id = v_mission.id;
      v_processed_unbilled := v_processed_unbilled + 1;
      CONTINUE;
    END IF;

    v_delta_ht := COALESCE(v_mission.montant_commission_ht, 0) - v_new_commission_ht;

    IF v_delta_ht = 0 THEN
      UPDATE public.missions SET commission_a_recalculer = FALSE
       WHERE id = v_mission.id;
      v_processed_unbilled := v_processed_unbilled + 1;
      CONTINUE;
    END IF;

    v_delta_tva := ROUND(abs(v_delta_ht) * 0.20, 2);
    v_delta_ttc := abs(v_delta_ht) + v_delta_tva;

    IF v_delta_ht > 0 THEN
      v_doc_number := public.next_avoir_commission_number(v_mission.etablissement_id);
      v_doc_type := 'AVOIR';
      INSERT INTO public.factures (
        etablissement_id, numero_facture, type_document, facture_precedente_id,
        montant_ht, montant_tva, montant_ttc, nombre_missions,
        statut, date_emission, date_echeance, periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_doc_number, 'AVOIR', v_mission.facture_id,
        v_delta_ht, v_delta_tva, v_delta_ttc, 1,
        'EMISE', now(), (now() + INTERVAL '30 days')::date,
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
      );
      v_avoirs_emis := v_avoirs_emis + 1;
    ELSE
      v_doc_number := public.next_facture_complementaire_number(v_mission.etablissement_id);
      v_doc_type := 'FACTURE_COMPLEMENTAIRE';
      INSERT INTO public.factures (
        etablissement_id, numero_facture, type_document, facture_precedente_id,
        montant_ht, montant_tva, montant_ttc, nombre_missions,
        statut, date_emission, date_echeance, periode_debut, periode_fin
      ) VALUES (
        v_mission.etablissement_id, v_doc_number, 'FACTURE_COMPLEMENTAIRE',
        v_mission.facture_id,
        abs(v_delta_ht), v_delta_tva, v_delta_ttc, 1,
        'EMISE', now(), (now() + INTERVAL '30 days')::date,
        date_trunc('month', now())::date,
        (date_trunc('month', now()) + INTERVAL '1 month' - INTERVAL '1 day')::date
      );
      v_fc_emises := v_fc_emises + 1;
    END IF;

    UPDATE public.missions
       SET montant_commission_ht  = v_new_commission_ht,
           montant_commission_tva = v_new_commission_tva,
           montant_commission_ttc = v_new_commission_ttc,
           commission_a_recalculer = FALSE
     WHERE id = v_mission.id;

    SELECT DISTINCT fh.litige_id INTO v_litige_id
      FROM public.factures_honoraires fh
     WHERE fh.mission_id = v_mission.id
       AND fh.litige_id IS NOT NULL
     ORDER BY fh.litige_id
     LIMIT 1;

    v_mission_intitule := COALESCE(v_mission.intitule, 'Mission #' || v_mission.id::text);

    PERFORM public.fn_litige_push_notification(
      v_mission.etablissement_id,
      'ETABLISSEMENT',
      'COMMISSION_AJUSTEE',
      CASE WHEN v_doc_type = 'AVOIR'
        THEN 'Avoir commission ' || v_doc_number || ' émis'
        ELSE 'Facture complémentaire ' || v_doc_number || ' émise'
      END,
      CASE WHEN v_doc_type = 'AVOIR'
        THEN 'Un avoir de ' || v_delta_ttc || ' € a été émis sur la commission de la mission "' || v_mission_intitule || '". Déduit de votre prochaine facture mensuelle.'
        ELSE 'Une facture complémentaire de ' || v_delta_ttc || ' € a été émise sur la commission de la mission "' || v_mission_intitule || '". Due aux conditions habituelles.'
      END,
      v_litige_id,
      jsonb_build_object(
        'type_document', v_doc_type,
        'numero_document', v_doc_number,
        'montant', v_delta_ttc,
        'mission_id', v_mission.id,
        'mission_intitule', v_mission_intitule,
        'etablissement_id', v_mission.etablissement_id
      )
    );
    v_notifs_envoyees := v_notifs_envoyees + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'processed_unbilled', v_processed_unbilled,
    'deferred_to_fix9_billed', 0,
    'avoirs_commission_emis', v_avoirs_emis,
    'factures_complementaires_emises', v_fc_emises,
    'notifications_envoyees', v_notifs_envoyees
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recalculer_tous_documents_valides()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM fn_calculer_tous_documents_valides(COALESCE(NEW.soignant_id, OLD.soignant_id));
  RETURN COALESCE(NEW, OLD);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rechercher_aide(p_query text DEFAULT NULL::text, p_audience text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_result jsonb;
  v_tsquery tsquery;
BEGIN
  IF p_query IS NOT NULL AND length(trim(p_query)) > 0 THEN
    -- Convertir la query en tsquery (websearch est plus tolérant aux fautes)
    v_tsquery := websearch_to_tsquery('french', p_query);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'slug', a.slug,
    'titre', a.titre,
    'audience', a.audience,
    'categorie', a.categorie,
    'extrait', LEFT(a.contenu, 200),
    'mis_a_jour_le', a.mis_a_jour_le,
    'rank', CASE WHEN v_tsquery IS NOT NULL
                 THEN ts_rank(to_tsvector('french', a.titre || ' ' || a.contenu), v_tsquery)
                 ELSE 0 END
  ) ORDER BY
    CASE WHEN v_tsquery IS NOT NULL
         THEN ts_rank(to_tsvector('french', a.titre || ' ' || a.contenu), v_tsquery)
         ELSE 0 END DESC,
    a.ordre_affichage ASC,
    a.titre ASC
  ), '[]'::jsonb)
  INTO v_result
  FROM articles_aide a
  WHERE a.publie = true
    AND (p_audience IS NULL OR a.audience = p_audience OR a.audience = 'COMMUN')
    AND (v_tsquery IS NULL OR
         to_tsvector('french', a.titre || ' ' || a.contenu) @@ v_tsquery);

  RETURN jsonb_build_object('articles', v_result, 'count', jsonb_array_length(v_result));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recalculer_score_fiabilite_soignant(p_soignant_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_new_score NUMERIC;
BEGIN
  UPDATE soignants SET
    score_fiabilite = GREATEST(0, LEAST(100,
      50.0
      + (COALESCE(total_missions_terminees, 0) * 2.0)
      - (COALESCE(total_missions_annulees, 0) * 8.0)
      - (COALESCE(total_absences, 0) * 25.0)
      - (COALESCE(total_retards_pointage, 0) * 3.0)
      - (COALESCE(total_litiges_perdus, 0) * 10.0)
      + CASE WHEN COALESCE(total_missions_terminees, 0) > 20 THEN 10.0 ELSE 0 END
      + CASE WHEN COALESCE(total_absences, 0) = 0 AND COALESCE(total_missions_terminees, 0) > 5 THEN 5.0 ELSE 0 END
      + CASE WHEN COALESCE(prevoyance_inscrit, false) THEN 3.0 ELSE 0 END
    )),
    modifie_le = NOW()
  WHERE id = p_soignant_id
  RETURNING score_fiabilite INTO v_new_score;

  RETURN v_new_score;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recalculer_scores_soignants_actifs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant record;
  v_mission record;
  v_result jsonb;
  v_count integer := 0;
  v_start timestamptz := clock_timestamp();
BEGIN
  -- 7d : médianes de marché + préférences horaires apprises, en amont du calcul.
  PERFORM public.fn_rafraichir_donnees_matching();

  -- Soignants actifs : ont swipé ou ont eu activité auth récente (24h)
  FOR v_soignant IN
    SELECT DISTINCT s.id
      FROM public.soignants s
      LEFT JOIN public.swipes sw ON sw.soignant_id = s.id
        AND sw.created_at > now() - interval '24 hours'
     WHERE sw.id IS NOT NULL
        OR EXISTS (
          SELECT 1 FROM auth.users u
           WHERE u.id = s.id AND u.last_sign_in_at > now() - interval '24 hours'
        )
     LIMIT 200
  LOOP
    FOR v_mission IN
      SELECT m.id
        FROM public.missions m
       WHERE m.statut = 'OUVERTE'
         AND m.id NOT IN (
           SELECT mission_id FROM public.swipes WHERE soignant_id = v_soignant.id
         )
       LIMIT 50
    LOOP
      v_result := public.fn_calculer_score_matching(v_soignant.id, v_mission.id);

      INSERT INTO public.matching_scores (soignant_id, mission_id, score_global, breakdown)
        VALUES (
          v_soignant.id,
          v_mission.id,
          (v_result->>'score')::integer,
          v_result->'breakdown'
        )
        ON CONFLICT (soignant_id, mission_id)
          DO UPDATE SET
            score_global = EXCLUDED.score_global,
            breakdown = EXCLUDED.breakdown,
            calcule_le = now();

      v_count := v_count + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'scores_calcules', v_count,
    'duree_ms', extract(epoch from (clock_timestamp() - v_start)) * 1000
  );
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_relancer_signatures_contrats()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_contrat RECORD;
    v_count INTEGER := 0;
    v_destinataire UUID;
BEGIN
    FOR v_contrat IN
        SELECT c.id, c.mission_id, c.soignant_id, c.etablissement_id,
               c.signature_soignant, c.signature_etablissement, c.cree_le,
               m.intitule
        FROM contrats_mission c
        JOIN missions m ON m.id = c.mission_id
        WHERE c.statut IN ('EN_ATTENTE_SIGNATURES', 'SIGNE_SOIGNANT', 'SIGNE_ETABLISSEMENT')
          AND c.cree_le + INTERVAL '24 hours' < NOW()
          AND c.cree_le + INTERVAL '72 hours' > NOW()
    LOOP
        -- Qui n'a pas signé ?
        IF NOT v_contrat.signature_soignant THEN
            v_destinataire := v_contrat.soignant_id;
        ELSIF NOT v_contrat.signature_etablissement THEN
            v_destinataire := v_contrat.etablissement_id;
        ELSE
            CONTINUE;
        END IF;

        -- Éviter les doublons de notification (max 1 relance par jour)
        IF NOT EXISTS (
            SELECT 1 FROM notifications
            WHERE id_ressource = v_contrat.id
              AND type = 'CONTRAT_A_SIGNER'
              AND cree_le > NOW() - INTERVAL '24 hours'
        ) THEN
            INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
            VALUES (
                v_destinataire,
                CASE WHEN v_destinataire = v_contrat.soignant_id THEN 'SOIGNANT' ELSE 'ETABLISSEMENT' END,
                'CONTRAT_A_SIGNER',
                'Rappel : contrat à signer',
                'Le contrat pour la mission "' || v_contrat.intitule || '" attend votre signature.',
                '/contrat/' || v_contrat.id::TEXT,
                'contrat',
                v_contrat.id
            );
            v_count := v_count + 1;
        END IF;
    END LOOP;

    -- Auto-annulation après 72h sans signature complète
    UPDATE contrats_mission SET statut = 'EXPIRE', modifie_le = NOW()
    WHERE statut IN ('EN_ATTENTE_SIGNATURES', 'SIGNE_SOIGNANT', 'SIGNE_ETABLISSEMENT')
      AND cree_le + INTERVAL '72 hours' < NOW();

    -- Annuler les missions correspondantes
    UPDATE missions SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = NOW()
    WHERE id IN (
        SELECT mission_id FROM contrats_mission
        WHERE statut = 'EXPIRE' AND modifie_le > NOW() - INTERVAL '1 minute'
    ) AND statut = 'ASSIGNEE';

    RETURN v_count;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rechercher_utilisateurs(p_query text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN '[]'::JSONB; END IF;

    RETURN (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', u.id,
            'type', CASE
                WHEN s.id IS NOT NULL THEN 'soignant'
                WHEN e.id IS NOT NULL THEN 'etablissement'
                ELSE 'inconnu'
            END,
            'nom', COALESCE(s.nom, e.nom, ''),
            'prenom', COALESCE(s.prenom, ''),
            'email', u.email,
            'profession', s.profession,
            'avatar_url', COALESCE(s.avatar_url, e.logo_url)
        )), '[]'::JSONB)
        FROM auth.users u
        LEFT JOIN soignants s ON s.id = u.id
        LEFT JOIN etablissements e ON e.id = u.id
        WHERE (
            LOWER(u.email) LIKE LOWER(p_query) || '%'
            OR LOWER(s.prenom || ' ' || s.nom) LIKE '%' || LOWER(p_query) || '%'
            OR LOWER(e.nom) LIKE '%' || LOWER(p_query) || '%'
        )
        LIMIT 10
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rejeter_virement_admin(p_facture_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_facture RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN json_build_object('error', 'Réservé aux administrateurs');
  END IF;

  SELECT id, statut INTO v_facture FROM factures WHERE id = p_facture_id;

  IF NOT FOUND THEN
    RETURN json_build_object('error', 'Facture introuvable');
  END IF;

  IF v_facture.statut != 'VIREMENT_DECLARE' THEN
    RETURN json_build_object('error', 'Cette facture n''est pas en attente de vérification de virement');
  END IF;

  UPDATE factures
     SET statut = 'EMISE',
         virement_reference = NULL,
         mode_paiement = 'STRIPE',
         modifie_le = now()
   WHERE id = p_facture_id;

  RETURN json_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_recommander_soignants(p_mission_id uuid, p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, prenom text, nom text, profession type_profession, score_fiabilite integer, distance_km numeric, missions_etab integer, missions_etablissement integer, score_matching numeric, est_favori boolean, type_exercice text, note_moyenne numeric, nb_evaluations integer, tous_documents_valides boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_etab_id UUID := mon_etablissement_id();
    v_mission RECORD;
    v_etab RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE missions.id = p_mission_id;
    IF v_mission IS NULL THEN RETURN; END IF;
    IF NOT est_admin() AND v_etab_id IS DISTINCT FROM v_mission.etablissement_id THEN
        RAISE EXCEPTION 'Accès refusé : mission non détenue par votre établissement' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_etab FROM etablissements WHERE etablissements.id = v_mission.etablissement_id;
    RETURN QUERY
    SELECT
        s.id, s.prenom, s.nom, s.profession,
        CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite::INTEGER ELSE NULL END,
        ROUND((CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
            )))
        ELSE 999 END)::NUMERIC, 1),
        (SELECT COUNT(*)::INTEGER FROM missions m2 WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = v_mission.etablissement_id AND m2.statut = 'TERMINEE'),
        (SELECT COUNT(*)::INTEGER FROM missions m2b WHERE m2b.soignant_assigne_id = s.id AND m2b.etablissement_id = v_mission.etablissement_id AND m2b.statut = 'TERMINEE') AS missions_etablissement,
        ROUND((COALESCE(s.score_fiabilite, 0) * 0.3
            + COALESCE(s.note_moyenne, 3) * 20 * 0.2
            + LEAST(100, (SELECT COUNT(*) FROM missions m3 WHERE m3.soignant_assigne_id = s.id AND m3.etablissement_id = v_mission.etablissement_id AND m3.statut = 'TERMINEE') * 10) * 0.2
            + CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
                GREATEST(0, 100 - (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                    COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                    COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                    SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
                )))))
              ELSE 0 END * 0.2
            + CASE WHEN EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id) THEN 20 ELSE 0 END
        )::NUMERIC, 1),
        EXISTS (SELECT 1 FROM favoris_etab_soignant f WHERE f.soignant_id = s.id AND f.etablissement_id = v_mission.etablissement_id),
        COALESCE(s.type_exercice, 'SALARIE'),
        CASE WHEN COALESCE(s.nb_evaluations, 0) >= 3 THEN s.note_moyenne ELSE NULL END,
        COALESCE(s.nb_evaluations, 0),
        s.tous_documents_valides
    FROM soignants s
    WHERE s.profession = v_mission.profession_requise
      AND s.supprime_le IS NULL
      AND fn_documents_ok_pour_mission(s.id, v_mission.type_contrat_recherche::text)
      AND (v_mission.type_contrat_recherche IS NULL OR v_mission.type_contrat_recherche = 'TOUS' OR s.type_exercice = 'MIXTE'
          OR (v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(s.type_exercice, 'SALARIE') IN ('SALARIE', 'MIXTE'))
          OR (v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(s.type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE')))
      AND (s.adresse_lat IS NULL OR v_etab.adresse_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
              COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
              SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
          )))) <= COALESCE(s.rayon_deplacement_km, 50))
      AND s.id NOT IN (
          SELECT m4.soignant_assigne_id FROM missions m4
          WHERE m4.soignant_assigne_id IS NOT NULL AND m4.statut IN ('ASSIGNEE', 'EN_COURS')
            AND m4.debut_le < v_mission.fin_le AND m4.fin_le > v_mission.debut_le
      )
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
    ORDER BY est_favori DESC, score_matching DESC
    LIMIT p_limit;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_rechercher_soignants_etab(p_profession text DEFAULT NULL::text, p_specialites text[] DEFAULT NULL::text[], p_ville text DEFAULT NULL::text, p_distance_max_km integer DEFAULT NULL::integer, p_type_exercice text DEFAULT NULL::text, p_note_min numeric DEFAULT NULL::numeric, p_score_min integer DEFAULT NULL::integer, p_experience_min integer DEFAULT NULL::integer, p_disponible_urgence boolean DEFAULT NULL::boolean, p_documents_valides boolean DEFAULT NULL::boolean, p_recherche_texte text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id UUID;
  v_etab_lat NUMERIC;
  v_etab_lng NUMERIC;
  v_limit INTEGER;
  v_offset INTEGER;
  v_result JSONB;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé : étab requis');
    END IF;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  IF v_etab_id IS NOT NULL AND p_distance_max_km IS NOT NULL THEN
    SELECT adresse_lat, adresse_lng INTO v_etab_lat, v_etab_lng
    FROM etablissements WHERE id = v_etab_id;
  END IF;

  WITH filtered AS (
    SELECT
      s.id, s.prenom, s.nom, s.profession, s.specialite_medicale,
      s.type_exercice, s.score_fiabilite, s.note_moyenne, s.nb_evaluations,
      s.total_missions_terminees, s.annees_experience, s.specialites,
      s.bio, s.avatar_url, s.rpps_verifie, s.tous_documents_valides,
      s.disponible_urgence, s.adresse_ville,
      s.priorite_missions_urgentes, s.badge_ambassadeur,
      CASE
        WHEN v_etab_lat IS NOT NULL AND s.adresse_lat IS NOT NULL THEN
          ROUND((6371 * 2 * asin(sqrt(
            power(sin(radians(s.adresse_lat - v_etab_lat) / 2), 2) +
            cos(radians(v_etab_lat)) * cos(radians(s.adresse_lat)) *
            power(sin(radians(s.adresse_lng - v_etab_lng) / 2), 2)
          )))::NUMERIC, 1)
        ELSE NULL
      END AS distance_km
    FROM soignants s
    WHERE s.supprime_le IS NULL
      AND (p_profession IS NULL OR p_profession = '' OR s.profession::TEXT = p_profession)
      AND (p_specialites IS NULL OR array_length(p_specialites, 1) IS NULL OR s.specialites && p_specialites)
      AND (p_ville IS NULL OR p_ville = '' OR s.adresse_ville ILIKE '%' || p_ville || '%')
      AND (p_type_exercice IS NULL OR p_type_exercice = '' OR COALESCE(s.type_exercice, 'SALARIE') = p_type_exercice)
      AND (p_note_min IS NULL OR (COALESCE(s.nb_evaluations, 0) >= 3 AND COALESCE(s.note_moyenne, 0) >= p_note_min))
      AND (p_score_min IS NULL OR (COALESCE(s.total_missions_terminees, 0) >= 3 AND COALESCE(s.score_fiabilite, 0) >= p_score_min))
      AND (p_experience_min IS NULL OR COALESCE(s.annees_experience, 0) >= p_experience_min)
      AND (p_disponible_urgence IS NULL OR COALESCE(s.disponible_urgence, false) = p_disponible_urgence)
      AND (p_documents_valides IS NULL OR COALESCE(s.tous_documents_valides, false) = p_documents_valides)
      AND (p_recherche_texte IS NULL OR p_recherche_texte = '' OR
           s.prenom ILIKE '%' || p_recherche_texte || '%' OR
           COALESCE(s.bio, '') ILIKE '%' || p_recherche_texte || '%')
  ),
  with_distance AS (
    SELECT * FROM filtered
    WHERE p_distance_max_km IS NULL
       OR distance_km IS NULL
       OR distance_km <= p_distance_max_km
  ),
  ranked AS (
    SELECT *,
      ROW_NUMBER() OVER (ORDER BY
        CASE WHEN COALESCE(total_missions_terminees, 0) >= 3 THEN score_fiabilite ELSE -1 END DESC NULLS LAST,
        CASE WHEN COALESCE(nb_evaluations, 0) >= 3 THEN note_moyenne ELSE -1 END DESC NULLS LAST,
        COALESCE(total_missions_terminees, 0) DESC,
        id
      ) AS rn,
      COUNT(*) OVER () AS total_count
    FROM with_distance
  ),
  paged AS (
    SELECT * FROM ranked
    WHERE rn > v_offset AND rn <= v_offset + v_limit
  )
  SELECT jsonb_build_object(
    'soignants', COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'prenom', p.prenom,
      'nom_initiale', LEFT(p.nom, 1) || '.',
      'profession', p.profession::TEXT,
      'specialite_medicale', p.specialite_medicale,
      'type_exercice', COALESCE(p.type_exercice, 'SALARIE'),
      'score_fiabilite', CASE WHEN COALESCE(p.total_missions_terminees, 0) >= 3 THEN p.score_fiabilite ELSE NULL END,
      'note_moyenne', CASE WHEN COALESCE(p.nb_evaluations, 0) >= 3 THEN p.note_moyenne ELSE NULL END,
      'nb_evaluations', COALESCE(p.nb_evaluations, 0),
      'total_missions_terminees', COALESCE(p.total_missions_terminees, 0),
      'annees_experience', p.annees_experience,
      'specialites', COALESCE(p.specialites, ARRAY[]::TEXT[]),
      'bio_extrait', LEFT(COALESCE(p.bio, ''), 200),
      'avatar_url', p.avatar_url,
      'rpps_verifie', COALESCE(p.rpps_verifie, false),
      'tous_documents_valides', COALESCE(p.tous_documents_valides, false),
      'disponible_urgence', COALESCE(p.disponible_urgence, false),
      'ville', p.adresse_ville,
      'distance_km', p.distance_km,
      'priorite_missions_urgentes', COALESCE(p.priorite_missions_urgentes, false),
      'badge_ambassadeur', COALESCE(p.badge_ambassadeur, false)
    ) ORDER BY p.rn), '[]'::jsonb),
    'count_total', COALESCE(MAX(p.total_count), 0),
    'limit', v_limit,
    'offset', v_offset
  ) INTO v_result
  FROM paged p;

  RETURN COALESCE(v_result, jsonb_build_object('soignants', '[]'::jsonb, 'count_total', 0, 'limit', v_limit, 'offset', v_offset));
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_regenerer_qr_mission(p_mission_id uuid, p_type text DEFAULT 'UNIVERSEL'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- Wrapper qui invalide l'ancien et génère un nouveau (idem à
  -- fn_generer_qr_mission grâce au UPDATE ... actif=false interne)
  RETURN public.fn_generer_qr_mission(p_mission_id, p_type);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_relancer_missions_sans_candidat()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_relancer_candidatures_en_attente()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  v_nb integer := 0;
  v_delai interval := (public.fn_param_num('delai_relance_candidatures_h', 24)::text || ' hours')::interval;
BEGIN
  FOR r IN
    SELECT m.id, m.etablissement_id, m.intitule,
           count(c.id) AS nb_attente,
           min(c.cree_le) AS plus_ancienne
    FROM missions m
    JOIN candidatures c ON c.mission_id = m.id AND c.statut = 'EN_ATTENTE'
    WHERE m.statut = 'OUVERTE'
    GROUP BY m.id, m.etablissement_id, m.intitule, m.derniere_relance_candidatures_le
    HAVING min(c.cree_le) < now() - v_delai
       AND (m.derniere_relance_candidatures_le IS NULL
            OR m.derniere_relance_candidatures_le < now() - v_delai)
  LOOP
    PERFORM public.fn_creer_notification(
      r.etablissement_id, 'ETABLISSEMENT', 'RAPPEL_CANDIDATURES',
      r.nb_attente || ' candidature(s) en attente',
      'Vous avez ' || r.nb_attente || ' candidature(s) à traiter sur « ' || r.intitule ||
        ' », dont la plus ancienne depuis plus de 24h. Répondez vite pour ne pas perdre le soignant.',
      '/etablissement/missions/' || r.id::text,
      'mission', r.id
    );
    UPDATE missions SET derniere_relance_candidatures_le = now() WHERE id = r.id;
    v_nb := v_nb + 1;
  END LOOP;
  RETURN v_nb;
END;
$function$

---FIN-FONCTION---

