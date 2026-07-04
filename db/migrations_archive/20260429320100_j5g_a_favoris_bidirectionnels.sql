-- J5.G.A — Favoris bidirectionnels (rename + nouvelle table + RPCs + trigger + audit + notif type)
--
-- 1) Rename ancienne table favoris (étab favorise soignant)
ALTER TABLE IF EXISTS public.favoris RENAME TO favoris_etab_soignant;

-- ALTER POLICY ne supporte pas IF EXISTS en SQL standard ; on défensive via DO bloc
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname='pol_fav_select' AND polrelid='public.favoris_etab_soignant'::regclass) THEN
    ALTER POLICY pol_fav_select ON public.favoris_etab_soignant RENAME TO pol_fav_es_select;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname='pol_fav_insert' AND polrelid='public.favoris_etab_soignant'::regclass) THEN
    ALTER POLICY pol_fav_insert ON public.favoris_etab_soignant RENAME TO pol_fav_es_insert;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polname='pol_fav_delete' AND polrelid='public.favoris_etab_soignant'::regclass) THEN
    ALTER POLICY pol_fav_delete ON public.favoris_etab_soignant RENAME TO pol_fav_es_delete;
  END IF;
EXCEPTION WHEN undefined_table THEN
  -- Si la table n'existe pas (cas où le rename précédent a aussi échoué)
  NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS favoris_etab_soignant_unique
  ON public.favoris_etab_soignant (etablissement_id, soignant_id);

-- 2) Nouvelle table favoris_soignant_etab
CREATE TABLE IF NOT EXISTS public.favoris_soignant_etab (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  soignant_id UUID NOT NULL REFERENCES public.soignants(id) ON DELETE CASCADE,
  etablissement_id UUID NOT NULL REFERENCES public.etablissements(id) ON DELETE CASCADE,
  cree_le TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (soignant_id, etablissement_id)
);

ALTER TABLE public.favoris_soignant_etab ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_fav_se_select ON public.favoris_soignant_etab;
CREATE POLICY pol_fav_se_select ON public.favoris_soignant_etab FOR SELECT
  USING (soignant_id = auth.uid() OR (SELECT est_admin()));

DROP POLICY IF EXISTS pol_fav_se_insert ON public.favoris_soignant_etab;
CREATE POLICY pol_fav_se_insert ON public.favoris_soignant_etab FOR INSERT
  WITH CHECK (soignant_id = auth.uid());

