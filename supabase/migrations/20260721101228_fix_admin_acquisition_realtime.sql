-- Corrige les faux zéros et les timeouts de la prospection admin.
-- Les compteurs sont exacts, maintenus en temps réel par triggers de niveau
-- statement (un seul ajustement par lot importé) et ne dépendent plus d'un
-- count(*) PostgREST sur 1,6 million de lignes.

-- Les comptes clients restent bornés à 8 s. Seule cette migration de
-- maintenance bénéficie d'une fenêtre plus longue pour construire les index
-- nationaux une fois, sans relever le timeout de l'application.
SET LOCAL statement_timeout = '10min';
SET LOCAL lock_timeout = '30s';

CREATE TABLE IF NOT EXISTS public.prospection_compteurs (
  cible text PRIMARY KEY CHECK (cible IN ('SOIGNANT', 'ETABLISSEMENT')),
  total bigint NOT NULL DEFAULT 0 CHECK (total >= 0),
  avec_email bigint NOT NULL DEFAULT 0 CHECK (avec_email >= 0),
  avec_email_non_contacte bigint NOT NULL DEFAULT 0 CHECK (avec_email_non_contacte >= 0),
  avec_telephone bigint NOT NULL DEFAULT 0 CHECK (avec_telephone >= 0),
  contactables bigint NOT NULL DEFAULT 0 CHECK (contactables >= 0),
  nouveaux_30j bigint NOT NULL DEFAULT 0 CHECK (nouveaux_30j >= 0),
  maj_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.prospection_compteurs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.prospection_compteurs FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.prospection_compteurs TO service_role;

CREATE OR REPLACE FUNCTION public.fn_prospection_compteur_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_cible text := CASE TG_TABLE_NAME
    WHEN 'prospects_soignants' THEN 'SOIGNANT'
    ELSE 'ETABLISSEMENT'
  END;
  v_total bigint;
  v_email bigint;
  v_email_non_contacte bigint;
  v_telephone bigint;
  v_contactables bigint;
  v_nouveaux bigint;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL),
         count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE importe_le >= now() - interval '30 days')
    INTO v_total, v_email, v_email_non_contacte, v_telephone, v_contactables, v_nouveaux
    FROM new_rows;

  INSERT INTO public.prospection_compteurs (
    cible, total, avec_email, avec_email_non_contacte, avec_telephone,
    contactables, nouveaux_30j, maj_le
  ) VALUES (
    v_cible, v_total, v_email, v_email_non_contacte, v_telephone,
    v_contactables, v_nouveaux, now()
  )
  ON CONFLICT (cible) DO UPDATE SET
    total = prospection_compteurs.total + EXCLUDED.total,
    avec_email = prospection_compteurs.avec_email + EXCLUDED.avec_email,
    avec_email_non_contacte = prospection_compteurs.avec_email_non_contacte + EXCLUDED.avec_email_non_contacte,
    avec_telephone = prospection_compteurs.avec_telephone + EXCLUDED.avec_telephone,
    contactables = prospection_compteurs.contactables + EXCLUDED.contactables,
    nouveaux_30j = prospection_compteurs.nouveaux_30j + EXCLUDED.nouveaux_30j,
    maj_le = now();
  RETURN NULL;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_prospection_compteur_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_cible text := CASE TG_TABLE_NAME
    WHEN 'prospects_soignants' THEN 'SOIGNANT'
    ELSE 'ETABLISSEMENT'
  END;
  v_email_delta bigint;
  v_email_non_contacte_delta bigint;
  v_telephone_delta bigint;
  v_contactables_delta bigint;
  v_nouveaux_delta bigint;
