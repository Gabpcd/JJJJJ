-- Agents de croissance en mode brouillon (08/11/2026).
--
-- Constat prod du 08/11 (cohorte réelle, comptes test exclus) : 2 soignants,
-- 0 établissement, 0 mission ; 64 058 établissements prospects dont 30 633
-- avec email, jamais contactés. Le moteur d'acquisition existant prépare des
-- recommandations internes mais aucun message.
--
-- Cette migration ajoute la pièce manquante : une file de brouillons de
-- messages (sujet + corps) écrite par quatre agents SQL quotidiens, et un
-- entonnoir hebdomadaire figé. AUCUN ENVOI : aucun agent n'appelle pg_net,
-- Resend, un SMS ou un réseau social. Un brouillon ne quitte la base que si
-- la fondatrice le valide puis l'envoie elle-même (Gmail) ou le publie
-- (copier-coller) ; « Marquer envoyé » journalise ensuite dans le CRM existant.
--
-- Réutilise : prospects_etablissements, acquisition_signaux,
-- acquisition_territoires (BMO), sales_contacts/sales_activites,
-- fn_sales_outreach_est_interdit (STOP), fn_admin_sourcing_ajouter_crm,
-- fn_crm_enregistrer_email_envoye (séquence J+3/J+7/J+14), growth_config.
-- Ne modifie AUCUNE fonction existante et laisse
-- growth_config.automatisations_marketing_actives inchangé.

-- ---------------------------------------------------------------------------
-- 1. Réglages (texte, comme le reste du moteur d'acquisition)
-- ---------------------------------------------------------------------------
INSERT INTO public.growth_config (cle, valeur, maj_le) VALUES
  ('agents_croissance_actifs', 'false', now()),
  ('agents_departements_cibles', '75,92,56', now()),
  ('agents_types_cibles', 'EHPAD,HANDICAP,DOMICILE,CENTRE_SANTE,HOPITAL,DIALYSE,ECOLE_SANTE', now()),
  ('agents_prospection_quota_jour', '20', now()),
  ('agents_prospection_file_max', '60', now()),
  ('prospection_signature', E'Gabrielle\nFondatrice de Jolene\nhttps://jolene.app', now()),
  ('prospection_mention_opposition',
   'Vos coordonnées professionnelles proviennent des annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé). Si vous ne souhaitez plus être contacté par Jolene, répondez simplement « STOP » à cet email : nous ne vous écrirons plus.',
   now())
ON CONFLICT (cle) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Tables
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.growth_brouillons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent text NOT NULL CHECK (agent IN (
    'PROSPECTION_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'
  )),
  canal text NOT NULL CHECK (canal IN ('EMAIL', 'LINKEDIN', 'FACEBOOK_GROUPE')),
  cible_type text NOT NULL CHECK (cible_type IN (
    'PROSPECT_ETABLISSEMENT', 'CONTACT_CRM', 'SOIGNANT', 'ETABLISSEMENT', 'MISSION', 'PUBLIC'
  )),
  cible_id text,
  destinataire_nom text,
  destinataire_email text,
  departement text,
  profession text,
  sequence_etape smallint CHECK (sequence_etape BETWEEN 1 AND 3),
  sujet text CHECK (sujet IS NULL OR char_length(sujet) <= 300),
  corps text NOT NULL CHECK (char_length(corps) BETWEEN 1 AND 8000),
  lien text,
  contexte jsonb NOT NULL DEFAULT '{}'::jsonb,
  score smallint,
  statut text NOT NULL DEFAULT 'BROUILLON' CHECK (statut IN (
    'BROUILLON', 'VALIDE', 'REJETE', 'ENVOYE', 'EXPIRE'
  )),
  motif_rejet text,
  idempotence_key text NOT NULL UNIQUE,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now(),
  expire_le timestamptz,
  valide_par uuid,
  valide_le timestamptz,
  envoye_par uuid,
  envoye_le timestamptz,
  CONSTRAINT growth_brouillons_email_destinataire CHECK (
    canal <> 'EMAIL' OR destinataire_email IS NOT NULL
  )
);

COMMENT ON TABLE public.growth_brouillons IS
  'Brouillons des agents de croissance. Aucun envoi automatique : validation puis envoi/publication humains.';

CREATE INDEX IF NOT EXISTS idx_growth_brouillons_file
  ON public.growth_brouillons (statut, agent, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_growth_brouillons_cible
  ON public.growth_brouillons (cible_type, cible_id);
CREATE INDEX IF NOT EXISTS idx_growth_brouillons_email
  ON public.growth_brouillons (lower(destinataire_email))
  WHERE destinataire_email IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.growth_agent_executions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  agent text NOT NULL,
  declencheur text NOT NULL CHECK (declencheur IN ('CRON', 'ADMIN')),
  debut_le timestamptz NOT NULL DEFAULT now(),
  fin_le timestamptz,
  brouillons_crees integer NOT NULL DEFAULT 0,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  erreur text
);
CREATE INDEX IF NOT EXISTS idx_growth_agent_executions_recent
  ON public.growth_agent_executions (agent, debut_le DESC);

