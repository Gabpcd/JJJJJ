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
-- 1. private.fn_growth_agent_prospection : corps repris à l'identique de
--    20261109140000_agents_croissance_brouillons.sql (seule définition du
--    dépôt ; dernière version du registre distant au 16/11 : 20261109140000).
--    Deux conditions ajoutées : l'exclusion des domaines mssante.fr et de leurs
--    sous-domaines, sur les premiers contacts (prospects_etablissements) et
--    sur les relances CRM (sales_contacts). La fonction reste SECURITY
--    INVOKER (appelée par l'orchestrateur et par la RPC admin SECURITY
--    DEFINER fn_admin_growth_executer_agents) : rien à inventorier.
-- 2. Les brouillons encore au statut BROUILLON de cet agent dont le
--    destinataire est une adresse MSSanté passent en EXPIRE, comme le ferait
--    l'expiration de l'orchestrateur : un brouillon jamais validé libère sa
--    clé. Aucun DELETE. Les brouillons VALIDE, ENVOYE, REJETE ou EXPIRE ne
--    sont pas touchés (un brouillon validé a pu partir sans constat).

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
        -- MSSanté : espace de confiance fermé, un envoi depuis Gmail est rejeté.
        AND btrim(p.email) !~* '@([a-z0-9-]+\.)*mssante\.fr$'
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
      AND btrim(sc.email) !~* '@([a-z0-9-]+\.)*mssante\.fr$'
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
-- Brouillons MSSanté déjà en file : expirés, jamais supprimés.
-- motif_rejet n'est contraint par aucun CHECK : il reste lisible dans
-- l'historique de l'onglet Agents (« Motif : … »).
-- ---------------------------------------------------------------------------
UPDATE public.growth_brouillons b
   SET statut = 'EXPIRE',
       maj_le = now(),
       motif_rejet = 'Adresse MSSanté : messagerie fermée aux emails hors MSSanté, un envoi depuis Gmail serait rejeté',
       idempotence_key = CASE WHEN b.valide_le IS NULL
                              THEN b.idempotence_key || ':expire:' || b.id
                              ELSE b.idempotence_key END
 WHERE b.agent = 'PROSPECTION_ETABLISSEMENT'
   AND b.statut = 'BROUILLON'
   AND b.destinataire_email IS NOT NULL
   AND btrim(b.destinataire_email) ~* '@([a-z0-9-]+\.)*mssante\.fr$';