DROP POLICY IF EXISTS pol_fav_se_delete ON public.favoris_soignant_etab;
CREATE POLICY pol_fav_se_delete ON public.favoris_soignant_etab FOR DELETE
  USING (soignant_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.favoris_soignant_etab TO authenticated;
GRANT ALL ON public.favoris_soignant_etab TO service_role;

CREATE INDEX IF NOT EXISTS idx_favoris_se_soignant ON public.favoris_soignant_etab (soignant_id);
CREATE INDEX IF NOT EXISTS idx_favoris_se_etab ON public.favoris_soignant_etab (etablissement_id);

-- 3) Audit constraint étendu : FAVORI_AJOUTE, FAVORI_RETIRE
ALTER TABLE public.journaux_audit DROP CONSTRAINT IF EXISTS journaux_audit_action_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK (action = ANY (ARRAY[
  'INSCRIPTION','CONNEXION','DECONNEXION','MODIFICATION_PROFIL','SUPPRESSION_COMPTE',
  'UPLOAD_DOCUMENT','TELECHARGEMENT_DOCUMENT','VERIFICATION_DOCUMENT','VERIFICATION_RPPS',
  'CREATION_MISSION','MODIFICATION_MISSION','ANNULATION_MISSION','CANDIDATURE','ASSIGNATION',
  'POINTAGE','SIGNATURE_CONTRAT','EVALUATION','PAIEMENT','FACTURATION',
  'DONNEES_PERSO_CONSULTATION','DONNEES_PERSO_EXPORT','DONNEES_PERSO_SUPPRESSION',
  'ADMIN_ACTION','SYSTEM','RIB_CONSULTE','RIB_PARTAGE','CONTRAT_SIGNE',
  'DOCUMENT_CONSULTATION','DOCUMENT_TELEVERSEMENT','DONNEES_PERSO_MODIFICATION',
  'EXPORT_RH_PAIE','FINANCE_FACTURE_PAYEE','MISSION_ASSIGNATION','MISSION_CREATION',
  'RGPD_EXPORT_DONNEES','RGPD_SUPPRESSION_COMPTE','RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT',
  'DEGEL_APPLIED','OVERRIDE_CHAMP_POST_GEL','GEL_APPLIED','OVERRIDE_ANTI_SEED',
  'CONNECT_METADATA_MANQUANTE','DOCUMENT_VERIFICATION_AUTO',
  'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE','FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE',
  'FINANCE_CHARGE_EXPIRED','FINANCE_CHARGE_FAILED','FINANCE_CHARGE_PENDING',
  'FINANCE_CHARGE_REFUNDED','FINANCE_DISPUTE_CLOSE','FINANCE_DISPUTE_OUVERTE',
  'FINANCE_PAYOUT_CANCELED','FINANCE_PAYOUT_CREATED','FINANCE_PAYOUT_FAILED',
  'FINANCE_PAYOUT_PAID','FINANCE_SEPA_CAPTURE','FINANCE_TRANSFER_CONNECT',
  'FINANCE_TRANSFER_CREATED','FINANCE_TRANSFER_FAILED','FINANCE_TRANSFER_REVERSED',
  'FINANCE_TRANSFER_UPDATED','STRIPE_CHECKOUT_ORPHANED_RECOVERED',
  'STRIPE_CONNECT_ACCOUNT_DELETED','ATTESTATION_SANTE_SIGNEE',
  'EXCLUSION_CREEE','EXCLUSION_SUPPRIMEE','FACTURE_GENEREE',
  'MISSION_ANNULATION_SERIE','MISSION_MODIFICATION','PAIEMENT_SOIGNANT_DECLARE_ETAB',
  'RECLAMATION_CREEE','ADMIN_CONSULTATION_ETABLISSEMENT','ADMIN_CONSULTATION_SOIGNANT',
  'DOCUMENT_SUPPRESSION','HEURES_EXTERNES_DECLAREES','MISSION_ANNULATION',
  'NOTE_HONORAIRES_GENEREE','PRESENCE_CONTESTATION','PRESENCE_POINTAGE_ARRIVEE',
  'PRESENCE_VALIDATION','PRESENCE_VALIDATION_LOT','RGPD_CONSENTEMENT_DONNE',
  'PAIEMENT_MONTANT_ECART','FACTURE_COMMISSION_CREATED_VIA_STRIPE',
  'TAUX_COMMISSION_MODIFIE','LITIGE_GEL_SCOPE_MODIFIE','PREFERENCE_NOTIFICATION_MODIFIEE',
  'NOTIFICATION_SKIPPED','SERIE_EMAIL_ENVOYE','SERIE_EMAIL_SKIPPED',
  'FILTRE_CREE','FILTRE_MODIFIE','FILTRE_SUPPRIME',
  'ALERTE_ACTIVEE','ALERTE_DESACTIVEE','ALERTE_ENVOYEE',
  'POOL_URGENCE_NOTIFICATIONS_ENVOYEES','POOL_URGENCE_ACCEPTATION_RAPIDE',
  'POOL_URGENCE_VALIDATION_ETAB','POOL_URGENCE_REFUS_ETAB','POOL_URGENCE_SMS_TOGGLE',
  'FAVORI_AJOUTE','FAVORI_RETIRE'
]));

-- 4) Notifications type FAVORI_NOUVELLE_MISSION
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'CANDIDATURE_ACCEPTEE','CANDIDATURE_REFUSEE','CANDIDATURE_PROPOSEE',
  'MISSION_ACCEPTEE','MISSION_ANNULEE','MISSION_TERMINEE','MISSION_URGENTE','MISSION_NON_POURVUE','MISSION_ASSIGNEE',
  'CONTRAT_A_SIGNER','CONTRAT_SIGNE','FACTURE_EMISE','FACTURE_PAYEE',
  'DOCUMENT_EXPIRANT','RAPPEL_DOCUMENTS','DOCUMENT_VERIFIE','DOCUMENT_REJETE',
  'MESSAGE_RECU','MESSAGE_ADMIN','POINTAGE_ARRIVEE','POINTAGE_DEPART','EVALUATION_RECUE','PARRAINAGE',
  'RAPPEL_MISSION','POOL_URGENCE','POOL_URGENCE_ACCEPTATION','SYSTEM',
  'LITIGE_OUVERT','LITIGE_REPONSE','LITIGE_RESOLU','LITIGE_MEDIATION',
  'CHORUS_DEPOSEE','CHORUS_MISE_A_DISPOSITION','CHORUS_PAIEMENT_EN_COURS','CHORUS_PAIEMENT_COMPTABILISE','CHORUS_REJETEE',
  'FAVORI_NOUVELLE_MISSION'
]));

