-- Rend le radar d'acquisition réellement exploitable avant lancement :
-- BMO mesure la tension territoriale, BOAMP apporte des besoins nommés et
-- FINESS fournit les établissements précis à prioriser. Cette migration ne
-- crée aucun envoi et maintient le verrou marketing global à false.

BEGIN;

INSERT INTO public.growth_config (cle, valeur, maj_le)
VALUES ('automatisations_marketing_actives', 'false', now())
ON CONFLICT (cle) DO UPDATE SET valeur = 'false', maj_le = now();

ALTER TABLE public.acquisition_territoires
  ADD COLUMN IF NOT EXISTS bmo_code_metier text,
  ADD COLUMN IF NOT EXISTS bmo_libelle_metier text,
  ADD COLUMN IF NOT EXISTS bmo_precision text,
  ADD COLUMN IF NOT EXISTS bmo_source_maj_le timestamptz;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'acquisition_territoires_bmo_precision_check'
  ) THEN
    ALTER TABLE public.acquisition_territoires
      ADD CONSTRAINT acquisition_territoires_bmo_precision_check
      CHECK (bmo_precision IS NULL OR bmo_precision IN ('EXACT', 'AGREGAT'));
  END IF;
END;
$do$;

CREATE INDEX IF NOT EXISTS idx_acquisition_territoires_tension
  ON public.acquisition_territoires
    (profession, bmo_difficulte_pct DESC, bmo_projets_recrutement DESC, departement)
  WHERE bmo_annee IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_prospects_etablissements_siret_non_null
  ON public.prospects_etablissements (siret)
  WHERE siret IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_prospects_etablissements_acquisition
  ON public.prospects_etablissements
    (departement, type_jolene, source_maj_le DESC, nom)
  WHERE statut_sourcing IN ('A_QUALIFIER', 'QUALIFIE')
    AND (telephone IS NOT NULL OR email IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_acquisition_signaux_actifs_identite
  ON public.acquisition_signaux (finess, siret, profession, score_demande DESC)
  WHERE statut IN ('NOUVEAU', 'QUALIFIE', 'CRM');

-- Un import national ne peut avoir qu'un seul détenteur de lease par source.
-- Les anciens doublons ou leases sans heartbeat sont fermés avant de poser la
-- contrainte, sans interrompre une exécution réellement active.
WITH runs AS (
  SELECT id,
    row_number() OVER (
      PARTITION BY source_code
      ORDER BY COALESCE(
        CASE WHEN COALESCE(details->>'heartbeat_le', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
          THEN (details->>'heartbeat_le')::timestamptz END,
        demarre_le
      ) DESC, demarre_le DESC, id DESC
    ) AS rang,
    COALESCE(
      CASE WHEN COALESCE(details->>'heartbeat_le', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
        THEN (details->>'heartbeat_le')::timestamptz END,
      demarre_le
    ) AS heartbeat_le
  FROM public.sourcing_imports
  WHERE statut = 'EN_COURS'
)
UPDATE public.sourcing_imports s
SET statut = 'ERREUR',
    termine_le = now(),
    erreur = 'Lease import fermé avant activation du verrou de concurrence'
FROM runs r
WHERE s.id = r.id
  AND (r.rang > 1 OR r.heartbeat_le < now() - interval '30 minutes');

CREATE UNIQUE INDEX IF NOT EXISTS uq_sourcing_imports_source_en_cours
  ON public.sourcing_imports (source_code)
  WHERE statut = 'EN_COURS';

-- Une source n'est affichée comme active qu'après un premier import réussi.
INSERT INTO public.acquisition_sources (
  code, libelle, type_source, source_url, automatique, actif,
  configuration_requise, dernier_statut, dernier_message, maj_le
) VALUES
  (
    'BMO_FRANCE_TRAVAIL', 'France Travail — BMO 2026', 'TENSION',
    'https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo',
    true, false, NULL, NULL, 'Import officiel en attente', now()
  ),
  (
    'BOAMP_API', 'BOAMP — besoins publics nommés', 'DEMANDE',
    'https://www.boamp.fr/explore/dataset/boamp/api/',
    true, false, NULL, NULL, 'Import officiel en attente', now()
  )
ON CONFLICT (code) DO UPDATE SET
  libelle = EXCLUDED.libelle,
  type_source = EXCLUDED.type_source,
  source_url = EXCLUDED.source_url,
  automatique = EXCLUDED.automatique,
  actif = CASE
    WHEN acquisition_sources.dernier_statut = 'OK'
      AND acquisition_sources.dernier_import_le IS NOT NULL THEN true
    ELSE false
  END,
  configuration_requise = EXCLUDED.configuration_requise,
  dernier_message = COALESCE(acquisition_sources.dernier_message, EXCLUDED.dernier_message),
  maj_le = now();

UPDATE public.acquisition_sources
SET actif = false,
    automatique = false,
    configuration_requise = 'Autorisation écrite FHF requise avant extraction automatisée',
    dernier_statut = 'NON_CONFIGURE',
    dernier_message = 'Import automatique volontairement désactivé',
    maj_le = now()
WHERE code = 'FHF_MANUEL';

UPDATE public.acquisition_sources
SET actif = false,
    automatique = false,
    dernier_statut = 'NON_CONFIGURE',
    dernier_message = 'Remplacé par la source BOAMP_API',
    maj_le = now()
WHERE code = 'BOAMP_MANUEL';

-- Ces professions ne doivent jamais alimenter le potentiel commercial Jolene :
-- pharmacien est non proposé et manipulateur radio est bloqué au lancement.
UPDATE public.acquisition_signaux
SET statut = 'IGNORE',
    details = details || jsonb_build_object(
      'ignore_automatique', true,
      'motif_ignore', 'Profession hors périmètre de missions Jolene au lancement'
    ),
    maj_le = now()
WHERE profession IN ('PHARMACIEN', 'MANIPULATEUR_RADIO')
  AND statut IN ('NOUVEAU', 'QUALIFIE', 'CRM');

-- Upsert atomique des agrégats BMO. En conflit, seules les colonnes issues de
-- BMO sont modifiées : les statuts, objectifs et notes choisis par l'admin sont
-- strictement conservés.
CREATE OR REPLACE FUNCTION public.fn_acquisition_upsert_bmo(p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_count integer := 0;
BEGIN
  IF NOT (
    public.est_admin()
    OR COALESCE(auth.role(), '') = 'service_role'
    OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role'
  ) THEN
    RAISE EXCEPTION 'Acces refuse' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.acquisition_territoires (
    departement, profession, bmo_annee, bmo_projets_recrutement,
    bmo_difficulte_pct, bmo_saisonnier_pct, bmo_code_metier,
    bmo_libelle_metier, bmo_precision, bmo_source_maj_le, source_url, maj_le
  )
  SELECT
    upper(btrim(r.departement)), upper(btrim(r.profession)), r.bmo_annee,
    GREATEST(COALESCE(r.bmo_projets_recrutement, 0), 0),
    CASE WHEN r.bmo_difficulte_pct IS NULL THEN NULL
      ELSE LEAST(GREATEST(r.bmo_difficulte_pct, 0), 100) END,
    CASE WHEN r.bmo_saisonnier_pct IS NULL THEN NULL
      ELSE LEAST(GREATEST(r.bmo_saisonnier_pct, 0), 100) END,
    NULLIF(btrim(r.bmo_code), ''), NULLIF(btrim(r.bmo_libelle), ''),
    CASE WHEN upper(r.precision) = 'EXACT' THEN 'EXACT' ELSE 'AGREGAT' END,
    COALESCE(r.bmo_source_maj_le, now()), NULLIF(btrim(r.source_url), ''), now()
  FROM jsonb_to_recordset(COALESCE(p_rows, '[]'::jsonb)) AS r(
    departement text, profession text, bmo_annee smallint,
    bmo_projets_recrutement integer, bmo_difficulte_pct numeric,
    bmo_saisonnier_pct numeric, bmo_code text, bmo_libelle text,
    precision text, bmo_source_maj_le timestamptz, source_url text
  )
  WHERE upper(btrim(COALESCE(r.departement, ''))) ~ '^([0-9]{2,3}|2A|2B)$'
    AND upper(btrim(COALESCE(r.profession, ''))) IN (
      'IDE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE', 'SAGE_FEMME',
      'KINE', 'MEDECIN', 'DENTISTE', 'PREPARATEUR_PHARMA',
      'DIETETICIEN', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
    )
    AND r.bmo_annee BETWEEN 2024 AND 2100
  ON CONFLICT (departement, profession) DO UPDATE SET
    bmo_annee = EXCLUDED.bmo_annee,
    bmo_projets_recrutement = EXCLUDED.bmo_projets_recrutement,
    bmo_difficulte_pct = EXCLUDED.bmo_difficulte_pct,
    bmo_saisonnier_pct = EXCLUDED.bmo_saisonnier_pct,
    bmo_code_metier = EXCLUDED.bmo_code_metier,
    bmo_libelle_metier = EXCLUDED.bmo_libelle_metier,
    bmo_precision = EXCLUDED.bmo_precision,
    bmo_source_maj_le = EXCLUDED.bmo_source_maj_le,
    source_url = EXCLUDED.source_url,
    maj_le = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_acquisition_upsert_bmo(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_acquisition_upsert_bmo(jsonb)
  TO service_role;

-- Liste concrète d'établissements FINESS à contacter. BMO est explicitement
-- une inférence territoriale ; un signal BOAMP/France Travail nommé et
-- rapproché par identifiant est une preuve directe.
-- La sélection exclut les comptes Jolene réels, le CRM, les oppositions, les
-- pharmacies et les écoles. Elle ne déclenche jamais de contact.
CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_cibles(
  p_departement text DEFAULT NULL,
  p_profession text DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_departement text := NULLIF(upper(btrim(COALESCE(p_departement, ''))), '');
  v_profession text := NULLIF(upper(btrim(COALESCE(p_profession, ''))), '');
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 10), 200);
  v_resultats jsonb := '[]'::jsonb;
  v_total integer := 0;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;

  WITH compatibilites AS MATERIALIZED (
    SELECT type_jolene, unnest(professions) AS profession
    FROM (VALUES
      ('HOPITAL', ARRAY[
        'IDE', 'IADE', 'IBODE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE',
        'SAGE_FEMME', 'KINE', 'MEDECIN', 'DENTISTE', 'PREPARATEUR_PHARMA',
        'DIETETICIEN', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
      ]::text[]),
      ('EHPAD', ARRAY[
        'IDE', 'AS', 'AES', 'KINE', 'MEDECIN', 'DIETETICIEN',
        'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
      ]::text[]),
      ('DOMICILE', ARRAY[
        'IDE', 'AS', 'AES', 'KINE', 'DIETETICIEN', 'ERGOTHERAPEUTE',
        'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
      ]::text[]),
      ('HANDICAP', ARRAY[
        'IDE', 'AS', 'AES', 'KINE', 'DIETETICIEN', 'ERGOTHERAPEUTE',
        'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
      ]::text[]),
      ('CENTRE_SANTE', ARRAY[
        'IDE', 'AS', 'SAGE_FEMME', 'KINE', 'MEDECIN', 'DENTISTE',
        'DIETETICIEN', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
      ]::text[]),
      ('DIALYSE', ARRAY['IDE', 'AS', 'MEDECIN', 'DIETETICIEN']::text[]),
      ('LABO', ARRAY['IDE', 'AS', 'MEDECIN']::text[])
    ) AS mapping(type_jolene, professions)
  ), etablissements_externes AS MATERIALIZED (
    SELECT p.*
    FROM public.prospects_etablissements p
    WHERE p.statut_sourcing IN ('A_QUALIFIER', 'QUALIFIE')
      AND p.type_jolene NOT IN ('PHARMACIE', 'ECOLE_SANTE')
      AND (NULLIF(btrim(p.telephone), '') IS NOT NULL OR NULLIF(btrim(p.email), '') IS NOT NULL)
      AND (v_departement IS NULL OR p.departement = v_departement)
      AND NOT EXISTS (
        SELECT 1 FROM public.sales_contacts sc
        WHERE sc.type = 'ETABLISSEMENT'
          AND (
            sc.finess = p.finess
            OR (p.email IS NOT NULL AND lower(sc.email) = lower(p.email))
            OR (p.telephone IS NOT NULL
              AND length(regexp_replace(p.telephone, '[^0-9]', '', 'g')) >= 9
              AND regexp_replace(sc.telephone, '[^0-9]', '', 'g') = regexp_replace(p.telephone, '[^0-9]', '', 'g'))
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.etablissements e
        WHERE e.supprime_le IS NULL
          AND COALESCE(e.est_compte_test, false) IS FALSE
          AND (e.finess = p.finess OR (p.siret IS NOT NULL AND e.siret = p.siret))
      )
  ), territoires_scores AS MATERIALIZED (
    SELECT t.*,
      LEAST(100, GREATEST(0,
        round(COALESCE(t.bmo_difficulte_pct, 0) * 0.65)
        + CASE WHEN t.bmo_precision = 'EXACT'
            THEN LEAST(COALESCE(t.bmo_projets_recrutement, 0), 700) / 20
            ELSE 0
          END
      ))::integer AS score_tension
    FROM public.acquisition_territoires t
    WHERE t.bmo_annee IS NOT NULL
      AND COALESCE(t.bmo_projets_recrutement, 0) > 0
  ), tensions AS MATERIALIZED (
    SELECT t.*
    FROM territoires_scores t
    WHERE (v_departement IS NULL OR t.departement = v_departement)
      AND (v_profession IS NULL OR t.profession = v_profession)
    ORDER BY t.score_tension DESC,
      CASE WHEN t.bmo_precision = 'EXACT' THEN t.bmo_projets_recrutement ELSE 0 END DESC
    LIMIT CASE
      WHEN v_departement IS NOT NULL AND v_profession IS NOT NULL THEN 1
      WHEN v_departement IS NOT NULL THEN 20
      ELSE 100
    END
  ), signaux_directs AS MATERIALIZED (
    SELECT s.finess, s.siret, s.profession,
      count(*)::integer AS nb_signaux,
      COALESCE(sum(s.volume_estime), 0)::integer AS volume,
      max(s.score_demande)::integer AS score_max,
      max(COALESCE(s.publie_le, s.maj_le)) AS dernier_signal_le,
      (array_agg(s.intitule ORDER BY s.score_demande DESC, s.maj_le DESC))[1] AS intitule_signal,
      (array_agg(s.source_code ORDER BY s.score_demande DESC, s.maj_le DESC))[1] AS source_signal,
      (array_agg(s.source_url ORDER BY s.score_demande DESC, s.maj_le DESC))[1] AS source_signal_url
    FROM public.acquisition_signaux s
    WHERE s.source_code IN ('BOAMP_API', 'FRANCE_TRAVAIL_OFFRES')
      AND s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')
      AND (s.expire_le IS NULL OR s.expire_le >= now())
      AND s.profession IN (
        'IDE', 'IADE', 'IBODE', 'AS', 'AES', 'AUXILIAIRE_PUERICULTURE',
        'SAGE_FEMME', 'KINE', 'MEDECIN', 'DENTISTE', 'PREPARATEUR_PHARMA',
        'DIETETICIEN', 'ERGOTHERAPEUTE', 'PSYCHOMOTRICIEN', 'ORTHOPHONISTE'
      )
      AND (v_profession IS NULL OR s.profession = v_profession)
      AND (s.finess IS NOT NULL OR s.siret IS NOT NULL)
    GROUP BY s.finess, s.siret, s.profession
  ), candidats_directs AS MATERIALIZED (
    SELECT
      p.finess, p.siret, p.nom, p.type_jolene, p.categorie_lib,
      p.telephone, p.email, p.adresse, p.code_postal, p.ville, p.departement,
      p.source_url AS finess_source_url, p.source_maj_le,
      d.profession, t.bmo_annee, t.bmo_projets_recrutement,
      t.bmo_difficulte_pct, t.bmo_saisonnier_pct, t.bmo_code_metier,
      t.bmo_libelle_metier, t.bmo_precision, t.source_url AS bmo_source_url,
      COALESCE(t.score_tension, 0) AS score_tension,
      d.nb_signaux AS signaux_directs, d.volume AS volume_direct,
      d.score_max AS score_signal, d.dernier_signal_le,
      d.intitule_signal, d.source_signal, d.source_signal_url
    FROM signaux_directs d
    JOIN etablissements_externes p
      ON (d.finess IS NOT NULL AND d.finess = p.finess)
      OR (d.siret IS NOT NULL AND p.siret IS NOT NULL AND d.siret = p.siret)
    JOIN compatibilites c
      ON c.type_jolene = p.type_jolene AND c.profession = d.profession
    LEFT JOIN territoires_scores t
      ON t.departement = p.departement AND t.profession = d.profession
  ), candidats_tension AS MATERIALIZED (
    SELECT
      p.finess, p.siret, p.nom, p.type_jolene, p.categorie_lib,
      p.telephone, p.email, p.adresse, p.code_postal, p.ville, p.departement,
      p.source_url AS finess_source_url, p.source_maj_le,
      t.profession, t.bmo_annee, t.bmo_projets_recrutement,
      t.bmo_difficulte_pct, t.bmo_saisonnier_pct, t.bmo_code_metier,
      t.bmo_libelle_metier, t.bmo_precision, t.source_url AS bmo_source_url,
      t.score_tension,
      COALESCE(sig.nb_signaux, 0) AS signaux_directs,
      COALESCE(sig.volume, 0) AS volume_direct,
      COALESCE(sig.score_max, 0) AS score_signal,
      sig.dernier_signal_le, sig.intitule_signal, sig.source_signal,
      sig.source_signal_url
    FROM tensions t
    JOIN LATERAL (
      SELECT pe.*
      FROM etablissements_externes pe
      WHERE pe.departement = t.departement
        AND EXISTS (
          SELECT 1 FROM compatibilites c
          WHERE c.type_jolene = pe.type_jolene AND c.profession = t.profession
        )
      ORDER BY
        CASE pe.type_jolene
          WHEN 'HOPITAL' THEN 6 WHEN 'EHPAD' THEN 6 WHEN 'DIALYSE' THEN 5
          WHEN 'DOMICILE' THEN 5 WHEN 'HANDICAP' THEN 4
          WHEN 'CENTRE_SANTE' THEN 3 ELSE 1
        END DESC,
        (CASE WHEN NULLIF(btrim(pe.email), '') IS NOT NULL THEN 1 ELSE 0 END
          + CASE WHEN NULLIF(btrim(pe.telephone), '') IS NOT NULL THEN 1 ELSE 0 END) DESC,
        pe.source_maj_le DESC NULLS LAST,
        pe.nom
      LIMIT CASE
        WHEN v_departement IS NOT NULL AND v_profession IS NOT NULL THEN 60
        WHEN v_departement IS NOT NULL THEN 10
        WHEN v_profession IS NOT NULL THEN 4
        ELSE 3
      END
    ) p ON true
    LEFT JOIN signaux_directs sig
      ON sig.profession = t.profession
      AND (
        (sig.finess IS NOT NULL AND sig.finess = p.finess)
        OR (sig.siret IS NOT NULL AND p.siret IS NOT NULL AND sig.siret = p.siret)
      )
  ), candidats AS MATERIALIZED (
    SELECT * FROM candidats_directs
    UNION ALL
    SELECT * FROM candidats_tension
  ), scores AS (
    SELECT c.*,
      LEAST(100, GREATEST(0,
        c.score_tension
        + CASE c.type_jolene
            WHEN 'HOPITAL' THEN 14 WHEN 'EHPAD' THEN 14 WHEN 'DIALYSE' THEN 12
            WHEN 'DOMICILE' THEN 10 WHEN 'HANDICAP' THEN 9
            WHEN 'CENTRE_SANTE' THEN 6 ELSE 3
          END
        + CASE WHEN NULLIF(btrim(c.email), '') IS NOT NULL THEN 4 ELSE 0 END
        + CASE WHEN NULLIF(btrim(c.telephone), '') IS NOT NULL THEN 4 ELSE 0 END
        + CASE WHEN c.signaux_directs > 0 THEN 50 + LEAST(c.signaux_directs, 4) * 2 ELSE 0 END
      ))::integer AS score,
      CASE
        WHEN c.signaux_directs > 0 THEN
          'Besoin public explicite : ' || COALESCE(c.intitule_signal, 'signal officiel')
          || '.'
          || CASE WHEN c.bmo_annee IS NULL THEN '' ELSE
            ' Tension BMO ' || c.bmo_annee
            || CASE WHEN c.bmo_precision = 'AGREGAT'
              THEN ' — catégorie agrégée « ' || COALESCE(c.bmo_libelle_metier, 'métiers de santé') || ' » tous métiers confondus'
              ELSE '' END
            || ' : ' || c.bmo_projets_recrutement || ' projet(s)'
            || CASE WHEN c.bmo_difficulte_pct IS NULL THEN '' ELSE
              ', ' || trim(to_char(c.bmo_difficulte_pct, 'FM990D0')) || ' % jugés difficiles' END
            || '.' END
        WHEN c.bmo_precision = 'AGREGAT' THEN
          'Priorité territoriale BMO ' || c.bmo_annee || ' — catégorie agrégée « '
          || COALESCE(c.bmo_libelle_metier, 'métiers de santé') || ' » : '
          || c.bmo_projets_recrutement || ' projet(s) tous métiers confondus'
          || CASE WHEN c.bmo_difficulte_pct IS NULL THEN '' ELSE
            ', ' || trim(to_char(c.bmo_difficulte_pct, 'FM990D0')) || ' % jugés difficiles' END
          || '. Établissement FINESS contactable ; besoin inféré, à qualifier humainement.'
        ELSE
          'Priorité territoriale BMO ' || c.bmo_annee || ' : '
          || c.bmo_projets_recrutement || ' projet(s), '
          || CASE WHEN c.bmo_difficulte_pct IS NULL THEN 'difficulté non publiée' ELSE
            trim(to_char(c.bmo_difficulte_pct, 'FM990D0')) || ' % jugés difficiles' END
          || '. Établissement FINESS contactable ; besoin inféré, à qualifier humainement.'
      END AS raison_priorite
    FROM candidats c
  ), dedup AS (
    SELECT s.*,
      row_number() OVER (
        PARTITION BY s.finess
        ORDER BY (s.signaux_directs > 0) DESC, s.score DESC,
          s.bmo_projets_recrutement DESC, s.profession
      ) AS rang
    FROM scores s
  ), selection AS (
    SELECT
      finess AS id, finess, siret, nom, type_jolene, categorie_lib,
      telephone, email, adresse, code_postal, ville, departement,
      profession, score, raison_priorite,
      CASE WHEN signaux_directs > 0 THEN 'DIRECT' ELSE 'INFERENCE_TERRITORIALE' END AS force_signal,
      signaux_directs, volume_direct, score_signal, dernier_signal_le,
      intitule_signal, source_signal,
      COALESCE(source_signal_url, bmo_source_url) AS source_demande_url,
      finess_source_url, source_maj_le,
      bmo_annee, bmo_projets_recrutement, bmo_difficulte_pct,
      bmo_saisonnier_pct, bmo_code_metier, bmo_libelle_metier, bmo_precision
    FROM dedup
    WHERE rang = 1
    ORDER BY (signaux_directs > 0) DESC, score DESC,
      bmo_projets_recrutement DESC, nom
    LIMIT v_limit
  )
  SELECT count(*)::integer,
    COALESCE(jsonb_agg(to_jsonb(selection) ORDER BY
      (signaux_directs > 0) DESC, score DESC, bmo_projets_recrutement DESC, nom), '[]'::jsonb)
  INTO v_total, v_resultats
  FROM selection;

  RETURN jsonb_build_object(
    'genere_le', now(),
    'contact_automatique', false,
    'total_classe', v_total,
    'resultats', v_resultats,
    'methode', 'Besoins nommés BOAMP/France Travail puis tension territoriale BMO croisée avec FINESS',
    'limite', v_limit
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_acquisition_cibles(text, text, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_cibles(text, text, integer)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_acquisition_cibles(text, text, integer) IS
  'Etablissements externes FINESS priorises par signaux nommes directs et tension BMO. Aucun contact automatique.';

-- Enrichit le radar existant sans faire passer BMO pour une demande directe ni
-- pour du chiffre d'affaires. La tension BMO ajoute au plus 35 points au score
-- de priorité et reste exposée séparément dans chaque segment.
CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_radar_externe(
  p_scope text DEFAULT 'REEL',
  p_jours integer DEFAULT 90,
  p_departement text DEFAULT NULL,
  p_profession text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_resultat jsonb;
  v_segments jsonb;
BEGIN
  v_resultat := public.fn_admin_acquisition_radar(
    p_scope, p_jours, p_departement, p_profession
  );

  WITH calc AS (
    SELECT element,
      COALESCE(NULLIF(element->>'score_priorite', '')::integer, 0) AS score_initial,
      CASE
        WHEN NULLIF(element->>'bmo_projets_recrutement', '') IS NULL THEN 0
        ELSE LEAST(35,
          round(COALESCE(NULLIF(element->>'bmo_difficulte_pct', '')::numeric, 0) * 0.25)::integer
          + CASE WHEN t.bmo_precision = 'EXACT'
              THEN LEAST(COALESCE(NULLIF(element->>'bmo_projets_recrutement', '')::integer, 0), 500) / 40
              ELSE 0
            END
        )
      END AS score_bmo,
      t.bmo_precision,
      t.bmo_code_metier,
      t.bmo_libelle_metier
    FROM jsonb_array_elements(COALESCE(v_resultat->'segments', '[]'::jsonb)) element
    LEFT JOIN public.acquisition_territoires t
      ON upper(COALESCE(p_scope, 'REEL')) <> 'TEST'
      AND t.departement = element->>'departement'
      AND t.profession = element->>'profession'
  ), enrichi AS (
    SELECT element || jsonb_build_object(
      'score_bmo', score_bmo,
      'bmo_precision', bmo_precision,
      'bmo_code_metier', bmo_code_metier,
      'bmo_libelle_metier', bmo_libelle_metier,
      'score_priorite', LEAST(100, score_initial + score_bmo)
    ) AS segment,
    LEAST(100, score_initial + score_bmo) AS score_final
    FROM calc
  )
  SELECT COALESCE(jsonb_agg(segment ORDER BY score_final DESC), '[]'::jsonb)
  INTO v_segments
  FROM enrichi;

  v_resultat := jsonb_set(v_resultat, '{segments}', v_segments, true);
  v_resultat := jsonb_set(
    v_resultat,
    '{hypotheses}',
    COALESCE(v_resultat->'hypotheses', '{}'::jsonb) || jsonb_build_object(
      'bmo', 'tension territoriale annuelle, boost du score uniquement ; les volumes agrégés restent ceux de la catégorie entière, jamais de la profession ; ni demande directe ni revenu'
    ),
    true
  );
  RETURN v_resultat;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_acquisition_radar_externe(text, integer, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_radar_externe(text, integer, text, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_acquisition_radar_externe(text, integer, text, text) IS
  'Radar acquisition avec score BMO explicite, sans transformer BMO en demande ou revenu.';

-- BMO est annuel : contrôle mensuel. BOAMP évolue chaque jour : deux imports
-- quotidiens. Chaque connecteur journalise son propre échec sans bloquer l'autre.
DO $cron$
DECLARE v_job record;
BEGIN
  FOR v_job IN
    SELECT jobid FROM cron.job
    WHERE jobname IN ('jolene_acquisition_bmo_mensuel', 'jolene_acquisition_boamp_quotidien')
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;

  PERFORM cron.schedule(
    'jolene_acquisition_bmo_mensuel',
    '15 2 2 * *',
    $job$
      SELECT net.http_post(
        url := rtrim((SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1), '/') || '/functions/v1/import-bmo-acquisition',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := '{"silencieux":true}'::jsonb,
        timeout_milliseconds := 120000
      );
    $job$
  );

  PERFORM cron.schedule(
    'jolene_acquisition_boamp_quotidien',
    '35 5,15 * * *',
    $job$
      SELECT net.http_post(
        url := rtrim((SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1), '/') || '/functions/v1/import-boamp-acquisition',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := '{"silencieux":true}'::jsonb,
        timeout_milliseconds := 120000
      );
    $job$
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron, pg_net ou vault indisponible : imports acquisition différés';
END;
$cron$;

COMMIT;
