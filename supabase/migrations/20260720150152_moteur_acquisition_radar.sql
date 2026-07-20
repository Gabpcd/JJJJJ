-- Moteur d'acquisition Jolene : radar de demande, liquidite locale, comptes
-- ancres, recurrence et pilotage economique.
--
-- IMPORTANT PRELANCEMENT : cette couche ne contacte personne. Elle importe des
-- signaux publics, calcule des scores et cree uniquement des actions internes
-- au statut BROUILLON. L'ajout explicite d'un signal au CRM conserve
-- sequence_active=false et prochaine_action_le=NULL.

INSERT INTO public.growth_config (cle, valeur, maj_le)
VALUES ('automatisations_marketing_actives', 'false', now())
ON CONFLICT (cle) DO UPDATE
SET valeur = 'false', maj_le = now();

-- ---------------------------------------------------------------------------
-- 1. Sources, signaux de demande, territoires, actions internes et depenses
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.acquisition_sources (
  code text PRIMARY KEY,
  libelle text NOT NULL,
  type_source text NOT NULL CHECK (type_source IN ('ANNUAIRE', 'DEMANDE', 'TENSION', 'PARTENARIAT')),
  source_url text NOT NULL,
  automatique boolean NOT NULL DEFAULT false,
  actif boolean NOT NULL DEFAULT false,
  configuration_requise text,
  dernier_import_le timestamptz,
  dernier_statut text CHECK (dernier_statut IS NULL OR dernier_statut IN ('OK', 'ERREUR', 'NON_CONFIGURE')),
  dernier_message text,
  maj_le timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.acquisition_sources (
  code, libelle, type_source, source_url, automatique, actif, configuration_requise
) VALUES
  ('FINESS_DATA_GOUV', 'FINESS / data.gouv.fr', 'ANNUAIRE',
   'https://www.data.gouv.fr/datasets/reexposition-des-donnees-finess', true, true, NULL),
  ('ANNUAIRE_SANTE_RPPS', 'Annuaire Sante / RPPS', 'ANNUAIRE',
   'https://www.data.gouv.fr/datasets/annuaire-sante-extractions-des-donnees-en-libre-acces', true, true, NULL),
  ('FRANCE_TRAVAIL_OFFRES', 'France Travail — offres actives', 'DEMANDE',
   'https://www.data.gouv.fr/dataservices/api-offres-demploi', false, false,
   'FRANCE_TRAVAIL_CLIENT_ID + FRANCE_TRAVAIL_CLIENT_SECRET'),
  ('BMO_FRANCE_TRAVAIL', 'France Travail — BMO 2026', 'TENSION',
   'https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo', false, true, NULL),
  ('FHF_MANUEL', 'Federation hospitaliere de France', 'DEMANDE',
   'https://emploi.fhf.fr/', false, true, NULL),
  ('BOAMP_MANUEL', 'BOAMP / marches publics', 'DEMANDE',
   'https://www.boamp.fr/', false, true, NULL)
ON CONFLICT (code) DO UPDATE SET
  libelle = EXCLUDED.libelle,
  type_source = EXCLUDED.type_source,
  source_url = EXCLUDED.source_url,
  configuration_requise = EXCLUDED.configuration_requise,
  maj_le = now();

CREATE TABLE IF NOT EXISTS public.acquisition_signaux (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_code text NOT NULL REFERENCES public.acquisition_sources(code),
  source_id text NOT NULL,
  source_url text,
  etablissement_id uuid REFERENCES public.etablissements(id) ON DELETE SET NULL,
  finess text,
  siret text,
  nom_etablissement text NOT NULL,
  intitule text NOT NULL,
  profession text,
  departement text,
  ville text,
  type_contrat text,
  publie_le timestamptz,
  expire_le timestamptz,
  volume_estime integer NOT NULL DEFAULT 1 CHECK (volume_estime BETWEEN 1 AND 10000),
  score_demande smallint NOT NULL DEFAULT 50 CHECK (score_demande BETWEEN 0 AND 100),
  statut text NOT NULL DEFAULT 'NOUVEAU'
    CHECK (statut IN ('NOUVEAU', 'QUALIFIE', 'CRM', 'CONVERTI', 'IGNORE', 'EXPIRE')),
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  importe_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_code, source_id)
);

CREATE INDEX IF NOT EXISTS idx_acquisition_signaux_radar
  ON public.acquisition_signaux (statut, score_demande DESC, maj_le DESC);
CREATE INDEX IF NOT EXISTS idx_acquisition_signaux_territoire
  ON public.acquisition_signaux (departement, profession, statut);
CREATE INDEX IF NOT EXISTS idx_acquisition_signaux_identifiants
  ON public.acquisition_signaux (finess, siret);

CREATE TABLE IF NOT EXISTS public.acquisition_territoires (
  departement text NOT NULL,
  profession text NOT NULL,
  statut text NOT NULL DEFAULT 'OBSERVATION'
    CHECK (statut IN ('OBSERVATION', 'PREPARATION', 'OUVERT', 'PAUSE')),
  objectif_etablissements_ancres integer NOT NULL DEFAULT 2 CHECK (objectif_etablissements_ancres BETWEEN 0 AND 1000),
  objectif_soignants_verifies integer NOT NULL DEFAULT 20 CHECK (objectif_soignants_verifies BETWEEN 0 AND 100000),
  objectif_missions_mensuelles integer NOT NULL DEFAULT 20 CHECK (objectif_missions_mensuelles BETWEEN 0 AND 100000),
  bmo_annee smallint,
  bmo_projets_recrutement integer CHECK (bmo_projets_recrutement IS NULL OR bmo_projets_recrutement >= 0),
  bmo_difficulte_pct numeric(5,2) CHECK (bmo_difficulte_pct IS NULL OR bmo_difficulte_pct BETWEEN 0 AND 100),
  bmo_saisonnier_pct numeric(5,2) CHECK (bmo_saisonnier_pct IS NULL OR bmo_saisonnier_pct BETWEEN 0 AND 100),
  source_url text,
  notes text,
  maj_le timestamptz NOT NULL DEFAULT now(),
  maj_par uuid,
  PRIMARY KEY (departement, profession)
);

