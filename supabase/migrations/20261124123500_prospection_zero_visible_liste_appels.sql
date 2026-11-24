-- Prospection : zéro visible et liste d'appels hebdomadaire (24/11/2026).
--
-- Constat prod du 20/11 (lecture seule) : depuis l'exclusion des messageries de
-- santé fermées (20261116143942, 20261117060000), l'agent de prospection par
-- email ne prépare plus aucun brouillon, sans erreur. Sur les 2 318
-- établissements ciblés des départements pilotes (75, 92, 56), 656 ont une
-- adresse, toutes MSSanté ou Apicrypt ; 2 017 ont un téléphone. Le résultat de
-- l'agent et le rapport hebdomadaire affichaient simplement zéro.
--
-- Deux réponses, sans aucun envoi ni appel automatique :
--   A. Zéro visible. Un seul univers ciblé, private.fn_growth_prospects_cibles(),
--      lu par l'agent email, par l'agent d'appels et par le décompte
--      private.fn_growth_cibles_prospection(). Ce décompte figure dans le
--      résultat de l'agent (donc dans growth_agent_executions.details) et dans
--      l'entonnoir figé chaque semaine. L'écran d'administration avertit quand
--      aucune adresse n'est utilisable. Pas d'exception : elle annulerait aussi
--      les relances du même passage.
--   B. Liste d'appels. Un nouvel agent, private.fn_growth_agent_appels(), écrit
--      chaque semaine des fiches d'appel dans growth_brouillons (canal
--      TELEPHONE) : établissements ciblés qui ont un téléphone, jamais
--      contactés, classés par le score existant sans sa part email (type,
--      signal BOAMP de moins de 90 jours, tension BMO exacte). Mêmes interdits
--      que l'email par le prédicat unique fn_growth_destinataire_bloque, moins
--      le motif MSSANTE qui ne concerne que l'email
--      (private.fn_growth_appel_bloque) ; un même numéro n'est proposé qu'une
--      fois. La fondatrice appelle elle-même, puis note le résultat : le
--      décideur admin crée la fiche CRM silencieuse
--      (fn_admin_sourcing_ajouter_crm) et traite le résultat par la logique CRM
--      existante (fn_admin_crm_effectuer_action : rappels dans « Actions du
--      jour », STOP et « pas intéressé » définitifs, tous canaux).
--
-- Volume : 30 fiches par semaine et 60 en file au plus, défauts portés par le
-- code (clés facultatives agents_appels_quota_semaine et agents_appels_file_max).
-- Aucune écriture dans growth_config.
--
-- Décisions prises après la revue fraîche B8 de #1178 :
--   * la sélection des deux agents n'est plus bornée avant leurs contrôles cible
--     par cible (ancien LIMIT places × 3) : des cibles écartées en tête de
--     classement (STOP, adresse ou numéro déjà pris) ne tarissent plus la liste.
--     Chaque agent dit dans son résultat combien de places il n'a pas pourvues ;
--   * « cible disponible » exclut aussi un établissement déjà au CRM (par son
--     FINESS) ou déjà inscrit sur la plateforme ;
--   * une cible n'a qu'un canal, et un brouillon rejeté, ou validé puis expiré,
--     ferme la cible aux DEUX canaux (prudence : la fondatrice a écarté cet
--     établissement, ou a pu le contacter sans le noter) ;
--   * un numéro est comparé sous sa forme nationale (0X…, +33 X… et 0033 X…
--     désignent le même numéro), pour le dédoublonnage comme pour le STOP ;
--   * la fiche est revérifiée à chaque demande d'appel (VALIDER est rejouable) ;
--     au constat, un refus entendu au téléphone est toujours enregistré, même
--     si une opposition est arrivée entre-temps.
--
-- Script d'appel (private.fn_growth_script_appel) : uniquement des affirmations
-- déjà publiées sur le site. La phrase sur la commission est celle de la FAQ
-- de l'accueil (src/lib/seo-contenu/accueil.ts, « Comment fonctionne la
-- commission ? »), mot pour mot ; la phrase « ni abonnement ni frais d'entrée »
-- est celle du guide (src/lib/seo-contenu/guides.ts). Aucun chiffre sans
-- source, aucune comparaison avec un autre type de prestataire, aucune règle
-- de droit. tests/node/prospection-liste-appels.node.mjs compare ces phrases à
-- leur source.
--
-- 0. Préflight fail-closed (CLAUDE.md, garde-fous 9.0 n°2 : toute redéfinition
--    part de la définition LIVE). Les quatre fonctions redéfinies et le prédicat
--    unique sur lequel repose l'agent d'appels doivent être, en base, exactement
--    ceux du dépôt (md5(prosrc) relus en prod le 24/11/2026, attributs, et ACL
--    du décideur). Les six fonctions neuves ne doivent pas exister. Les deux
--    contraintes CHECK élargies doivent porter exactement les valeurs connues.
-- 1. Contraintes : agent APPEL_ETABLISSEMENT, canal TELEPHONE, et une fiche
--    d'appel exige un prospect établissement et un numéro français complet
--    (dix chiffres, ou sa forme +33 / 0033).
-- 2 à 7. Fonctions. Toutes SECURITY INVOKER dans le schéma private, sauf le
--    décideur public.fn_admin_growth_brouillon_decider (SECURITY DEFINER, garde
--    auth.uid() + est_admin() inchangée), dont l'empreinte est mise à jour dans
--    private.security_definer_inventory. CREATE OR REPLACE conserve
--    propriétaire et ACL ; les REVOKE et GRANT d'origine sont rejoués.
-- 8. Post-conditions : attributs, droits, règle téléphone et contraintes.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Préflight : corps LIVE attendus, helpers absents, contraintes connues
-- ---------------------------------------------------------------------------
DO $prospection_liste_appels_avant$
DECLARE
  p record;
  v_valeurs text[];