BEGIN
  SELECT
    (SELECT count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL) FROM new_rows)
      - (SELECT count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL) FROM old_rows),
    (SELECT count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL) FROM new_rows)
      - (SELECT count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL) FROM old_rows),
    (SELECT count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL) FROM new_rows)
      - (SELECT count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL) FROM old_rows),
    (SELECT count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL) FROM new_rows)
      - (SELECT count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL) FROM old_rows),
    (SELECT count(*) FILTER (WHERE importe_le >= now() - interval '30 days') FROM new_rows)
      - (SELECT count(*) FILTER (WHERE importe_le >= now() - interval '30 days') FROM old_rows)
    INTO v_email_delta, v_email_non_contacte_delta, v_telephone_delta,
         v_contactables_delta, v_nouveaux_delta;

  UPDATE public.prospection_compteurs SET
    avec_email = GREATEST(0, avec_email + v_email_delta),
    avec_email_non_contacte = GREATEST(0, avec_email_non_contacte + v_email_non_contacte_delta),
    avec_telephone = GREATEST(0, avec_telephone + v_telephone_delta),
    contactables = GREATEST(0, contactables + v_contactables_delta),
    nouveaux_30j = GREATEST(0, nouveaux_30j + v_nouveaux_delta),
    maj_le = now()
  WHERE cible = v_cible;
  RETURN NULL;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_prospection_compteur_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_cible text := CASE TG_TABLE_NAME
    WHEN 'prospects_soignants' THEN 'SOIGNANT'
    ELSE 'ETABLISSEMENT'
  END;
  v_total bigint;
  v_email bigint;
  v_email_non_contacte bigint;
  v_telephone bigint;
  v_contactables bigint;
  v_nouveaux bigint;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL),
         count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE importe_le >= now() - interval '30 days')
    INTO v_total, v_email, v_email_non_contacte, v_telephone, v_contactables, v_nouveaux
    FROM old_rows;

  UPDATE public.prospection_compteurs SET
    total = GREATEST(0, total - v_total),
    avec_email = GREATEST(0, avec_email - v_email),
    avec_email_non_contacte = GREATEST(0, avec_email_non_contacte - v_email_non_contacte),
    avec_telephone = GREATEST(0, avec_telephone - v_telephone),
    contactables = GREATEST(0, contactables - v_contactables),
    nouveaux_30j = GREATEST(0, nouveaux_30j - v_nouveaux),
    maj_le = now()
  WHERE cible = v_cible;
  RETURN NULL;
END;
$fn$;

-- Ces fonctions sont exclusivement appelees par leurs triggers. Elles ne
-- constituent pas des RPC et ne doivent jamais etre invocables par un client.
REVOKE ALL ON FUNCTION public.fn_prospection_compteur_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_prospection_compteur_update() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_prospection_compteur_delete() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_prospection_compteur_insert() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_prospection_compteur_update() TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_prospection_compteur_delete() TO service_role;

-- Ferme la seule fenêtre possible entre l'amorçage et l'installation des
-- triggers. Les imports officiels attendent la fin de cette transaction ;
-- aucune ligne ne peut donc échapper aux compteurs.
LOCK TABLE public.prospects_soignants, public.prospects_etablissements
  IN SHARE ROW EXCLUSIVE MODE;

-- Amorçage exact unique. Les futurs imports ajustent ces valeurs par lot.
INSERT INTO public.prospection_compteurs (
  cible, total, avec_email, avec_email_non_contacte, avec_telephone,
  contactables, nouveaux_30j, maj_le
)
SELECT 'SOIGNANT', count(*),
       count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL),
       count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL),
       count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL),
       count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
       count(*) FILTER (WHERE importe_le >= now() - interval '30 days'), now()
FROM public.prospects_soignants
ON CONFLICT (cible) DO UPDATE SET
  total = EXCLUDED.total,
  avec_email = EXCLUDED.avec_email,
  avec_email_non_contacte = EXCLUDED.avec_email_non_contacte,
  avec_telephone = EXCLUDED.avec_telephone,
  contactables = EXCLUDED.contactables,
  nouveaux_30j = EXCLUDED.nouveaux_30j,
  maj_le = now();