-- 5) RPC fn_toggle_favori_etablissement (soignant)
CREATE OR REPLACE FUNCTION public.fn_toggle_favori_etablissement(
  p_etablissement_id UUID, p_actif BOOLEAN
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_etab_existe BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Non authentifié');
  END IF;

  SELECT EXISTS (SELECT 1 FROM etablissements WHERE id = p_etablissement_id) INTO v_etab_existe;
  IF NOT v_etab_existe THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  IF p_actif THEN
    INSERT INTO favoris_soignant_etab (soignant_id, etablissement_id)
    VALUES (v_uid, p_etablissement_id)
    ON CONFLICT (soignant_id, etablissement_id) DO NOTHING;
    PERFORM public.fn_ecrire_audit_safe(v_uid, 'SOIGNANT', 'FAVORI_AJOUTE', 'etablissement', p_etablissement_id, jsonb_build_object('sens', 'soignant_etab'));
  ELSE
    DELETE FROM favoris_soignant_etab
    WHERE soignant_id = v_uid AND etablissement_id = p_etablissement_id;
    PERFORM public.fn_ecrire_audit_safe(v_uid, 'SOIGNANT', 'FAVORI_RETIRE', 'etablissement', p_etablissement_id, jsonb_build_object('sens', 'soignant_etab'));
  END IF;

  RETURN jsonb_build_object('success', true, 'actif', p_actif);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_toggle_favori_etablissement(UUID, BOOLEAN) TO authenticated;

-- 6) RPC fn_mes_favoris_etablissements (soignant) — colonne `type` (pas type_etablissement)
CREATE OR REPLACE FUNCTION public.fn_mes_favoris_etablissements()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error', 'Non authentifié'); END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'etablissement_id', e.id,
    'nom', e.nom,
    'ville', e.adresse_ville,
    'logo_url', e.logo_url,
    'type_etablissement', e.type,
    'nb_missions_ouvertes', (
      SELECT count(*) FROM missions m
      WHERE m.etablissement_id = e.id AND m.statut = 'OUVERTE' AND m.debut_le > NOW()
    ),
    'cree_le', f.cree_le
  ) ORDER BY f.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM favoris_soignant_etab f
  JOIN etablissements e ON e.id = f.etablissement_id
  WHERE f.soignant_id = v_uid;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mes_favoris_etablissements() TO authenticated;

-- 7) RPC fn_mes_favoris_soignants (étab) — RGPD
CREATE OR REPLACE FUNCTION public.fn_mes_favoris_soignants()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab_id UUID;
  v_result JSONB;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object('error', 'Accès refusé');
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'soignant_id', s.id,
    'prenom', s.prenom,
    'nom_initiale', LEFT(s.nom, 1) || '.',
    'profession', s.profession::text,
    'specialite_medicale', s.specialite_medicale,
    'avatar_url', s.avatar_url,
    'score_fiabilite', CASE WHEN COALESCE(s.total_missions_terminees, 0) >= 3 THEN s.score_fiabilite ELSE NULL END,
    'note_moyenne', CASE WHEN COALESCE(s.nb_evaluations, 0) >= 3 THEN s.note_moyenne ELSE NULL END,
    'rpps_verifie', COALESCE(s.rpps_verifie, false),
    'tous_documents_valides', COALESCE(s.tous_documents_valides, false),
    'disponible_urgence', COALESCE(s.disponible_urgence, false),
    'cree_le', f.cree_le
  ) ORDER BY f.cree_le DESC), '[]'::jsonb)
  INTO v_result
  FROM favoris_etab_soignant f
  JOIN soignants s ON s.id = f.soignant_id
  WHERE (f.etablissement_id = v_etab_id OR est_admin())
    AND s.supprime_le IS NULL;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_mes_favoris_soignants() TO authenticated;

-- 8) Trigger fn_trg_favori_nouvelle_mission AFTER INSERT missions
CREATE OR REPLACE FUNCTION public.fn_trg_favori_nouvelle_mission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_etab RECORD;
  v_soignant_id UUID;
  v_url TEXT;
  v_token TEXT;
