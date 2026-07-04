-- ============================================================
-- CP-LITIGES-7b-1 — 2 RPCs admin (preuves agrégées + historique)
-- ============================================================
-- Objectif : supporter la refonte UI AdminModeration (CP7b-2) en
-- éliminant les N+1 queries côté front. Chaque litige affiché dans la
-- console admin a besoin de l'intégralité du contexte (mission,
-- soignant, étab, pointages GPS, factures, messages) + des arbitrages
-- similaires passés pour maintenir la cohérence des décisions.
--
-- RPC 1 : fn_litige_preuves_agregees(p_litige_id) → JSONB unifié
-- RPC 2 : fn_litiges_historique_similaires(p_litige_id, p_limit) → TABLE
--
-- Sécurité : SECURITY DEFINER + guard est_admin() explicite (RAISE
-- EXCEPTION si non-admin → 403 côté client, pas de fuite de données).
--
-- Notes schéma :
--   • `en_faveur_de` n'est pas une colonne directe de `litiges` : dérivé
--     du statut terminal (RESOLU_SOIGNANT / RESOLU_ETABLISSEMENT /
--     RESOLU_ADMIN).
--   • `ajuster_heures` / `ajuster_taux` / `action_financiere_appliquee`
--     sont stockés dans `audit_rgpd` (fn_ecrire_audit
--     'LITIGE_RESOLUTION' payload) — hors scope de cette RPC pour
--     rester robuste si la table audit évolue. La refonte UI pourra
--     lire l'audit séparément si besoin.
--   • `presences` (legacy) est la source des pointages GPS liés aux
--     litiges (via `litiges.presence_id`). La migration vers
--     `scans_pointage` (CP5b) pour les missions récentes est
--     orthogonale à cette RPC — on expose ici ce qui est directement
--     rattaché au litige.
-- ============================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────
-- RPC 1 — fn_litige_preuves_agregees
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_litige_preuves_agregees(
  p_litige_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_litige            public.litiges%ROWTYPE;
  v_mission           public.missions%ROWTYPE;
  v_soignant          RECORD;
  v_etab              RECORD;
  v_presence          RECORD;
  v_result            JSONB;
  v_pointages         JSONB;
  v_factures          JSONB;
  v_messages          JSONB;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'fn_litige_preuves_agregees: accès admin requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_litige FROM public.litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Litige % introuvable', p_litige_id
      USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_mission FROM public.missions WHERE id = v_litige.mission_id;

  SELECT s.id, s.nom, s.prenom, s.numero_rpps, s.note_moyenne,
         s.telephone, s.est_salarie_etablissement, s.profession
    INTO v_soignant
    FROM public.soignants s
   WHERE s.id = v_litige.soignant_id;

  SELECT e.id, e.nom, e.siret,
         e.adresse_rue, e.adresse_code_postal, e.adresse_ville,
         e.telephone_contact, e.email_contact, e.est_secteur_public
    INTO v_etab
    FROM public.etablissements e
   WHERE e.id = v_litige.etablissement_id;

  -- Pointages : presences legacy (une ligne avec arrivee/depart pair).
  -- On projette en array de 2 événements pour le rendu UI timeline.
  SELECT p.* INTO v_presence
    FROM public.presences p
   WHERE p.id = v_litige.presence_id;

  IF v_presence IS NOT NULL AND v_presence.id IS NOT NULL THEN
    v_pointages := jsonb_build_array(
      jsonb_build_object(
        'id', v_presence.id,
        'type', 'ARRIVEE',
        'horodatage', v_presence.pointage_arrivee_le,
        'latitude', v_presence.arrivee_lat,
        'longitude', v_presence.arrivee_lng,
        'precision_gps_m', v_presence.arrivee_precision_gps_m,
        'methode', v_presence.methode_pointage_arrivee,
        'is_geo_ok', v_presence.perimetre_gps_valide
      ),
      jsonb_build_object(
        'id', v_presence.id,
        'type', 'DEPART',
        'horodatage', v_presence.pointage_depart_le,
        'latitude', v_presence.depart_lat,
        'longitude', v_presence.depart_lng,
        'precision_gps_m', v_presence.depart_precision_gps_m,
        'methode', v_presence.methode_pointage_depart,
        'is_geo_ok', v_presence.perimetre_gps_valide
      )
    );
  ELSE
    v_pointages := '[]'::jsonb;
  END IF;

  -- Factures liées (FIX 9 : AVOIR commission + FC potentiellement
  -- rattachés au litige via factures.litige_id, d'où filtre étendu).
  SELECT COALESCE(jsonb_agg(f_row ORDER BY f_row->>'date_emission' DESC), '[]'::jsonb)
    INTO v_factures
    FROM (
      SELECT jsonb_build_object(
        'id', f.id,
        'numero_facture', f.numero_facture,
        'type_document', f.type_document,
        'statut', f.statut,
        'statut_litige', f.statut_litige,
        'montant_ht', f.montant_ht,
        'montant_ttc', f.montant_ttc,
        'date_emission', f.date_emission,
        'facture_precedente_id', f.facture_precedente_id
      ) AS f_row
        FROM public.factures_honoraires f
       WHERE f.litige_id = p_litige_id
          OR f.id = v_litige.facture_id
    ) sub;

  -- Messages : résoudre auteur_nom via soignants / etablissements
  -- selon type_auteur ('SOIGNANT' | 'ETABLISSEMENT' | 'ADMIN').
  SELECT COALESCE(jsonb_agg(m_row ORDER BY (m_row->>'cree_le')::timestamptz ASC), '[]'::jsonb)
    INTO v_messages
    FROM (
      SELECT jsonb_build_object(
        'id', m.id,
        'auteur_type', m.type_auteur,
        'auteur_id', m.auteur_id,
        'auteur_nom', CASE m.type_auteur
          WHEN 'SOIGNANT' THEN (
            SELECT trim(s.prenom || ' ' || s.nom)
              FROM public.soignants s WHERE s.id = m.auteur_id
          )
          WHEN 'ETABLISSEMENT' THEN (
            SELECT e.nom FROM public.etablissements e
             WHERE e.id = v_litige.etablissement_id
          )
          WHEN 'ADMIN' THEN 'Admin Jolene'
          ELSE NULL
        END,
        'contenu', m.contenu,
        'cree_le', m.cree_le
      ) AS m_row
        FROM public.messages_litige m
       WHERE m.litige_id = p_litige_id
    ) sub;

  v_result := jsonb_build_object(
    'litige', jsonb_build_object(
      'id', v_litige.id,
      'type_litige', v_litige.type_litige,
      'categorie_litige', v_litige.categorie_litige,
      'statut', v_litige.statut,
      'initie_par', v_litige.initie_par,
      'cree_le', v_litige.cree_le,
      'motif', v_litige.motif,
      'resolution', v_litige.resolution,
      'resolu_le', v_litige.resolu_le,
      'resolu_par', v_litige.resolu_par,
      'escalade_auto_le', v_litige.escalade_auto_le,
      'escalade_auto_motif', v_litige.escalade_auto_motif,
      'est_informatif', v_litige.est_informatif,
      'type_legacy', v_litige.type_legacy,
      'montant_tresorerie_bloquee', v_litige.montant_tresorerie_bloquee,
      'facture_id', v_litige.facture_id,
      'mission_id', v_litige.mission_id
    ),
    'mission', CASE WHEN v_mission.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_mission.id,
      'intitule', v_mission.intitule,
      'service', v_mission.service,
      'debut_le', v_mission.debut_le,
      'fin_le', v_mission.fin_le,
      'duree_heures', v_mission.duree_heures,
      'type_contrat_applique', v_mission.type_contrat_applique,
      'taux_horaire_base', v_mission.taux_horaire_base,
      'profession_requise', v_mission.profession_requise,
      'soignant_assigne_id', v_mission.soignant_assigne_id,
      'statut', v_mission.statut,
      'regularisation_sociale_requise', v_mission.regularisation_sociale_requise
    ) END,
    'soignant', CASE WHEN v_soignant.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_soignant.id,
      'nom', v_soignant.nom,
      'prenom', v_soignant.prenom,
      'rpps', v_soignant.numero_rpps,
      'profession', v_soignant.profession,
      'note_moyenne', v_soignant.note_moyenne,
      'telephone', v_soignant.telephone,
      'est_salarie_etablissement', v_soignant.est_salarie_etablissement
    ) END,
    'etablissement', CASE WHEN v_etab.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_etab.id,
      'nom', v_etab.nom,
      'siret', v_etab.siret,
      'adresse', concat_ws(', ', v_etab.adresse_rue, v_etab.adresse_code_postal, v_etab.adresse_ville),
      'telephone_contact', v_etab.telephone_contact,
      'email_contact', v_etab.email_contact,
      'est_secteur_public', v_etab.est_secteur_public
    ) END,
    'pointages', v_pointages,
    'heures', jsonb_build_object(
      'prevues', CASE WHEN v_mission.id IS NULL THEN NULL ELSE jsonb_build_object(
        'debut', v_mission.debut_le,
        'fin', v_mission.fin_le,
        'duree_h', v_mission.duree_heures
      ) END,
      'declarees', CASE WHEN v_presence IS NULL OR v_presence.id IS NULL THEN NULL ELSE jsonb_build_object(
        'debut', v_presence.pointage_arrivee_le,
        'fin', v_presence.pointage_depart_le,
        'duree_nette_min', v_presence.duree_nette_min,
        'heures_reelles', v_presence.heures_reelles,
        'retard_min', v_presence.retard_min,
        'depart_anticipe_min', v_presence.depart_anticipe_min,
        'valide_par_etablissement', v_presence.valide_par_etablissement,
        'valide_le', v_presence.valide_le
      ) END
    ),
    'factures_liees', v_factures,
    'messages', v_messages
  );

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.fn_litige_preuves_agregees(UUID) IS
  'CP-LITIGES-7b-1 — retourne un JSONB unifié (litige + mission + '
  'soignant + étab + pointages GPS + heures prévues/déclarées + '
  'factures liées + messages) pour alimenter la console admin '
  'AdminModeration en une seule requête. SECURITY DEFINER + guard '
  'est_admin() explicite.';

