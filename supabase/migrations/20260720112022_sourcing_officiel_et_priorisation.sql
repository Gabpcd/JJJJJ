-- Sourcing commercial silencieux : enrichit et priorise les annuaires officiels
-- sans jamais envoyer d'email, SMS ou notification. L'ajout au CRM reste une
-- action admin explicite et les séquences sont créées désactivées.

-- Garde-fou global des campagnes automatiques avant lancement. Les fonctions
-- marketing lisent cette valeur avant toute sélection de destinataire. Les
-- messages transactionnels déclenchés par une action utilisateur ne sont pas
-- concernés.
INSERT INTO public.growth_config (cle, valeur, maj_le)
VALUES ('automatisations_marketing_actives', 'false', now())
ON CONFLICT (cle) DO UPDATE
SET valeur = 'false', maj_le = now();

ALTER TABLE public.prospects_etablissements
  ADD COLUMN IF NOT EXISTS source_code text NOT NULL DEFAULT 'FINESS_HISTORIQUE',
  ADD COLUMN IF NOT EXISTS source_url text,
  ADD COLUMN IF NOT EXISTS source_maj_le timestamptz,
  ADD COLUMN IF NOT EXISTS importe_le timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS dernier_controle_le timestamptz,
  ADD COLUMN IF NOT EXISTS statut_sourcing text NOT NULL DEFAULT 'A_QUALIFIER',
  ADD COLUMN IF NOT EXISTS ajoute_crm_le timestamptz;

ALTER TABLE public.prospects_soignants
  ADD COLUMN IF NOT EXISTS numero_rpps text,
  ADD COLUMN IF NOT EXISTS mode_exercice text,
  ADD COLUMN IF NOT EXISTS finess_structure text,
  ADD COLUMN IF NOT EXISTS siret_structure text,
  ADD COLUMN IF NOT EXISTS source_code text NOT NULL DEFAULT 'CNAM_2026_DEPRECIE',
  ADD COLUMN IF NOT EXISTS source_url text,
  ADD COLUMN IF NOT EXISTS source_maj_le timestamptz,
  ADD COLUMN IF NOT EXISTS importe_le timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS dernier_controle_le timestamptz,
  ADD COLUMN IF NOT EXISTS statut_sourcing text NOT NULL DEFAULT 'A_QUALIFIER',
  ADD COLUMN IF NOT EXISTS ajoute_crm_le timestamptz;

ALTER TABLE public.sales_contacts
  ADD COLUMN IF NOT EXISTS source_prospect_type text,
  ADD COLUMN IF NOT EXISTS source_prospect_id text,
  ADD COLUMN IF NOT EXISTS source_donnees text,
  ADD COLUMN IF NOT EXISTS score_sourcing smallint;

UPDATE public.prospects_etablissements
   SET source_maj_le = COALESCE(source_maj_le, maj_le),
       dernier_controle_le = COALESCE(dernier_controle_le, enrichi_le, maj_le)
 WHERE source_maj_le IS NULL OR dernier_controle_le IS NULL;