BEGIN
  FOR p IN
    SELECT v.signature, v.empreinte, v.secdef, v.volatilite,
           f.prosrc, f.prosecdef, f.provolatile, f.proconfig, f.oid
    FROM (VALUES
      ('private.fn_growth_agent_prospection()', '2ccf9311871dfc416d609f0112da9a5b', false, 'v'),
      ('private.fn_growth_entonnoir(timestamp with time zone,timestamp with time zone)', '1bbdcc1d21b6d5a1e5f4b3dc95e846af', false, 's'),
      ('private.fn_growth_agents_executer(text)', 'e33a12bd3ba065d985703bfa44b6c1d8', false, 'v'),
      ('public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', '4e31aeaa8f63beb16036fddb78c86fbd', true, 'v'),
      ('private.fn_growth_destinataire_bloque(text,text,text,text,text)', 'dd7d2f13403693c74fde8ece09452928', false, 's')
    ) AS v(signature, empreinte, secdef, volatilite)
    LEFT JOIN pg_catalog.pg_proc f ON f.oid = pg_catalog.to_regprocedure(v.signature)
  LOOP
    IF p.prosrc IS NULL
      OR pg_catalog.md5(p.prosrc) <> p.empreinte
      OR p.prosecdef IS DISTINCT FROM p.secdef
      OR p.provolatile::text <> p.volatilite
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
    THEN
      RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_SOURCE_AVANT_DIVERGENTE : % en base (md5 %, prosecdef %, volatilité %, search_path %) ne correspond plus au corps du dépôt (md5 %, prosecdef %, volatilité %, search_path vide). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        p.signature, COALESCE(pg_catalog.md5(p.prosrc), 'fonction absente'), p.prosecdef, p.provolatile, p.proconfig,
        p.empreinte, p.secdef, p.volatilite;
    END IF;
  END LOOP;

  -- Décideur : EXECUTE pour authenticated et service_role, jamais pour anon ni PUBLIC.
  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('service_role', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'EXECUTE')
    OR pg_catalog.has_function_privilege('anon', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'EXECUTE')
  THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_ACL_DIVERGENTE : public.fn_admin_growth_brouillon_decider (EXECUTE attendu pour authenticated et service_role, refusé à anon). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).';
  END IF;

  -- Fonctions CRM réutilisées par le constat d'appel : présentes, sinon rien n'est modifié.
  IF pg_catalog.to_regprocedure('public.fn_admin_sourcing_ajouter_crm(text,text,smallint)') IS NULL
    OR pg_catalog.to_regprocedure('public.fn_admin_crm_effectuer_action(uuid,text,text,timestamp with time zone)') IS NULL
    OR pg_catalog.to_regprocedure('public.fn_sales_outreach_est_interdit(uuid,text,text,text,text)') IS NULL
  THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_CRM_ABSENT : fn_admin_sourcing_ajouter_crm, fn_admin_crm_effectuer_action ou fn_sales_outreach_est_interdit absente : le constat d''appel ne pourrait pas alimenter le CRM.';
  END IF;

  -- Les six fonctions créées ici sont neuves : un homonyme en base serait une
  -- dérive non capturée que CREATE OR REPLACE écraserait sans trace.
  IF pg_catalog.to_regprocedure('private.fn_growth_telephone_national(text)') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_prospects_cibles()') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_cibles_prospection()') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_appel_bloque(text,text,text)') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_script_appel(text)') IS NOT NULL
    OR pg_catalog.to_regprocedure('private.fn_growth_agent_appels()') IS NOT NULL
  THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_HELPER_DEJA_PRESENT : une fonction private.fn_growth_* de ce lot existe déjà en base sans migration du dépôt. Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).';
  END IF;

  -- Contraintes élargies : valeurs LIVE = valeurs de 20261109140000.
  SELECT pg_catalog.array_agg(m.v ORDER BY m.v) INTO v_valeurs
  FROM pg_catalog.pg_constraint c
  CROSS JOIN LATERAL (SELECT x[1] AS v FROM pg_catalog.regexp_matches(pg_catalog.pg_get_constraintdef(c.oid), '''([A-Z_]+)''', 'g') AS x) m
  WHERE c.conrelid = 'public.growth_brouillons'::pg_catalog.regclass AND c.conname = 'growth_brouillons_agent_check';
  IF v_valeurs IS DISTINCT FROM ARRAY['MISSION_A_POURVOIR', 'POST_SOCIAL', 'PROSPECTION_ETABLISSEMENT', 'REACTIVATION']::text[] THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_CONTRAINTE_DIVERGENTE : growth_brouillons_agent_check porte % au lieu des quatre agents de 20261109140000.', v_valeurs;
  END IF;
  SELECT pg_catalog.array_agg(m.v ORDER BY m.v) INTO v_valeurs
  FROM pg_catalog.pg_constraint c
  CROSS JOIN LATERAL (SELECT x[1] AS v FROM pg_catalog.regexp_matches(pg_catalog.pg_get_constraintdef(c.oid), '''([A-Z_]+)''', 'g') AS x) m
  WHERE c.conrelid = 'public.growth_brouillons'::pg_catalog.regclass AND c.conname = 'growth_brouillons_canal_check';
  IF v_valeurs IS DISTINCT FROM ARRAY['EMAIL', 'FACEBOOK_GROUPE', 'LINKEDIN']::text[] THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_CONTRAINTE_DIVERGENTE : growth_brouillons_canal_check porte % au lieu des trois canaux de 20261109140000.', v_valeurs;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
             WHERE c.conrelid = 'public.growth_brouillons'::pg_catalog.regclass
               AND c.conname = 'growth_brouillons_telephone_destinataire') THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_CONTRAINTE_DIVERGENTE : growth_brouillons_telephone_destinataire existe déjà sans migration du dépôt.';
  END IF;
END;
$prospection_liste_appels_avant$;

