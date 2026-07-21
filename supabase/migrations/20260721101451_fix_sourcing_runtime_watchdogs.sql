-- Le cockpit ne doit jamais scorer/dédoublonner 1,6 million de lignes dans une
-- seule requête. On borne d'abord un pool indexé, puis on calcule le score et
-- les correspondances CRM uniquement sur ce pool.

SET LOCAL statement_timeout = '10min';
SET LOCAL lock_timeout = '30s';

CREATE INDEX IF NOT EXISTS idx_prospects_soignants_sourcing_recent
  ON public.prospects_soignants (importe_le DESC, cle)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_sourcing_profession
  ON public.prospects_soignants (profession, importe_le DESC, cle)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_sourcing_departement
  ON public.prospects_soignants (departement, importe_le DESC, cle)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_sourcing_prof_dept
  ON public.prospects_soignants (profession, departement, importe_le DESC, cle)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');
CREATE INDEX IF NOT EXISTS idx_prospects_etab_sourcing_recent
  ON public.prospects_etablissements (importe_le DESC, finess)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');
CREATE INDEX IF NOT EXISTS idx_prospects_etab_sourcing_type
  ON public.prospects_etablissements (type_jolene, importe_le DESC, finess)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');
CREATE INDEX IF NOT EXISTS idx_prospects_etab_sourcing_departement
  ON public.prospects_etablissements (departement, importe_le DESC, finess)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');
CREATE INDEX IF NOT EXISTS idx_prospects_etab_sourcing_type_dept
  ON public.prospects_etablissements (type_jolene, departement, importe_le DESC, finess)
  WHERE statut_sourcing NOT IN ('IGNORE', 'OPPOSITION');