BEGIN
  IF TG_OP <> 'INSERT' OR NEW.statut <> 'OUVERTE' THEN RETURN NEW; END IF;

  SELECT id, nom, adresse_ville INTO v_etab FROM etablissements WHERE id = NEW.etablissement_id;

  BEGIN
    v_url := public.fn_lire_secret_cron('supabase_url');
    v_token := public.fn_lire_secret_cron('service_role_key');
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL; v_token := NULL;
  END;

  FOR v_soignant_id IN
    SELECT f.soignant_id FROM favoris_soignant_etab f
    JOIN soignants s ON s.id = f.soignant_id AND s.supprime_le IS NULL
    WHERE f.etablissement_id = NEW.etablissement_id
      AND public.fn_soignant_compatible_mission(
        s.profession, s.specialite_medicale,
        NEW.profession_requise, NEW.specialite_medicale_requise,
        COALESCE(NEW.accepte_non_specialises, true)
      ) = true
  LOOP
    IF public.fn_doit_notifier(v_soignant_id, 'FAVORI_NOUVELLE_MISSION'::type_evenement_notification, 'IN_APP'::canal_notification) THEN
      INSERT INTO notifications (
        destinataire_id, type_destinataire, type, titre, corps, lien,
        type_ressource, id_ressource
      ) VALUES (
        v_soignant_id, 'SOIGNANT', 'FAVORI_NOUVELLE_MISSION',
        '⭐ Nouvelle mission chez ' || v_etab.nom,
        v_etab.nom || ' a publié "' || COALESCE(NEW.intitule, NEW.profession_requise::text)
          || '" à ' || COALESCE(v_etab.adresse_ville, 'votre zone')
          || ' · ' || COALESCE(NEW.taux_horaire_base::text, '?') || '€/h.',
        '/soignant/missions/' || NEW.id::text,
        'mission', NEW.id
      );
    END IF;

    IF v_url IS NOT NULL AND v_token IS NOT NULL
       AND public.fn_doit_notifier(v_soignant_id, 'FAVORI_NOUVELLE_MISSION'::type_evenement_notification, 'EMAIL'::canal_notification) THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token),
          body := jsonb_build_object(
            'type', 'FAVORI_NOUVELLE_MISSION',
            'destinataire_id', v_soignant_id,
            'data', jsonb_build_object(
              'mission_id', NEW.id, 'mission_intitule', NEW.intitule,
              'etab_nom', v_etab.nom, 'etab_ville', v_etab.adresse_ville,
              'taux_horaire', NEW.taux_horaire_base, 'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_favori_nouvelle_mission ON public.missions;
CREATE TRIGGER trg_favori_nouvelle_mission
  AFTER INSERT ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_favori_nouvelle_mission();

-- 9) Update fn_pool_urgence_etablissement (FROM favoris → FROM favoris_etab_soignant)
CREATE OR REPLACE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
RETURNS TABLE(soignant_id uuid, prenom text, nom text, profession text, score_fiabilite integer, pool_urgence_rayon_km integer, distance_km numeric, missions_urgence_terminees bigint, en_mission_maintenant boolean, derniere_mission_chez_nous timestamp with time zone, bio text, avatar_url text, est_favori boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_etab RECORD;
BEGIN
    SELECT e.id, e.adresse_lat, e.adresse_lng INTO v_etab
    FROM etablissements e WHERE e.id = p_etablissement_id;
    IF NOT FOUND THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        s.id AS soignant_id,
        s.prenom::TEXT, s.nom::TEXT, s.profession::TEXT,
        COALESCE(s.score_fiabilite, 0)::INTEGER AS score_fiabilite,
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
      AND s.tous_documents_valides = TRUE
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
    ORDER BY score_fiabilite DESC, distance_km NULLS LAST;
END;
$function$;

-- 10) Update fn_recommander_soignants (FROM favoris → FROM favoris_etab_soignant + tri est_favori en premier)
CREATE OR REPLACE FUNCTION public.fn_recommander_soignants(p_mission_id uuid, p_limit integer DEFAULT 20)
RETURNS TABLE(id uuid, prenom text, nom text, profession type_profession, score_fiabilite integer, distance_km numeric, missions_etab integer, missions_etablissement integer, score_matching numeric, est_favori boolean, type_exercice text, note_moyenne numeric, nb_evaluations integer, tous_documents_valides boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_etab RECORD;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE missions.id = p_mission_id;
    SELECT * INTO v_etab FROM etablissements WHERE etablissements.id = v_mission.etablissement_id;

    RETURN QUERY
    SELECT
        s.id, s.prenom, s.nom, s.profession,
        s.score_fiabilite::INTEGER,
        ROUND((CASE WHEN s.adresse_lat IS NOT NULL AND v_etab.adresse_lat IS NOT NULL THEN
            6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
                COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
                COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
                SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
            )))
        ELSE 999 END)::NUMERIC, 1),
        (SELECT COUNT(*)::INTEGER FROM missions m2
         WHERE m2.soignant_assigne_id = s.id AND m2.etablissement_id = v_mission.etablissement_id AND m2.statut = 'TERMINEE'),
        (SELECT COUNT(*)::INTEGER FROM missions m2b
         WHERE m2b.soignant_assigne_id = s.id AND m2b.etablissement_id = v_mission.etablissement_id AND m2b.statut = 'TERMINEE') AS missions_etablissement,
        ROUND((
            s.score_fiabilite * 0.3
            + COALESCE(s.note_moyenne, 3) * 20 * 0.2
            + LEAST(100, (SELECT COUNT(*) FROM missions m3
                WHERE m3.soignant_assigne_id = s.id AND m3.etablissement_id = v_mission.etablissement_id AND m3.statut = 'TERMINEE') * 10) * 0.2
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
        s.note_moyenne,
        s.nb_evaluations,
        s.tous_documents_valides
    FROM soignants s
    WHERE s.profession = v_mission.profession_requise
      AND s.supprime_le IS NULL
      AND s.tous_documents_valides = TRUE
      AND (
          v_mission.type_contrat_recherche IS NULL
          OR v_mission.type_contrat_recherche = 'TOUS'
          OR s.type_exercice = 'MIXTE'
          OR (v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(s.type_exercice, 'SALARIE') IN ('SALARIE', 'MIXTE'))
          OR (v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(s.type_exercice, 'SALARIE') IN ('LIBERAL', 'MIXTE'))
      )
      AND (s.adresse_lat IS NULL OR v_etab.adresse_lat IS NULL
          OR (6371 * ACOS(LEAST(1.0, GREATEST(-1.0,
              COS(RADIANS(s.adresse_lat)) * COS(RADIANS(v_etab.adresse_lat)) *
              COS(RADIANS(v_etab.adresse_lng) - RADIANS(s.adresse_lng)) +
              SIN(RADIANS(s.adresse_lat)) * SIN(RADIANS(v_etab.adresse_lat))
          )))) <= COALESCE(s.rayon_deplacement_km, 50)
      )
      AND s.id NOT IN (
          SELECT m4.soignant_assigne_id FROM missions m4
          WHERE m4.soignant_assigne_id IS NOT NULL AND m4.statut IN ('ASSIGNEE', 'EN_COURS')
            AND m4.debut_le < v_mission.fin_le AND m4.fin_le > v_mission.debut_le
      )
      AND NOT fn_est_exclu(s.id, v_mission.etablissement_id)
    ORDER BY est_favori DESC, score_matching DESC
    LIMIT p_limit;
END;
$function$;

-- 11) fn_exporter_mes_donnees v5 : 26 clés (ajout favoris_etablissements)
CREATE OR REPLACE FUNCTION public.fn_exporter_mes_donnees()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT jsonb_build_object(
    'export_date', NOW(),
    'utilisateur_id', v_uid,
    'profil', (SELECT to_jsonb(s.*) - 'numero_secu' - 'numero_securite_sociale' FROM soignants s WHERE id = v_uid),
    'missions', (SELECT COALESCE(jsonb_agg(to_jsonb(m.*) - 'taux_commission' - 'montant_commission_ht' - 'montant_commission_tva' - 'montant_commission_ttc' ORDER BY m.cree_le DESC), '[]'::jsonb) FROM missions m WHERE m.soignant_assigne_id = v_uid),
    'candidatures', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.cree_le DESC), '[]'::jsonb) FROM candidatures c WHERE c.soignant_id = v_uid),
    'presences', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM presences p WHERE p.soignant_id = v_uid),
    'factures_honoraires', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',f.id,'numero_facture',f.numero_facture,'mission_id',f.mission_id,'etablissement_id',f.etablissement_id,'montant_ht',f.montant_ht,'montant_ttc',f.montant_ttc,'taux_tva',f.taux_tva,'exoneration_tva',f.exoneration_tva,'date_emission',f.date_emission,'date_echeance',f.date_echeance,'date_paiement',f.date_paiement,'statut',f.statut,'type_document',f.type_document,'pdf_s3_key',f.pdf_s3_key) ORDER BY f.date_emission DESC), '[]'::jsonb) FROM factures_honoraires f WHERE f.soignant_id = v_uid),
    'bulletins_paie', (SELECT COALESCE(jsonb_agg(to_jsonb(b.*) ORDER BY b.periode_debut DESC), '[]'::jsonb) FROM bulletins_paie b WHERE b.soignant_id = v_uid),
    'cotisations_sociales', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.calcule_le DESC), '[]'::jsonb) FROM cotisations_sociales c WHERE c.soignant_id = v_uid),
    'mandats_facturation', (SELECT COALESCE(jsonb_agg(jsonb_build_object('version',version,'signed_at',signed_at,'revoked_at',revoked_at,'ip_address',ip_address,'contenu_hash',contenu_hash) ORDER BY signed_at DESC), '[]'::jsonb) FROM mandats_facturation_signatures WHERE soignant_id = v_uid),
    'cessions_creance', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.signed_at DESC), '[]'::jsonb) FROM cessions_creance c WHERE c.soignant_id = v_uid),
    'factor_advances', (SELECT COALESCE(jsonb_agg(to_jsonb(fa.*) ORDER BY fa.cree_le DESC), '[]'::jsonb) FROM factor_advances fa WHERE fa.soignant_id = v_uid),
    'paiements_soignant', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM paiements_soignant p WHERE p.soignant_id = v_uid),
    'contrats_mission', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'mission_id',mission_id,'type_contrat',type_contrat,'numero_contrat',numero_contrat,'statut',statut,'signature_soignant_le',signature_soignant_le,'signature_etablissement_le',signature_etablissement_le,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM contrats_mission WHERE soignant_id = v_uid),
    'documents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type_document,'libelle',libelle,'statut_verification',statut_verification,'valide_jusqua',valide_jusqua,'televerse_le',televerse_le) ORDER BY televerse_le DESC), '[]'::jsonb) FROM documents_soignants WHERE soignant_id = v_uid AND supprime_le IS NULL),
    'evaluations_recues', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evalue_id = v_uid),
    'evaluations_donnees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evaluateur_id = v_uid),
    'messages_chat', (SELECT COALESCE(jsonb_agg(jsonb_build_object('conversation_id',conversation_id,'contenu',contenu,'cree_le',cree_le,'lu',lu) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_chat WHERE auteur_id = v_uid),
    'notifications', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type,'titre',titre,'corps',corps,'lue',lue,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notifications WHERE destinataire_id = v_uid),
    'partages_rib', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id',etablissement_id,'mission_id',mission_id,'partage_le',partage_le,'consulte_le',consulte_le,'expire_le',expire_le,'actif',actif)), '[]'::jsonb) FROM partages_rib WHERE soignant_id = v_uid),
    'parrainages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('role', CASE WHEN parrain_id = v_uid THEN 'parrain' ELSE 'filleul' END,'code_parrainage',code_parrainage,'statut',statut,'valide_le',valide_le,'cree_le',cree_le)), '[]'::jsonb) FROM parrainages WHERE parrain_id = v_uid OR filleul_id = v_uid),
    'preferences_notifications', (SELECT to_jsonb(p) - 'utilisateur_id' FROM preferences_notifications p WHERE utilisateur_id = v_uid),
    'preferences_notifications_par_evenement', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type_evenement',type_evenement,'canal',canal,'actif',actif)), '[]'::jsonb) FROM preferences_notifications_par_evenement WHERE utilisateur_id = v_uid),
    'serie_email_envois', (SELECT COALESCE(jsonb_agg(jsonb_build_object('serie',serie,'etape',etape,'planifie_le',planifie_le,'envoye_le',envoye_le,'statut',statut,'skip_raison',skip_raison) ORDER BY planifie_le DESC), '[]'::jsonb) FROM serie_email_envois WHERE utilisateur_id = v_uid),
    'filtres_sauvegardes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('nom',nom,'audience',audience,'filtres',filtres,'alerte_active',alerte_active,'frequence_alerte',frequence_alerte,'dernier_check_le',dernier_check_le,'nb_resultats_dernier_check',nb_resultats_dernier_check,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM filtres_sauvegardes WHERE utilisateur_id = v_uid),
    'favoris_etablissements', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id', etablissement_id, 'cree_le', cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM favoris_soignant_etab WHERE soignant_id = v_uid)
  ) INTO v_result;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'RGPD_EXPORT_DONNEES',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('version', 'v5_avec_favoris')
  );

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