INSERT INTO public.prospection_compteurs (
  cible, total, avec_email, avec_email_non_contacte, avec_telephone,
  contactables, nouveaux_30j, maj_le
)
SELECT 'ETABLISSEMENT', count(*),
       count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL),
       count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL),
       count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL),
       count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
       count(*) FILTER (WHERE importe_le >= now() - interval '30 days'), now()
FROM public.prospects_etablissements
ON CONFLICT (cible) DO UPDATE SET
  total = EXCLUDED.total,
  avec_email = EXCLUDED.avec_email,
  avec_email_non_contacte = EXCLUDED.avec_email_non_contacte,
  avec_telephone = EXCLUDED.avec_telephone,
  contactables = EXCLUDED.contactables,
  nouveaux_30j = EXCLUDED.nouveaux_30j,
  maj_le = now();

DROP TRIGGER IF EXISTS trg_prospects_soignants_compteur_insert ON public.prospects_soignants;
CREATE TRIGGER trg_prospects_soignants_compteur_insert
AFTER INSERT ON public.prospects_soignants
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prospection_compteur_insert();
DROP TRIGGER IF EXISTS trg_prospects_soignants_compteur_update ON public.prospects_soignants;
CREATE TRIGGER trg_prospects_soignants_compteur_update
AFTER UPDATE ON public.prospects_soignants
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prospection_compteur_update();
DROP TRIGGER IF EXISTS trg_prospects_soignants_compteur_delete ON public.prospects_soignants;
CREATE TRIGGER trg_prospects_soignants_compteur_delete
AFTER DELETE ON public.prospects_soignants
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prospection_compteur_delete();

DROP TRIGGER IF EXISTS trg_prospects_etablissements_compteur_insert ON public.prospects_etablissements;
CREATE TRIGGER trg_prospects_etablissements_compteur_insert
AFTER INSERT ON public.prospects_etablissements
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prospection_compteur_insert();
DROP TRIGGER IF EXISTS trg_prospects_etablissements_compteur_update ON public.prospects_etablissements;
CREATE TRIGGER trg_prospects_etablissements_compteur_update
AFTER UPDATE ON public.prospects_etablissements
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prospection_compteur_update();
DROP TRIGGER IF EXISTS trg_prospects_etablissements_compteur_delete ON public.prospects_etablissements;
CREATE TRIGGER trg_prospects_etablissements_compteur_delete
AFTER DELETE ON public.prospects_etablissements
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION public.fn_prospection_compteur_delete();

