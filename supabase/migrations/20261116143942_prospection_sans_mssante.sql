-- Prospection sans adresses MSSanté (16/11/2026).
--
-- Constat prod : les 60 brouillons de prospection préparés depuis le 13/11
-- visent tous une adresse *.mssante.fr. MSSanté est un espace de confiance
-- fermé : une boîte MSSanté n'échange qu'avec les messageries MSSanté de la
-- liste blanche de l'ANS. Un email envoyé depuis le Gmail de la fondatrice
-- y est rejeté (https://esante.gouv.fr/doctrine/mssante). La table
-- prospects_etablissements contient 21 304 adresses MSSanté et 9 329 adresses
-- classiques (source FINESS_DATA_GOUV) : l'agent doit viser les classiques.
--
-- 0. Préflight fail-closed (CLAUDE.md, garde-fous 9.0 n°2 : toute
--    redéfinition part de la définition LIVE). Les deux fonctions redéfinies
--    doivent être, en base, exactement celles de
--    20261109140000_agents_croissance_brouillons.sql : md5(prosrc), SECURITY
--    INVOKER, volatilité et search_path. Sinon la migration entière est
--    refusée avant toute écriture. Empreintes = md5 du texte compris entre
--    les deux délimiteurs $body$ de 20261109140000 (ce que PostgreSQL stocke
--    dans pg_proc.prosrc), recalculées par tests/node/prospection-sans-mssante.node.mjs.
-- 1. Une seule règle MSSanté : private.fn_growth_email_mssante(text), IMMUTABLE
--    (domaine mssante.fr et ses sous-domaines, casse et espaces de bord
--    ignorés ; NULL = false).
-- 2. private.fn_growth_destinataire_bloque (prédicat UNIQUE des agents et de
--    la décision admin) : corps repris à l'identique, plus le motif 'MSSANTE'
--    après les motifs existants (compte supprimé, emails désactivés, STOP
--    gardent la priorité). La validation et le constat d'envoi refusent donc
--    aussi une adresse MSSanté, pour tous les agents.
-- 3. private.fn_growth_agent_prospection : corps repris à l'identique, plus
--    l'exclusion MSSanté des premiers contacts et des relances CRM, et un
--    quota du jour qui ne compte plus les brouillons expirés par la présente
--    correction (repérés par leur motif_rejet).
-- 4. private.fn_growth_expirer_brouillons_mssante() : expire les brouillons
--    MSSanté de l'agent encore en file (BROUILLON ou VALIDE), sans DELETE, avec
--    la libération de clé de l'orchestrateur (seul un brouillon jamais validé
--    libère sa cible). Appelée ci-dessous et par
--    tests/security/agents-croissance-brouillons.test.sql (une seule source).
-- Toutes les fonctions restent SECURITY INVOKER (rien à inventorier dans
-- private.security_definer_inventory) ; propriétaire et ACL d'origine
-- conservés par CREATE OR REPLACE, REVOKE d'origine rejoués.

DO $prospection_sans_mssante_avant$
DECLARE
  p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('private.fn_growth_agent_prospection()');
  IF NOT FOUND
    OR pg_catalog.md5(p.prosrc) <> 'f7fe0ee536b4e2bcf737c10194744b06'
    OR p.prosecdef IS DISTINCT FROM false
    OR p.provolatile <> 'v'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
  THEN
    RAISE EXCEPTION 'PROSPECTION_SANS_MSSANTE_SOURCE_AVANT_DIVERGENTE : private.fn_growth_agent_prospection() en base (md5 %, prosecdef %, search_path %) ne correspond plus au corps de 20261109140000 (md5 f7fe0ee536b4e2bcf737c10194744b06, SECURITY INVOKER, search_path vide). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
      COALESCE(pg_catalog.md5(p.prosrc), 'fonction absente'), p.prosecdef, p.proconfig;
  END IF;

  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('private.fn_growth_destinataire_bloque(text,text,text,text,text)');
  IF NOT FOUND
    OR pg_catalog.md5(p.prosrc) <> '0e27c9a65a314a4b70af2c0df4923031'
    OR p.prosecdef IS DISTINCT FROM false
    OR p.provolatile <> 's'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
  THEN
    RAISE EXCEPTION 'PROSPECTION_SANS_MSSANTE_SOURCE_AVANT_DIVERGENTE : private.fn_growth_destinataire_bloque(text,text,text,text,text) en base (md5 %, prosecdef %, search_path %) ne correspond plus au corps de 20261109140000 (md5 0e27c9a65a314a4b70af2c0df4923031, SECURITY INVOKER, STABLE, search_path vide). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
      COALESCE(pg_catalog.md5(p.prosrc), 'fonction absente'), p.prosecdef, p.proconfig;
  END IF;

  -- Les trois fonctions créées ici sont neuves : un homonyme en base serait
  -- une dérive non capturée que CREATE OR REPLACE écraserait sans trace.
  IF pg_catalog.to_regprocedure('private.fn_growth_email_mssante(text)') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_motif_expiration_mssante()') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_expirer_brouillons_mssante()') IS NOT NULL
  THEN
    RAISE EXCEPTION 'PROSPECTION_SANS_MSSANTE_HELPER_DEJA_PRESENT : une fonction private.fn_growth_*_mssante existe déjà en base sans migration du dépôt. Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).';
  END IF;