UPDATE public.prospects_soignants
   SET source_maj_le = COALESCE(source_maj_le, maj_le),
       dernier_controle_le = COALESCE(dernier_controle_le, enrichi_le, maj_le)
 WHERE source_maj_le IS NULL OR dernier_controle_le IS NULL;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'prospects_etab_statut_sourcing_check') THEN
    ALTER TABLE public.prospects_etablissements
      ADD CONSTRAINT prospects_etab_statut_sourcing_check
      CHECK (statut_sourcing IN ('A_QUALIFIER', 'QUALIFIE', 'IGNORE', 'OPPOSITION'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'prospects_soignants_statut_sourcing_check') THEN
    ALTER TABLE public.prospects_soignants
      ADD CONSTRAINT prospects_soignants_statut_sourcing_check
      CHECK (statut_sourcing IN ('A_QUALIFIER', 'QUALIFIE', 'IGNORE', 'OPPOSITION'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sales_contacts_source_prospect_type_check') THEN
    ALTER TABLE public.sales_contacts
      ADD CONSTRAINT sales_contacts_source_prospect_type_check
      CHECK (source_prospect_type IS NULL OR source_prospect_type IN ('ETABLISSEMENT', 'SOIGNANT'));
  END IF;
END;
$do$;

CREATE INDEX IF NOT EXISTS idx_prospects_etab_sourcing
  ON public.prospects_etablissements (statut_sourcing, departement, type_jolene, importe_le DESC);
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_sourcing
  ON public.prospects_soignants (statut_sourcing, departement, profession, importe_le DESC);
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_rpps
  ON public.prospects_soignants (numero_rpps) WHERE numero_rpps IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sales_contacts_email_normalise
  ON public.sales_contacts (lower(email)) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_soignants_email_normalise
  ON public.soignants (lower(email)) WHERE supprime_le IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_contacts_source_prospect
  ON public.sales_contacts (source_prospect_type, source_prospect_id)
  WHERE source_prospect_type IS NOT NULL AND source_prospect_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.sourcing_imports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_code text NOT NULL,
  cible text NOT NULL CHECK (cible IN ('ETABLISSEMENT', 'SOIGNANT')),
  statut text NOT NULL DEFAULT 'EN_COURS' CHECK (statut IN ('EN_COURS', 'TERMINE', 'ERREUR')),
  source_url text,
  source_maj_le timestamptz,
  demarre_le timestamptz NOT NULL DEFAULT now(),
  termine_le timestamptz,
  lignes_lues bigint NOT NULL DEFAULT 0,
  lignes_importees bigint NOT NULL DEFAULT 0,
  erreur text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.sourcing_imports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_all_sourcing_imports ON public.sourcing_imports;
CREATE POLICY admin_all_sourcing_imports
  ON public.sourcing_imports TO authenticated
  USING (public.est_admin()) WITH CHECK (public.est_admin());
REVOKE ALL ON TABLE public.sourcing_imports FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.sourcing_imports TO authenticated;
GRANT ALL ON TABLE public.sourcing_imports TO service_role;

-- Fusion idempotente des établissements. Les coordonnées saisies/enrichies dans
-- Jolene ne sont jamais remplacées par une valeur vide du fichier officiel.
CREATE OR REPLACE FUNCTION public.fn_sourcing_upsert_etablissements(p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_count integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.prospects_etablissements (
    finess, siret, nom, type_jolene, categorie_lib, telephone, email,
    adresse, code_postal, ville, departement, source_code, source_url,
    source_maj_le, importe_le, dernier_controle_le
  )
  SELECT r.finess, r.siret, r.nom, r.type_jolene, r.categorie_lib,
         r.telephone, r.email, r.adresse, r.code_postal, r.ville,
         r.departement, COALESCE(r.source_code, 'FINESS_DATA_GOUV'),
         r.source_url, r.source_maj_le, now(), now()
  FROM jsonb_to_recordset(COALESCE(p_rows, '[]'::jsonb)) AS r(
    finess text, siret text, nom text, type_jolene text, categorie_lib text,
    telephone text, email text, adresse text, code_postal text, ville text,
    departement text, source_code text, source_url text, source_maj_le timestamptz
  )
  WHERE r.finess IS NOT NULL AND r.nom IS NOT NULL
  ON CONFLICT (finess) DO UPDATE SET
    siret = COALESCE(EXCLUDED.siret, prospects_etablissements.siret),
    nom = EXCLUDED.nom,
    type_jolene = EXCLUDED.type_jolene,
    categorie_lib = COALESCE(EXCLUDED.categorie_lib, prospects_etablissements.categorie_lib),
    telephone = COALESCE(NULLIF(EXCLUDED.telephone, ''), prospects_etablissements.telephone),
    email = COALESCE(NULLIF(EXCLUDED.email, ''), prospects_etablissements.email),
    adresse = COALESCE(EXCLUDED.adresse, prospects_etablissements.adresse),
    code_postal = COALESCE(EXCLUDED.code_postal, prospects_etablissements.code_postal),
    ville = COALESCE(EXCLUDED.ville, prospects_etablissements.ville),
    departement = COALESCE(EXCLUDED.departement, prospects_etablissements.departement),
    source_code = EXCLUDED.source_code,
    source_url = EXCLUDED.source_url,
    source_maj_le = COALESCE(EXCLUDED.source_maj_le, prospects_etablissements.source_maj_le),
    dernier_controle_le = now(),
    maj_le = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

-- Fusion idempotente de l'extraction RPPS. La clé associe la personne à son
-- lieu d'exercice afin de conserver les coordonnées professionnelles publiques.
CREATE OR REPLACE FUNCTION public.fn_sourcing_upsert_soignants(p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_count integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.prospects_soignants (
    cle, nom, prenom, profession, enseigne, telephone, email, adresse,
    code_postal, ville, departement, est_etudiant, numero_rpps,
    mode_exercice, finess_structure, siret_structure, source_code,
    source_url, source_maj_le, importe_le, dernier_controle_le
  )
  SELECT r.cle, r.nom, r.prenom, r.profession, r.enseigne, r.telephone,
         r.email, r.adresse, r.code_postal, r.ville, r.departement,
         COALESCE(r.est_etudiant, false), r.numero_rpps, r.mode_exercice,
         r.finess_structure, r.siret_structure,
         COALESCE(r.source_code, 'ANNUAIRE_SANTE_RPPS'), r.source_url,
         r.source_maj_le, now(), now()
  FROM jsonb_to_recordset(COALESCE(p_rows, '[]'::jsonb)) AS r(
    cle text, nom text, prenom text, profession text, enseigne text,
    telephone text, email text, adresse text, code_postal text, ville text,
    departement text, est_etudiant boolean, numero_rpps text,
    mode_exercice text, finess_structure text, siret_structure text,
    source_code text, source_url text, source_maj_le timestamptz
  )
  WHERE r.cle IS NOT NULL AND r.nom IS NOT NULL AND r.profession IS NOT NULL
  ON CONFLICT (cle) DO UPDATE SET
    nom = EXCLUDED.nom,
    prenom = EXCLUDED.prenom,
    profession = EXCLUDED.profession,
    enseigne = COALESCE(EXCLUDED.enseigne, prospects_soignants.enseigne),
    telephone = COALESCE(NULLIF(EXCLUDED.telephone, ''), prospects_soignants.telephone),
    email = COALESCE(NULLIF(EXCLUDED.email, ''), prospects_soignants.email),
    adresse = COALESCE(EXCLUDED.adresse, prospects_soignants.adresse),
    code_postal = COALESCE(EXCLUDED.code_postal, prospects_soignants.code_postal),
    ville = COALESCE(EXCLUDED.ville, prospects_soignants.ville),
    departement = COALESCE(EXCLUDED.departement, prospects_soignants.departement),
    est_etudiant = EXCLUDED.est_etudiant,
    numero_rpps = COALESCE(EXCLUDED.numero_rpps, prospects_soignants.numero_rpps),
    mode_exercice = COALESCE(EXCLUDED.mode_exercice, prospects_soignants.mode_exercice),
    finess_structure = COALESCE(EXCLUDED.finess_structure, prospects_soignants.finess_structure),
    siret_structure = COALESCE(EXCLUDED.siret_structure, prospects_soignants.siret_structure),
    source_code = EXCLUDED.source_code,
    source_url = EXCLUDED.source_url,
    source_maj_le = COALESCE(EXCLUDED.source_maj_le, prospects_soignants.source_maj_le),
    dernier_controle_le = now(),
    maj_le = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

-- Vue de pilotage unifiée : score déterministe et explicable, calculé sur la
-- contactabilité, la fraîcheur officielle, la demande Jolene et les doublons.
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
  v_total bigint := 0;
  v_nouveaux bigint := 0;
  v_contactables bigint := 0;
  v_hors_crm bigint := 0;
  v_resultats jsonb := '[]'::jsonb;
  v_besoins jsonb := '[]'::jsonb;
  v_imports jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;
  IF v_cible NOT IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    RAISE EXCEPTION 'Cible invalide';
  END IF;

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
    ), calc AS (
      SELECT p.*,
        EXISTS (
          SELECT 1 FROM public.sales_contacts c
          WHERE c.source_prospect_type = 'SOIGNANT' AND c.source_prospect_id = p.cle
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
      FROM public.prospects_soignants p
      LEFT JOIN demandes d ON d.profession = p.profession AND d.departement = p.departement
      WHERE p.statut_sourcing NOT IN ('IGNORE', 'OPPOSITION')
        AND (p_departement IS NULL OR p_departement = '' OR p.departement = lpad(upper(p_departement), 2, '0'))
        AND (p_profession IS NULL OR p_profession = '' OR p.profession = upper(p_profession))
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
      SELECT * FROM scores s
      WHERE (NOT p_nouveaux OR s.importe_le >= now() - interval '30 days')
        AND (NOT p_contactables OR NULLIF(btrim(s.email), '') IS NOT NULL OR NULLIF(btrim(s.telephone), '') IS NOT NULL)
        AND (NOT p_hors_crm OR (NOT s.deja_crm AND NOT s.deja_inscrit))
    )
    SELECT count(*),
           count(*) FILTER (WHERE importe_le >= now() - interval '30 days'),
           count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
           count(*) FILTER (WHERE NOT deja_crm AND NOT deja_inscrit),
           COALESCE((
             SELECT jsonb_agg(to_jsonb(x) ORDER BY x.score DESC, x.missions_ouvertes DESC, x.nom)
             FROM (
               SELECT cle AS id, 'SOIGNANT'::text AS cible, nom, prenom,
                      profession, enseigne AS sous_titre, telephone, email,
                      ville, departement, code_postal, numero_rpps,
                      mode_exercice, finess_structure, NULL::text AS type_etab,
                      source_code, source_url, source_maj_le, importe_le,
                      statut_sourcing, deja_crm, deja_inscrit,
                      missions_ouvertes, score
               FROM filtres
               ORDER BY score DESC, missions_ouvertes DESC, nom
               LIMIT v_par_page OFFSET (v_page - 1) * v_par_page
             ) x
           ), '[]'::jsonb)
      INTO v_total, v_nouveaux, v_contactables, v_hors_crm, v_resultats
      FROM filtres;
  ELSE
    WITH calc AS (
      SELECT p.*,
        EXISTS (SELECT 1 FROM public.sales_contacts c WHERE c.finess = p.finess
          OR (p.email IS NOT NULL AND lower(c.email) = lower(p.email))
          OR (p.telephone IS NOT NULL AND length(regexp_replace(p.telephone, '\\D', '', 'g')) >= 9
              AND regexp_replace(c.telephone, '\\D', '', 'g') = regexp_replace(p.telephone, '\\D', '', 'g'))) AS deja_crm,
        EXISTS (SELECT 1 FROM public.etablissements e WHERE e.supprime_le IS NULL AND (
          e.finess = p.finess OR (p.siret IS NOT NULL AND e.siret = p.siret)
          OR (p.email IS NOT NULL AND lower(e.email_contact) = lower(p.email)))) AS deja_inscrit
      FROM public.prospects_etablissements p
      WHERE p.statut_sourcing NOT IN ('IGNORE', 'OPPOSITION')
        AND (p_departement IS NULL OR p_departement = '' OR p.departement = upper(p_departement))
        AND (p_type_etab IS NULL OR p_type_etab = '' OR p.type_jolene = upper(p_type_etab))
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
      SELECT * FROM scores s
      WHERE (NOT p_nouveaux OR s.importe_le >= now() - interval '30 days')
        AND (NOT p_contactables OR NULLIF(btrim(s.email), '') IS NOT NULL OR NULLIF(btrim(s.telephone), '') IS NOT NULL)
        AND (NOT p_hors_crm OR (NOT s.deja_crm AND NOT s.deja_inscrit))
    )
    SELECT count(*),
           count(*) FILTER (WHERE importe_le >= now() - interval '30 days'),
           count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
           count(*) FILTER (WHERE NOT deja_crm AND NOT deja_inscrit),
           COALESCE((
             SELECT jsonb_agg(to_jsonb(x) ORDER BY x.score DESC, x.nom)
             FROM (
               SELECT finess AS id, 'ETABLISSEMENT'::text AS cible, nom,
                      NULL::text AS prenom, NULL::text AS profession,
                      categorie_lib AS sous_titre, telephone, email, ville,
                      departement, code_postal, NULL::text AS numero_rpps,
                      NULL::text AS mode_exercice, finess AS finess_structure,
                      type_jolene AS type_etab, source_code, source_url,
                      source_maj_le, importe_le, statut_sourcing, deja_crm,
                      deja_inscrit, 0::integer AS missions_ouvertes, score
               FROM filtres
               ORDER BY score DESC, nom
               LIMIT v_par_page OFFSET (v_page - 1) * v_par_page
             ) x
           ), '[]'::jsonb)
      INTO v_total, v_nouveaux, v_contactables, v_hors_crm, v_resultats
      FROM filtres;
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
    GROUP BY 1, 2
    ORDER BY 3 DESC
    LIMIT 12
  ) b;

  SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.demarre_le DESC), '[]'::jsonb)
    INTO v_imports
  FROM (
    SELECT id, source_code, cible, statut, source_maj_le, demarre_le,
           termine_le, lignes_lues, lignes_importees, erreur
    FROM public.sourcing_imports
    ORDER BY demarre_le DESC LIMIT 6
  ) i;

  RETURN jsonb_build_object(
    'stats', jsonb_build_object(
      'total', v_total, 'nouveaux_30j', v_nouveaux,
      'contactables', v_contactables, 'hors_crm', v_hors_crm
    ),
    'resultats', v_resultats,
    'besoins', v_besoins,
    'imports', v_imports,
    'page', v_page,
    'par_page', v_par_page,
    'total_pages', ceil(v_total::numeric / v_par_page),
    'genere_le', now()
  );
END;
$fn$;

-- Ajout volontaire au CRM. Une découverte ne peut pas activer une séquence :
-- cela garantit qu'aucun prospect nouvellement importé n'est contacté seul.
CREATE OR REPLACE FUNCTION public.fn_admin_sourcing_ajouter_crm(
  p_cible text,
  p_prospect_id text,
  p_score smallint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_cible text := upper(COALESCE(p_cible, ''));
  v_contact_id uuid;
  v_etab public.prospects_etablissements%ROWTYPE;
  v_soignant public.prospects_soignants%ROWTYPE;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;

  IF v_cible = 'ETABLISSEMENT' THEN
    SELECT * INTO v_etab FROM public.prospects_etablissements WHERE finess = p_prospect_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Prospect etablissement introuvable'; END IF;

    INSERT INTO public.sales_contacts (
      type, nom, telephone, email, ville, departement, type_etab, finess,
      statut, notes, source_prospect_type, source_prospect_id,
      source_donnees, score_sourcing, sequence_active, prochaine_action_le
    ) VALUES (
      'ETABLISSEMENT', v_etab.nom, v_etab.telephone, v_etab.email,
      v_etab.ville, v_etab.departement, v_etab.type_jolene, v_etab.finess,
      'PROSPECT', 'Source officielle FINESS ' || v_etab.finess,
      'ETABLISSEMENT', v_etab.finess, v_etab.source_code, p_score,
      false, NULL
    )
    ON CONFLICT (finess) DO UPDATE SET
      telephone = COALESCE(sales_contacts.telephone, EXCLUDED.telephone),
      email = COALESCE(sales_contacts.email, EXCLUDED.email),
      source_prospect_type = COALESCE(sales_contacts.source_prospect_type, EXCLUDED.source_prospect_type),
      source_prospect_id = COALESCE(sales_contacts.source_prospect_id, EXCLUDED.source_prospect_id),
      source_donnees = COALESCE(sales_contacts.source_donnees, EXCLUDED.source_donnees),
      score_sourcing = COALESCE(EXCLUDED.score_sourcing, sales_contacts.score_sourcing),
      maj_le = now()
    RETURNING id INTO v_contact_id;

    UPDATE public.prospects_etablissements
       SET ajoute_crm_le = COALESCE(ajoute_crm_le, now()), statut_sourcing = 'QUALIFIE'
     WHERE finess = p_prospect_id;
  ELSIF v_cible = 'SOIGNANT' THEN
    SELECT * INTO v_soignant FROM public.prospects_soignants WHERE cle = p_prospect_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Prospect soignant introuvable'; END IF;

    SELECT c.id INTO v_contact_id
      FROM public.sales_contacts c
     WHERE (c.source_prospect_type = 'SOIGNANT' AND c.source_prospect_id = v_soignant.cle)
        OR (v_soignant.email IS NOT NULL AND lower(c.email) = lower(v_soignant.email))
        OR (v_soignant.telephone IS NOT NULL
            AND length(regexp_replace(v_soignant.telephone, '\\D', '', 'g')) >= 9
            AND regexp_replace(c.telephone, '\\D', '', 'g') = regexp_replace(v_soignant.telephone, '\\D', '', 'g'))
     ORDER BY c.cree_le LIMIT 1;

    IF v_contact_id IS NULL THEN
      INSERT INTO public.sales_contacts (
        type, nom, profession, telephone, email, ville, departement,
        statut, notes, source_prospect_type, source_prospect_id,
        source_donnees, score_sourcing, sequence_active, prochaine_action_le
      ) VALUES (
        'SOIGNANT', concat_ws(' ', v_soignant.prenom, v_soignant.nom),
        v_soignant.profession, v_soignant.telephone, v_soignant.email,
        v_soignant.ville, v_soignant.departement, 'PROSPECT',
        'Source officielle Annuaire Sante' || CASE WHEN v_soignant.numero_rpps IS NOT NULL THEN ' - RPPS ' || v_soignant.numero_rpps ELSE '' END,
        'SOIGNANT', v_soignant.cle, v_soignant.source_code, p_score,
        false, NULL
      ) RETURNING id INTO v_contact_id;
    ELSE
      UPDATE public.sales_contacts
         SET source_prospect_type = COALESCE(source_prospect_type, 'SOIGNANT'),
             source_prospect_id = COALESCE(source_prospect_id, v_soignant.cle),
             source_donnees = COALESCE(source_donnees, v_soignant.source_code),
             score_sourcing = COALESCE(p_score, score_sourcing),
             maj_le = now()
       WHERE id = v_contact_id;
    END IF;

    UPDATE public.prospects_soignants
       SET ajoute_crm_le = COALESCE(ajoute_crm_le, now()), statut_sourcing = 'QUALIFIE'
     WHERE cle = p_prospect_id;
  ELSE
    RAISE EXCEPTION 'Cible invalide';
  END IF;

  RETURN jsonb_build_object('success', true, 'contact_id', v_contact_id, 'sequence_active', false);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_sourcing_qualifier(
  p_cible text,
  p_prospect_id text,
  p_statut text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_statut text := upper(COALESCE(p_statut, ''));
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501'; END IF;
  IF v_statut NOT IN ('A_QUALIFIER', 'QUALIFIE', 'IGNORE', 'OPPOSITION') THEN RAISE EXCEPTION 'Statut invalide'; END IF;
  IF upper(p_cible) = 'ETABLISSEMENT' THEN
    UPDATE public.prospects_etablissements SET statut_sourcing = v_statut WHERE finess = p_prospect_id;
  ELSIF upper(p_cible) = 'SOIGNANT' THEN
    UPDATE public.prospects_soignants SET statut_sourcing = v_statut WHERE cle = p_prospect_id;
  ELSE
    RAISE EXCEPTION 'Cible invalide';
  END IF;
END;
$fn$;

-- Lance uniquement une synchronisation d'annuaire. Cette fonction n'appelle
-- aucune fonction d'outreach et n'active aucune séquence CRM.
CREATE OR REPLACE FUNCTION public.fn_sourcing_lancer_import(p_cible text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth, vault, extensions
AS $fn$
DECLARE
  v_cible text := upper(COALESCE(p_cible, ''));
  v_source text;
  v_fonction text;
  v_url text;
  v_token text;
  v_request_id bigint;
  v_run_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  IF v_cible = 'SOIGNANT' THEN
    v_source := 'ANNUAIRE_SANTE_RPPS';
    v_fonction := 'import-annuaire-rpps';
  ELSIF v_cible = 'ETABLISSEMENT' THEN
    v_source := 'FINESS_DATA_GOUV';
    v_fonction := 'import-finess';
  ELSE
    RAISE EXCEPTION 'Cible invalide';
  END IF;

  SELECT i.id INTO v_run_id
  FROM public.sourcing_imports i
  WHERE i.source_code = v_source
    AND i.statut = 'EN_COURS'
    AND i.demarre_le >= now() - interval '6 hours'
  ORDER BY i.demarre_le DESC LIMIT 1;

  IF v_run_id IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'already_running', true, 'run_id', v_run_id);
  END IF;

  SELECT NULLIF(btrim(ds.decrypted_secret), '') INTO v_url
  FROM vault.decrypted_secrets ds WHERE ds.name = 'supabase_url' LIMIT 1;
  v_token := public.fn_lire_secret_cron();
  IF v_url IS NULL OR v_token IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Secrets cron sourcing indisponibles');
  END IF;

  SELECT net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/' || v_fonction,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_token
    ),
    body := jsonb_build_object('offset', 0),
    timeout_milliseconds := 5000
  ) INTO v_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'cible', v_cible,
    'source', v_source,
    'request_id', v_request_id,
    'silencieux', true
  );
END;
$fn$;

-- Synchronisation hebdomadaire des deux référentiels. Elle alimente seulement
-- la file de découverte ; elle ne crée pas de tâche et ne contacte personne.
DO $cron$
DECLARE v_job record;
BEGIN
  FOR v_job IN
    SELECT jobid FROM cron.job
    WHERE jobname IN ('jolene_sourcing_rpps_hebdo', 'jolene_sourcing_finess_hebdo')
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
  PERFORM cron.schedule(
    'jolene_sourcing_rpps_hebdo',
    '15 3 * * 0',
    $job$SELECT public.fn_sourcing_lancer_import('SOIGNANT');$job$
  );
  PERFORM cron.schedule(
    'jolene_sourcing_finess_hebdo',
    '45 3 * * 0',
    $job$SELECT public.fn_sourcing_lancer_import('ETABLISSEMENT');$job$
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name THEN
    RAISE NOTICE 'pg_cron indisponible : imports sourcing non planifies';
END;
$cron$;

REVOKE ALL ON FUNCTION public.fn_sourcing_upsert_etablissements(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_sourcing_upsert_soignants(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sourcing_upsert_etablissements(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_sourcing_upsert_soignants(jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.fn_admin_sourcing_tableau(text, text, text, text, boolean, boolean, boolean, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_sourcing_ajouter_crm(text, text, smallint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_sourcing_qualifier(text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_sourcing_lancer_import(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_sourcing_tableau(text, text, text, text, boolean, boolean, boolean, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_sourcing_ajouter_crm(text, text, smallint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_sourcing_qualifier(text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_sourcing_lancer_import(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_sourcing_ajouter_crm(text, text, smallint) IS
  'Ajout manuel d un prospect au CRM. La sequence reste desactivee : aucun contact automatique.';
