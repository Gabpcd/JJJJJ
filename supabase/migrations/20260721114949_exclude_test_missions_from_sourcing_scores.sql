-- Les données de démonstration restent disponibles pour les captures stores,
-- mais leurs missions et leurs comptes ne doivent jamais influencer la demande
-- réelle, le score de priorité ou la déduplication des prospects.

BEGIN;

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
        AND COALESCE(e.est_compte_test, false) IS FALSE
      GROUP BY 1, 2
    ), candidats AS MATERIALIZED (
      SELECT p.cle, p.nom, p.prenom, p.profession, p.enseigne, p.telephone,
             p.email, p.ville, p.departement, p.code_postal, p.numero_rpps,
             p.mode_exercice, p.finess_structure, p.source_code, p.source_url,
             p.source_maj_le, p.importe_le, p.statut_sourcing
      FROM public.prospects_soignants p
      WHERE p.statut_sourcing NOT IN ('IGNORE', 'OPPOSITION')
        AND (v_departement IS NULL OR p.departement = CASE
          WHEN v_departement ~ '^\d$' THEN lpad(v_departement, 2, '0')
          ELSE v_departement
        END)
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
          WHERE c.type = 'SOIGNANT'
            AND (
              (c.source_prospect_type = 'SOIGNANT' AND c.source_prospect_id = p.cle)
              OR (p.numero_rpps IS NOT NULL AND c.notes ILIKE '%' || p.numero_rpps || '%')
              OR (p.email IS NOT NULL AND lower(c.email) = lower(p.email))
              OR (p.telephone IS NOT NULL AND length(regexp_replace(p.telephone, '\\D', '', 'g')) >= 9
                  AND regexp_replace(c.telephone, '\\D', '', 'g') = regexp_replace(p.telephone, '\\D', '', 'g'))
            )
        ) AS deja_crm,
        EXISTS (
          SELECT 1 FROM public.soignants s
          WHERE s.supprime_le IS NULL
            AND COALESCE(s.est_compte_test, false) IS FALSE
            AND (
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
          WHERE c.type = 'ETABLISSEMENT'
            AND (
              c.finess = p.finess
              OR (p.email IS NOT NULL AND lower(c.email) = lower(p.email))
              OR (p.telephone IS NOT NULL AND length(regexp_replace(p.telephone, '\\D', '', 'g')) >= 9
                  AND regexp_replace(c.telephone, '\\D', '', 'g') = regexp_replace(p.telephone, '\\D', '', 'g'))
            )
        ) AS deja_crm,
        EXISTS (
          SELECT 1 FROM public.etablissements e
          WHERE e.supprime_le IS NULL
            AND COALESCE(e.est_compte_test, false) IS FALSE
            AND (
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
      AND COALESCE(e.est_compte_test, false) IS FALSE
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

-- L'ajout manuel au CRM reste strictement silencieux, y compris lorsqu'un
-- prospect correspond a un contact deja present. La deduplication soignant ne
-- doit jamais reutiliser un contact etablissement partageant un email ou un
-- numero de telephone.
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
    SELECT * INTO v_etab
      FROM public.prospects_etablissements
     WHERE finess = p_prospect_id;
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
      sequence_active = false,
      prochaine_action_le = NULL,
      maj_le = now()
    RETURNING id INTO v_contact_id;

    UPDATE public.prospects_etablissements
       SET ajoute_crm_le = COALESCE(ajoute_crm_le, now()),
           statut_sourcing = 'QUALIFIE'
     WHERE finess = p_prospect_id;
  ELSIF v_cible = 'SOIGNANT' THEN
    SELECT * INTO v_soignant
      FROM public.prospects_soignants
     WHERE cle = p_prospect_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Prospect soignant introuvable'; END IF;

    SELECT c.id INTO v_contact_id
      FROM public.sales_contacts c
     WHERE c.type = 'SOIGNANT'
       AND (
         (c.source_prospect_type = 'SOIGNANT' AND c.source_prospect_id = v_soignant.cle)
         OR (v_soignant.email IS NOT NULL AND lower(c.email) = lower(v_soignant.email))
         OR (v_soignant.telephone IS NOT NULL
             AND length(regexp_replace(v_soignant.telephone, '\\D', '', 'g')) >= 9
             AND regexp_replace(c.telephone, '\\D', '', 'g') = regexp_replace(v_soignant.telephone, '\\D', '', 'g'))
       )
     ORDER BY c.cree_le
     LIMIT 1;

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
             sequence_active = false,
             prochaine_action_le = NULL,
             maj_le = now()
       WHERE id = v_contact_id;
    END IF;

    UPDATE public.prospects_soignants
       SET ajoute_crm_le = COALESCE(ajoute_crm_le, now()),
           statut_sourcing = 'QUALIFIE'
     WHERE cle = p_prospect_id;
  ELSE
    RAISE EXCEPTION 'Cible invalide';
  END IF;

  -- Le trigger d'initialisation historique peut poser une echeance sur INSERT.
  -- Ce verrou final garantit le meme etat silencieux sur insert et deduplication.
  UPDATE public.sales_contacts
     SET sequence_active = false,
         prochaine_action_le = NULL,
         maj_le = now()
   WHERE id = v_contact_id;

  RETURN jsonb_build_object(
    'success', true,
    'contact_id', v_contact_id,
    'sequence_active', false,
    'prochaine_action_le', NULL,
    'contact_automatique', false
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_sourcing_ajouter_crm(text, text, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_sourcing_ajouter_crm(text, text, smallint) TO authenticated, service_role;

-- Le cycle des recommandations est une regle serveur, pas seulement une
-- contrainte d'interface. Le verrou empeche deux onglets admin de valider des
-- transitions concurrentes a partir d'un meme etat obsolete.
CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_changer_action(
  p_action_id uuid,
  p_statut text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_statut_actuel text;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin requis' USING ERRCODE = '42501';
  END IF;
  IF p_statut IS NULL OR p_statut NOT IN ('BROUILLON', 'PRIORISEE', 'EN_COURS', 'TERMINEE', 'IGNORE') THEN
    RAISE EXCEPTION 'Statut invalide' USING ERRCODE = '22023';
  END IF;

  SELECT statut
    INTO v_statut_actuel
    FROM public.acquisition_actions
   WHERE id = p_action_id
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Action introuvable'; END IF;

  -- Autoriser le meme statut rend un retry reseau idempotent sans rouvrir le
  -- cycle. Toutes les autres transitions doivent suivre la matrice ci-dessous.
  IF p_statut <> v_statut_actuel
     AND NOT (
       (v_statut_actuel = 'BROUILLON' AND p_statut IN ('PRIORISEE', 'IGNORE'))
       OR (v_statut_actuel = 'PRIORISEE' AND p_statut IN ('EN_COURS', 'IGNORE'))
       OR (v_statut_actuel = 'EN_COURS' AND p_statut = 'TERMINEE')
     ) THEN
    RAISE EXCEPTION 'Transition invalide (% -> %)', v_statut_actuel, p_statut
      USING ERRCODE = '22023';
  END IF;

  IF p_statut <> v_statut_actuel THEN
    UPDATE public.acquisition_actions
       SET statut = p_statut,
           maj_le = now()
     WHERE id = p_action_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'statut', p_statut);
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_acquisition_changer_action(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_acquisition_changer_action(uuid, text) TO authenticated, service_role;

COMMIT;