-- ---------------------------------------------------------------------------
-- 1. Contraintes : agent d'appels, canal téléphone, numéro exigé
-- ---------------------------------------------------------------------------
-- Élargissement seulement : les lignes existantes satisfont les nouvelles
-- contraintes (aucun brouillon TELEPHONE n'a pu exister).
ALTER TABLE public.growth_brouillons
  DROP CONSTRAINT growth_brouillons_agent_check,
  ADD CONSTRAINT growth_brouillons_agent_check CHECK (agent IN (
    'PROSPECTION_ETABLISSEMENT', 'APPEL_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'
  )),
  DROP CONSTRAINT growth_brouillons_canal_check,
  ADD CONSTRAINT growth_brouillons_canal_check CHECK (canal IN ('EMAIL', 'TELEPHONE', 'LINKEDIN', 'FACEBOOK_GROUPE')),
  ADD CONSTRAINT growth_brouillons_telephone_destinataire CHECK (
    canal <> 'TELEPHONE'
    OR (cible_type = 'PROSPECT_ETABLISSEMENT'
        AND cible_id IS NOT NULL
        AND regexp_replace(COALESCE(contexte->>'telephone', ''), '\D', '', 'g') ~ '^(0|33|0033)[1-9][0-9]{8}$')
  );

-- ---------------------------------------------------------------------------
-- 2. Univers ciblé UNIQUE, décompte, règle téléphone, script
-- ---------------------------------------------------------------------------
-- Forme nationale d'un numéro français (dix chiffres commençant par 0), ou
-- NULL si le champ n'en contient pas exactement un : 01 23 45 67 89,
-- +33 1 23 45 67 89 et 0033 1 23 45 67 89 désignent le même numéro. Sert au
-- ciblage, au dédoublonnage et à la comparaison d'un STOP.
CREATE OR REPLACE FUNCTION private.fn_growth_telephone_national(p_telephone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT CASE
    WHEN n.chiffres ~ '^0[1-9][0-9]{8}$' THEN n.chiffres
    WHEN n.chiffres ~ '^33[1-9][0-9]{8}$' THEN '0' || substr(n.chiffres, 3)
    WHEN n.chiffres ~ '^0033[1-9][0-9]{8}$' THEN '0' || substr(n.chiffres, 5)
  END
  FROM (SELECT regexp_replace(COALESCE(p_telephone, ''), '\D', '', 'g') AS chiffres) n;
$body$;

-- Établissements des départements et types ciblés (growth_config), avec ce que
-- chaque canal a besoin de savoir. Source UNIQUE de l'agent email, de l'agent
-- d'appels et du décompte : ne jamais re-décider localement.
--   email_ferme       : adresse bien formée mais en messagerie de santé fermée ;
--   email_utilisable  : adresse bien formée et ouverte à un envoi depuis Gmail ;
--   telephone_utilisable : un numéro français complet (forme nationale) ;
--   disponible        : jamais contacté, absent du CRM (date d'ajout ou contact
--                       au même FINESS), pas encore inscrit sur la plateforme,
--                       ni ignoré ni en opposition, sans brouillon vivant sur
--                       cette cible, quel qu'en soit le canal (seul un brouillon
--                       jamais validé puis expiré libère la cible : un brouillon
--                       validé a pu partir sans constat, un brouillon rejeté
--                       dit que la fondatrice a écarté cet établissement).
-- Score : type d'établissement, signal BOAMP de moins de 90 jours, tension BMO
-- exacte des aides-soignants (les mêmes expressions que 20261109140000).
CREATE OR REPLACE FUNCTION private.fn_growth_prospects_cibles()
RETURNS TABLE (
  finess text, nom text, type_jolene text, email text, telephone text,
  ville text, departement text,
  email_ferme boolean, email_utilisable boolean, telephone_utilisable boolean, disponible boolean,
  pts_type integer, pts_signal integer, pts_tension integer, bmo jsonb
)
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT p.finess, p.nom, p.type_jolene, p.email, p.telephone, p.ville, p.departement,
         (NULLIF(btrim(p.email), '') IS NOT NULL
          AND btrim(p.email) ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
          AND private.fn_growth_email_mssante(p.email)) AS email_ferme,
         (NULLIF(btrim(p.email), '') IS NOT NULL
          AND btrim(p.email) ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$'
          -- MSSanté, Apicrypt : espace de confiance fermé, un envoi depuis Gmail est rejeté.
          AND NOT private.fn_growth_email_mssante(p.email)) AS email_utilisable,
         (private.fn_growth_telephone_national(p.telephone) IS NOT NULL) AS telephone_utilisable,
         (p.email_envoye_le IS NULL
          AND p.ajoute_crm_le IS NULL
          AND p.statut_sourcing NOT IN ('IGNORE', 'OPPOSITION')
          -- Déjà suivi au CRM (contact créé hors sourcing) ou déjà inscrit : pas de premier contact.
          AND NOT EXISTS (SELECT 1 FROM public.sales_contacts sc WHERE sc.finess = p.finess)
          AND NOT EXISTS (SELECT 1 FROM public.etablissements e
                          WHERE e.finess = p.finess AND e.supprime_le IS NULL)
          AND NOT EXISTS (
            SELECT 1 FROM public.growth_brouillons b
            WHERE b.cible_type = 'PROSPECT_ETABLISSEMENT' AND b.cible_id = p.finess
              -- Seul un brouillon jamais validé puis expiré libère la cible : un
              -- brouillon validé a pu être envoyé sans « J'ai envoyé ».
              AND NOT (b.statut = 'EXPIRE' AND b.valide_le IS NULL)
          )) AS disponible,
         CASE p.type_jolene
           WHEN 'EHPAD' THEN 40 WHEN 'HOPITAL' THEN 35 WHEN 'HANDICAP' THEN 30
           WHEN 'DOMICILE' THEN 25 WHEN 'CENTRE_SANTE' THEN 20 WHEN 'DIALYSE' THEN 20
           ELSE 15 END AS pts_type,
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
  WHERE p.departement = ANY (private.fn_growth_config_liste('agents_departements_cibles', '75,92,56'))
    AND p.type_jolene = ANY (private.fn_growth_config_liste(
          'agents_types_cibles', 'EHPAD,HANDICAP,DOMICILE,CENTRE_SANTE,HOPITAL,DIALYSE,ECOLE_SANTE'));
$body$;

-- Décompte de l'univers ciblé, pour que « zéro brouillon » ne soit plus muet.
-- « restantes » et « restants » : avant le contrôle STOP et le dédoublonnage
-- d'adresse ou de numéro, que les agents appliquent cible par cible.
CREATE OR REPLACE FUNCTION private.fn_growth_cibles_prospection()
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT jsonb_build_object(
    'departements', to_jsonb(private.fn_growth_config_liste('agents_departements_cibles', '75,92,56')),
    'etablissements_cibles', count(*),
    'adresses_fermees', count(*) FILTER (WHERE c.email_ferme),
    'adresses_utilisables', count(*) FILTER (WHERE c.email_utilisable),
    'adresses_restantes', count(*) FILTER (WHERE c.email_utilisable AND c.disponible),
    'telephones_utilisables', count(*) FILTER (WHERE c.telephone_utilisable),
    'telephones_restants', count(*) FILTER (WHERE c.telephone_utilisable AND c.disponible))
  FROM private.fn_growth_prospects_cibles() c;
$body$;

-- Canal téléphone : les interdits du prédicat UNIQUE (STOP, opposition, contact
-- perdu, comparés par FINESS, adresse et numéro), sans le motif MSSANTE qui ne
-- dit rien d'un appel. NULL = appel possible ; sinon le motif.
-- fn_sales_outreach_est_interdit compare les chiffres tels qu'ils sont saisis :
-- le numéro est donc présenté sous ses trois écritures (nationale, 33…, 0033…),
-- pour qu'un STOP noté « +33 1 … » au CRM bloque aussi le « 01 … » de l'annuaire.
CREATE OR REPLACE FUNCTION private.fn_growth_appel_bloque(p_finess text, p_email text, p_telephone text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO ''
AS $body$
  SELECT CASE
    WHEN 'STOP' IN (COALESCE(v.national, ''), COALESCE(v.international, ''), COALESCE(v.international_00, '')) THEN 'STOP'
    ELSE NULLIF(v.national, 'MSSANTE')
  END
  FROM (
    SELECT private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, p_email, COALESCE(n.numero, p_telephone), NULL) AS national,
           private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, NULL, '33' || substr(n.numero, 2), NULL) AS international,
           private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', p_finess, NULL, '0033' || substr(n.numero, 2), NULL) AS international_00
    FROM (SELECT private.fn_growth_telephone_national(p_telephone) AS numero) n
  ) v;
