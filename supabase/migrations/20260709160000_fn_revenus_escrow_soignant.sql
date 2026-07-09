-- Visibilité escrow ⚡ côté revenus soignant (chantier post-flip, point 1).
-- Cf. docs/SPEC_ESCROW_REVENUS_SOIGNANT.md.
--
-- 1. fn_mes_paiements_escrow() : cycle par mission des paiements escrow du
--    soignant courant, avec l'état SOIGNANT (jamais la mécanique étab) calculé
--    depuis paiements_escrow.statut + validation des présences.
-- 2. fn_mes_revenus_connect() enrichie : total (versés) + en_attente (in-flight)
--    incluent désormais l'escrow (paiements_escrow), sans double-comptage avec
--    stripe_transfers (missions disjointes : l'escrow remplace le transfer
--    direct quand ⚡ actif).
--
-- INVARIANTS (spec §0) : part soignant seule (honoraires_cents, jamais le total
-- ni la commission), montant figé à la confirmation (plancher, règle #11).
-- Unités : honoraires_cents en CENTIMES → /100.0 pour des euros (l'ancien
-- modèle stripe_transfers/paiements_soignant est déjà en euros). Ne jamais
-- mélanger centimes et euros dans un même calcul (règle CLAUDE.md).

-- ── 1. Cycle par mission ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mes_paiements_escrow()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH base AS (
    SELECT
      pe.mission_id,
      m.intitule                       AS mission_intitule,
      e.nom                            AS etablissement_nom,
      pe.honoraires_cents,
      pe.statut,
      pe.paye_le,
      pe.release_planifie_le,
      pe.disponible_le,
      pe.relance_prevue_le,
      m.debut_le                       AS mission_date,
      COALESCE(pr.travaillee, false)                       AS travaillee,
      COALESCE(pr.bloquante, false)                        AS bloquante,
      COALESCE(pr.a_litige_presence, false)                AS a_litige_presence
    FROM paiements_escrow pe
    JOIN missions m         ON m.id = pe.mission_id
    JOIN etablissements e   ON e.id = pe.etablissement_id
    LEFT JOIN LATERAL (
      SELECT
        bool_or(p.pointage_depart_le IS NOT NULL) AS travaillee,
        bool_or(COALESCE(p.valide_par_etablissement, false) = false
                AND (p.pointage_depart_le IS NOT NULL OR p.motif_litige IS NOT NULL)) AS bloquante,
        bool_or(p.motif_litige IS NOT NULL) AS a_litige_presence
      FROM presences p
      WHERE p.mission_id = pe.mission_id
    ) pr ON true
    WHERE pe.soignant_id = auth.uid()
  ),
  calc AS (
    SELECT
      base.*,
      CASE
        WHEN statut = 'PAYE'                            THEN 'VERSE'
        WHEN statut = 'REMBOURSE' AND paye_le IS NOT NULL THEN 'VERSE'      -- absorption post-versement : le soignant a touché 100 %
        WHEN statut = 'REMBOURSE'                       THEN 'ANNULE'
        WHEN statut = 'ECHOUE'                          THEN 'RETARDE'
        WHEN statut = 'DISPUTE'                         THEN 'LITIGE'
        -- in-flight : INITIE / DEBITE / DISPONIBLE / RELEASE_PLANIFIE
        WHEN travaillee AND NOT bloquante               THEN 'VERSEMENT_EN_COURS'
        WHEN travaillee                                 THEN 'ATTENTE_VALIDATION'
        ELSE 'RESERVE'
      END AS etat
    FROM base
  )
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'mission_id',        mission_id,
      'mission_intitule',  mission_intitule,
      'etablissement_nom', etablissement_nom,
      'honoraires_cents',  honoraires_cents,
      'etat',              etat,
      'date_affichee',     CASE etat
                             WHEN 'VERSE'              THEN paye_le
                             WHEN 'VERSEMENT_EN_COURS' THEN COALESCE(release_planifie_le, disponible_le)
                             WHEN 'RETARDE'            THEN relance_prevue_le
                             ELSE NULL
                           END,
      'mission_date',      mission_date,
      'a_litige',          a_litige_presence OR statut = 'DISPUTE'
    )
    ORDER BY
      -- en cours / attente d'abord, versés/annulés ensuite ; récents d'abord
      CASE etat
        WHEN 'RETARDE' THEN 0 WHEN 'LITIGE' THEN 1
        WHEN 'ATTENTE_VALIDATION' THEN 2 WHEN 'VERSEMENT_EN_COURS' THEN 3
        WHEN 'RESERVE' THEN 4 WHEN 'VERSE' THEN 5 ELSE 6
      END,
      mission_date DESC
  ), '[]'::jsonb)
  FROM calc;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_mes_paiements_escrow() TO authenticated;