CREATE TABLE IF NOT EXISTS public.acquisition_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type_action text NOT NULL CHECK (type_action IN (
    'COMPTE_ANCRE', 'RENFORCER_VIVIER', 'REVERSE_MARKETPLACE',
    'RECURRENCE', 'CIBLER_GROUPE', 'PARTENARIAT_ECOLE', 'QUALIFIER_SIGNAL'
  )),
  cible_type text NOT NULL CHECK (cible_type IN ('TERRITOIRE', 'ETABLISSEMENT', 'GROUPE', 'SIGNAL', 'ECOLE')),
  cible_id text NOT NULL,
  titre text NOT NULL,
  description text,
  departement text,
  profession text,
  score smallint NOT NULL DEFAULT 50 CHECK (score BETWEEN 0 AND 100),
  revenu_mensuel_estime_ht numeric(12,2) NOT NULL DEFAULT 0 CHECK (revenu_mensuel_estime_ht >= 0),
  statut text NOT NULL DEFAULT 'BROUILLON'
    CHECK (statut IN ('BROUILLON', 'PRIORISEE', 'EN_COURS', 'TERMINEE', 'IGNORE')),
  origine text NOT NULL DEFAULT 'RADAR' CHECK (origine IN ('RADAR', 'MANUEL')),
  responsable_id uuid REFERENCES public.equipe_admin(user_id) ON DELETE SET NULL,
  echeance_le timestamptz,
  idempotence_key text NOT NULL UNIQUE,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_acquisition_actions_file
  ON public.acquisition_actions (statut, score DESC, cree_le DESC);

CREATE TABLE IF NOT EXISTS public.acquisition_depenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  canal text NOT NULL,
  campagne text NOT NULL DEFAULT '',
  periode_debut date NOT NULL,
  periode_fin date NOT NULL,
  montant_ht numeric(12,2) NOT NULL CHECK (montant_ht >= 0),
  notes text,
  cree_par uuid,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now(),
  CHECK (periode_debut <= periode_fin),
  UNIQUE (canal, campagne, periode_debut, periode_fin)
);

ALTER TABLE public.acquisition_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_signaux ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_territoires ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acquisition_depenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_all_acquisition_sources ON public.acquisition_sources;
CREATE POLICY admin_all_acquisition_sources ON public.acquisition_sources
  TO authenticated USING (public.est_admin()) WITH CHECK (public.est_admin());
DROP POLICY IF EXISTS admin_all_acquisition_signaux ON public.acquisition_signaux;
CREATE POLICY admin_all_acquisition_signaux ON public.acquisition_signaux
  TO authenticated USING (public.est_admin()) WITH CHECK (public.est_admin());
DROP POLICY IF EXISTS admin_all_acquisition_territoires ON public.acquisition_territoires;
CREATE POLICY admin_all_acquisition_territoires ON public.acquisition_territoires
  TO authenticated USING (public.est_admin()) WITH CHECK (public.est_admin());
DROP POLICY IF EXISTS admin_all_acquisition_actions ON public.acquisition_actions;
CREATE POLICY admin_all_acquisition_actions ON public.acquisition_actions
  TO authenticated USING (public.est_admin()) WITH CHECK (public.est_admin());
DROP POLICY IF EXISTS admin_all_acquisition_depenses ON public.acquisition_depenses;
CREATE POLICY admin_all_acquisition_depenses ON public.acquisition_depenses
  TO authenticated USING (public.est_admin()) WITH CHECK (public.est_admin());

REVOKE ALL ON TABLE public.acquisition_sources FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.acquisition_signaux FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.acquisition_territoires FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.acquisition_actions FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.acquisition_depenses FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.acquisition_sources TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.acquisition_signaux TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.acquisition_territoires TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.acquisition_actions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.acquisition_depenses TO authenticated;
GRANT ALL ON TABLE public.acquisition_sources TO service_role;
GRANT ALL ON TABLE public.acquisition_signaux TO service_role;
GRANT ALL ON TABLE public.acquisition_territoires TO service_role;
GRANT ALL ON TABLE public.acquisition_actions TO service_role;
GRANT ALL ON TABLE public.acquisition_depenses TO service_role;