$body$;

-- Script d'appel, lu par la fondatrice et modifiable sur la fiche. Source des
-- phrases : en-tête de cette migration (garde tests/node/prospection-liste-appels.node.mjs).
CREATE OR REPLACE FUNCTION private.fn_growth_script_appel(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT CASE WHEN p_type = 'ECOLE_SANTE' THEN concat_ws(E'\n\n',
    'Bonjour, Gabrielle, fondatrice de Jolene. Pourrais-je parler à la personne qui accompagne l''insertion professionnelle de vos étudiants et de vos jeunes diplômés ?',
    'Jolene met en relation des soignants et des établissements de santé pour des missions et remplacements ponctuels. L''inscription est gratuite pour les soignants.',
    'Nous démarrons dans votre secteur et aimerions faire connaître Jolene à vos jeunes diplômés. Seriez-vous ouvert à un échange de quinze minutes pour voir comment la présenter à vos promotions (affiche, courte intervention ou information aux diplômés) ?',
    'Si vous préférez ne pas être rappelé, dites-le-moi : je le note et Jolene ne vous rappellera plus.')
  ELSE concat_ws(E'\n\n',
    'Bonjour, Gabrielle, fondatrice de Jolene. Pourrais-je parler à la personne qui organise les remplacements de soignants ?',
    'Jolene est une plateforme de mise en relation directe entre les établissements de santé et des soignants vérifiés, pour des missions et remplacements ponctuels.',
    'Vous publiez votre besoin, des soignants vérifiés candidatent, et le contrat est signé en ligne.',
    'Jolene facture à l''établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée, majorations et indemnités incluses lorsqu’elles entrent dans cette base. Il n’y a ni abonnement ni frais d’entrée : vous ne payez que lorsque vous recrutez.',
    'Nous démarrons dans votre secteur : je vous propose de publier votre première mission avec vous, au téléphone. Auriez-vous quinze minutes cette semaine ?',
    'Si vous préférez ne pas être rappelé, dites-le-moi : je le note et Jolene ne vous rappellera plus.')
  END;
$body$;

-- ---------------------------------------------------------------------------
-- 3. Agent 1 — prospection email : univers unique, décompte dans le résultat
-- ---------------------------------------------------------------------------
-- Corps LIVE (20261116143942) repris à l'identique, à quatre endroits près :
-- la sélection des premiers contacts lit private.fn_growth_prospects_cibles()
-- (mêmes filtres et mêmes points, écrits une seule fois, plus l'exclusion des
-- établissements déjà au CRM ou déjà inscrits), la variable v_types devenue sans
-- objet disparaît, la sélection n'est plus bornée à trois fois les places (une
-- tête de classement écartée cible par cible tarissait la file), et le résultat
-- porte le décompte « cibles » et les places non pourvues.
CREATE OR REPLACE FUNCTION private.fn_growth_agent_prospection()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_depts text[] := private.fn_growth_config_liste('agents_departements_cibles', '75,92,56');
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
             p.pts_type,
             CASE
               WHEN split_part(lower(p.email), '@', 1)
                    ~ '^(contact|accueil|direction|directeur|directrice|secretariat|info|rh|recrutement|admin|standard)'
                 THEN 10
               WHEN split_part(lower(p.email), '@', 2)
                    ~ '^(gmail|hotmail|yahoo|outlook|orange|wanadoo|free|sfr|laposte|live)\.'
                 THEN 0
               ELSE 5 END AS pts_email,
             CASE WHEN NULLIF(btrim(p.telephone), '') IS NOT NULL THEN 10 ELSE 0 END AS pts_tel,
             p.pts_signal, p.pts_tension, p.bmo
      -- Univers ciblé unique (départements, types, adresse ouverte, cible libre).
      FROM private.fn_growth_prospects_cibles() p
      WHERE p.email_utilisable AND p.disponible
    ) s
    ) q
    ORDER BY q.rang_departement, q.score_total DESC, q.nom, q.finess
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
    -- Places restées vides alors que toutes les cibles disponibles ont été examinées.
    'places_non_pourvues', greatest(0, v_place - v_crees),
    'exclus_stop', v_exclus_stop,
    'departements', to_jsonb(v_depts),
    -- Décompte après ce passage : un zéro n'est plus muet (écran d'administration).
    'cibles', private.fn_growth_cibles_prospection());