END;
$prospection_sans_mssante_avant$;

-- ---------------------------------------------------------------------------
-- 1. Règle MSSanté unique et motif d'expiration
-- ---------------------------------------------------------------------------
-- true si l'adresse relève de MSSanté (domaine mssante.fr ou un sous-domaine).
-- Faux amis non exclus : pasmssante.fr, mssante.fr.exemple.com, mssante-fr.fr.
CREATE OR REPLACE FUNCTION private.fn_growth_email_mssante(p_email text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT COALESCE(lower(btrim(p_email, E' \t\r\n')) ~ '[@.]mssante\.fr$', false);
$body$;

-- Motif posé par fn_growth_expirer_brouillons_mssante, relu par le quota du
-- jour de l'agent de prospection : une seule source pour les deux.
CREATE OR REPLACE FUNCTION private.fn_growth_motif_expiration_mssante()
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT 'Adresse MSSanté : messagerie fermée aux emails hors MSSanté, un envoi depuis Gmail serait rejeté'::text;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_email_mssante(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_motif_expiration_mssante() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Prédicat UNIQUE de joignabilité : + MSSanté
-- ---------------------------------------------------------------------------
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
    -- MSSanté (20261116143942) : messagerie fermée, un envoi depuis Gmail est rejeté.
    IF private.fn_growth_email_mssante(p_email) THEN
      RETURN 'MSSANTE';
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
    -- MSSanté (20261116143942) : messagerie fermée, un envoi depuis Gmail est rejeté.
    IF private.fn_growth_email_mssante(p_email) THEN
      RETURN 'MSSANTE';
    END IF;
    RETURN NULL;
  END IF;
  -- MSSanté (20261116143942) : messagerie fermée, un envoi depuis Gmail est rejeté.
  IF private.fn_growth_email_mssante(p_email) THEN
    RETURN 'MSSANTE';
  END IF;
  RETURN NULL;
END;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_destinataire_bloque(text, text, text, text, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Agent 1 — prospection établissements : + MSSanté, quota du jour
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
    -- Un brouillon expiré par la correction MSSanté (20261116143942) ne consomme pas le quota du jour.
    AND NOT (b.statut = 'EXPIRE' AND b.motif_rejet IS NOT DISTINCT FROM private.fn_growth_motif_expiration_mssante())
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
        -- MSSanté : espace de confiance fermé, un envoi depuis Gmail est rejeté.
        AND NOT private.fn_growth_email_mssante(p.email)
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
      -- MSSanté : une relance y serait rejetée comme le premier email.
      AND NOT private.fn_growth_email_mssante(sc.email)
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

REVOKE ALL ON FUNCTION private.fn_growth_agent_prospection() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Brouillons MSSanté déjà en file : expirés, jamais supprimés
-- ---------------------------------------------------------------------------
-- BROUILLON et VALIDE : un brouillon validé affiche encore « Rouvrir Gmail » et
-- « J'ai envoyé ». Libération de clé identique à l'expiration de
-- l'orchestrateur (fn_growth_agents_executer, 20261109140000) : un brouillon
-- jamais validé libère sa cible ; un brouillon validé a pu partir sans
-- constat, sa clé et sa cible restent donc bloquées. motif_rejet n'est
-- contraint par aucun CHECK et reste lisible dans l'historique de l'onglet
-- Agents (« Motif : … »). Une seule source : cette fonction est aussi celle
-- qu'exécute tests/security/agents-croissance-brouillons.test.sql.
CREATE OR REPLACE FUNCTION private.fn_growth_expirer_brouillons_mssante()
RETURNS integer
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_n integer;
BEGIN
  UPDATE public.growth_brouillons b
     SET statut = 'EXPIRE',
         maj_le = now(),
         motif_rejet = private.fn_growth_motif_expiration_mssante(),
         idempotence_key = CASE WHEN b.valide_le IS NULL
                                THEN b.idempotence_key || ':expire:' || b.id
                                ELSE b.idempotence_key END
   WHERE b.agent = 'PROSPECTION_ETABLISSEMENT'
     AND b.statut IN ('BROUILLON', 'VALIDE')
     AND private.fn_growth_email_mssante(b.destinataire_email);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_expirer_brouillons_mssante() FROM PUBLIC, anon, authenticated;

DO $prospection_sans_mssante_expiration$
DECLARE
  v_n integer;
BEGIN
  v_n := private.fn_growth_expirer_brouillons_mssante();
  RAISE NOTICE 'Brouillons MSSanté de l''agent de prospection expirés : %', v_n;
END;
$prospection_sans_mssante_expiration$;