REVOKE EXECUTE ON FUNCTION public.fn_litige_preuves_agregees(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_litige_preuves_agregees(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- RPC 2 — fn_litiges_historique_similaires
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_litiges_historique_similaires(
  p_litige_id UUID,
  p_limit INTEGER DEFAULT 5
)
RETURNS TABLE (
  id                   UUID,
  type_litige          public.type_litige,
  resolution           TEXT,
  en_faveur_de         TEXT,
  cree_le              TIMESTAMPTZ,
  resolu_le            TIMESTAMPTZ,
  motif                TEXT,
  statut               TEXT,
  mission_id           UUID,
  montant_tresorerie_bloquee NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_type_litige   public.type_litige;
  v_etab_id       UUID;
  v_limit         INTEGER := GREATEST(1, LEAST(p_limit, 50));
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'fn_litiges_historique_similaires: accès admin requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT l.type_litige, l.etablissement_id
    INTO v_type_litige, v_etab_id
    FROM public.litiges l
   WHERE l.id = p_litige_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Litige % introuvable', p_litige_id
      USING ERRCODE = 'P0002';
  END IF;

  RETURN QUERY
    SELECT
      l.id,
      l.type_litige,
      l.resolution,
      CASE l.statut
        WHEN 'RESOLU_SOIGNANT'      THEN 'SOIGNANT'
        WHEN 'RESOLU_ETABLISSEMENT' THEN 'ETABLISSEMENT'
        WHEN 'RESOLU_ADMIN'         THEN 'PARTAGE'
        ELSE NULL
      END AS en_faveur_de,
      l.cree_le,
      l.resolu_le,
      l.motif,
      l.statut,
      l.mission_id,
      l.montant_tresorerie_bloquee
      FROM public.litiges l
     WHERE l.id <> p_litige_id
       AND l.type_litige = v_type_litige
       AND l.etablissement_id = v_etab_id
       AND l.statut IN (
         'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN',
         'FERME', 'CLOTURE', 'RESOLU'
       )
     ORDER BY l.resolu_le DESC NULLS LAST, l.cree_le DESC
     LIMIT v_limit;
END;
$$;

COMMENT ON FUNCTION public.fn_litiges_historique_similaires(UUID, INTEGER) IS
  'CP-LITIGES-7b-1 — retourne les litiges résolus similaires (même '
  'type + même établissement) au plus récents en premier, pour aider '
  'l''admin à maintenir la cohérence de ses arbitrages. en_faveur_de '
  'dérivé du statut terminal. Limit borné [1..50]. SECURITY DEFINER + '
  'guard est_admin().';

REVOKE EXECUTE ON FUNCTION public.fn_litiges_historique_similaires(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_litiges_historique_similaires(UUID, INTEGER) TO authenticated;

COMMIT;