END;
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_agent_prospection() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Agent 5 — liste d'appels hebdomadaire (fiches, jamais d'appel automatique)
-- ---------------------------------------------------------------------------
-- Quota à la semaine (lundi, heure de Paris) : le passage quotidien complète
-- la liste de la semaine sans la dépasser. Les départements alternent comme
-- pour l'email. Une fiche non traitée expire au bout de 14 jours ; jamais
-- validée, elle libère sa cible.
CREATE OR REPLACE FUNCTION private.fn_growth_agent_appels()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_quota integer := private.fn_growth_config_int('agents_appels_quota_semaine', 30, 0, 200);
  v_file_max integer := private.fn_growth_config_int('agents_appels_file_max', 60, 0, 500);
  v_semaine timestamptz := date_trunc('week', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris';
  v_deja integer;
  v_file integer;
  v_place integer;
  v_crees integer := 0;
  v_exclus_stop integer := 0;
  v_numeros_deja_en_file integer := 0;
  v_examines integer := 0;
  v_n integer;
  v_numero text;
  r record;
BEGIN
  SELECT count(*) INTO v_deja
  FROM public.growth_brouillons b
  WHERE b.agent = 'APPEL_ETABLISSEMENT' AND b.cree_le >= v_semaine;
  SELECT count(*) INTO v_file
  FROM public.growth_brouillons b
  WHERE b.agent = 'APPEL_ETABLISSEMENT' AND b.statut = 'BROUILLON';
  v_place := greatest(0, least(v_quota - v_deja, v_file_max - v_file));

  FOR r IN
    SELECT q.*
    FROM (
      SELECT c.*,
             c.pts_type + c.pts_signal + c.pts_tension AS score_total,
             row_number() OVER (
               PARTITION BY c.departement
               ORDER BY c.pts_type + c.pts_signal + c.pts_tension DESC, c.nom, c.finess
             ) AS rang_departement
      FROM private.fn_growth_prospects_cibles() c
      WHERE c.telephone_utilisable AND c.disponible
    ) q
    ORDER BY q.rang_departement, q.score_total DESC, q.nom, q.finess
  LOOP
    -- Pas de borne avant les contrôles cible par cible : la boucle s'arrête
    -- quand les places sont pourvues, sinon elle examine toutes les cibles.
    EXIT WHEN v_crees >= v_place;
    v_examines := v_examines + 1;

    IF private.fn_growth_appel_bloque(r.finess, btrim(r.email), r.telephone) IS NOT NULL THEN
      v_exclus_stop := v_exclus_stop + 1;
      CONTINUE;
    END IF;
    -- Un même numéro (standard partagé, siège) n'est proposé qu'une fois, sous
    -- la même règle que la cible : seule une fiche jamais validée puis expirée
    -- le libère.
    v_numero := private.fn_growth_telephone_national(r.telephone);
    IF EXISTS (
      SELECT 1 FROM public.growth_brouillons b
      WHERE b.canal = 'TELEPHONE'
        AND private.fn_growth_telephone_national(b.contexte->>'telephone') = v_numero
        AND NOT (b.statut = 'EXPIRE' AND b.valide_le IS NULL)
    ) THEN
      v_numeros_deja_en_file := v_numeros_deja_en_file + 1;
      CONTINUE;
    END IF;

    INSERT INTO public.growth_brouillons (
      agent, canal, cible_type, cible_id, destinataire_nom, departement,
      corps, contexte, score, idempotence_key, expire_le
    ) VALUES (
      'APPEL_ETABLISSEMENT', 'TELEPHONE', 'PROSPECT_ETABLISSEMENT', r.finess,
      r.nom, r.departement, private.fn_growth_script_appel(r.type_jolene),
      jsonb_build_object(
        'type_etablissement', r.type_jolene,
        'ville', r.ville,
        'telephone', btrim(r.telephone),
        'source', 'Annuaires publics des établissements de santé (répertoire FINESS et Annuaire Santé)',
        'semaine', to_char(now() AT TIME ZONE 'Europe/Paris', 'IYYY-"S"IW'),
        'score', jsonb_build_object(
          'type', r.pts_type, 'signal_boamp_90j', r.pts_signal, 'tension_bmo_as', r.pts_tension)),
      r.score_total, 'appel:' || r.finess, now() + interval '14 days'
    )
    ON CONFLICT (idempotence_key) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_crees := v_crees + v_n;
  END LOOP;

  RETURN jsonb_build_object(
    'brouillons_crees', v_crees,
    'fiches_appel', v_crees,
    'places_de_la_semaine', v_place,
    -- Places restées vides alors que toutes les cibles disponibles ont été examinées.
    'places_non_pourvues', greatest(0, v_place - v_crees),
    'quota_semaine', v_quota,
    'candidats_examines', v_examines,
    'exclus_stop', v_exclus_stop,
    'numeros_deja_en_file', v_numeros_deja_en_file);
END;
$body$;

-- ---------------------------------------------------------------------------
-- 5. Orchestrateur : cinquième agent, après l'email (une cible, un seul canal)
-- ---------------------------------------------------------------------------
-- Corps LIVE (20261109140000) repris à l'identique, plus APPEL_ETABLISSEMENT
-- dans la boucle et dans l'aiguillage.
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

  FOREACH v_agent IN ARRAY ARRAY['PROSPECTION_ETABLISSEMENT', 'APPEL_ETABLISSEMENT', 'POST_SOCIAL', 'MISSION_A_POURVOIR', 'REACTIVATION'] LOOP
    INSERT INTO public.growth_agent_executions (agent, declencheur)
    VALUES (v_agent, v_declencheur) RETURNING id INTO v_exec;
    BEGIN
      v_res := CASE v_agent
        WHEN 'PROSPECTION_ETABLISSEMENT' THEN private.fn_growth_agent_prospection()
        WHEN 'APPEL_ETABLISSEMENT' THEN private.fn_growth_agent_appels()
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
-- ---------------------------------------------------------------------------
-- 6. Entonnoir : décompte des cibles et appels notés, figés chaque semaine
-- ---------------------------------------------------------------------------
-- Corps LIVE (20261109140000) repris à l'identique, plus deux clés dans le bloc
-- « prospection » : cibles_agent (le même décompte que l'agent) et
-- fiches_appel_notees_periode (fiches de la liste d'appels dont le résultat a
-- été noté sur la période ; les rappels suivants se comptent dans le CRM).
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
    'crm_stop', (SELECT count(*) FROM public.sales_contacts sc WHERE sc.ne_plus_contacter IS TRUE),
    'fiches_appel_notees_periode', (SELECT count(*) FROM public.growth_brouillons b
                                    WHERE b.canal = 'TELEPHONE' AND b.statut = 'ENVOYE'
                                      AND b.envoye_le >= p_debut AND b.envoye_le < p_fin),
    -- État des cibles des agents au moment du calcul (pas une mesure de période).
    'cibles_agent', private.fn_growth_cibles_prospection()
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
-- ---------------------------------------------------------------------------
-- 7. Décision admin : la fiche d'appel suit le même parcours que l'email
-- ---------------------------------------------------------------------------
-- Corps LIVE (20261109140000) repris à l'identique, plus le canal TELEPHONE :
--   * VALIDER et MARQUER_ENVOYE revérifient les interdits avant l'appel et au
--     constat, par private.fn_growth_appel_bloque (adresse relue sur le
--     prospect, pour qu'un STOP posé sur l'adresse bloque aussi l'appel).
--     VALIDER est rejouable sur une fiche déjà validée : l'écran le rappelle à
--     chaque demande d'appel. Avant l'appel, il refuse aussi une cible passée
--     au CRM, inscrite ou écartée entre-temps, et suit un numéro modifié dans
--     l'annuaire. Au constat, un refus entendu (STOP, pas intéressé) est
--     enregistré même si une opposition est arrivée entre-temps ; tout autre
--     résultat est alors refusé au CRM mais reste lisible sur la fiche ;
--   * MARQUER_ENVOYE exige le résultat de l'appel dans p_motif (mêmes valeurs
--     que « Actions du jour ») ; il crée la fiche CRM silencieuse, une tâche
--     « premier appel », puis délègue le résultat à fn_admin_crm_effectuer_action
--     (statut, rappel, STOP définitif : une seule logique de résultat) ;
--   * le résultat reste lisible sur la fiche (contexte.resultat_appel).
-- Garde auth.uid() + est_admin(), verrou FOR UPDATE et parcours email inchangés.
-- Aucune action n'appelle ni n'envoie quoi que ce soit.
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
  -- Fiche d'appel : résultat noté par la fondatrice, lu dans p_motif.
  v_resultat text := upper(btrim(COALESCE(p_motif, '')));
  v_tache_id uuid;
  v_consigne text;
  v_prospect record;
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
  -- Un appel ne se note pas sans son résultat (mêmes valeurs que « Actions du jour »).
  IF v_action = 'MARQUER_ENVOYE' AND v_b.canal = 'TELEPHONE'
     AND v_resultat NOT IN ('APPEL_REPONDU', 'SANS_REPONSE', 'INTERESSE', 'A_RAPPELER', 'PAS_INTERESSE', 'STOP') THEN
    RAISE EXCEPTION 'Résultat d''appel requis : APPEL_REPONDU, SANS_REPONSE, INTERESSE, A_RAPPELER, PAS_INTERESSE ou STOP';
  END IF;

  -- Joignabilité revérifiée à chaque validation et au constat d'envoi : une
  -- opposition, un refus d'emails ou une suppression de compte a pu arriver.
  -- Pas de RAISE ici : il annulerait le rejet, qui doit persister.
  IF v_action IN ('VALIDER', 'MARQUER_ENVOYE') AND v_b.canal IN ('EMAIL', 'TELEPHONE') THEN
    IF v_b.canal = 'TELEPHONE' THEN
      -- Fiche d'appel. VALIDER est rejouable : l'écran le rappelle à chaque
      -- demande d'appel, pour que rien ne soit composé sur une fiche périmée.
      v_consigne := CASE WHEN v_action = 'VALIDER' THEN 'ne pas appeler' ELSE 'appel non enregistré au CRM' END;
      SELECT btrim(p.email) AS email, p.telephone, p.statut_sourcing INTO v_prospect
        FROM public.prospects_etablissements p WHERE p.finess = v_b.cible_id;
      IF NOT FOUND OR v_b.cible_type <> 'PROSPECT_ETABLISSEMENT' THEN
        v_motif := 'CIBLE_INVALIDE';
      ELSE
        -- Mêmes interdits que l'email, sans le motif MSSANTE.
        v_motif := private.fn_growth_appel_bloque(v_b.cible_id, v_prospect.email, v_b.contexte->>'telephone');
        IF v_motif IS NULL AND v_action = 'VALIDER' THEN
          -- Avant l'appel, la cible doit encore être à appeler depuis cette fiche.
          IF v_prospect.statut_sourcing = 'IGNORE'
             OR EXISTS (SELECT 1 FROM public.sales_contacts sc WHERE sc.finess = v_b.cible_id)
             OR EXISTS (SELECT 1 FROM public.etablissements e
                        WHERE e.finess = v_b.cible_id AND e.supprime_le IS NULL) THEN
            v_motif := 'DEJA_SUIVI';
          ELSIF private.fn_growth_telephone_national(v_prospect.telephone) IS NULL THEN
            v_motif := 'CIBLE_INVALIDE';
          ELSIF private.fn_growth_telephone_national(v_prospect.telephone)
                IS DISTINCT FROM private.fn_growth_telephone_national(v_b.contexte->>'telephone') THEN
            -- Numéro modifié dans l'annuaire : la fiche le suit, et les
            -- interdits sont relus sur le nouveau numéro.
            UPDATE public.growth_brouillons
               SET contexte = contexte || jsonb_build_object('telephone', btrim(v_prospect.telephone)), maj_le = now()
             WHERE id = p_id;
            v_motif := private.fn_growth_appel_bloque(v_b.cible_id, v_prospect.email, v_prospect.telephone);
          END IF;
        END IF;
      END IF;
    ELSE
      v_consigne := 'aucun envoi possible';
      v_motif := private.fn_growth_destinataire_bloque(
        v_b.cible_type, v_b.cible_id, v_b.destinataire_email,
        v_b.contexte->>'telephone', v_b.contexte->>'finess');
    END IF;
    IF v_motif = 'COMPTE_SUPPRIME' THEN
      DELETE FROM public.growth_brouillons WHERE id = p_id;
      RETURN jsonb_build_object('success', false, 'id', p_id, 'statut', 'SUPPRIME',
        'raison', 'Compte supprimé : brouillon effacé, aucun envoi possible');
    ELSIF v_motif = 'STOP' AND v_b.canal = 'TELEPHONE' AND v_action = 'MARQUER_ENVOYE'
          AND v_resultat IN ('PAS_INTERESSE', 'STOP') THEN
      -- L'appel a eu lieu et l'établissement a refusé : ce refus s'enregistre
      -- toujours (il protège), même si une opposition est arrivée entre-temps.
      v_motif := NULL;
    ELSIF v_motif IS NOT NULL THEN
      UPDATE public.growth_brouillons
         SET statut = 'REJETE', maj_le = now(),
             motif_rejet = CASE v_motif
               WHEN 'STOP' THEN 'Opposition (STOP) ou contact perdu'
               WHEN 'EMAILS_DESACTIVES' THEN 'Emails désactivés par le destinataire'
               WHEN 'DEJA_SUIVI' THEN 'Établissement déjà suivi au CRM, déjà inscrit ou écarté'
               ELSE 'Destinataire invalide' END,
             -- Un appel déjà passé garde son résultat sur la fiche, même refusé au CRM.
             contexte = CASE WHEN v_b.canal = 'TELEPHONE' AND v_action = 'MARQUER_ENVOYE'
                             THEN contexte || jsonb_build_object('resultat_appel', v_resultat)
                             ELSE contexte END
       WHERE id = p_id;
      RETURN jsonb_build_object('success', false, 'id', p_id, 'statut', 'REJETE',
        'raison', CASE v_motif
          WHEN 'STOP' THEN 'Contact en opposition (STOP) ou perdu : ' || v_consigne
          WHEN 'EMAILS_DESACTIVES' THEN 'Le destinataire a désactivé ces emails : ' || v_consigne
          WHEN 'DEJA_SUIVI' THEN 'Établissement déjà suivi au CRM, déjà inscrit ou écarté : ' || v_consigne
          ELSE 'Destinataire invalide : ' || v_consigne END);
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
    ELSIF v_b.canal = 'TELEPHONE' AND v_b.cible_type = 'PROSPECT_ETABLISSEMENT' THEN
      -- Constat d'appel : fiche CRM silencieuse, tâche « premier appel », puis
      -- le résultat est traité par la logique CRM existante (rappel programmé
      -- dans « Actions du jour », STOP et « pas intéressé » définitifs).
      v_crm := public.fn_admin_sourcing_ajouter_crm('ETABLISSEMENT', v_b.cible_id, v_b.score);
      v_contact_id := (v_crm->>'contact_id')::uuid;
      INSERT INTO public.sales_taches (
        contact_id, type, canal, priorite, titre, echeance_le, sequence_etape, origine, idempotence_key
      ) VALUES (
        v_contact_id, 'PREMIER_CONTACT', 'TELEPHONE', 'NORMALE',
        left('Premier appel — ' || COALESCE(v_b.destinataire_nom, v_b.cible_id), 200),
        now(), 0, 'MANUEL', 'growth:appel:' || v_b.id
      )
      RETURNING id INTO v_tache_id;
      PERFORM public.fn_admin_crm_effectuer_action(
        v_tache_id, v_resultat, 'Fiche d''appel agent ' || v_b.id, NULL);
    END IF;
    UPDATE public.growth_brouillons
       SET statut = 'ENVOYE', envoye_par = auth.uid(), envoye_le = now(), maj_le = now(),
           contexte = CASE WHEN v_b.canal = 'TELEPHONE'
                           THEN contexte || jsonb_build_object('resultat_appel', v_resultat)
                           ELSE contexte END
     WHERE id = p_id;
  END IF;

  SELECT * INTO v_b FROM public.growth_brouillons WHERE id = p_id;
  RETURN jsonb_build_object('success', true, 'id', v_b.id, 'statut', v_b.statut,
    'contact_crm_id', v_contact_id,
    -- Numéro de la fiche après revérification : c'est lui que l'écran compose.
    'telephone', v_b.contexte->>'telephone');
END;
$body$;
-- CREATE OR REPLACE conserve propriétaire et ACL ; droits d'origine rejoués.
REVOKE ALL ON FUNCTION public.fn_admin_growth_brouillon_decider(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_growth_brouillon_decider(uuid, text, text, text, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.fn_growth_telephone_national(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_prospects_cibles() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_cibles_prospection() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_appel_bloque(text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_script_appel(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_agent_appels() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_agents_executer(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_growth_entonnoir(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

-- Inventaire SECURITY DEFINER : empreinte du décideur redéfini.
INSERT INTO private.security_definer_inventory (signature, categorie, definition_md5, justification, recense_le)
SELECT 'fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'ADMIN_EST_ADMIN_VALIDE', pg_catalog.md5(p.prosrc),
       'UID non NULL + est_admin() ; verrou FOR UPDATE, garde STOP fn_sales_outreach_est_interdit et préférences email, revérifiée aussi avant un appel et à son constat ; journalisation CRM existante (email : séquence ; appel : fn_admin_crm_effectuer_action) ; n''envoie rien et n''appelle personne. Source : 20261124123500_prospection_zero_visible_liste_appels.sql',
       pg_catalog.now()
FROM pg_catalog.pg_proc p
WHERE p.oid = 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)'::pg_catalog.regprocedure
ON CONFLICT (signature) DO UPDATE
SET categorie = EXCLUDED.categorie,
    definition_md5 = EXCLUDED.definition_md5,
    justification = EXCLUDED.justification,
    recense_le = EXCLUDED.recense_le;

-- ---------------------------------------------------------------------------
-- 8. Post-conditions (sinon toute la migration est annulée)
-- ---------------------------------------------------------------------------
DO $prospection_liste_appels_apres$
DECLARE
  p record;
BEGIN
  -- Attributs : seul le décideur est SECURITY DEFINER ; search_path vide partout.
  FOR p IN
    SELECT v.signature, v.secdef, f.prosecdef, f.proconfig
    FROM (VALUES
      ('private.fn_growth_telephone_national(text)', false),
      ('private.fn_growth_prospects_cibles()', false),
      ('private.fn_growth_cibles_prospection()', false),
      ('private.fn_growth_appel_bloque(text,text,text)', false),
      ('private.fn_growth_script_appel(text)', false),
      ('private.fn_growth_agent_appels()', false),
      ('private.fn_growth_agent_prospection()', false),
      ('private.fn_growth_agents_executer(text)', false),
      ('private.fn_growth_entonnoir(timestamp with time zone,timestamp with time zone)', false),
      ('public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', true)
    ) AS v(signature, secdef)
    LEFT JOIN pg_catalog.pg_proc f ON f.oid = pg_catalog.to_regprocedure(v.signature)
  LOOP
    IF p.prosecdef IS DISTINCT FROM p.secdef
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
      OR pg_catalog.has_function_privilege('anon', p.signature, 'EXECUTE')
      OR (p.secdef IS FALSE AND pg_catalog.has_function_privilege('authenticated', p.signature, 'EXECUTE'))
    THEN
      RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_POSTCONDITION : % (prosecdef %, search_path %) : attributs ou droits inattendus.',
        p.signature, p.prosecdef, p.proconfig;
    END IF;
  END LOOP;
  IF NOT pg_catalog.has_function_privilege('authenticated', 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)', 'EXECUTE')
    OR NOT EXISTS (
      SELECT 1 FROM private.security_definer_inventory i
      JOIN pg_catalog.pg_proc f ON f.oid = 'public.fn_admin_growth_brouillon_decider(uuid,text,text,text,text)'::pg_catalog.regprocedure
      WHERE i.signature = 'fn_admin_growth_brouillon_decider(uuid,text,text,text,text)'
        AND i.definition_md5 = pg_catalog.md5(f.prosrc))
  THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_POSTCONDITION : décideur non exécutable par authenticated ou inventaire SECURITY DEFINER non synchronisé.';
  END IF;

  -- Règle téléphone : une adresse en messagerie fermée ne bloque pas un appel,
  -- et le prédicat unique continue de la refuser pour un email.
  -- Sans numéro : aucun contact réel ne peut faire échouer ce contrôle.
  IF private.fn_growth_appel_bloque('POSTCONDITION', 'postcondition@interop-mssante.apicrypt.org', NULL) IS NOT NULL
    OR private.fn_growth_destinataire_bloque('PROSPECT_ETABLISSEMENT', 'POSTCONDITION', 'postcondition@interop-mssante.apicrypt.org', NULL, NULL) IS DISTINCT FROM 'MSSANTE'
    OR private.fn_growth_telephone_national('+33 1 23 45 67 89') IS DISTINCT FROM '0123456789'
    OR private.fn_growth_telephone_national('0033123456789') IS DISTINCT FROM '0123456789'
    OR private.fn_growth_telephone_national('01 23 45 67 89 / 01 98 76 54 32') IS NOT NULL
    OR private.fn_growth_telephone_national('123456789') IS NOT NULL
  THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_POSTCONDITION : règle téléphone inexacte (le motif MSSANTE doit valoir pour l''email seulement ; forme nationale d''un numéro).';
  END IF;

  -- Décompte lisible, contraintes en place.
  IF (private.fn_growth_cibles_prospection()->>'etablissements_cibles') IS NULL
    OR (SELECT count(*) FROM pg_catalog.pg_constraint c
        WHERE c.conrelid = 'public.growth_brouillons'::pg_catalog.regclass
          AND c.conname IN ('growth_brouillons_agent_check', 'growth_brouillons_canal_check', 'growth_brouillons_telephone_destinataire')) <> 3
  THEN
    RAISE EXCEPTION 'PROSPECTION_LISTE_APPELS_POSTCONDITION : décompte des cibles illisible ou contrainte absente.';
  END IF;
END;
$prospection_liste_appels_apres$;