CREATE OR REPLACE FUNCTION public.fn_rafraichir_prospection_compteurs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_soignants bigint; v_etablissements bigint;
BEGIN
  INSERT INTO public.prospection_compteurs (
    cible, total, avec_email, avec_email_non_contacte, avec_telephone,
    contactables, nouveaux_30j, maj_le
  )
  SELECT 'SOIGNANT', count(*),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL),
         count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE importe_le >= now() - interval '30 days'), now()
  FROM public.prospects_soignants
  ON CONFLICT (cible) DO UPDATE SET
    total = EXCLUDED.total, avec_email = EXCLUDED.avec_email,
    avec_email_non_contacte = EXCLUDED.avec_email_non_contacte,
    avec_telephone = EXCLUDED.avec_telephone, contactables = EXCLUDED.contactables,
    nouveaux_30j = EXCLUDED.nouveaux_30j, maj_le = now()
  RETURNING total INTO v_soignants;

  INSERT INTO public.prospection_compteurs (
    cible, total, avec_email, avec_email_non_contacte, avec_telephone,
    contactables, nouveaux_30j, maj_le
  )
  SELECT 'ETABLISSEMENT', count(*),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL AND email_envoye_le IS NULL),
         count(*) FILTER (WHERE NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE NULLIF(btrim(email), '') IS NOT NULL OR NULLIF(btrim(telephone), '') IS NOT NULL),
         count(*) FILTER (WHERE importe_le >= now() - interval '30 days'), now()
  FROM public.prospects_etablissements
  ON CONFLICT (cible) DO UPDATE SET
    total = EXCLUDED.total, avec_email = EXCLUDED.avec_email,
    avec_email_non_contacte = EXCLUDED.avec_email_non_contacte,
    avec_telephone = EXCLUDED.avec_telephone, contactables = EXCLUDED.contactables,
    nouveaux_30j = EXCLUDED.nouveaux_30j, maj_le = now()
  RETURNING total INTO v_etablissements;

  RETURN jsonb_build_object(
    'soignants', COALESCE(v_soignants, 0),
    'etablissements', COALESCE(v_etablissements, 0),
    'maj_le', now()
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_rafraichir_prospection_compteurs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_rafraichir_prospection_compteurs() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_prospection_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'soignants', COALESCE((SELECT to_jsonb(c) - 'cible' FROM public.prospection_compteurs c WHERE cible = 'SOIGNANT'), '{}'::jsonb),
    'etablissements', COALESCE((SELECT to_jsonb(c) - 'cible' FROM public.prospection_compteurs c WHERE cible = 'ETABLISSEMENT'), '{}'::jsonb),
    'crm_soignants', (SELECT count(*) FROM public.sales_contacts WHERE type = 'SOIGNANT' AND NOT COALESCE(archive, false)),
    'crm_etablissements', (SELECT count(*) FROM public.sales_contacts WHERE type = 'ETABLISSEMENT' AND NOT COALESCE(archive, false)),
    'exact', true,
    'genere_le', now()
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_prospection_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_prospection_stats() TO authenticated, service_role;

-- L'évaluation admin devient un initplan unique au lieu d'être rejouée pour
-- chaque ligne lors des lectures directes PostgREST.
DROP POLICY IF EXISTS admin_all_prospects_soignants ON public.prospects_soignants;
CREATE POLICY admin_all_prospects_soignants ON public.prospects_soignants
  FOR ALL TO authenticated
  USING ((SELECT public.est_admin()))
  WITH CHECK ((SELECT public.est_admin()));
DROP POLICY IF EXISTS admin_all_prospects_etab ON public.prospects_etablissements;
CREATE POLICY admin_all_prospects_etab ON public.prospects_etablissements
  FOR ALL TO authenticated
  USING ((SELECT public.est_admin()))
  WITH CHECK ((SELECT public.est_admin()));
DROP POLICY IF EXISTS admin_all_sales_contacts ON public.sales_contacts;
CREATE POLICY admin_all_sales_contacts ON public.sales_contacts
  FOR ALL TO authenticated
  USING ((SELECT public.est_admin()))
  WITH CHECK ((SELECT public.est_admin()));

-- Index compatibles avec le tri de la page et les filtres fréquents.
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_browse
  ON public.prospects_soignants (favori DESC, departement, ville, nom, cle);
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_prof_browse
  ON public.prospects_soignants (profession, favori DESC, departement, ville, nom, cle);
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_email_filtre
  ON public.prospects_soignants (profession, departement, cle)
  WHERE NULLIF(btrim(email), '') IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_tel_filtre
  ON public.prospects_soignants (profession, departement, cle)
  WHERE NULLIF(btrim(telephone), '') IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_prospects_etab_browse
  ON public.prospects_etablissements (favori DESC, departement, nom, finess);
CREATE INDEX IF NOT EXISTS idx_prospects_etab_type_browse
  ON public.prospects_etablissements (type_jolene, favori DESC, departement, nom, finess);
CREATE INDEX IF NOT EXISTS idx_prospects_soignants_enrichissables
  ON public.prospects_soignants (maj_le, cle)
  WHERE enrichi_le IS NULL
    AND NULLIF(btrim(numero_rpps), '') IS NOT NULL
    AND (NULLIF(btrim(email), '') IS NULL OR NULLIF(btrim(telephone), '') IS NULL);
CREATE INDEX IF NOT EXISTS idx_prospects_etab_enrichissables
  ON public.prospects_etablissements (maj_le, finess)
  WHERE enrichi_le IS NULL
    AND (NULLIF(btrim(email), '') IS NULL OR NULLIF(btrim(telephone), '') IS NULL);

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects_soignants(
  p_profession text DEFAULT NULL,
  p_departement text DEFAULT NULL,
  p_q text DEFAULT NULL,
  p_favoris boolean DEFAULT false,
  p_page integer DEFAULT 1,
  p_avec_email boolean DEFAULT false,
  p_avec_tel boolean DEFAULT false,
  p_etudiants boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_total bigint;
  v_res jsonb;
  v_page integer := GREATEST(COALESCE(p_page, 1), 1);
  v_profession text := NULLIF(upper(btrim(COALESCE(p_profession, ''))), '');
  v_departement text := NULLIF(upper(btrim(COALESCE(p_departement, ''))), '');
  v_q text := NULLIF(btrim(COALESCE(p_q, '')), '');
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;

  IF v_profession IS NULL AND v_departement IS NULL AND v_q IS NULL
     AND NOT p_favoris AND NOT p_avec_email AND NOT p_avec_tel AND NOT p_etudiants THEN
    SELECT total INTO v_total FROM public.prospection_compteurs WHERE cible = 'SOIGNANT';
  ELSIF v_profession IS NULL AND v_departement IS NULL AND v_q IS NULL
     AND NOT p_favoris AND p_avec_email AND NOT p_avec_tel AND NOT p_etudiants THEN
    SELECT avec_email INTO v_total FROM public.prospection_compteurs WHERE cible = 'SOIGNANT';
  ELSIF v_profession IS NULL AND v_departement IS NULL AND v_q IS NULL
     AND NOT p_favoris AND NOT p_avec_email AND p_avec_tel AND NOT p_etudiants THEN
    SELECT avec_telephone INTO v_total FROM public.prospection_compteurs WHERE cible = 'SOIGNANT';
  ELSE
    SELECT count(*) INTO v_total
    FROM public.prospects_soignants p
    WHERE (v_profession IS NULL OR p.profession = v_profession)
      AND (v_departement IS NULL OR p.departement = CASE
        WHEN v_departement ~ '^\d$' THEN lpad(v_departement, 2, '0')
        ELSE v_departement
      END)
      AND (NOT p_favoris OR p.favori)
      AND (NOT p_avec_email OR NULLIF(btrim(p.email), '') IS NOT NULL)
      AND (NOT p_avec_tel OR NULLIF(btrim(p.telephone), '') IS NOT NULL)
      AND (NOT p_etudiants OR p.est_etudiant)
      AND (v_q IS NULL OR p.nom ILIKE '%' || v_q || '%' OR p.ville ILIKE '%' || v_q || '%' OR p.enseigne ILIKE '%' || v_q || '%');
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_res
  FROM (
    SELECT p.cle, p.nom, p.prenom, p.profession, p.enseigne, p.telephone,
           p.email, p.adresse, p.code_postal, p.ville, p.departement,
           p.favori, p.est_etudiant, p.ecole, p.formation, p.numero_rpps,
           p.mode_exercice, p.finess_structure, p.siret_structure,
           p.source_code, p.source_url, p.source_maj_le, p.importe_le,
           p.statut_sourcing
    FROM public.prospects_soignants p
    WHERE (v_profession IS NULL OR p.profession = v_profession)
      AND (v_departement IS NULL OR p.departement = CASE
        WHEN v_departement ~ '^\d$' THEN lpad(v_departement, 2, '0')
        ELSE v_departement
      END)
      AND (NOT p_favoris OR p.favori)
      AND (NOT p_avec_email OR NULLIF(btrim(p.email), '') IS NOT NULL)
      AND (NOT p_avec_tel OR NULLIF(btrim(p.telephone), '') IS NOT NULL)
      AND (NOT p_etudiants OR p.est_etudiant)
      AND (v_q IS NULL OR p.nom ILIKE '%' || v_q || '%' OR p.ville ILIKE '%' || v_q || '%' OR p.enseigne ILIKE '%' || v_q || '%')
    ORDER BY p.favori DESC, p.departement, p.ville, p.nom, p.cle
    LIMIT 30 OFFSET (v_page - 1) * 30
  ) t;

  RETURN jsonb_build_object(
    'total', COALESCE(v_total, 0),
    'page', v_page,
    'total_pages', CEIL(COALESCE(v_total, 0) / 30.0),
    'resultats', v_res,
    'compteur_exact', true
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects(
  p_type text DEFAULT NULL,
  p_departement text DEFAULT NULL,
  p_q text DEFAULT NULL,
  p_favoris boolean DEFAULT false,
  p_page integer DEFAULT 1,
  p_avec_email boolean DEFAULT false,
  p_avec_tel boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_total bigint;
  v_resultats jsonb;
  v_page integer := GREATEST(COALESCE(p_page, 1), 1);
  v_type text := NULLIF(upper(btrim(COALESCE(p_type, ''))), '');
  v_departement text := NULLIF(upper(btrim(COALESCE(p_departement, ''))), '');
  v_q text := NULLIF(btrim(COALESCE(p_q, '')), '');
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;

  IF v_type IS NULL AND v_departement IS NULL AND v_q IS NULL
     AND NOT p_favoris AND NOT p_avec_email AND NOT p_avec_tel THEN
    SELECT total INTO v_total FROM public.prospection_compteurs WHERE cible = 'ETABLISSEMENT';
  ELSIF v_type IS NULL AND v_departement IS NULL AND v_q IS NULL
     AND NOT p_favoris AND p_avec_email AND NOT p_avec_tel THEN
    SELECT avec_email INTO v_total FROM public.prospection_compteurs WHERE cible = 'ETABLISSEMENT';
  ELSIF v_type IS NULL AND v_departement IS NULL AND v_q IS NULL
     AND NOT p_favoris AND NOT p_avec_email AND p_avec_tel THEN
    SELECT avec_telephone INTO v_total FROM public.prospection_compteurs WHERE cible = 'ETABLISSEMENT';
  ELSE
    SELECT count(*) INTO v_total
    FROM public.prospects_etablissements p
    WHERE (v_type IS NULL OR p.type_jolene = v_type)
      AND (v_departement IS NULL OR p.departement = v_departement)
      AND (NOT p_favoris OR p.favori)
      AND (NOT p_avec_email OR NULLIF(btrim(p.email), '') IS NOT NULL)
      AND (NOT p_avec_tel OR NULLIF(btrim(p.telephone), '') IS NOT NULL)
      AND (v_q IS NULL OR p.nom ILIKE '%' || v_q || '%' OR p.ville ILIKE '%' || v_q || '%');
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(t)), '[]'::jsonb) INTO v_resultats
  FROM (
    SELECT p.finess, p.siret, p.nom, p.type_jolene, p.categorie_lib,
           p.telephone, p.email, p.adresse, p.code_postal, p.ville,
           p.departement, p.favori, p.source_code, p.source_url,
           p.source_maj_le, p.importe_le, p.statut_sourcing
    FROM public.prospects_etablissements p
    WHERE (v_type IS NULL OR p.type_jolene = v_type)
      AND (v_departement IS NULL OR p.departement = v_departement)
      AND (NOT p_favoris OR p.favori)
      AND (NOT p_avec_email OR NULLIF(btrim(p.email), '') IS NOT NULL)
      AND (NOT p_avec_tel OR NULLIF(btrim(p.telephone), '') IS NOT NULL)
      AND (v_q IS NULL OR p.nom ILIKE '%' || v_q || '%' OR p.ville ILIKE '%' || v_q || '%')
    ORDER BY p.favori DESC, p.departement, p.nom, p.finess
    LIMIT 30 OFFSET (v_page - 1) * 30
  ) t;

  RETURN jsonb_build_object(
    'total', COALESCE(v_total, 0),
    'page', v_page,
    'total_pages', CEIL(COALESCE(v_total, 0)::numeric / 30),
    'resultats', v_resultats,
    'compteur_exact', true
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_chercher_prospects_soignants(text, text, text, boolean, integer, boolean, boolean, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_chercher_prospects(text, text, text, boolean, integer, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_chercher_prospects_soignants(text, text, text, boolean, integer, boolean, boolean, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_chercher_prospects(text, text, text, boolean, integer, boolean, boolean) TO authenticated, service_role;

-- Réclamation atomique : aucune double passe manuelle/cron sur la même fiche.
CREATE OR REPLACE FUNCTION public.fn_reclamer_prospects_enrichissement(
  p_cible text,
  p_departement text DEFAULT NULL,
  p_limite integer DEFAULT 40
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_cible text := upper(COALESCE(p_cible, ''));
  v_departement text := NULLIF(upper(btrim(COALESCE(p_departement, ''))), '');
  v_limite integer := LEAST(GREATEST(COALESCE(p_limite, 40), 1), 60);
  v_resultat jsonb;
BEGIN
  IF NOT (public.est_admin() OR COALESCE(auth.role(), '') = 'service_role'
    OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RAISE EXCEPTION 'Acces refuse' USING ERRCODE = '42501';
  END IF;

  IF v_cible = 'ETABLISSEMENT' THEN
    WITH candidats AS (
      SELECT p.finess
      FROM public.prospects_etablissements p
      WHERE p.enrichi_le IS NULL
        AND (NULLIF(btrim(p.email), '') IS NULL OR NULLIF(btrim(p.telephone), '') IS NULL)
        AND (p.dernier_controle_le IS NULL OR p.dernier_controle_le < now() - interval '15 minutes')
        AND (v_departement IS NULL OR p.departement = v_departement)
      ORDER BY p.maj_le, p.finess
      FOR UPDATE SKIP LOCKED
      LIMIT v_limite
    ), reclames AS (
      UPDATE public.prospects_etablissements p
         SET dernier_controle_le = now()
        FROM candidats c
       WHERE p.finess = c.finess
      RETURNING p.finess AS identifiant, p.finess, NULL::text AS cle,
                p.nom, NULL::text AS prenom, NULL::text AS numero_rpps,
                p.email, p.telephone
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) INTO v_resultat FROM reclames r;
  ELSIF v_cible = 'SOIGNANT' THEN
    WITH candidats AS (
      SELECT p.cle
      FROM public.prospects_soignants p
      WHERE p.enrichi_le IS NULL
        AND NULLIF(btrim(p.numero_rpps), '') IS NOT NULL
        AND (NULLIF(btrim(p.email), '') IS NULL OR NULLIF(btrim(p.telephone), '') IS NULL)
        AND (p.dernier_controle_le IS NULL OR p.dernier_controle_le < now() - interval '15 minutes')
        AND (v_departement IS NULL OR p.departement = CASE
          WHEN v_departement ~ '^\d$' THEN lpad(v_departement, 2, '0')
          ELSE v_departement
        END)
      ORDER BY p.maj_le, p.cle
      FOR UPDATE SKIP LOCKED
      LIMIT v_limite
    ), reclames AS (
      UPDATE public.prospects_soignants p
         SET dernier_controle_le = now()
        FROM candidats c
       WHERE p.cle = c.cle
      RETURNING p.cle AS identifiant, NULL::text AS finess, p.cle,
                p.nom, p.prenom, p.numero_rpps, p.email, p.telephone
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb) INTO v_resultat FROM reclames r;
  ELSE
    RAISE EXCEPTION 'Cible invalide';
  END IF;
  RETURN COALESCE(v_resultat, '[]'::jsonb);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_terminer_prospects_enrichissement(
  p_cible text,
  p_resultats jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_cible text := upper(COALESCE(p_cible, ''));
  v_traites integer := 0;
  v_emails integer := 0;
  v_telephones integer := 0;
BEGIN
  IF NOT (public.est_admin() OR COALESCE(auth.role(), '') = 'service_role'
    OR COALESCE(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
    RAISE EXCEPTION 'Acces refuse' USING ERRCODE = '42501';
  END IF;

  IF v_cible = 'ETABLISSEMENT' THEN
    WITH r AS (
      SELECT * FROM jsonb_to_recordset(COALESCE(p_resultats, '[]'::jsonb)) AS x(
        identifiant text, email text, telephone text, termine boolean
      )
    ), maj AS (
      UPDATE public.prospects_etablissements p SET
        email = CASE WHEN NULLIF(btrim(p.email), '') IS NULL THEN NULLIF(lower(btrim(r.email)), '') ELSE p.email END,
        telephone = CASE WHEN NULLIF(btrim(p.telephone), '') IS NULL THEN NULLIF(btrim(r.telephone), '') ELSE p.telephone END,
        enrichi_le = CASE WHEN COALESCE(r.termine, false) THEN now() ELSE p.enrichi_le END,
        dernier_controle_le = now(),
        maj_le = CASE WHEN (NULLIF(btrim(p.email), '') IS NULL AND NULLIF(btrim(r.email), '') IS NOT NULL)
                        OR (NULLIF(btrim(p.telephone), '') IS NULL AND NULLIF(btrim(r.telephone), '') IS NOT NULL)
                      THEN now() ELSE p.maj_le END
      FROM r WHERE p.finess = r.identifiant
      RETURNING (NULLIF(btrim(r.email), '') IS NOT NULL)::integer AS email_ajoute,
                (NULLIF(btrim(r.telephone), '') IS NOT NULL)::integer AS telephone_ajoute
    )
    SELECT count(*), COALESCE(sum(email_ajoute), 0), COALESCE(sum(telephone_ajoute), 0)
      INTO v_traites, v_emails, v_telephones FROM maj;
  ELSIF v_cible = 'SOIGNANT' THEN
    WITH r AS (
      SELECT * FROM jsonb_to_recordset(COALESCE(p_resultats, '[]'::jsonb)) AS x(
        identifiant text, email text, telephone text, termine boolean
      )
    ), maj AS (
      UPDATE public.prospects_soignants p SET
        email = CASE WHEN NULLIF(btrim(p.email), '') IS NULL THEN NULLIF(lower(btrim(r.email)), '') ELSE p.email END,
        telephone = CASE WHEN NULLIF(btrim(p.telephone), '') IS NULL THEN NULLIF(btrim(r.telephone), '') ELSE p.telephone END,
        enrichi_le = CASE WHEN COALESCE(r.termine, false) THEN now() ELSE p.enrichi_le END,
        dernier_controle_le = now(),
        maj_le = CASE WHEN (NULLIF(btrim(p.email), '') IS NULL AND NULLIF(btrim(r.email), '') IS NOT NULL)
                        OR (NULLIF(btrim(p.telephone), '') IS NULL AND NULLIF(btrim(r.telephone), '') IS NOT NULL)
                      THEN now() ELSE p.maj_le END
      FROM r WHERE p.cle = r.identifiant
      RETURNING (NULLIF(btrim(r.email), '') IS NOT NULL)::integer AS email_ajoute,
                (NULLIF(btrim(r.telephone), '') IS NOT NULL)::integer AS telephone_ajoute
    )
    SELECT count(*), COALESCE(sum(email_ajoute), 0), COALESCE(sum(telephone_ajoute), 0)
      INTO v_traites, v_emails, v_telephones FROM maj;
  ELSE
    RAISE EXCEPTION 'Cible invalide';
  END IF;

  RETURN jsonb_build_object('traites', v_traites, 'emails', v_emails, 'telephones', v_telephones);
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_reclamer_prospects_enrichissement(text, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_terminer_prospects_enrichissement(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_reclamer_prospects_enrichissement(text, text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_terminer_prospects_enrichissement(text, jsonb) TO authenticated, service_role;