CREATE TABLE IF NOT EXISTS public.growth_rapports_hebdo (
  semaine_debut date PRIMARY KEY,
  semaine_fin date NOT NULL,
  donnees jsonb NOT NULL,
  cree_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.growth_brouillons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.growth_agent_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.growth_rapports_hebdo ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.growth_brouillons FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.growth_agent_executions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.growth_rapports_hebdo FROM PUBLIC, anon, authenticated;
-- Lecture seule côté client (admin, RLS). Toute écriture passe par les RPC.
GRANT SELECT ON TABLE public.growth_brouillons TO authenticated;
GRANT SELECT ON TABLE public.growth_agent_executions TO authenticated;
GRANT SELECT ON TABLE public.growth_rapports_hebdo TO authenticated;
GRANT ALL ON TABLE public.growth_brouillons TO service_role;
GRANT ALL ON TABLE public.growth_agent_executions TO service_role;
GRANT ALL ON TABLE public.growth_rapports_hebdo TO service_role;

DROP POLICY IF EXISTS growth_brouillons_admin_lecture ON public.growth_brouillons;
CREATE POLICY growth_brouillons_admin_lecture ON public.growth_brouillons
  FOR SELECT TO authenticated USING ((SELECT public.est_admin()));
DROP POLICY IF EXISTS growth_agent_executions_admin_lecture ON public.growth_agent_executions;
CREATE POLICY growth_agent_executions_admin_lecture ON public.growth_agent_executions
  FOR SELECT TO authenticated USING ((SELECT public.est_admin()));
DROP POLICY IF EXISTS growth_rapports_hebdo_admin_lecture ON public.growth_rapports_hebdo;
CREATE POLICY growth_rapports_hebdo_admin_lecture ON public.growth_rapports_hebdo
  FOR SELECT TO authenticated USING ((SELECT public.est_admin()));

-- ---------------------------------------------------------------------------
-- 3. Utilitaires internes (schéma private, jamais exposés à PostgREST)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fn_growth_config(p_cle text, p_defaut text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT COALESCE(
    (SELECT NULLIF(btrim(g.valeur), '') FROM public.growth_config g WHERE g.cle = p_cle),
    p_defaut
  );
$body$;

CREATE OR REPLACE FUNCTION private.fn_growth_config_int(
  p_cle text, p_defaut integer, p_min integer, p_max integer
)
RETURNS integer
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $body$
DECLARE
  v text := private.fn_growth_config(p_cle, NULL);
BEGIN
  IF v IS NULL OR v !~ '^\d{1,6}$' THEN
    RETURN p_defaut;
  END IF;
  RETURN greatest(p_min, least(p_max, v::integer));
END;
$body$;

CREATE OR REPLACE FUNCTION private.fn_growth_config_liste(p_cle text, p_defaut text)
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT COALESCE(array_agg(x ORDER BY x) FILTER (WHERE x <> ''), ARRAY[]::text[])
  FROM unnest(string_to_array(
    upper(replace(private.fn_growth_config(p_cle, p_defaut), ' ', '')), ','
  )) AS x;
$body$;

-- Lien jolene.app avec UTM (attribution déjà capturée côté front).
CREATE OR REPLACE FUNCTION private.fn_growth_lien(
  p_chemin text, p_source text, p_medium text, p_campagne text, p_contenu text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT 'https://jolene.app' || p_chemin
    || CASE WHEN position('?' IN p_chemin) > 0 THEN '&' ELSE '?' END
    || 'utm_source=' || p_source
    || '&utm_medium=' || p_medium
    || '&utm_campaign=' || p_campagne
    || '&utm_content=' || lower(regexp_replace(COALESCE(p_contenu, ''), '[^A-Za-z0-9_-]+', '-', 'g'));
$body$;

CREATE OR REPLACE FUNCTION private.fn_growth_libelle_profession(p_profession text, p_pluriel boolean)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT CASE upper(COALESCE(p_profession, ''))
    WHEN 'AS' THEN CASE WHEN p_pluriel THEN 'aides-soignants' ELSE 'aide-soignant' END
    WHEN 'IDE' THEN CASE WHEN p_pluriel THEN 'infirmiers' ELSE 'infirmier' END
    WHEN 'AES' THEN CASE WHEN p_pluriel THEN 'accompagnants éducatifs et sociaux' ELSE 'accompagnant éducatif et social' END
    WHEN 'MEDECIN' THEN CASE WHEN p_pluriel THEN 'médecins' ELSE 'médecin' END
    WHEN 'KINE' THEN CASE WHEN p_pluriel THEN 'kinésithérapeutes' ELSE 'kinésithérapeute' END
    WHEN 'SAGE_FEMME' THEN CASE WHEN p_pluriel THEN 'sages-femmes' ELSE 'sage-femme' END
    WHEN 'IBODE' THEN 'IBODE'
    WHEN 'IADE' THEN 'IADE'
    ELSE lower(replace(COALESCE(p_profession, 'soignant'), '_', ' '))
  END;
$body$;

CREATE OR REPLACE FUNCTION private.fn_growth_majuscule(p_texte text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT upper(left(COALESCE(p_texte, ''), 1)) || substr(COALESCE(p_texte, ''), 2);
$body$;

-- Missions des établissements réels (hors cohorte test). Ce n'est PAS le filtre public :
-- toute surface publique (posts) ajoute public.fn_mission_publique(m.id) IS NOT NULL.
CREATE OR REPLACE FUNCTION private.fn_growth_missions_reelles()
RETURNS SETOF public.missions
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT m.*
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE e.est_compte_test IS FALSE
    AND e.supprime_le IS NULL
    AND private.fn_mission_lie_compte_test(m.id) IS FALSE;
$body$;

-- Prédicat UNIQUE de joignabilité d'un destinataire (agents + décision admin).
-- NULL = joignable ; sinon le motif. Ne jamais re-décider localement.
CREATE OR REPLACE FUNCTION private.fn_growth_destinataire_bloque(
  p_cible_type text, p_cible_id text, p_email text, p_telephone text, p_finess text
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $body$
DECLARE
  v_uid uuid;
  v_finess text := p_finess;
BEGIN
  IF p_cible_type IN ('SOIGNANT', 'ETABLISSEMENT') THEN
    BEGIN
      v_uid := p_cible_id::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      RETURN 'CIBLE_INVALIDE';
    END;
    IF p_cible_type = 'SOIGNANT' AND NOT EXISTS (
      SELECT 1 FROM public.soignants s
      WHERE s.id = v_uid AND s.supprime_le IS NULL AND s.est_compte_test IS FALSE
    ) THEN
      RETURN 'COMPTE_SUPPRIME';
    END IF;
    IF p_cible_type = 'ETABLISSEMENT' THEN
      SELECT e.finess INTO v_finess FROM public.etablissements e
      WHERE e.id = v_uid AND e.supprime_le IS NULL AND e.est_compte_test IS FALSE;
      IF NOT FOUND THEN
        RETURN 'COMPTE_SUPPRIME';
      END IF;
    END IF;
    -- Mêmes préférences que send-email : canal email global, puis l'événement
    -- SERIE_ONBOARDING (relances d'activation).
    IF EXISTS (SELECT 1 FROM public.preferences_notifications pn
               WHERE pn.utilisateur_id = v_uid AND pn.canal_email IS FALSE)
       OR EXISTS (SELECT 1 FROM public.preferences_notifications_par_evenement pe
                  WHERE pe.utilisateur_id = v_uid AND pe.type_evenement::text = 'SERIE_ONBOARDING'
                    AND pe.canal::text = 'EMAIL' AND pe.actif IS FALSE) THEN
      RETURN 'EMAILS_DESACTIVES';
    END IF;
    IF public.fn_sales_outreach_est_interdit(
         NULL, CASE WHEN p_cible_type = 'SOIGNANT' THEN 'SOIGNANT' ELSE 'ETABLISSEMENT' END,
         CASE WHEN p_cible_type = 'ETABLISSEMENT' THEN v_finess END, p_email, p_telephone) THEN
      RETURN 'STOP';
    END IF;
    RETURN NULL;
  ELSIF p_cible_type IN ('PROSPECT_ETABLISSEMENT', 'CONTACT_CRM') THEN
    IF p_cible_type = 'CONTACT_CRM' THEN
      BEGIN
        v_uid := p_cible_id::uuid;
      EXCEPTION WHEN invalid_text_representation THEN
        RETURN 'CIBLE_INVALIDE';
      END;
    END IF;
    IF public.fn_sales_outreach_est_interdit(
         v_uid, 'ETABLISSEMENT',
         CASE WHEN p_cible_type = 'PROSPECT_ETABLISSEMENT' THEN p_cible_id ELSE p_finess END,
         p_email, p_telephone) THEN
      RETURN 'STOP';
    END IF;
    RETURN NULL;
  END IF;
  RETURN NULL;
END;
$body$;

-- ---------------------------------------------------------------------------
-- 4. Agent 1 — prospection établissements (étape 1 + relances CRM 2 et 3)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fn_growth_agent_prospection()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_depts text[] := private.fn_growth_config_liste('agents_departements_cibles', '75,92,56');
  v_types text[] := private.fn_growth_config_liste(
    'agents_types_cibles', 'EHPAD,HANDICAP,DOMICILE,CENTRE_SANTE,HOPITAL,DIALYSE,ECOLE_SANTE');
  v_quota integer := private.fn_growth_config_int('agents_prospection_quota_jour', 20, 0, 100);
  v_file_max integer := private.fn_growth_config_int('agents_prospection_file_max', 60, 0, 500);
  v_signature text := private.fn_growth_config('prospection_signature', E'Gabrielle\nFondatrice de Jolene');
  v_mention text := private.fn_growth_config('prospection_mention_opposition', NULL);
  v_deja integer;
  v_file integer;
  v_place integer;
  v_crees integer := 0;
  v_relances integer := 0;
  v_exclus_stop integer := 0;
  v_n integer;
  r record;
  c record;
  v_sujet text;
  v_corps text;
  v_lien text;
  v_accroche text;
  v_tension text;
  v_etape smallint;
BEGIN
  -- Sans mention d'opposition, aucun brouillon de prospection (verrou explicite).
  IF v_mention IS NULL THEN
    RAISE EXCEPTION 'growth_config.prospection_mention_opposition absente : brouillons de prospection bloqués (docs/AGENTS_CROISSANCE.md §Conformité)';
  END IF;

  SELECT count(*) INTO v_deja
  FROM public.growth_brouillons b
  WHERE b.agent = 'PROSPECTION_ETABLISSEMENT' AND b.sequence_etape = 1
    AND b.cree_le >= date_trunc('day', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris';
  SELECT count(*) INTO v_file
  FROM public.growth_brouillons b
  WHERE b.agent = 'PROSPECTION_ETABLISSEMENT' AND b.statut = 'BROUILLON';
  v_place := greatest(0, least(v_quota - v_deja, v_file_max - v_file));

  -- Étape 1 : nouveaux prospects des marchés cibles, jamais contactés.
  -- Les départements alternent (rang par département) : la tension BMO ne
  -- doit pas concentrer toute la file sur un seul marché pilote.
  FOR r IN
    SELECT q.*
    FROM (
    SELECT s.*,
           s.pts_type + s.pts_email + s.pts_tel + s.pts_signal + s.pts_tension AS score_total,
           row_number() OVER (
             PARTITION BY s.departement
             ORDER BY s.pts_type + s.pts_email + s.pts_tel + s.pts_signal + s.pts_tension DESC, s.nom, s.finess
           ) AS rang_departement
    FROM (
      SELECT p.finess, p.nom, p.type_jolene, btrim(p.email) AS email, p.telephone,
             p.ville, p.departement,
             CASE p.type_jolene
               WHEN 'EHPAD' THEN 40 WHEN 'HOPITAL' THEN 35 WHEN 'HANDICAP' THEN 30
               WHEN 'DOMICILE' THEN 25 WHEN 'CENTRE_SANTE' THEN 20 WHEN 'DIALYSE' THEN 20
               ELSE 15 END AS pts_type,
             CASE
               WHEN split_part(lower(p.email), '@', 1)
                    ~ '^(contact|accueil|direction|directeur|directrice|secretariat|info|rh|recrutement|admin|standard)'
                 THEN 10
               WHEN split_part(lower(p.email), '@', 2)
                    ~ '^(gmail|hotmail|yahoo|outlook|orange|wanadoo|free|sfr|laposte|live)\.'
                 THEN 0
               ELSE 5 END AS pts_email,
             CASE WHEN NULLIF(btrim(p.telephone), '') IS NOT NULL THEN 10 ELSE 0 END AS pts_tel,
             CASE WHEN EXISTS (
               SELECT 1 FROM public.acquisition_signaux sg
               WHERE sg.finess = p.finess
                 AND sg.statut NOT IN ('IGNORE', 'EXPIRE')
                 AND sg.importe_le > now() - interval '90 days'
             ) THEN 20 ELSE 0 END AS pts_signal,
             COALESCE((
               SELECT round(t.bmo_difficulte_pct / 10)::integer
               FROM public.acquisition_territoires t
               WHERE t.departement = p.departement AND t.profession = 'AS'
                 AND t.bmo_precision = 'EXACT' AND t.bmo_difficulte_pct IS NOT NULL
             ), 0) AS pts_tension,
             (
               SELECT jsonb_build_object(
                 'projets', t.bmo_projets_recrutement,
                 'difficulte_pct', round(t.bmo_difficulte_pct),
                 'annee', t.bmo_annee)
               FROM public.acquisition_territoires t
               WHERE t.departement = p.departement AND t.profession = 'AS'
                 AND t.bmo_precision = 'EXACT'
                 AND t.bmo_projets_recrutement > 0
                 AND t.bmo_difficulte_pct IS NOT NULL
             ) AS bmo
      FROM public.prospects_etablissements p
      WHERE p.departement = ANY (v_depts)
        AND p.type_jolene = ANY (v_types)
        AND NULLIF(btrim(p.email), '') IS NOT NULL
        AND btrim(p.email) ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
        AND p.email_envoye_le IS NULL
        AND p.ajoute_crm_le IS NULL
        AND p.statut_sourcing NOT IN ('IGNORE', 'OPPOSITION')
        AND NOT EXISTS (
          SELECT 1 FROM public.growth_brouillons b
          WHERE b.cible_type = 'PROSPECT_ETABLISSEMENT' AND b.cible_id = p.finess
            -- Seul un brouillon jamais validé puis expiré libère la cible : un
            -- brouillon validé a pu être envoyé sans « J'ai envoyé ».
            AND NOT (b.statut = 'EXPIRE' AND b.valide_le IS NULL)
        )
    ) s
    ) q
    ORDER BY q.rang_departement, q.score_total DESC, q.nom, q.finess
    LIMIT v_place * 3
  LOOP
    EXIT WHEN v_crees >= v_place;

    IF private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', r.finess, r.email, r.telephone, NULL) IS NOT NULL THEN
      v_exclus_stop := v_exclus_stop + 1;
      CONTINUE;
    END IF;
    -- Une même adresse (siège, groupe) ne reçoit qu'une séquence.
    IF EXISTS (
      SELECT 1 FROM public.growth_brouillons b
      WHERE lower(b.destinataire_email) = lower(r.email)
        AND (b.statut IN ('BROUILLON', 'VALIDE', 'ENVOYE')
             OR (b.statut = 'EXPIRE' AND b.valide_le IS NOT NULL))
    ) THEN
      CONTINUE;
    END IF;

    v_tension := NULL;
    IF r.bmo IS NOT NULL AND (r.bmo->>'difficulte_pct')::numeric >= 40 THEN
      v_tension := format(
        'Dans votre département (%s), France Travail recense %s projets de recrutement d''aides-soignants en %s, dont %s %% jugés difficiles par les employeurs (enquête BMO).',
        r.departement, r.bmo->>'projets', r.bmo->>'annee', r.bmo->>'difficulte_pct');
    END IF;

    IF r.type_jolene = 'ECOLE_SANTE' THEN
      v_lien := private.fn_growth_lien('/devenir-soignant', 'prospection', 'email',
        'agent-prospection', 'ecole-' || r.departement);
      v_sujet := 'Missions pour vos jeunes diplômés';
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Je suis Gabrielle, fondatrice de Jolene, une plateforme qui met en relation des soignants et des établissements de santé pour des missions courtes : vacations, CDD courts et remplacements. L''inscription est gratuite pour les soignants.',
        format('Nous démarrons dans votre secteur et aimerions faire connaître Jolene aux jeunes diplômés de %s. Seriez-vous ouvert à un échange de 15 minutes pour voir comment la présenter à vos promotions (affiche, courte intervention ou information aux diplômés) ?', r.nom),
        'Présentation pour les soignants : ' || v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention);
    ELSE
      v_accroche := CASE r.type_jolene
        WHEN 'EHPAD' THEN 'Pour un EHPAD, Jolene permet de couvrir un arrêt, un week-end ou une période de congés avec des aides-soignants et infirmiers, sans passer par une agence.'
        WHEN 'HANDICAP' THEN 'Pour un établissement médico-social, Jolene permet de trouver des aides-soignants, AES et infirmiers pour une absence ou un renfort ponctuel.'
        WHEN 'DOMICILE' THEN 'Pour un service de soins à domicile, Jolene permet de trouver des aides-soignants et infirmiers pour une absence ou un pic d''activité.'
        WHEN 'CENTRE_SANTE' THEN 'Pour un centre de santé, Jolene permet de trouver des remplaçants (médecins, infirmiers, kinésithérapeutes) pour une vacation ou une période de congés.'
        ELSE 'Pour un établissement de soins, Jolene permet de publier un besoin de renfort (infirmiers, aides-soignants, IBODE, IADE) et de recevoir des candidatures de professionnels vérifiés.'
      END;
      v_lien := private.fn_growth_lien('/recruter-soignants', 'prospection', 'email',
        'agent-prospection', lower(r.type_jolene) || '-' || r.departement);
      v_sujet := left('Renforts soignants pour ' || r.nom, 140);
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Je suis Gabrielle, fondatrice de Jolene, une plateforme qui met directement en relation les établissements de santé et des soignants vérifiés pour des missions courtes : vacations, CDD courts et remplacements.',
        v_accroche,
        v_tension,
        E'Concrètement :\n- vous publiez une mission en quelques minutes ;\n- l''identité et les qualifications professionnelles des soignants sont contrôlées, notamment via le RPPS lorsqu''il existe ;\n- contrats et facturation sont générés automatiquement ;\n- 15 % HT de commission sur le montant de la mission, sans abonnement ni frais d''entrée : vous ne payez que si vous recrutez.',
        'Nous démarrons dans votre secteur et je vous propose d''accompagner personnellement la publication de votre première mission. Seriez-vous disponible 15 minutes cette semaine pour en parler ?',
        'Pour découvrir le fonctionnement : ' || v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention);
    END IF;

    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, destinataire_email,
      departement, profession, sequence_etape, sujet, corps, lien, contexte,
      score, idempotence_key, expire_le
    ) VALUES (
      'PROSPECTION_ETABLISSEMENT', 'EMAIL', 'PROSPECT_ETABLISSEMENT', r.finess,
      r.nom, r.email, r.departement, NULL, 1, v_sujet, v_corps, v_lien,
      jsonb_build_object(
        'type_etablissement', r.type_jolene,
        'ville', r.ville,
        'telephone', NULLIF(btrim(r.telephone), ''),
        'source', 'FINESS (établissement) + Annuaire Santé (email)',
        'score', jsonb_build_object(
          'type', r.pts_type, 'email', r.pts_email, 'telephone', r.pts_tel,
          'signal_boamp_90j', r.pts_signal, 'tension_bmo_as', r.pts_tension),
        'bmo_as', r.bmo),
      r.score_total, 'prospection:' || r.finess || ':etape1', now() + interval '14 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_crees := v_crees + v_n;
  END LOOP;

  -- Étapes 2 et 3 : relances des contacts CRM dont l'échéance est passée,
  -- sans réponse, toujours contactables. La cadence reste celle du CRM.
  FOR c IN
    SELECT sc.id, sc.nom, btrim(sc.email) AS email, sc.telephone, sc.finess,
           sc.departement, sc.type_etab, sc.sequence_etape
    FROM public.sales_contacts sc
    WHERE sc.type = 'ETABLISSEMENT'
      AND sc.sequence_active IS TRUE
      AND sc.prochaine_action_le <= now()
      AND sc.derniere_action_type = 'EMAIL_ENVOYE'
      AND sc.statut IN ('CONTACTE', 'RELANCE')
      AND COALESCE(sc.reponse, 'EN_ATTENTE') = 'EN_ATTENTE'
      AND sc.ne_plus_contacter IS NOT TRUE
      AND COALESCE(sc.archive, false) IS FALSE
      AND sc.sequence_etape BETWEEN 1 AND 2
      AND NULLIF(btrim(sc.email), '') IS NOT NULL
      -- Seuls les contacts ouverts par cet agent : la mention de source reste exacte.
      AND EXISTS (
        SELECT 1 FROM public.growth_brouillons b0
        WHERE b0.agent = 'PROSPECTION_ETABLISSEMENT' AND b0.statut = 'ENVOYE'
          AND b0.cible_type = 'PROSPECT_ETABLISSEMENT' AND b0.cible_id = sc.finess
      )
    ORDER BY sc.prochaine_action_le
    LIMIT 50
  LOOP
    IF private.fn_growth_destinataire_bloque('CONTACT_CRM', c.id::text, c.email, c.telephone, c.finess) IS NOT NULL THEN
      v_exclus_stop := v_exclus_stop + 1;
      CONTINUE;
    END IF;
    v_etape := (c.sequence_etape + 1)::smallint;
    v_lien := private.fn_growth_lien('/recruter-soignants', 'prospection', 'email',
      'agent-prospection-relance', 'etape' || v_etape || '-' || COALESCE(c.departement, 'na'));
    IF v_etape = 2 THEN
      v_sujet := left('Re : renforts soignants pour ' || c.nom, 140);
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Je me permets de revenir vers vous au sujet de Jolene. Si un remplacement se profile dans les prochaines semaines, je peux publier la mission avec vous au téléphone, en une dizaine de minutes.',
        'Le fonctionnement en bref : ' || v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention);
    ELSE
      v_sujet := left('Dernier message — Jolene pour ' || c.nom, 140);
      v_corps := concat_ws(E'\n\n',
        'Bonjour,',
        'Dernier message de ma part : je ne vous relancerai plus. Si un besoin de renfort soignant devient d''actualité, il suffit de répondre à cet email et je vous rappelle.',
        v_lien,
        'Bien cordialement,' || E'\n' || v_signature,
        v_mention);
    END IF;

    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, destinataire_email,
      departement, sequence_etape, sujet, corps, lien, contexte, idempotence_key, expire_le
    ) VALUES (
      'PROSPECTION_ETABLISSEMENT', 'EMAIL', 'CONTACT_CRM', c.id::text, c.nom, c.email,
      c.departement, v_etape, v_sujet, v_corps, v_lien,
      jsonb_build_object('finess', c.finess, 'type_etablissement', c.type_etab,
        'telephone', NULLIF(btrim(c.telephone), ''), 'relance_crm', true),
      'prospection:crm:' || c.id || ':etape' || v_etape, now() + interval '7 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_relances := v_relances + v_n;
  END LOOP;

  RETURN jsonb_build_object(
    'brouillons_crees', v_crees + v_relances,
    'premiers_contacts', v_crees,
    'relances', v_relances,
    'places_du_jour', v_place,
    'exclus_stop', v_exclus_stop,
    'departements', to_jsonb(v_depts));
END;
$body$;

-- ---------------------------------------------------------------------------
-- 5. Agent 2 — posts sociaux hebdomadaires (copier-coller, jamais d'auto-post)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fn_growth_agent_posts()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_depts text[] := private.fn_growth_config_liste('agents_departements_cibles', '75,92,56');
  v_semaine text := to_char(now() AT TIME ZONE 'Europe/Paris', 'IYYY-"S"IW');
  v_angle integer := (extract(week FROM now() AT TIME ZONE 'Europe/Paris')::integer % 3);
  v_dept text;
  v_prof text;
  v_n integer;
  v_crees integer := 0;
  v_nb integer;
  v_taux numeric;
  v_bmo record;
  v_lien text;
  v_corps text;
  v_groupes jsonb;
BEGIN
  FOREACH v_dept IN ARRAY v_depts LOOP
    FOREACH v_prof IN ARRAY ARRAY['AS', 'IDE'] LOOP
      SELECT count(*), max(m.taux_horaire_base) INTO v_nb, v_taux
      FROM private.fn_growth_missions_reelles() m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.statut = 'OUVERTE' AND m.debut_le > now()
        AND m.profession_requise::text = v_prof
        AND e.adresse_departement = v_dept
        AND public.fn_mission_publique(m.id) IS NOT NULL;

      SELECT t.bmo_projets_recrutement AS projets, round(t.bmo_difficulte_pct) AS pct, t.bmo_annee AS annee
        INTO v_bmo
      FROM public.acquisition_territoires t
      WHERE t.departement = v_dept AND t.profession = v_prof AND t.bmo_precision = 'EXACT'
        AND t.bmo_projets_recrutement > 0 AND t.bmo_difficulte_pct IS NOT NULL;

      SELECT COALESCE(jsonb_agg(jsonb_build_object('nom', g.nom, 'url', g.url, 'membres', g.membres)
               ORDER BY g.favori DESC, g.membres DESC NULLS LAST), '[]'::jsonb)
        INTO v_groupes
      FROM (
        SELECT sg.nom, sg.url, sg.membres, sg.favori
        FROM public.sales_groupes sg
        WHERE sg.plateforme = 'FACEBOOK'
          AND sg.profession IN (v_prof, 'TOUTES')
          AND COALESCE(sg.audience, 'MIXTE') IN ('SOIGNANTS', 'MIXTE')
          AND COALESCE(sg.statut, '') <> 'INACTIF'
        ORDER BY sg.favori DESC, sg.membres DESC NULLS LAST
        LIMIT 5
      ) g;

      v_lien := private.fn_growth_lien('/devenir-soignant', 'facebook', 'social',
        'agent-posts', v_dept || '-' || lower(v_prof) || '-' || v_semaine);

      IF v_nb > 0 THEN
        v_corps := concat_ws(E'\n\n',
          format('%s du %s : %s mission%s à pourvoir en ce moment sur Jolene%s.',
            private.fn_growth_majuscule(private.fn_growth_libelle_profession(v_prof, true)), v_dept, v_nb,
            CASE WHEN v_nb > 1 THEN 's' ELSE '' END,
            CASE WHEN v_taux IS NOT NULL THEN format(', jusqu''à %s €/h', trim(to_char(v_taux, 'FM999990.00'))) ELSE '' END),
          'Vacations, CDD courts et remplacements auprès d''établissements de santé. Inscription gratuite, contrats générés automatiquement.',
          'Voir les missions et s''inscrire : ' || v_lien);
      ELSE
        v_corps := concat_ws(E'\n\n',
          format('%s du %s : inscrivez-vous gratuitement sur Jolene et soyez prévenu dès qu''un établissement proche de chez vous publie une mission (vacation, CDD court, remplacement).',
            private.fn_growth_majuscule(private.fn_growth_libelle_profession(v_prof, true)), v_dept),
          CASE WHEN v_bmo.projets IS NOT NULL THEN format(
            'Pour information, France Travail recense %s projets de recrutement de %s dans le %s en %s, dont %s %% jugés difficiles par les employeurs (enquête BMO).',
            v_bmo.projets, private.fn_growth_libelle_profession(v_prof, true), v_dept, v_bmo.annee, v_bmo.pct) END,
          'Créer son profil en 2 minutes : ' || v_lien);
      END IF;

      INSERT INTO public.growth_brouillons (
        agent, canal, cible_type, departement, profession, corps, lien, contexte,
        idempotence_key, expire_le
      ) VALUES (
        'POST_SOCIAL', 'FACEBOOK_GROUPE', 'PUBLIC', v_dept, v_prof, v_corps, v_lien,
        jsonb_build_object('semaine', v_semaine, 'missions_ouvertes_reelles', v_nb,
          'groupes_suggeres', v_groupes,
          'regle', 'Publication manuelle uniquement : pas d''auto-post, pas de scraping des membres.'),
        'posts:' || v_semaine || ':fb:' || v_dept || ':' || v_prof,
        now() + interval '7 days'
      )
      ON CONFLICT (idempotence_key) DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_crees := v_crees + v_n;
    END LOOP;
  END LOOP;

  -- Un post LinkedIn fondatrice par semaine, cible établissements.
  v_lien := private.fn_growth_lien('/recruter-soignants', 'linkedin', 'social',
    'agent-posts', 'etablissements-' || v_semaine);
  v_corps := CASE v_angle
    WHEN 0 THEN concat_ws(E'\n\n',
      'Un arrêt maladie à 6 h du matin, un week-end à couvrir, des congés qui se chevauchent : dans beaucoup d''EHPAD et de structures médico-sociales, le remplacement se joue au téléphone, au dernier moment.',
      'Avec Jolene, vous publiez la mission en quelques minutes et les soignants candidatent directement. Contrats et facturation sont générés automatiquement.',
      'Nous démarrons en Île-de-France et dans le Morbihan. Si vous dirigez un établissement et voulez tester sur votre prochaine absence, écrivez-moi : je publie la première mission avec vous.',
      v_lien)
    WHEN 1 THEN concat_ws(E'\n\n',
      'Une question que me posent les directeurs d''établissement : « combien ça coûte ? »',
      'Sur Jolene : 15 % HT de commission sur le montant de la mission, sans abonnement ni frais d''entrée. Vous ne payez que si vous recrutez. Pas de marge d''agence.',
      'Nous ouvrons la plateforme établissement par établissement en Île-de-France et dans le Morbihan, avec un accompagnement personnel pour la première mission.',
      v_lien)
    ELSE concat_ws(E'\n\n',
      'Recruter un renfort, c''est aussi vérifier : identité, diplôme, numéro RPPS lorsqu''il existe.',
      'Sur Jolene, l''identité et les qualifications professionnelles des soignants sont contrôlées, notamment via le RPPS lorsqu''il existe, et vous gardez la décision finale sur chaque candidature.',
      'Vous dirigez un EHPAD, un centre de santé ou une structure médico-sociale en Île-de-France ou dans le Morbihan ? Parlons de votre prochaine absence à couvrir.',
      v_lien)
  END;
  INSERT INTO public.growth_brouillons (
    agent, canal, cible_type, corps, lien, contexte, idempotence_key, expire_le
  ) VALUES (
    'POST_SOCIAL', 'LINKEDIN', 'PUBLIC', v_corps, v_lien,
    jsonb_build_object('semaine', v_semaine, 'angle', v_angle,
      'cible', 'Directions d''établissements (profil LinkedIn de la fondatrice)'),
    'posts:' || v_semaine || ':linkedin', now() + interval '7 days'
  )
  ON CONFLICT (idempotence_key) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_crees := v_crees + v_n;

  RETURN jsonb_build_object('brouillons_crees', v_crees, 'semaine', v_semaine);
END;
$body$;

-- ---------------------------------------------------------------------------
-- 6. Agent 3 — missions à pourvoir (réelles, ouvertes, sans candidature)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fn_growth_agent_missions()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  r record;
  v_n integer;
  v_crees integer := 0;
  v_lien text;
  v_corps text;
BEGIN
  FOR r IN
    SELECT m.id, m.profession_requise::text AS profession, m.debut_le, m.fin_le,
           m.taux_horaire_base, m.est_urgente, e.adresse_ville AS ville,
           e.adresse_departement AS departement,
           (SELECT count(*) FROM public.soignants s
             WHERE s.est_compte_test IS FALSE AND s.supprime_le IS NULL
               AND s.profession::text = m.profession_requise::text
               AND s.tous_documents_valides IS TRUE) AS soignants_verifies_profession
    FROM private.fn_growth_missions_reelles() m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND m.cree_le < now() - interval '6 hours'
      AND NOT EXISTS (SELECT 1 FROM public.candidatures ca WHERE ca.mission_id = m.id)
      -- Visibilité publique = source canonique (page /mission/:id), jamais re-décidée ici.
      AND public.fn_mission_publique(m.id) IS NOT NULL
    ORDER BY m.debut_le
    LIMIT 30
  LOOP
    v_lien := private.fn_growth_lien('/mission/' || r.id, 'facebook', 'social',
      'agent-missions', COALESCE(r.departement, 'na') || '-' || lower(r.profession));
    v_corps := concat_ws(E'\n\n',
      format('%sMission %s à %s%s : %s.',
        CASE WHEN r.est_urgente THEN 'Urgent — ' ELSE '' END,
        private.fn_growth_libelle_profession(r.profession, false),
        COALESCE(r.ville, 'proximité'),
        CASE WHEN r.departement IS NOT NULL THEN ' (' || r.departement || ')' ELSE '' END,
        CASE WHEN r.fin_le IS NOT NULL AND (r.fin_le AT TIME ZONE 'Europe/Paris')::date <> (r.debut_le AT TIME ZONE 'Europe/Paris')::date
          THEN 'du ' || to_char(r.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM') || ' au ' || to_char(r.fin_le AT TIME ZONE 'Europe/Paris', 'DD/MM')
          ELSE 'le ' || to_char(r.debut_le AT TIME ZONE 'Europe/Paris', 'DD/MM à HH24"h"MI') END),
      CASE WHEN r.taux_horaire_base IS NOT NULL
        THEN format('Taux affiché : %s €/h.', trim(to_char(r.taux_horaire_base, 'FM999990.00'))) END,
      'Détails et candidature (inscription gratuite) : ' || v_lien);

    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, departement, profession, corps, lien,
      contexte, idempotence_key, expire_le
    ) VALUES (
      'MISSION_A_POURVOIR', 'FACEBOOK_GROUPE', 'MISSION', r.id::text, r.departement,
      r.profession, v_corps, v_lien,
      jsonb_build_object('debut_le', r.debut_le,
        'soignants_verifies_meme_profession', r.soignants_verifies_profession,
        'conseil', 'Publier dans les groupes locaux puis appeler les soignants vérifiés disponibles (Admin → Missions).'),
      'mission:' || r.id, r.debut_le
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_crees := v_crees + v_n;
  END LOOP;
  RETURN jsonb_build_object('brouillons_crees', v_crees);
END;
$body$;

-- ---------------------------------------------------------------------------
-- 7. Agent 4 — réactivation des inscrits réels bloqués
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fn_growth_agent_reactivation()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  r record;
  v_n integer;
  v_crees integer := 0;
  v_signature text := private.fn_growth_config('prospection_signature', E'Gabrielle\nFondatrice de Jolene');
  v_message text;
  v_lien text;
  v_cle text := to_char(now() AT TIME ZONE 'Europe/Paris', 'IYYY-"S"IW');
BEGIN
  -- Soignants : inscrits depuis plus de 3 jours, sans candidature.
  FOR r IN
    SELECT s.id, s.prenom, btrim(s.email) AS email, s.profession::text AS profession,
           s.adresse_departement_calc AS departement, s.blocage
    FROM (
      SELECT so.*, NULLIF(left(COALESCE(so.adresse_code_postal, ''), 2), '') AS adresse_departement_calc,
        CASE
          WHEN NOT EXISTS (SELECT 1 FROM public.documents_soignants d
                           WHERE d.soignant_id = so.id AND d.supprime_le IS NULL) THEN 'DOCUMENTS'
          WHEN so.tous_documents_valides IS NOT TRUE THEN 'VERIFICATION'
          ELSE 'CANDIDATURE'
        END AS blocage
      FROM public.soignants so
      WHERE so.est_compte_test IS FALSE
        AND so.supprime_le IS NULL
        AND COALESCE(so.statut_compte::text, 'ACTIF') = 'ACTIF'
        AND so.cree_le < now() - interval '3 days'
        AND NULLIF(btrim(so.email), '') IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM public.candidatures ca WHERE ca.soignant_id = so.id)
        AND private.fn_growth_destinataire_bloque('SOIGNANT', so.id::text, so.email, so.telephone, NULL) IS NULL
        AND NOT EXISTS (SELECT 1 FROM public.growth_brouillons b
                        WHERE b.agent = 'REACTIVATION' AND b.cible_type = 'SOIGNANT'
                          AND b.cible_id = so.id::text AND b.cree_le > now() - interval '14 days')
      ORDER BY so.cree_le DESC
      LIMIT 30
    ) s
  LOOP
    v_lien := private.fn_growth_lien(
      CASE r.blocage WHEN 'CANDIDATURE' THEN '/soignant/recherche-missions' ELSE '/soignant/documents' END,
      'reactivation', 'email', 'agent-reactivation', lower(r.blocage));
    v_message := CASE r.blocage
      WHEN 'DOCUMENTS' THEN 'Il vous reste à ajouter vos documents pour compléter votre profil : une photo prise avec votre téléphone suffit.'
      WHEN 'VERIFICATION' THEN 'Certains de vos documents sont encore en attente ou à compléter : vous pouvez suivre leur état depuis votre espace.'
      ELSE 'Votre profil est prêt. Activez une alerte sur votre zone et votre métier : vous serez prévenu dès qu''une mission correspondante est publiée.'
    END;
    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, destinataire_email,
      departement, profession, sujet, corps, lien, contexte, idempotence_key, expire_le
    ) VALUES (
      'REACTIVATION', 'EMAIL', 'SOIGNANT', r.id::text, r.prenom, r.email,
      r.departement, r.profession,
      CASE r.blocage WHEN 'CANDIDATURE' THEN 'Votre profil Jolene est prêt' ELSE 'Complétez votre profil Jolene' END,
      concat_ws(E'\n\n',
        'Bonjour' || COALESCE(' ' || NULLIF(btrim(r.prenom), ''), '') || ',',
        'Merci de vous être inscrit sur Jolene.',
        v_message,
        v_lien,
        'Belle journée,' || E'\n' || v_signature,
        'Vous pouvez gérer vos préférences d''email depuis votre compte Jolene.'),
      v_lien,
      jsonb_build_object('blocage', r.blocage, 'base', 'Compte inscrit (relation existante), préférences email respectées'),
      'reactivation:soignant:' || r.id || ':' || v_cle, now() + interval '7 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_crees := v_crees + v_n;
  END LOOP;

  -- Établissements réels inscrits n'ayant jamais publié.
  FOR r IN
    SELECT e.id, e.nom, btrim(e.email_contact) AS email, e.adresse_departement AS departement,
           CASE WHEN e.peut_publier_missions IS TRUE THEN 'PUBLICATION' ELSE 'VERIFICATION' END AS blocage
    FROM public.etablissements e
    WHERE e.est_compte_test IS FALSE
      AND e.supprime_le IS NULL
      AND e.cree_le < now() - interval '2 days'
      AND NULLIF(btrim(e.email_contact), '') IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM public.missions m WHERE m.etablissement_id = e.id)
      AND private.fn_growth_destinataire_bloque('ETABLISSEMENT', e.id::text, e.email_contact, e.telephone_contact, e.finess) IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.growth_brouillons b
                      WHERE b.agent = 'REACTIVATION' AND b.cible_type = 'ETABLISSEMENT'
                        AND b.cible_id = e.id::text AND b.cree_le > now() - interval '14 days')
    ORDER BY e.cree_le DESC
    LIMIT 30
  LOOP
    v_lien := private.fn_growth_lien(
      CASE r.blocage WHEN 'PUBLICATION' THEN '/etablissement/missions/creer' ELSE '/etablissement/activer' END,
      'reactivation', 'email', 'agent-reactivation', 'etab-' || lower(r.blocage));
    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, destinataire_email,
      departement, sujet, corps, lien, contexte, idempotence_key, expire_le
    ) VALUES (
      'REACTIVATION', 'EMAIL', 'ETABLISSEMENT', r.id::text, r.nom, r.email, r.departement,
      CASE r.blocage WHEN 'PUBLICATION' THEN 'Publions ensemble votre première mission' ELSE 'Finaliser l''activation de votre établissement' END,
      concat_ws(E'\n\n',
        'Bonjour,',
        'Merci d''avoir inscrit ' || r.nom || ' sur Jolene.',
        CASE r.blocage
          WHEN 'PUBLICATION' THEN 'Votre établissement peut publier des missions. Si vous avez une absence à couvrir prochainement, je vous propose de publier la première mission avec vous au téléphone, en une dizaine de minutes.'
          ELSE 'Il reste quelques éléments pour activer votre établissement et publier votre première mission. Je peux vous accompagner par téléphone si besoin.'
        END,
        v_lien,
        'Bien cordialement,' || E'\n' || v_signature),
      v_lien,
      jsonb_build_object('blocage', r.blocage, 'base', 'Compte inscrit (relation existante)'),
      'reactivation:etab:' || r.id || ':' || v_cle, now() + interval '7 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_crees := v_crees + v_n;
  END LOOP;

  RETURN jsonb_build_object('brouillons_crees', v_crees);
END;
$body$;

-- ---------------------------------------------------------------------------
-- 8. Entonnoir (cohorte réelle uniquement) et rapport hebdomadaire figé
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fn_growth_entonnoir(p_debut timestamptz, p_fin timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $body$
DECLARE
  v_soignants jsonb;
  v_etabs jsonb;
  v_missions jsonb;
  v_prospection jsonb;
  v_agents jsonb;
  v_sources jsonb;
  v_test jsonb;
BEGIN
  IF p_debut IS NULL OR p_fin IS NULL OR p_fin <= p_debut THEN
    RAISE EXCEPTION 'Période invalide';
  END IF;

  WITH s AS (
    SELECT so.* FROM public.soignants so
    WHERE so.est_compte_test IS FALSE AND so.supprime_le IS NULL AND so.cree_le < p_fin
  )
  SELECT jsonb_build_object(
    'inscrits_total', count(*),
    'inscrits_periode', count(*) FILTER (WHERE s.cree_le >= p_debut),
    'avec_document', count(*) FILTER (WHERE EXISTS (
      SELECT 1 FROM public.documents_soignants d WHERE d.soignant_id = s.id AND d.supprime_le IS NULL)),
    'documents_valides', count(*) FILTER (WHERE s.tous_documents_valides IS TRUE),
    'onboarding_termine', count(*) FILTER (WHERE s.onboarding_termine_le IS NOT NULL),
    'ayant_candidate', count(*) FILTER (WHERE EXISTS (
      SELECT 1 FROM public.candidatures ca WHERE ca.soignant_id = s.id)),
    'ayant_realise_mission', count(*) FILTER (WHERE s.premiere_mission_le IS NOT NULL),
    'actifs_periode', count(*) FILTER (WHERE s.derniere_activite_le >= p_debut)
  ) INTO v_soignants FROM s;

  WITH e AS (
    SELECT et.* FROM public.etablissements et
    WHERE et.est_compte_test IS FALSE AND et.supprime_le IS NULL AND et.cree_le < p_fin
  )
  SELECT jsonb_build_object(
    'inscrits_total', count(*),
    'inscrits_periode', count(*) FILTER (WHERE e.cree_le >= p_debut),
    'peuvent_publier', count(*) FILTER (WHERE e.peut_publier_missions IS TRUE),
    'ayant_publie', count(*) FILTER (WHERE EXISTS (
      SELECT 1 FROM public.missions m WHERE m.etablissement_id = e.id))
  ) INTO v_etabs FROM e;

  WITH m AS (SELECT * FROM private.fn_growth_missions_reelles())
  SELECT jsonb_build_object(
    'publiees_periode', count(*) FILTER (WHERE m.cree_le >= p_debut AND m.cree_le < p_fin),
    'pourvues_periode', count(*) FILTER (WHERE m.cree_le >= p_debut AND m.cree_le < p_fin
                                           AND m.soignant_assigne_id IS NOT NULL),
    'terminees_periode', count(*) FILTER (WHERE m.statut = 'TERMINEE'
                                            AND m.terminee_le >= p_debut AND m.terminee_le < p_fin),
    'ouvertes_a_venir', count(*) FILTER (WHERE m.statut = 'OUVERTE' AND m.debut_le > now()),
    'ouvertes_sans_candidature', count(*) FILTER (WHERE m.statut = 'OUVERTE' AND m.debut_le > now()
      AND NOT EXISTS (SELECT 1 FROM public.candidatures ca WHERE ca.mission_id = m.id)),
    'candidatures_periode', (
      SELECT count(*) FROM public.candidatures ca
      JOIN private.fn_growth_missions_reelles() mr ON mr.id = ca.mission_id
      WHERE ca.cree_le >= p_debut AND ca.cree_le < p_fin)
  ) INTO v_missions FROM m;

  SELECT jsonb_build_object(
    'prospects_etablissements', (SELECT count(*) FROM public.prospects_etablissements),
    'prospects_avec_email', (SELECT count(*) FROM public.prospects_etablissements
                             WHERE NULLIF(btrim(email), '') IS NOT NULL),
    'prospects_contactes_total', (SELECT count(*) FROM public.prospects_etablissements
                                  WHERE email_envoye_le IS NOT NULL),
    'emails_journalises_periode', (SELECT count(*) FROM public.sales_activites a
                                   WHERE a.action_type = 'EMAIL_ENVOYE'
                                     AND a.cree_le >= p_debut AND a.cree_le < p_fin),
    'crm_par_statut', (SELECT COALESCE(jsonb_object_agg(x.statut, x.n), '{}'::jsonb)
                       FROM (SELECT sc.statut, count(*) AS n FROM public.sales_contacts sc
                             WHERE COALESCE(sc.archive, false) IS FALSE GROUP BY sc.statut) x),
    'crm_reponses_positives', (SELECT count(*) FROM public.sales_contacts sc WHERE sc.reponse = 'POSITIVE'),
    'crm_stop', (SELECT count(*) FROM public.sales_contacts sc WHERE sc.ne_plus_contacter IS TRUE)
  ) INTO v_prospection;

  SELECT jsonb_build_object(
    'crees_periode', count(*) FILTER (WHERE b.cree_le >= p_debut AND b.cree_le < p_fin),
    'valides_periode', count(*) FILTER (WHERE b.valide_le >= p_debut AND b.valide_le < p_fin),
    'envoyes_periode', count(*) FILTER (WHERE b.envoye_le >= p_debut AND b.envoye_le < p_fin),
    'rejetes_periode', count(*) FILTER (WHERE b.statut = 'REJETE' AND b.maj_le >= p_debut AND b.maj_le < p_fin),
    'en_attente', count(*) FILTER (WHERE b.statut IN ('BROUILLON', 'VALIDE')),
    'par_agent', (SELECT COALESCE(jsonb_object_agg(y.agent, y.d), '{}'::jsonb) FROM (
      SELECT b2.agent, jsonb_build_object(
        'en_attente', count(*) FILTER (WHERE b2.statut IN ('BROUILLON', 'VALIDE')),
        'envoyes_periode', count(*) FILTER (WHERE b2.envoye_le >= p_debut AND b2.envoye_le < p_fin),
        'crees_periode', count(*) FILTER (WHERE b2.cree_le >= p_debut AND b2.cree_le < p_fin)) AS d
      FROM public.growth_brouillons b2 GROUP BY b2.agent) y)
  ) INTO v_agents FROM public.growth_brouillons b;

  SELECT COALESCE(jsonb_object_agg(z.source, z.n), '{}'::jsonb) INTO v_sources
  FROM (
    SELECT COALESCE(NULLIF(u.utm_source, ''), NULLIF(u.source_acquisition::text, ''), 'DIRECT') AS source,
           count(*) AS n
    FROM (
      SELECT so.utm_source, so.source_acquisition::text AS source_acquisition FROM public.soignants so
      WHERE so.est_compte_test IS FALSE AND so.supprime_le IS NULL
        AND so.cree_le >= p_debut AND so.cree_le < p_fin
      UNION ALL
      SELECT et.utm_source, et.source_acquisition::text FROM public.etablissements et
      WHERE et.est_compte_test IS FALSE AND et.supprime_le IS NULL
        AND et.cree_le >= p_debut AND et.cree_le < p_fin
    ) u
    GROUP BY 1
  ) z;

  SELECT jsonb_build_object(
    'soignants_test', (SELECT count(*) FROM public.soignants WHERE est_compte_test IS TRUE),
    'etablissements_test', (SELECT count(*) FROM public.etablissements WHERE est_compte_test IS TRUE)
  ) INTO v_test;

  RETURN jsonb_build_object(
    'periode', jsonb_build_object('debut', p_debut, 'fin', p_fin),
    'genere_le', now(),
    'cohorte', 'REELLE',
    'soignants', v_soignants,
    'etablissements', v_etabs,
    'missions', v_missions,
    'prospection', v_prospection,
    'agents', v_agents,
    'sources_inscriptions_periode', v_sources,
    'exclus_cohorte_test', v_test);
END;
$body$;

CREATE OR REPLACE FUNCTION private.fn_growth_snapshot_hebdo()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  -- Semaine ISO complète précédente, en heure de Paris.
  v_lundi date := (date_trunc('week', now() AT TIME ZONE 'Europe/Paris'))::date - 7;
  v_debut timestamptz := (v_lundi::timestamp) AT TIME ZONE 'Europe/Paris';
  v_fin timestamptz := ((v_lundi + 7)::timestamp) AT TIME ZONE 'Europe/Paris';
  v_donnees jsonb;
BEGIN
  v_donnees := private.fn_growth_entonnoir(v_debut, v_fin);
  INSERT INTO public.growth_rapports_hebdo (semaine_debut, semaine_fin, donnees)
  VALUES (v_lundi, v_lundi + 6, v_donnees)
  ON CONFLICT (semaine_debut) DO UPDATE
    SET donnees = EXCLUDED.donnees, semaine_fin = EXCLUDED.semaine_fin, cree_le = now();
  RETURN jsonb_build_object('semaine_debut', v_lundi, 'donnees', v_donnees);
END;
$body$;

-- ---------------------------------------------------------------------------
-- 9. Orchestrateur : exécute chaque agent isolément et trace l'exécution
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.fn_growth_agents_executer(p_declencheur text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_declencheur text := upper(COALESCE(p_declencheur, 'CRON'));
  v_agent text;
  v_res jsonb;
  v_exec bigint;
  v_bilan jsonb := '{}'::jsonb;
  v_expires integer;
BEGIN
  IF v_declencheur NOT IN ('CRON', 'ADMIN') THEN
    RAISE EXCEPTION 'Déclencheur invalide';
  END IF;
  -- Le cron respecte l'interrupteur ; un lancement manuel admin reste possible.
  IF v_declencheur = 'CRON'
     AND private.fn_growth_config('agents_croissance_actifs', 'false') <> 'true' THEN
    RETURN jsonb_build_object('ignore', true, 'raison', 'growth_config.agents_croissance_actifs <> true');
  END IF;

  -- Données d'un compte supprimé : aucun brouillon ne les conserve.
  DELETE FROM public.growth_brouillons b
   WHERE (b.cible_type = 'SOIGNANT' AND NOT EXISTS (
            SELECT 1 FROM public.soignants s
            WHERE s.id::text = b.cible_id AND s.supprime_le IS NULL AND s.est_compte_test IS FALSE))
      OR (b.cible_type = 'ETABLISSEMENT' AND NOT EXISTS (
            SELECT 1 FROM public.etablissements e
            WHERE e.id::text = b.cible_id AND e.supprime_le IS NULL AND e.est_compte_test IS FALSE));

  -- Un brouillon non envoyé expire, même validé. Seul un brouillon jamais
  -- validé libère sa clé (cible reproposable) ; un brouillon validé a pu être
  -- envoyé sans constat, sa cible reste donc exclue.
  UPDATE public.growth_brouillons
     SET statut = 'EXPIRE', maj_le = now(),
         idempotence_key = CASE WHEN valide_le IS NULL
                                THEN idempotence_key || ':expire:' || id
                                ELSE idempotence_key END
   WHERE statut IN ('BROUILLON', 'VALIDE') AND expire_le IS NOT NULL AND expire_le < now();
  GET DIAGNOSTICS v_expires = ROW_COUNT;

  FOREACH v_agent IN ARRAY ARRAY['PROSPECTION_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'] LOOP
    INSERT INTO public.growth_agent_executions (agent, declencheur)
    VALUES (v_agent, v_declencheur) RETURNING id INTO v_exec;
    BEGIN
      v_res := CASE v_agent
        WHEN 'PROSPECTION_ETABLISSEMENT' THEN private.fn_growth_agent_prospection()
        WHEN 'POST_SOCIAL' THEN private.fn_growth_agent_posts()
        WHEN 'MISSION_A_POURVOIR' THEN private.fn_growth_agent_missions()
        ELSE private.fn_growth_agent_reactivation()
      END;
      UPDATE public.growth_agent_executions
         SET fin_le = clock_timestamp(),
             brouillons_crees = COALESCE((v_res->>'brouillons_crees')::integer, 0),
             details = v_res
       WHERE id = v_exec;
    EXCEPTION WHEN OTHERS THEN
      v_res := jsonb_build_object('erreur', SQLERRM);
      UPDATE public.growth_agent_executions
         SET fin_le = clock_timestamp(), erreur = left(SQLERRM, 1000)
       WHERE id = v_exec;
    END;
    v_bilan := v_bilan || jsonb_build_object(v_agent, v_res);
  END LOOP;

  RETURN jsonb_build_object('declencheur', v_declencheur, 'expires', v_expires, 'agents', v_bilan);
END;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_config(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_config_int(text, integer, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_config_liste(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_lien(text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_libelle_profession(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_majuscule(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_missions_reelles() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_destinataire_bloque(text, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_agent_prospection() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_agent_posts() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_agent_missions() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_agent_reactivation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_entonnoir(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_snapshot_hebdo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_agents_executer(text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 10. RPC admin (SECURITY DEFINER, inventoriées)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_admin_growth_entonnoir(p_jours integer DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $body$
DECLARE
  v_jours integer := greatest(1, least(365, COALESCE(p_jours, 7)));
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès admin requis' USING ERRCODE = '42501';
  END IF;
  RETURN private.fn_growth_entonnoir(now() - make_interval(days => v_jours), now());
END;
$body$;

CREATE OR REPLACE FUNCTION public.fn_admin_growth_executer_agents()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $body$
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès admin requis' USING ERRCODE = '42501';
  END IF;
  RETURN private.fn_growth_agents_executer('ADMIN');
END;
$body$;

-- Décision humaine sur un brouillon. Aucune action n'envoie de message :
-- MARQUER_ENVOYE constate un envoi/une publication faits par la fondatrice.
CREATE OR REPLACE FUNCTION public.fn_admin_growth_brouillon_decider(
  p_id uuid,
  p_action text,
  p_sujet text DEFAULT NULL,
  p_corps text DEFAULT NULL,
  p_motif text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $body$
DECLARE
  v_action text := upper(btrim(COALESCE(p_action, '')));
  v_b public.growth_brouillons%ROWTYPE;
  v_contact_id uuid;
  v_crm jsonb;
  v_motif text;
  v_sujet text := NULLIF(btrim(COALESCE(p_sujet, '')), '');
  v_corps text := NULLIF(btrim(COALESCE(p_corps, '')), '');
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès admin requis' USING ERRCODE = '42501';
  END IF;
  IF v_action NOT IN ('MODIFIER', 'VALIDER', 'REJETER', 'MARQUER_ENVOYE') THEN
    RAISE EXCEPTION 'Action invalide : %', v_action;
  END IF;

  SELECT * INTO v_b FROM public.growth_brouillons WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Brouillon introuvable';
  END IF;

  IF v_action IN ('MODIFIER', 'VALIDER', 'REJETER') AND v_b.statut NOT IN ('BROUILLON', 'VALIDE') THEN
    RAISE EXCEPTION 'Brouillon déjà traité (%)', v_b.statut;
  END IF;
  IF v_action = 'MARQUER_ENVOYE' AND v_b.statut <> 'VALIDE' THEN
    RAISE EXCEPTION 'Seul un brouillon validé peut être marqué envoyé (statut actuel : %)', v_b.statut;
  END IF;
  IF v_corps IS NOT NULL AND char_length(v_corps) > 8000 THEN
    RAISE EXCEPTION 'Corps trop long';
  END IF;
  IF v_sujet IS NOT NULL AND char_length(v_sujet) > 300 THEN
    RAISE EXCEPTION 'Sujet trop long';
  END IF;

  -- Joignabilité revérifiée à chaque validation et au constat d'envoi : une
  -- opposition, un refus d'emails ou une suppression de compte a pu arriver.
  -- Pas de RAISE ici : il annulerait le rejet, qui doit persister.
  IF v_action IN ('VALIDER', 'MARQUER_ENVOYE') AND v_b.canal = 'EMAIL' THEN
    v_motif := private.fn_growth_destinataire_bloque(
      v_b.cible_type, v_b.cible_id, v_b.destinataire_email,
      v_b.contexte->>'telephone', v_b.contexte->>'finess');
    IF v_motif = 'COMPTE_SUPPRIME' THEN
      DELETE FROM public.growth_brouillons WHERE id = p_id;
      RETURN jsonb_build_object('success', false, 'id', p_id, 'statut', 'SUPPRIME',
        'raison', 'Compte supprimé : brouillon effacé, aucun envoi possible');
    ELSIF v_motif IS NOT NULL THEN
      UPDATE public.growth_brouillons
         SET statut = 'REJETE', maj_le = now(),
             motif_rejet = CASE v_motif
               WHEN 'STOP' THEN 'Opposition (STOP) ou contact perdu'
               WHEN 'EMAILS_DESACTIVES' THEN 'Emails désactivés par le destinataire'
               ELSE 'Destinataire invalide' END
       WHERE id = p_id;
      RETURN jsonb_build_object('success', false, 'id', p_id, 'statut', 'REJETE',
        'raison', CASE v_motif
          WHEN 'STOP' THEN 'Contact en opposition (STOP) ou perdu : aucun envoi possible'
          WHEN 'EMAILS_DESACTIVES' THEN 'Le destinataire a désactivé ces emails : aucun envoi possible'
          ELSE 'Destinataire invalide : aucun envoi possible' END);
    END IF;
  END IF;

  IF v_action = 'MODIFIER' THEN
    UPDATE public.growth_brouillons
       SET sujet = COALESCE(v_sujet, sujet), corps = COALESCE(v_corps, corps), maj_le = now()
     WHERE id = p_id;
  ELSIF v_action = 'VALIDER' THEN
    UPDATE public.growth_brouillons
       SET sujet = COALESCE(v_sujet, sujet), corps = COALESCE(v_corps, corps),
           statut = 'VALIDE', valide_par = auth.uid(), valide_le = now(), maj_le = now()
     WHERE id = p_id;
  ELSIF v_action = 'REJETER' THEN
    UPDATE public.growth_brouillons
       SET statut = 'REJETE', motif_rejet = left(COALESCE(NULLIF(btrim(p_motif), ''), 'Rejeté par l''admin'), 500),
           maj_le = now()
     WHERE id = p_id;
  ELSE
    -- Constat d'envoi : alimente le CRM et la séquence existants.
    IF v_b.canal = 'EMAIL' AND v_b.cible_type = 'PROSPECT_ETABLISSEMENT' THEN
      v_crm := public.fn_admin_sourcing_ajouter_crm('ETABLISSEMENT', v_b.cible_id, v_b.score);
      v_contact_id := (v_crm->>'contact_id')::uuid;
      PERFORM public.fn_crm_enregistrer_email_envoye(
        v_contact_id, false, 'Brouillon agent ' || v_b.id || ' (étape ' || COALESCE(v_b.sequence_etape, 1) || ')');
      UPDATE public.prospects_etablissements
         SET email_envoye_le = COALESCE(email_envoye_le, now())
       WHERE finess = v_b.cible_id;
    ELSIF v_b.canal = 'EMAIL' AND v_b.cible_type = 'CONTACT_CRM' THEN
      v_contact_id := v_b.cible_id::uuid;
      PERFORM public.fn_crm_enregistrer_email_envoye(
        v_contact_id, false, 'Brouillon agent ' || v_b.id || ' (étape ' || COALESCE(v_b.sequence_etape, 2) || ')');
      -- L'étape 3 annonce « je ne vous relancerai plus » : le CRM ne doit plus
      -- programmer de relance ni garder de tâche ouverte.
      IF v_b.sequence_etape = 3 THEN
        UPDATE public.sales_contacts
           SET sequence_active = false, prochaine_action_le = NULL, a_rappeler = false, maj_le = now()
         WHERE id = v_contact_id;
        UPDATE public.sales_taches
           SET statut = 'ANNULEE', maj_le = now()
         WHERE contact_id = v_contact_id AND statut IN ('A_FAIRE', 'EN_COURS');
      END IF;
    END IF;
    UPDATE public.growth_brouillons
       SET statut = 'ENVOYE', envoye_par = auth.uid(), envoye_le = now(), maj_le = now()
     WHERE id = p_id;
  END IF;

  SELECT * INTO v_b FROM public.growth_brouillons WHERE id = p_id;
  RETURN jsonb_build_object('success', true, 'id', v_b.id, 'statut', v_b.statut,
    'contact_crm_id', v_contact_id);
END;
$body$;

-- Interrupteur de la préparation automatique : p_actif NULL = lecture seule.
-- Active/désactive les deux crons ET growth_config.agents_croissance_actifs.
-- Les agents n'écrivent que des brouillons : aucun envoi n'en dépend.
CREATE OR REPLACE FUNCTION public.fn_admin_growth_planification(p_actif boolean DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $body$
DECLARE
  v_job record;
  v_cron boolean := EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron');
  v_jobs jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.est_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Accès admin requis' USING ERRCODE = '42501';
  END IF;

  IF p_actif IS NOT NULL THEN
    INSERT INTO public.growth_config (cle, valeur, maj_le)
    VALUES ('agents_croissance_actifs', CASE WHEN p_actif THEN 'true' ELSE 'false' END, now())
    ON CONFLICT (cle) DO UPDATE SET valeur = EXCLUDED.valeur, maj_le = now();
    IF v_cron THEN
      FOR v_job IN
        SELECT j.jobid FROM cron.job j
        WHERE j.jobname IN ('jolene_growth_agents_quotidien', 'jolene_growth_rapport_hebdo')
      LOOP
        PERFORM cron.alter_job(job_id := v_job.jobid, active := p_actif);
      END LOOP;
    END IF;
    INSERT INTO public.growth_agent_executions (agent, declencheur, fin_le, details)
    VALUES ('PLANIFICATION', 'ADMIN', now(),
      jsonb_build_object('actif', p_actif, 'par', auth.uid()));
  END IF;

  IF v_cron THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'jobname', j.jobname, 'schedule', j.schedule, 'active', j.active)
             ORDER BY j.jobname), '[]'::jsonb)
      INTO v_jobs
    FROM cron.job j
    WHERE j.jobname IN ('jolene_growth_agents_quotidien', 'jolene_growth_rapport_hebdo');
  END IF;

  RETURN jsonb_build_object(
    'actif', private.fn_growth_config('agents_croissance_actifs', 'false') = 'true'
             AND (NOT v_cron OR (
               jsonb_array_length(v_jobs) = 2
               AND NOT EXISTS (
                 SELECT 1 FROM jsonb_array_elements(v_jobs) x WHERE (x->>'active')::boolean IS NOT TRUE))),
    'pg_cron', v_cron,
    'jobs', v_jobs);
END;
$body$;

REVOKE ALL ON FUNCTION public.fn_admin_growth_entonnoir(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_growth_executer_agents() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_growth_brouillon_decider(uuid, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_growth_planification(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_growth_entonnoir(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_growth_executer_agents() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_growth_brouillon_decider(uuid, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_growth_planification(boolean) TO authenticated, service_role;

INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT x.signature, 'ADMIN_EST_ADMIN_VALIDE', pg_catalog.md5(p.prosrc), x.justification, pg_catalog.now()
FROM (VALUES
  ('fn_admin_growth_entonnoir(integer)', 'public.fn_admin_growth_entonnoir(integer)',
   'UID non NULL + est_admin() ; lecture agrégée de l''entonnoir, cohorte réelle uniquement, aucune donnée nominative. Source : 20261109082510_agents_croissance_brouillons.sql'),
  ('fn_admin_growth_executer_agents()', 'public.fn_admin_growth_executer_agents()',
   'UID non NULL + est_admin() ; lance les agents qui écrivent des brouillons, aucun envoi. Source : 20261109082510_agents_croissance_brouillons.sql'),
  ('fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)',
   'UID non NULL + est_admin() ; verrou FOR UPDATE, garde STOP fn_sales_outreach_est_interdit et préférences email, journalisation CRM existante ; n''envoie rien. Source : 20261109082510_agents_croissance_brouillons.sql'),
  ('fn_admin_growth_planification(boolean)', 'public.fn_admin_growth_planification(boolean)',
   'UID non NULL + est_admin() ; active/désactive uniquement les deux crons jolene_growth_* (brouillons, aucun envoi) et le drapeau growth_config associé ; NULL = lecture. Source : 20261109082510_agents_croissance_brouillons.sql')
) AS x(signature, regsig, justification)
JOIN pg_catalog.pg_proc p ON p.oid = x.regsig::pg_catalog.regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

-- ---------------------------------------------------------------------------
-- 11. Crons (SQL pur, bornés, sans pg_net). Garde pg_cron pour les branches.
-- ---------------------------------------------------------------------------
DO $cron$
DECLARE
  v_job record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;
  FOR v_job IN
    SELECT jobid FROM cron.job
    WHERE jobname IN ('jolene_growth_agents_quotidien', 'jolene_growth_rapport_hebdo')
  LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
  -- Créés DÉSACTIVÉS partout (le staging reste fermé, et en production
  -- l'activation est un geste explicite de la fondatrice depuis l'admin :
  -- fn_admin_growth_planification(true)).
  -- 06:50 heure de Paris en hiver : brouillons prêts pour la session de 9 h.
  PERFORM cron.alter_job(
    job_id := cron.schedule('jolene_growth_agents_quotidien', '50 5 * * *',
      $job$SELECT private.fn_growth_agents_executer('CRON')$job$),
    active := false);
  -- Lundi 06:15 heure de Paris en hiver : rapport de la semaine écoulée.
  PERFORM cron.alter_job(
    job_id := cron.schedule('jolene_growth_rapport_hebdo', '15 5 * * 1',
      $job$SELECT private.fn_growth_snapshot_hebdo()$job$),
    active := false);
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RAISE NOTICE 'pg_cron indisponible : planification différée';
END;
$cron$;