-- ── 2. Agrégats enrichis (escrow inclus, sans double-comptage) ────────────────
CREATE OR REPLACE FUNCTION public.fn_mes_revenus_connect(p_mois_debut date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_debut DATE;
    v_connect_mois NUMERIC;
    v_connect_total NUMERIC;
    v_connect_attente NUMERIC;
    v_paiements_mois NUMERIC;
    v_paiements_total NUMERIC;
    -- Escrow (paiements_escrow) : honoraires_cents en CENTIMES → euros.
    v_escrow_mois NUMERIC;
    v_escrow_total NUMERIC;
    v_escrow_attente NUMERIC;
BEGIN
    v_debut := COALESCE(p_mois_debut, DATE_TRUNC('month', CURRENT_DATE)::DATE);

    -- Stripe Connect transfers (ancien modèle, déjà en euros) — inchangé.
    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_mois
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('TRANSFERE','PAYE') AND transfere_le >= v_debut;

    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_total
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('TRANSFERE','PAYE');

    SELECT COALESCE(SUM(montant_soignant), 0) INTO v_connect_attente
    FROM stripe_transfers WHERE soignant_id = auth.uid() AND statut IN ('EN_ATTENTE');

    -- Paiements manuels confirmés (déjà en euros) — inchangé.
    SELECT COALESCE(SUM(montant_net), 0) INTO v_paiements_mois
    FROM paiements_soignant WHERE soignant_id = auth.uid() AND statut = 'CONFIRME' AND confirme_par_soignant_le >= v_debut;

    SELECT COALESCE(SUM(montant_net), 0) INTO v_paiements_total
    FROM paiements_soignant WHERE soignant_id = auth.uid() AND statut = 'CONFIRME';

    -- Escrow versé (PAYE) — centimes → euros. Missions disjointes de
    -- stripe_transfers (l'escrow remplace le transfer direct) → pas de double-compte.
    SELECT COALESCE(SUM(honoraires_cents), 0) / 100.0 INTO v_escrow_mois
    FROM paiements_escrow WHERE soignant_id = auth.uid() AND statut = 'PAYE' AND paye_le >= v_debut;

    SELECT COALESCE(SUM(honoraires_cents), 0) / 100.0 INTO v_escrow_total
    FROM paiements_escrow WHERE soignant_id = auth.uid() AND statut = 'PAYE';

    -- Escrow in-flight (réservé / en attente / versement en cours) = à venir.
    SELECT COALESCE(SUM(honoraires_cents), 0) / 100.0 INTO v_escrow_attente
    FROM paiements_escrow
    WHERE soignant_id = auth.uid()
      AND statut IN ('INITIE','DEBITE','DISPONIBLE','RELEASE_PLANIFIE');

    RETURN jsonb_build_object(
        'mois_en_cours', v_connect_mois + v_paiements_mois + v_escrow_mois,
        'total', v_connect_total + v_paiements_total + v_escrow_total,
        'en_attente', v_connect_attente + v_escrow_attente,
        'stripe_connect_actif', fn_soignant_stripe_connect_actif(auth.uid())
    );
END;
$function$;