-- ---------------------------------------------------------------------------
-- 2. Import atomique des signaux de demande (Edge Function / service role)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_acquisition_upsert_signaux(p_rows jsonb)
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

  INSERT INTO public.acquisition_signaux (
    source_code, source_id, source_url, etablissement_id, finess, siret,
    nom_etablissement, intitule, profession, departement, ville, type_contrat,
    publie_le, expire_le, volume_estime, score_demande, details, importe_le, maj_le
  )
  SELECT
    r.source_code, r.source_id, r.source_url, e.id, r.finess, r.siret,
    r.nom_etablissement, r.intitule, r.profession, r.departement, r.ville,
    r.type_contrat, r.publie_le, r.expire_le,
    LEAST(GREATEST(COALESCE(r.volume_estime, 1), 1), 10000),
    LEAST(GREATEST(COALESCE(r.score_demande, 50), 0), 100),
    COALESCE(r.details, '{}'::jsonb), now(), now()
  FROM jsonb_to_recordset(COALESCE(p_rows, '[]'::jsonb)) AS r(
    source_code text, source_id text, source_url text, finess text, siret text,
    nom_etablissement text, intitule text, profession text, departement text,
    ville text, type_contrat text, publie_le timestamptz, expire_le timestamptz,
    volume_estime integer, score_demande integer, details jsonb
  )
  LEFT JOIN LATERAL (
    SELECT et.id
    FROM public.etablissements et
    WHERE et.supprime_le IS NULL
      AND ((r.finess IS NOT NULL AND et.finess = r.finess)
        OR (r.siret IS NOT NULL AND et.siret = r.siret))
    ORDER BY CASE WHEN et.est_compte_test THEN 1 ELSE 0 END, et.cree_le
    LIMIT 1
  ) e ON true
  WHERE r.source_code IS NOT NULL
    AND r.source_id IS NOT NULL
    AND r.nom_etablissement IS NOT NULL
    AND r.intitule IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.acquisition_sources src WHERE src.code = r.source_code)
  ON CONFLICT (source_code, source_id) DO UPDATE SET
    source_url = COALESCE(EXCLUDED.source_url, acquisition_signaux.source_url),
    etablissement_id = COALESCE(EXCLUDED.etablissement_id, acquisition_signaux.etablissement_id),
    finess = COALESCE(EXCLUDED.finess, acquisition_signaux.finess),
    siret = COALESCE(EXCLUDED.siret, acquisition_signaux.siret),
    nom_etablissement = EXCLUDED.nom_etablissement,
    intitule = EXCLUDED.intitule,
    profession = COALESCE(EXCLUDED.profession, acquisition_signaux.profession),
    departement = COALESCE(EXCLUDED.departement, acquisition_signaux.departement),
    ville = COALESCE(EXCLUDED.ville, acquisition_signaux.ville),
    type_contrat = COALESCE(EXCLUDED.type_contrat, acquisition_signaux.type_contrat),
    publie_le = COALESCE(EXCLUDED.publie_le, acquisition_signaux.publie_le),
    expire_le = COALESCE(EXCLUDED.expire_le, acquisition_signaux.expire_le),
    volume_estime = EXCLUDED.volume_estime,
    score_demande = EXCLUDED.score_demande,
    details = acquisition_signaux.details || EXCLUDED.details,
    statut = CASE WHEN acquisition_signaux.statut = 'EXPIRE' THEN 'NOUVEAU' ELSE acquisition_signaux.statut END,
    maj_le = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_acquisition_upsert_signaux(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_acquisition_upsert_signaux(jsonb) TO service_role;

-- ---------------------------------------------------------------------------
-- 3. Actions admin explicites : qualifier, CRM silencieux, territoires, couts
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_qualifier_signal(
  p_signal_id uuid,
  p_statut text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;
  IF p_statut NOT IN ('NOUVEAU', 'QUALIFIE', 'CONVERTI', 'IGNORE', 'EXPIRE') THEN
    RAISE EXCEPTION 'Statut invalide';
  END IF;
  UPDATE public.acquisition_signaux
     SET statut = p_statut, maj_le = now()
   WHERE id = p_signal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Signal introuvable'; END IF;
  RETURN jsonb_build_object('success', true, 'statut', p_statut);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_ajouter_crm(p_signal_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_signal public.acquisition_signaux%ROWTYPE;
  v_contact_id uuid;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_signal FROM public.acquisition_signaux WHERE id = p_signal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Signal introuvable'; END IF;

  INSERT INTO public.sales_contacts (
    type, nom, profession, ville, departement, finess, statut, notes,
    source_prospect_type, source_prospect_id, source_donnees, score_sourcing,
    sequence_active, prochaine_action_le, sequence_etape, ne_plus_contacter
  ) VALUES (
    'ETABLISSEMENT', v_signal.nom_etablissement, v_signal.profession,
    v_signal.ville, v_signal.departement, v_signal.finess, 'PROSPECT',
    'Signal de demande : ' || v_signal.intitule || E'\nSource : ' || COALESCE(v_signal.source_url, v_signal.source_code),
    'ETABLISSEMENT', 'SIGNAL:' || v_signal.id::text, v_signal.source_code,
    v_signal.score_demande, false, NULL, 0, false
  )
  ON CONFLICT (source_prospect_type, source_prospect_id)
    WHERE source_prospect_type IS NOT NULL AND source_prospect_id IS NOT NULL
  DO UPDATE SET
    notes = EXCLUDED.notes,
    score_sourcing = EXCLUDED.score_sourcing,
    sequence_active = false,
    prochaine_action_le = NULL,
    maj_le = now()
  RETURNING id INTO v_contact_id;

  -- Le trigger CRM historique initialise une echeance sur les nouveaux
  -- contacts. Le radar la remet explicitement a NULL apres l'INSERT.
  UPDATE public.sales_contacts
     SET sequence_active = false,
         prochaine_action_le = NULL,
         maj_le = now()
   WHERE id = v_contact_id;

  UPDATE public.acquisition_signaux
     SET statut = 'CRM', maj_le = now()
   WHERE id = p_signal_id;

  RETURN jsonb_build_object(
    'success', true,
    'contact_id', v_contact_id,
    'sequence_active', false,
    'prochaine_action_le', NULL,
    'contact_automatique', false
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_configurer_territoire(
  p_departement text,
  p_profession text,
  p_statut text,
  p_objectif_ancres integer,
  p_objectif_soignants integer,
  p_objectif_missions integer,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501'; END IF;
  IF p_departement IS NULL OR btrim(p_departement) = '' OR p_profession IS NULL OR btrim(p_profession) = '' THEN
    RAISE EXCEPTION 'Departement et profession requis';
  END IF;
  IF p_statut NOT IN ('OBSERVATION', 'PREPARATION', 'OUVERT', 'PAUSE') THEN RAISE EXCEPTION 'Statut invalide'; END IF;

  INSERT INTO public.acquisition_territoires (
    departement, profession, statut, objectif_etablissements_ancres,
    objectif_soignants_verifies, objectif_missions_mensuelles,
    source_url, notes, maj_le, maj_par
  ) VALUES (
    upper(btrim(p_departement)), upper(btrim(p_profession)), p_statut,
    LEAST(GREATEST(COALESCE(p_objectif_ancres, 2), 0), 1000),
    LEAST(GREATEST(COALESCE(p_objectif_soignants, 20), 0), 100000),
    LEAST(GREATEST(COALESCE(p_objectif_missions, 20), 0), 100000),
    'https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo',
    NULLIF(btrim(COALESCE(p_notes, '')), ''), now(), auth.uid()
  )
  ON CONFLICT (departement, profession) DO UPDATE SET
    statut = EXCLUDED.statut,
    objectif_etablissements_ancres = EXCLUDED.objectif_etablissements_ancres,
    objectif_soignants_verifies = EXCLUDED.objectif_soignants_verifies,
    objectif_missions_mensuelles = EXCLUDED.objectif_missions_mensuelles,
    notes = EXCLUDED.notes,
    maj_le = now(),
    maj_par = auth.uid();

  RETURN jsonb_build_object('success', true);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_enregistrer_depense(
  p_canal text,
  p_campagne text,
  p_periode_debut date,
  p_periode_fin date,
  p_montant_ht numeric,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501'; END IF;
  IF p_canal IS NULL OR btrim(p_canal) = '' OR p_periode_debut IS NULL OR p_periode_fin IS NULL
     OR p_periode_debut > p_periode_fin OR COALESCE(p_montant_ht, -1) < 0 THEN
    RAISE EXCEPTION 'Depense invalide';
  END IF;
  INSERT INTO public.acquisition_depenses (
    canal, campagne, periode_debut, periode_fin, montant_ht, notes, cree_par, maj_le
  ) VALUES (
    upper(btrim(p_canal)), COALESCE(btrim(p_campagne), ''), p_periode_debut,
    p_periode_fin, p_montant_ht, NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid(), now()
  )
  ON CONFLICT (canal, campagne, periode_debut, periode_fin) DO UPDATE SET
    montant_ht = EXCLUDED.montant_ht,
    notes = EXCLUDED.notes,
    maj_le = now();
  RETURN jsonb_build_object('success', true);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_changer_action(
  p_action_id uuid,
  p_statut text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501'; END IF;
  IF p_statut NOT IN ('BROUILLON', 'PRIORISEE', 'EN_COURS', 'TERMINEE', 'IGNORE') THEN
    RAISE EXCEPTION 'Statut invalide';
  END IF;
  UPDATE public.acquisition_actions SET statut = p_statut, maj_le = now() WHERE id = p_action_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Action introuvable'; END IF;
  RETURN jsonb_build_object('success', true, 'statut', p_statut);
END;
$fn$;

-- ---------------------------------------------------------------------------
-- 4. Generation de recommandations internes. Aucun canal d'envoi n'existe ici.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_generer_actions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE v_creees integer := 0; v_ajoutees integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  SELECT
    'QUALIFIER_SIGNAL', 'SIGNAL', s.id::text,
    'Qualifier le besoin — ' || s.nom_etablissement,
    s.intitule || ' · ' || COALESCE(s.ville, s.departement, 'localisation inconnue'),
    s.departement, s.profession, s.score_demande,
    round((s.volume_estime * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'SIGNAL:' || s.id::text
  FROM public.acquisition_signaux s
  WHERE s.statut IN ('NOUVEAU', 'QUALIFIE')
    AND (s.expire_le IS NULL OR s.expire_le >= now())
  ON CONFLICT (idempotence_key) DO UPDATE SET
    titre = EXCLUDED.titre,
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH segments AS (
    SELECT
      t.departement, t.profession, t.objectif_soignants_verifies,
      t.objectif_missions_mensuelles,
      (SELECT count(*) FROM public.soignants s
        WHERE s.supprime_le IS NULL AND NOT s.est_compte_test
          AND s.tous_documents_valides
          AND s.profession::text = t.profession
          AND (CASE WHEN s.adresse_code_postal LIKE '97%' THEN left(s.adresse_code_postal, 3) ELSE left(s.adresse_code_postal, 2) END) = t.departement) AS soignants,
      (SELECT COALESCE(sum(sig.volume_estime), 0) FROM public.acquisition_signaux sig
        WHERE sig.departement = t.departement AND sig.profession = t.profession
          AND sig.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')) AS demande
    FROM public.acquisition_territoires t
    WHERE t.statut IN ('PREPARATION', 'OUVERT')
  )
  SELECT
    'RENFORCER_VIVIER', 'TERRITOIRE', departement || ':' || profession,
    'Renforcer le vivier ' || profession || ' — ' || departement,
    soignants::text || ' soignant(s) verifie(s) pour un objectif de ' || objectif_soignants_verifies::text,
    departement, profession,
    LEAST(100, 50 + GREATEST(objectif_soignants_verifies - soignants, 0) * 2)::smallint,
    round((LEAST(demande, objectif_missions_mensuelles) * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'VIVIER:' || departement || ':' || profession
  FROM segments
  WHERE soignants < objectif_soignants_verifies AND demande > 0
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Transformer plusieurs signaux publics convergents en compte ancre a
  -- qualifier. Cette recommandation reste strictement interne.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH signaux_identifies AS (
    SELECT s.*,
      COALESCE(
        NULLIF(s.finess, ''),
        NULLIF(s.siret, ''),
        CASE
          WHEN lower(btrim(s.nom_etablissement)) NOT IN (
            'employeur non communique', 'employeur non communiqué',
            'entreprise non communiquee', 'entreprise non communiquée'
          ) THEN md5(lower(btrim(s.nom_etablissement)))
        END
      ) AS cible_id
    FROM public.acquisition_signaux s
    WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')
      AND (s.expire_le IS NULL OR s.expire_le >= now())
  ), ancres AS (
    SELECT
      s.cible_id,
      max(s.nom_etablissement) AS nom_etablissement,
      max(s.departement) AS departement,
      max(s.profession) AS profession,
      count(*)::integer AS signaux,
      sum(s.volume_estime)::integer AS volume,
      max(s.score_demande)::smallint AS score
    FROM signaux_identifies s
    WHERE s.cible_id IS NOT NULL
    GROUP BY s.cible_id
    HAVING count(*) >= 2 OR sum(s.volume_estime) >= 3
  )
  SELECT
    'COMPTE_ANCRE', 'ETABLISSEMENT', cible_id,
    'Qualifier comme compte ancre — ' || nom_etablissement,
    signaux::text || ' signal(aux) public(s), besoin estime a ' || volume::text
      || ' mission(s). Aucune prise de contact automatique.',
    departement, profession, LEAST(100, score + 10)::smallint,
    round((volume * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'ANCRE:' || cible_id
  FROM ancres
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Reverse marketplace : montrer a l'equipe les segments ou l'offre verifiee
  -- peut etre proposee manuellement aux etablissements, sans exposer les
  -- coordonnees des soignants ni lancer une campagne.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH disponibilite AS (
    SELECT
      CASE WHEN s.adresse_code_postal LIKE '97%' THEN left(s.adresse_code_postal, 3) ELSE left(s.adresse_code_postal, 2) END AS departement,
      s.profession::text AS profession,
      count(DISTINCT s.id)::integer AS soignants_disponibles
    FROM public.soignants s
    JOIN public.disponibilites_soignant ds ON ds.soignant_id = s.id
      AND ds.jour BETWEEN current_date AND current_date + 14
    WHERE s.supprime_le IS NULL
      AND NOT s.est_compte_test
      AND s.tous_documents_valides
      AND s.profession IS NOT NULL
    GROUP BY 1, 2
  )
  SELECT
    'REVERSE_MARKETPLACE', 'TERRITOIRE', d.departement || ':' || d.profession,
    'Valoriser le vivier disponible — ' || d.profession || ' · ' || d.departement,
    d.soignants_disponibles::text || ' soignant(s) verifie(s) disponible(s) sous 14 jours. '
      || 'Preparer une offre anonymisee a valider humainement.',
    d.departement, d.profession,
    LEAST(100, 45 + d.soignants_disponibles * 3)::smallint,
    round((LEAST(d.soignants_disponibles, 20) * 8 * 25 * 0.15)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'REVERSE:' || d.departement || ':' || d.profession
  FROM disponibilite d
  LEFT JOIN public.acquisition_territoires t
    ON t.departement = d.departement AND t.profession = d.profession
  WHERE d.departement IS NOT NULL
    AND d.soignants_disponibles >= 3
    AND COALESCE(t.statut, 'OBSERVATION') <> 'PAUSE'
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Les etablissements ayant deja repete des missions sont les candidats les
  -- plus solides a une planification recurrente.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  WITH recurrents AS (
    SELECT
      e.id, e.nom, e.adresse_departement AS departement,
      max(m.profession_requise::text) AS profession,
      count(m.id)::integer AS missions,
      count(DISTINCT m.serie_id) FILTER (WHERE m.serie_id IS NOT NULL)::integer AS series,
      round((COALESCE(sum(COALESCE(m.montant_commission_ht,
        COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
          * COALESCE(m.taux_commission, 15) / 100)), 0) / 180 * 30)::numeric, 2) AS commission_mensuelle_ht
    FROM public.etablissements e
    JOIN public.missions m ON m.etablissement_id = e.id
    WHERE e.supprime_le IS NULL
      AND NOT e.est_compte_test
      AND m.cree_le >= now() - interval '180 days'
    GROUP BY e.id, e.nom, e.adresse_departement
    HAVING count(m.id) >= 2
  )
  SELECT
    'RECURRENCE', 'ETABLISSEMENT', id::text,
    'Proposer un rythme recurrent — ' || nom,
    missions::text || ' mission(s) sur 180 jours, dont ' || series::text
      || ' serie(s). Preparer un calendrier recurrent pour validation humaine.',
    departement, profession, LEAST(100, 55 + missions * 3)::smallint,
    GREATEST(commission_mensuelle_ht, 0),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'RECURRENCE:' || id::text
  FROM recurrents
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Expansion des groupes deja identifies : une validation humaine decide
  -- ensuite si le contrat peut etre etendu a d'autres etablissements.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  SELECT
    'CIBLER_GROUPE', 'GROUPE', g.id::text,
    'Etendre le deploiement — ' || g.nom,
    count(e.id)::text || ' etablissement(s) deja rattache(s). Identifier les implantations suivantes avant toute prise de contact.',
    NULL, NULL, LEAST(100, 60 + count(e.id) * 3)::smallint,
    round((count(e.id) * 10 * 8 * 25 * COALESCE(g.taux_commission_negocie, 15) / 100)::numeric, 2),
    'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'GROUPE:' || g.id::text
  FROM public.groupes_sante g
  LEFT JOIN public.etablissements e ON e.groupe_sante_id = g.id AND e.supprime_le IS NULL AND NOT e.est_compte_test
  WHERE g.supprime_le IS NULL
  GROUP BY g.id, g.nom, g.taux_commission_negocie
  HAVING count(e.id) >= 1
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    revenu_mensuel_estime_ht = EXCLUDED.revenu_mensuel_estime_ht,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  -- Les ecoles issues du repertoire public alimentent un vivier futur. Leur
  -- fiche est uniquement placee dans la file de qualification interne.
  INSERT INTO public.acquisition_actions (
    type_action, cible_type, cible_id, titre, description, departement,
    profession, score, revenu_mensuel_estime_ht, statut, origine,
    responsable_id, idempotence_key
  )
  SELECT
    'PARTENARIAT_ECOLE', 'ECOLE', p.finess,
    'Qualifier un partenariat ecole — ' || p.nom,
    COALESCE(NULLIF(p.categorie_lib, ''), 'Etablissement de formation')
      || ' · ' || COALESCE(NULLIF(p.ville, ''), NULLIF(p.departement, ''), 'localisation inconnue')
      || '. Aucun message ne sera envoye sans action humaine.',
    p.departement, NULL, CASE WHEN p.favori THEN 75 ELSE 50 END::smallint,
    0, 'BROUILLON', 'RADAR',
    (SELECT ea.user_id FROM public.equipe_admin ea WHERE ea.actif IS TRUE ORDER BY CASE WHEN lower(ea.email) = 'gabrielle.pcd@outlook.com' THEN 0 ELSE 1 END, ea.cree_le LIMIT 1),
    'ECOLE:' || p.finess
  FROM public.prospects_etablissements p
  WHERE p.type_jolene = 'ECOLE_SANTE'
  ON CONFLICT (idempotence_key) DO UPDATE SET
    description = EXCLUDED.description,
    score = EXCLUDED.score,
    maj_le = now();
  GET DIAGNOSTICS v_ajoutees = ROW_COUNT;
  v_creees := v_creees + v_ajoutees;

  RETURN jsonb_build_object(
    'success', true,
    'actions_preparees', v_creees,
    'statut', 'BROUILLON',
    'contact_automatique', false,
    'genere_le', now()
  );
END;
$fn$;

-- ---------------------------------------------------------------------------
-- 5. Radar unifie : demande externe + missions + disponibilites + revenu.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_radar(
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
  v_scope text := upper(COALESCE(p_scope, 'REEL'));
  v_jours integer := LEAST(GREATEST(COALESCE(p_jours, 90), 7), 365);
  v_departement text := NULLIF(upper(btrim(COALESCE(p_departement, ''))), '');
  v_profession text := NULLIF(upper(btrim(COALESCE(p_profession, ''))), '');
  v_taux numeric := 15;
  v_taux_horaire numeric := 25;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501'; END IF;
  IF v_scope NOT IN ('REEL', 'TEST', 'TOUS') THEN RAISE EXCEPTION 'Scope invalide'; END IF;

  SELECT COALESCE(avg(NULLIF(m.taux_commission, 0)), 15),
         COALESCE(avg(NULLIF(m.taux_horaire_base, 0)), 25)
    INTO v_taux, v_taux_horaire
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE m.cree_le >= now() - make_interval(days => v_jours)
     AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test));

  RETURN (
    WITH offre AS (
      SELECT
        CASE WHEN s.adresse_code_postal LIKE '97%' THEN left(s.adresse_code_postal, 3) ELSE left(s.adresse_code_postal, 2) END AS departement,
        s.profession::text AS profession,
        count(DISTINCT s.id) FILTER (WHERE s.tous_documents_valides)::integer AS verifies,
        count(DISTINCT ds.soignant_id) FILTER (WHERE ds.jour BETWEEN current_date AND current_date + 14)::integer AS disponibles_14j
      FROM public.soignants s
      LEFT JOIN public.disponibilites_soignant ds ON ds.soignant_id = s.id
      WHERE s.supprime_le IS NULL
        AND s.profession IS NOT NULL
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND s.est_compte_test) OR (v_scope = 'REEL' AND NOT s.est_compte_test))
      GROUP BY 1, 2
    ),
    demande_interne AS (
      SELECT e.adresse_departement AS departement, m.profession_requise::text AS profession,
        count(*)::integer AS missions,
        count(*) FILTER (WHERE m.statut = 'OUVERTE')::integer AS ouvertes,
        count(*) FILTER (WHERE m.soignant_assigne_id IS NOT NULL)::integer AS pourvues,
        count(DISTINCT m.etablissement_id)::integer AS etablissements,
        COALESCE(sum(COALESCE(m.montant_commission_ht,
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100)), 0)::numeric AS commission_ht
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test))
      GROUP BY 1, 2
    ),
    demande_externe AS (
      SELECT s.departement, s.profession,
        count(*)::integer AS signaux,
        COALESCE(sum(s.volume_estime), 0)::integer AS volume,
        COALESCE(round(avg(s.score_demande)), 0)::integer AS score_moyen
      FROM public.acquisition_signaux s
      WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')
        AND (s.expire_le IS NULL OR s.expire_le >= now())
      GROUP BY 1, 2
    ),
    cles AS (
      SELECT departement, profession FROM offre
      UNION SELECT departement, profession FROM demande_interne
      UNION SELECT departement, profession FROM demande_externe
      UNION SELECT departement, profession FROM public.acquisition_territoires
    ),
    segments AS (
      SELECT
        c.departement, c.profession,
        COALESCE(o.verifies, 0) AS soignants_verifies,
        COALESCE(o.disponibles_14j, 0) AS disponibles_14j,
        COALESCE(di.missions, 0) AS missions_90j,
        COALESCE(di.ouvertes, 0) AS missions_ouvertes,
        COALESCE(di.pourvues, 0) AS missions_pourvues,
        COALESCE(di.etablissements, 0) AS etablissements_actifs,
        COALESCE(de.signaux, 0) AS signaux_externes,
        COALESCE(de.volume, 0) AS volume_externe,
        COALESCE(de.score_moyen, 0) AS score_signal,
        COALESCE(t.statut, 'OBSERVATION') AS statut_territoire,
        COALESCE(t.objectif_etablissements_ancres, 2) AS objectif_ancres,
        COALESCE(t.objectif_soignants_verifies, 20) AS objectif_soignants,
        COALESCE(t.objectif_missions_mensuelles, 20) AS objectif_missions,
        t.bmo_annee, t.bmo_projets_recrutement, t.bmo_difficulte_pct,
        LEAST(100, GREATEST(0,
          20 + COALESCE(de.score_moyen, 0) * 0.35
          + LEAST(COALESCE(de.volume, 0), 20) * 2
          + LEAST(COALESCE(di.ouvertes, 0), 10) * 2
          - LEAST(COALESCE(o.disponibles_14j, 0), 20)
        ))::integer AS score_priorite,
        round((COALESCE(de.volume, 0) * 8 * v_taux_horaire * v_taux / 100)::numeric, 2) AS potentiel_commission_mensuel_ht,
        COALESCE(di.commission_ht, 0) AS commission_observee_ht
      FROM cles c
      LEFT JOIN offre o ON o.departement IS NOT DISTINCT FROM c.departement AND o.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN demande_interne di ON di.departement IS NOT DISTINCT FROM c.departement AND di.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN demande_externe de ON de.departement IS NOT DISTINCT FROM c.departement AND de.profession IS NOT DISTINCT FROM c.profession
      LEFT JOIN public.acquisition_territoires t ON t.departement IS NOT DISTINCT FROM c.departement AND t.profession IS NOT DISTINCT FROM c.profession
      WHERE c.departement IS NOT NULL AND c.profession IS NOT NULL
        AND (v_departement IS NULL OR c.departement = v_departement)
        AND (v_profession IS NULL OR c.profession = v_profession)
    ),
    signaux_identifies AS (
      SELECT s.*,
        COALESCE(
          NULLIF(s.finess, ''),
          NULLIF(s.siret, ''),
          CASE
            WHEN lower(btrim(s.nom_etablissement)) NOT IN (
              'employeur non communique', 'employeur non communiqué',
              'entreprise non communiquee', 'entreprise non communiquée'
            ) THEN md5(lower(btrim(s.nom_etablissement)))
          END
        ) AS cible_id
      FROM public.acquisition_signaux s
      WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM')
        AND (s.expire_le IS NULL OR s.expire_le >= now())
        AND (v_departement IS NULL OR s.departement = v_departement)
        AND (v_profession IS NULL OR s.profession = v_profession)
    ),
    ancres AS (
      SELECT
        max(s.nom_etablissement) AS nom,
        max(s.departement) AS departement,
        max(s.ville) AS ville,
        max(s.finess) AS finess,
        max(s.siret) AS siret,
        count(*)::integer AS nb_signaux,
        sum(s.volume_estime)::integer AS volume,
        max(s.score_demande)::integer AS score,
        jsonb_agg(DISTINCT s.profession) FILTER (WHERE s.profession IS NOT NULL) AS professions,
        bool_or(s.etablissement_id IS NOT NULL) AS deja_inscrit,
        round((sum(s.volume_estime) * 8 * v_taux_horaire * v_taux / 100)::numeric, 2) AS potentiel_commission_mensuel_ht
      FROM signaux_identifies s
      WHERE s.cible_id IS NOT NULL
      GROUP BY s.cible_id
    ),
    recurrence AS (
      SELECT e.id, e.nom, e.adresse_departement AS departement,
        count(m.id)::integer AS missions,
        count(DISTINCT m.serie_id) FILTER (WHERE m.serie_id IS NOT NULL)::integer AS series,
        count(DISTINCT m.profession_requise)::integer AS professions,
        round((COALESCE(sum(COALESCE(m.montant_commission_ht,
          COALESCE(NULLIF(m.net_a_payer, 0), m.duree_heures * m.taux_horaire_base, 0)
            * COALESCE(m.taux_commission, v_taux) / 100)), 0)
          / GREATEST(v_jours, 1) * 30)::numeric, 2) AS commission_mensuelle_estimee_ht
      FROM public.etablissements e
      JOIN public.missions m ON m.etablissement_id = e.id
      WHERE m.cree_le >= now() - make_interval(days => v_jours)
        AND (v_scope = 'TOUS' OR (v_scope = 'TEST' AND e.est_compte_test) OR (v_scope = 'REEL' AND NOT e.est_compte_test))
        AND (v_departement IS NULL OR e.adresse_departement = v_departement)
        AND (v_profession IS NULL OR m.profession_requise::text = v_profession)
      GROUP BY e.id, e.nom, e.adresse_departement
      HAVING count(m.id) >= 2
    )
    SELECT jsonb_build_object(
      'scope', v_scope,
      'jours', v_jours,
      'genere_le', now(),
      'contact_automatique', false,
      'marketing_actif', COALESCE((SELECT valeur::boolean FROM public.growth_config WHERE cle = 'automatisations_marketing_actives'), false),
      'hypotheses', jsonb_build_object(
        'taux_commission_pct', round(v_taux, 2),
        'taux_horaire_moyen', round(v_taux_horaire, 2),
        'duree_signal_heures', 8,
        'caractere', 'estimation, pas revenu garanti'
      ),
      'stats', jsonb_build_object(
        'signaux_actifs', (SELECT count(*) FROM public.acquisition_signaux s WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM') AND (s.expire_le IS NULL OR s.expire_le >= now())),
        'etablissements_a_potentiel', (SELECT count(*) FROM ancres),
        'soignants_verifies', (SELECT COALESCE(sum(soignants_verifies), 0) FROM segments),
        'disponibles_14j', (SELECT COALESCE(sum(disponibles_14j), 0) FROM segments),
        'potentiel_commission_mensuel_ht', (SELECT COALESCE(sum(potentiel_commission_mensuel_ht), 0) FROM segments),
        'commission_observee_ht', (SELECT COALESCE(sum(commission_observee_ht), 0) FROM segments),
        'actions_brouillon', (SELECT count(*) FROM public.acquisition_actions WHERE statut = 'BROUILLON')
      ),
      'segments', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.score_priorite DESC, s.volume_externe DESC) FROM segments s), '[]'::jsonb),
      'ancres', COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.score DESC, a.volume DESC) FROM (SELECT * FROM ancres ORDER BY score DESC, volume DESC LIMIT 50) a), '[]'::jsonb),
      'recurrence', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.missions DESC) FROM (SELECT * FROM recurrence ORDER BY missions DESC LIMIT 30) r), '[]'::jsonb),
      'signaux', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.score_demande DESC, s.maj_le DESC) FROM (SELECT * FROM public.acquisition_signaux s WHERE s.statut IN ('NOUVEAU', 'QUALIFIE', 'CRM') AND (s.expire_le IS NULL OR s.expire_le >= now()) AND (v_departement IS NULL OR s.departement = v_departement) AND (v_profession IS NULL OR s.profession = v_profession) ORDER BY s.score_demande DESC, s.maj_le DESC LIMIT 100) s), '[]'::jsonb),
      'actions', COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.score DESC, a.cree_le DESC) FROM (SELECT * FROM public.acquisition_actions WHERE statut IN ('BROUILLON', 'PRIORISEE', 'EN_COURS') ORDER BY score DESC, cree_le DESC LIMIT 100) a), '[]'::jsonb),
      'sources', COALESCE((SELECT jsonb_agg(to_jsonb(src) ORDER BY src.type_source, src.libelle) FROM public.acquisition_sources src), '[]'::jsonb),
      'depenses', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.periode_fin DESC, d.canal) FROM public.acquisition_depenses d WHERE d.periode_fin >= current_date - make_interval(days => v_jours)), '[]'::jsonb)
    )
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_acquisition_qualifier_signal(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_acquisition_ajouter_crm(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_acquisition_configurer_territoire(text, text, text, integer, integer, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_acquisition_enregistrer_depense(text, text, date, date, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_acquisition_changer_action(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_acquisition_generer_actions() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_qualifier_signal(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_ajouter_crm(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_configurer_territoire(text, text, text, integer, integer, integer, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_enregistrer_depense(text, text, date, date, numeric, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_changer_action(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_generer_actions() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) TO authenticated, service_role;

-- Le cron ne fait que recalculer des recommandations internes en BROUILLON.
-- Il ne declenche aucune Edge Function et ne possede aucun canal d'envoi.
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron absent — recommandations acquisition non planifiees';
    RETURN;
  END IF;
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'jolene_acquisition_brouillons';
  PERFORM cron.schedule(
    'jolene_acquisition_brouillons',
    '10 6 * * *',
    'SELECT public.fn_admin_acquisition_generer_actions()'
  );
END;
$do$;

COMMENT ON TABLE public.acquisition_signaux IS
  'Signaux publics de besoin en recrutement. Donnees de pilotage seulement : aucun contact automatique.';
COMMENT ON TABLE public.acquisition_actions IS
  'Recommandations internes generees en BROUILLON. Toute prise de contact reste une action humaine explicite.';
COMMENT ON FUNCTION public.fn_admin_acquisition_radar(text, integer, text, text) IS
  'Radar fondateur : demande, offre verifiee, liquidite, comptes ancres, recurrence et potentiel de commission HT.';