CREATE OR REPLACE FUNCTION public.fn_admin_sourcing_tableau(
  p_cible text DEFAULT 'SOIGNANT',
  p_departement text DEFAULT NULL,
  p_profession text DEFAULT NULL,
  p_type_etab text DEFAULT NULL,
  p_nouveaux boolean DEFAULT false,
  p_contactables boolean DEFAULT true,
  p_hors_crm boolean DEFAULT true,
  p_page integer DEFAULT 1,
  p_par_page integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_cible text := upper(COALESCE(p_cible, 'SOIGNANT'));
  v_page integer := greatest(COALESCE(p_page, 1), 1);
  v_par_page integer := least(greatest(COALESCE(p_par_page, 30), 10), 100);
  v_pool integer;
  v_total bigint := 0;
  v_total_pool bigint := 0;
  v_nouveaux bigint := 0;
  v_contactables bigint := 0;
  v_resultats jsonb := '[]'::jsonb;
  v_besoins jsonb := '[]'::jsonb;
  v_imports jsonb := '[]'::jsonb;
  v_departement text := NULLIF(upper(btrim(COALESCE(p_departement, ''))), '');
  v_profession text := NULLIF(upper(btrim(COALESCE(p_profession, ''))), '');
  v_type_etab text := NULLIF(upper(btrim(COALESCE(p_type_etab, ''))), '');
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;
  IF v_cible NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RAISE EXCEPTION 'Cible invalide';
  END IF;

  -- Pool assez large pour absorber les rares doublons sans exposer la base à
  -- une agrégation nationale. Le plafond garde un temps de réponse constant.
  v_pool := LEAST(5000, GREATEST(600, (v_page * v_par_page) + 300));

  SELECT c.total, c.nouveaux_30j, c.contactables
    INTO v_total, v_nouveaux, v_contactables
    FROM public.prospection_compteurs c
   WHERE c.cible = v_cible;

  IF v_cible = 'SOIGNANT' THEN
    WITH demandes AS (
      SELECT m.profession_requise::text AS profession,
             e.adresse_departement AS departement,
             count(*)::integer AS nb
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.statut = 'OUVERTE'::public.statut_mission
        AND m.fin_le >= now() AND e.supprime_le IS NULL
      GROUP BY 1, 2
    ), candidats AS MATERIALIZED (
      SELECT p.cle, p.nom, p.prenom, p.profession, p.enseigne, p.telephone,
             p.email, p.ville, p.departement, p.code_postal, p.numero_rpps,
             p.mode_exercice, p.finess_structure, p.source_code, p.source_url,
             p.source_maj_le, p.importe_le, p.statut_sourcing
      FROM public.prospects_soignants p
      WHERE p.statut_sourcing NOT IN ('IGNORE', 'OPPOSITION')
        AND (v_departement IS NULL OR p.departement = lpad(v_departement, 2, '0'))
        AND (v_profession IS NULL OR p.profession = v_profession)
        AND (NOT p_nouveaux OR p.importe_le >= now() - interval '30 days')
        AND (NOT p_contactables OR NULLIF(btrim(p.email), '') IS NOT NULL OR NULLIF(btrim(p.telephone), '') IS NOT NULL)
      -- Sans filtre, le pool national doit contenir les fiches les plus
      -- recentes, pas seulement les premieres professions alphabetiques.
      ORDER BY p.importe_le DESC, p.cle
      LIMIT v_pool
    ), calc AS (
      SELECT p.*,
        EXISTS (
          SELECT 1 FROM public.sales_contacts c
          WHERE (c.source_prospect_type = 'SOIGNANT' AND c.source_prospect_id = p.cle)
             OR (p.numero_rpps IS NOT NULL AND c.notes ILIKE '%' || p.numero_rpps || '%')
             OR (p.email IS NOT NULL AND lower(c.email) = lower(p.email))
             OR (p.telephone IS NOT NULL AND length(regexp_replace(p.telephone, '\\D', '', 'g')) >= 9
                 AND regexp_replace(c.telephone, '\\D', '', 'g') = regexp_replace(p.telephone, '\\D', '', 'g'))
        ) AS deja_crm,
        EXISTS (
          SELECT 1 FROM public.soignants s
          WHERE s.supprime_le IS NULL AND (
            (p.numero_rpps IS NOT NULL AND s.numero_rpps = p.numero_rpps)
            OR (p.email IS NOT NULL AND lower(s.email) = lower(p.email))
            OR (p.telephone IS NOT NULL AND length(regexp_replace(p.telephone, '\\D', '', 'g')) >= 9
                AND regexp_replace(s.telephone::text, '\\D', '', 'g') = regexp_replace(p.telephone, '\\D', '', 'g'))
          )
        ) AS deja_inscrit,
        COALESCE(d.nb, 0) AS missions_ouvertes
      FROM candidats p
      LEFT JOIN demandes d ON d.profession = p.profession AND d.departement = p.departement
    ), scores AS (
      SELECT c.*,
        least(100, greatest(0,
          (CASE WHEN NULLIF(btrim(c.email), '') IS NOT NULL THEN 25 ELSE 0 END)
          + (CASE WHEN NULLIF(btrim(c.telephone), '') IS NOT NULL THEN 20 ELSE 0 END)
          + (CASE WHEN NULLIF(btrim(c.email), '') IS NOT NULL AND NULLIF(btrim(c.telephone), '') IS NOT NULL THEN 5 ELSE 0 END)
          + (CASE WHEN c.source_maj_le >= now() - interval '45 days' THEN 15 WHEN c.source_maj_le >= now() - interval '180 days' THEN 7 ELSE 0 END)
          + least(c.missions_ouvertes * 5, 25)
          + (CASE WHEN c.source_code = 'ANNUAIRE_SANTE_RPPS' THEN 10 ELSE 0 END)
          + (CASE WHEN c.deja_crm THEN -30 ELSE 10 END)
          + (CASE WHEN c.deja_inscrit THEN -50 ELSE 5 END)
        ))::smallint AS score
      FROM calc c
    ), filtres AS (
      SELECT * FROM scores WHERE NOT p_hors_crm OR (NOT deja_crm AND NOT deja_inscrit)
    )
    SELECT (SELECT count(*) FROM filtres),
           COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.score DESC, x.missions_ouvertes DESC, x.nom), '[]'::jsonb)
      INTO v_total_pool, v_resultats
    FROM (
      SELECT cle AS id, 'SOIGNANT'::text AS cible, nom, prenom, profession,
             enseigne AS sous_titre, telephone, email, ville, departement,
             code_postal, numero_rpps, mode_exercice, finess_structure,
             NULL::text AS type_etab, source_code, source_url, source_maj_le,
             importe_le, statut_sourcing, deja_crm, deja_inscrit,
             missions_ouvertes, score
      FROM filtres
      ORDER BY score DESC, missions_ouvertes DESC, nom, id
      LIMIT v_par_page OFFSET (v_page - 1) * v_par_page
    ) x;
  ELSE
    WITH candidats AS MATERIALIZED (
      SELECT p.finess, p.siret, p.nom, p.type_jolene, p.categorie_lib,
             p.telephone, p.email, p.ville, p.departement, p.code_postal,
             p.source_code, p.source_url, p.source_maj_le, p.importe_le,
             p.statut_sourcing
      FROM public.prospects_etablissements p
      WHERE p.statut_sourcing NOT IN ('IGNORE', 'OPPOSITION')
        AND (v_departement IS NULL OR p.departement = v_departement)
        AND (v_type_etab IS NULL OR p.type_jolene = v_type_etab)
        AND (NOT p_nouveaux OR p.importe_le >= now() - interval '30 days')
        AND (NOT p_contactables OR NULLIF(btrim(p.email), '') IS NOT NULL OR NULLIF(btrim(p.telephone), '') IS NOT NULL)
      ORDER BY p.importe_le DESC, p.finess
      LIMIT v_pool
    ), calc AS (
      SELECT p.*,
        EXISTS (
          SELECT 1 FROM public.sales_contacts c
          WHERE c.finess = p.finess
             OR (p.email IS NOT NULL AND lower(c.email) = lower(p.email))
             OR (p.telephone IS NOT NULL AND length(regexp_replace(p.telephone, '\\D', '', 'g')) >= 9
                 AND regexp_replace(c.telephone, '\\D', '', 'g') = regexp_replace(p.telephone, '\\D', '', 'g'))
        ) AS deja_crm,
        EXISTS (
          SELECT 1 FROM public.etablissements e
          WHERE e.supprime_le IS NULL AND (
            e.finess = p.finess OR (p.siret IS NOT NULL AND e.siret = p.siret)
            OR (p.email IS NOT NULL AND lower(e.email_contact) = lower(p.email))
          )
        ) AS deja_inscrit
      FROM candidats p
    ), scores AS (
      SELECT c.*,
        least(100, greatest(0,
          (CASE WHEN NULLIF(btrim(c.email), '') IS NOT NULL THEN 25 ELSE 0 END)
          + (CASE WHEN NULLIF(btrim(c.telephone), '') IS NOT NULL THEN 20 ELSE 0 END)
          + (CASE WHEN NULLIF(btrim(c.email), '') IS NOT NULL AND NULLIF(btrim(c.telephone), '') IS NOT NULL THEN 5 ELSE 0 END)
          + (CASE WHEN c.source_maj_le >= now() - interval '45 days' THEN 15 WHEN c.source_maj_le >= now() - interval '180 days' THEN 7 ELSE 0 END)
          + (CASE c.type_jolene WHEN 'HOPITAL' THEN 15 WHEN 'EHPAD' THEN 15 WHEN 'DOMICILE' THEN 12 WHEN 'HANDICAP' THEN 10 WHEN 'ECOLE_SANTE' THEN 10 ELSE 5 END)
          + (CASE WHEN c.source_code = 'FINESS_DATA_GOUV' THEN 10 ELSE 0 END)
          + (CASE WHEN c.deja_crm THEN -30 ELSE 10 END)
          + (CASE WHEN c.deja_inscrit THEN -50 ELSE 5 END)
        ))::smallint AS score
      FROM calc c
    ), filtres AS (
      SELECT * FROM scores WHERE NOT p_hors_crm OR (NOT deja_crm AND NOT deja_inscrit)
    )
    SELECT (SELECT count(*) FROM filtres),
           COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.score DESC, x.nom), '[]'::jsonb)
      INTO v_total_pool, v_resultats
    FROM (
      SELECT finess AS id, 'ETABLISSEMENT'::text AS cible, nom,
             NULL::text AS prenom, NULL::text AS profession,
             categorie_lib AS sous_titre, telephone, email, ville, departement,
             code_postal, NULL::text AS numero_rpps, NULL::text AS mode_exercice,
             finess AS finess_structure, type_jolene AS type_etab, source_code,
             source_url, source_maj_le, importe_le, statut_sourcing, deja_crm,
             deja_inscrit, 0::integer AS missions_ouvertes, score
      FROM filtres
      ORDER BY score DESC, nom, id
      LIMIT v_par_page OFFSET (v_page - 1) * v_par_page
    ) x;
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(b) ORDER BY b.missions_ouvertes DESC), '[]'::jsonb)
    INTO v_besoins
  FROM (
    SELECT m.profession_requise::text AS profession,
           e.adresse_departement AS departement,
           count(*)::integer AS missions_ouvertes
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'::public.statut_mission
      AND m.fin_le >= now() AND e.supprime_le IS NULL
    GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 12
  ) b;

  SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.demarre_le DESC), '[]'::jsonb)
    INTO v_imports
  FROM (
    SELECT id, source_code, cible, statut, source_maj_le, demarre_le,
           termine_le, lignes_lues, lignes_importees, erreur
    FROM public.sourcing_imports ORDER BY demarre_le DESC LIMIT 6
  ) i;

  RETURN jsonb_build_object(
    'stats', jsonb_build_object(
      'total', COALESCE(v_total, 0),
      'nouveaux_30j', COALESCE(v_nouveaux, 0),
      'contactables', COALESCE(v_contactables, 0),
      -- Valeur exacte uniquement dans le pool classe. Soustraire le nombre de
      -- lignes CRM au volume national produisait un faux chiffre (doublons,
      -- contacts archives et fiches non issues des annuaires).
      'hors_crm', CASE WHEN p_hors_crm THEN COALESCE(v_total_pool, 0) ELSE NULL END,
      'hors_crm_global', false,
      'compteurs_globaux', true
    ),
    'resultats', v_resultats,
    'besoins', v_besoins,
    'imports', v_imports,
    'page', v_page,
    'par_page', v_par_page,
    -- Le cockpit est une file priorisee, volontairement bornee. La recherche
    -- exhaustive reste disponible dans l'onglet Prospection.
    'total_pages', ceil(COALESCE(v_total_pool, 0)::numeric / v_par_page),
    'genere_le', now(),
    'pool_evalue', v_pool,
    'pool_resultats', COALESCE(v_total_pool, 0)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_sourcing_tableau(text, text, text, text, boolean, boolean, boolean, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_sourcing_tableau(text, text, text, text, boolean, boolean, boolean, integer, integer) TO authenticated, service_role;

-- Replanifie les enrichissements sans chevauchement et avec une seule écriture
-- SQL par lot. Établissements : contrôle quotidien (la file est terminée).
-- Soignants : lot de 60 toutes les dix minutes.
DO $cron$
DECLARE v_job record;
BEGIN
  FOR v_job IN
    SELECT jobid FROM cron.job
    WHERE jobname IN (
      'enrich-prospects-etab', 'enrich-prospects-soignant',
      'jolene_sourcing_rpps_watchdog', 'jolene_prospection_compteurs_quotidien'
    )
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;

  PERFORM cron.schedule(
    'enrich-prospects-etab',
    '40 4 * * *',
    $job$
      SELECT net.http_post(
        url := rtrim((SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1), '/') || '/functions/v1/enrich-prospects-annuaire',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := '{"cible":"ETABLISSEMENT","limite":20}'::jsonb,
        timeout_milliseconds := 120000
      );
    $job$
  );

  PERFORM cron.schedule(
    'enrich-prospects-soignant',
    '3,13,23,33,43,53 * * * *',
    $job$
      SELECT net.http_post(
        url := rtrim((SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1), '/') || '/functions/v1/enrich-prospects-annuaire',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := '{"cible":"SOIGNANT","limite":60}'::jsonb,
        timeout_milliseconds := 120000
      );
    $job$
  );

  -- Le watchdog ne démarre jamais un import terminé : il reprend uniquement
  -- une exécution dont le heartbeat s'est arrêté.
  PERFORM cron.schedule(
    'jolene_sourcing_rpps_watchdog',
    '*/5 * * * *',
    $job$
      SELECT net.http_post(
        url := rtrim((SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1), '/') || '/functions/v1/import-annuaire-rpps',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := '{"watchdog":true}'::jsonb,
        timeout_milliseconds := 120000
      );
    $job$
  );

  PERFORM cron.schedule(
    'jolene_prospection_compteurs_quotidien',
    '25 2 * * *',
    'SELECT public.fn_rafraichir_prospection_compteurs();'
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron, pg_net ou vault indisponible : planification differee';
END;
$cron$;
