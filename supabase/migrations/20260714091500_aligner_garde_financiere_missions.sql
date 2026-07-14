-- Corrige le garde anti-seed sans modifier le moteur financier canonique.
-- Ordre final des triggers BEFORE : plafond Rist, contrôle du snapshot fourni,
-- moteur financier, commission établissement, estimation nette. Le calculateur
-- historique des seules heures majorées est retiré : exécuté après le moteur,
-- il remettait notamment les heures à zéro sur les missions sans créneaux.

CREATE OR REPLACE FUNCTION public.fn_anti_seed_mission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_ctx text;
  v_admin_reason text;
  v_calcul jsonb;
  v_taux_effectif numeric;
  v_expected_duree numeric;
  v_expected_brut numeric;
  v_expected_ifm numeric;
  v_expected_icp numeric;
  v_expected_net numeric;
  v_est_liberal boolean;
  v_snapshot_absent boolean;
BEGIN
  v_ctx := NULLIF(
    pg_catalog.current_setting('jolene.creer_mission_context', true),
    ''
  );
  IF v_ctx = 'true' THEN RETURN NEW; END IF;

  v_admin_reason := NULLIF(
    pg_catalog.current_setting('jolene.admin_seed_override_reason', true),
    ''
  );
  IF v_admin_reason IS NOT NULL THEN
    INSERT INTO public.journaux_audit (
      acteur_id,
      type_acteur,
      action,
      type_ressource,
      id_ressource,
      details
    ) VALUES (
      auth.uid(),
      'ADMIN_PLATEFORME',
      'OVERRIDE_ANTI_SEED',
      'missions',
      NEW.id,
      pg_catalog.jsonb_build_object(
        'reason', v_admin_reason,
        'intitule', NEW.intitule,
        'etablissement_id', NEW.etablissement_id,
        'total_brut', NEW.total_brut,
        'net_a_payer', NEW.net_a_payer
      )
    );
    RETURN NEW;
  END IF;

  -- Les colonnes ont historiquement DEFAULT 0. Un INSERT applicatif/API qui ne
  -- fournit aucun snapshot arrive donc ici avec 0/0, et non NULL/NULL. Ces deux
  -- couples représentent l'absence de snapshot : le moteur canonique placé
  -- après ce garde les remplit. Toute autre combinaison reste contrôlée.
  v_snapshot_absent :=
    (NEW.total_brut IS NULL AND NEW.net_a_payer IS NULL)
    OR (NEW.total_brut = 0 AND NEW.net_a_payer = 0);

  IF (NEW.total_brut IS NULL) <> (NEW.net_a_payer IS NULL) THEN
    RAISE EXCEPTION
      'anti-seed mission: total_brut et net_a_payer doivent être tous deux NULL ou tous deux renseignés.'
      USING ERRCODE = '23514';
  END IF;
  -- Conserve le parcours applicatif historique : quand aucun snapshot n'est
  -- fourni, le moteur financier placé après ce garde calcule toutes les
  -- colonnes. Le garde ne doit pas imposer duree_heures aux INSERT normaux.
  IF v_snapshot_absent THEN RETURN NEW; END IF;

  IF NEW.duree_heures IS NULL OR NEW.taux_horaire_base IS NULL THEN
    RAISE EXCEPTION
      'anti-seed mission: durée et taux horaire sont obligatoires pour un INSERT direct. Utilisez fn_creer_mission ou jolene.admin_seed_override_reason.'
      USING ERRCODE = '23514';
  END IF;

  -- Le trigger plafond Rist s'exécute avant celui-ci et a déjà posé le taux
  -- réellement applicable à la profession requise par la mission.
  v_taux_effectif := COALESCE(
    NEW.taux_rist_plafonne,
    NEW.taux_horaire_base
  );
  v_calcul := public.fn_calculer_remuneration_mission(
    NEW.debut_le,
    NEW.fin_le,
    v_taux_effectif,
    NEW.etablissement_id,
    NULL
  );
  v_expected_duree := pg_catalog.round(
    (v_calcul ->> 'heures_totales')::numeric,
    2
  );
  v_expected_brut := pg_catalog.round(
    (v_calcul ->> 'total_brut')::numeric,
    2
  );

  -- La mission, jamais le profil du soignant, décide du régime financier.
  v_est_liberal := COALESCE(
    NEW.type_contrat_applique::text,
    CASE
      WHEN NEW.type_contrat_recherche = 'LIBERAL' THEN 'LIBERAL'
      ELSE 'SALARIE'
    END
  ) = 'LIBERAL';
  IF v_est_liberal THEN
    v_expected_ifm := 0;
    v_expected_icp := 0;
  ELSE
    v_expected_ifm := pg_catalog.round(v_expected_brut * 0.10, 2);
    v_expected_icp := pg_catalog.round(
      (v_expected_brut + v_expected_ifm) * 0.10,
      2
    );
  END IF;
  v_expected_net := pg_catalog.round(
    v_expected_brut + v_expected_ifm + v_expected_icp,
    2
  );

  IF NEW.duree_heures IS DISTINCT FROM v_expected_duree THEN
    RAISE EXCEPTION
      'anti-seed mission: duree_heures % incohérente avec le créneau canonique %.',
      NEW.duree_heures,
      v_expected_duree
      USING ERRCODE = '23514';
  END IF;

  IF NEW.total_brut IS DISTINCT FROM v_expected_brut THEN
    RAISE EXCEPTION
      'anti-seed mission: total_brut % incohérent avec le moteur canonique % (majorations incluses).',
      NEW.total_brut,
      v_expected_brut
      USING ERRCODE = '23514';
  END IF;
  IF NEW.net_a_payer IS DISTINCT FROM v_expected_net THEN
    RAISE EXCEPTION
      'anti-seed mission: net_a_payer % incohérent avec brut + IFM + ICP = %. La commission Jolene est facturée séparément et ne doit jamais être déduite.',
      NEW.net_a_payer,
      v_expected_net
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_anti_seed_mission()
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_anti_seed_mission() IS
  'Contrôle avant calcul les snapshots financiers seedés : majorations incluses, IFM/ICP selon le contrat de la mission, commission jamais déduite.';

-- dec_mission_z_finance calcule déjà les heures majorées et leurs montants dans
-- la même passe. Le trigger historique ci-dessous s'exécutait plus tard par
-- ordre alphabétique et réécrivait seulement les heures. Sans mission_creneaux
-- (parcours mono-jour et API), il les remettait toutes à zéro tout en laissant
-- les montants calculés, créant un snapshot contradictoire.
DROP TRIGGER IF EXISTS trg_auto_heures_majorees ON public.missions;
DROP FUNCTION IF EXISTS public.fn_trg_auto_heures_majorees();

DROP TRIGGER IF EXISTS trg_anti_seed_mission ON public.missions;
DROP TRIGGER IF EXISTS dec_mission_y_anti_seed ON public.missions;
CREATE TRIGGER dec_mission_y_anti_seed
  BEFORE INSERT ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_anti_seed_mission();

-- PostgreSQL ordonne les triggers d'un même événement par nom. La commission
-- lit obligatoirement le net produit par dec_mission_z_finance.
DROP TRIGGER IF EXISTS dec_mission_commission ON public.missions;
DROP TRIGGER IF EXISTS dec_mission_zz_commission ON public.missions;
CREATE TRIGGER dec_mission_zz_commission
  BEFORE INSERT OR UPDATE ON public.missions
  FOR EACH ROW
  EXECUTE FUNCTION public.dec_calculer_commission();

DO $verification_ordre_financier$
DECLARE
  v_order text[];
  v_rist integer;
  v_anti integer;
  v_finance integer;
  v_commission integer;
  v_net_estime integer;
BEGIN
  SELECT pg_catalog.array_agg(t.tgname::text ORDER BY t.tgname::text)
  INTO v_order
  FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid = 'public.missions'::pg_catalog.regclass
    AND t.tgisinternal IS FALSE;

  v_rist := pg_catalog.array_position(v_order, 'dec_mission_plafond_rist');
  v_anti := pg_catalog.array_position(v_order, 'dec_mission_y_anti_seed');
  v_finance := pg_catalog.array_position(v_order, 'dec_mission_z_finance');
  v_commission := pg_catalog.array_position(
    v_order,
    'dec_mission_zz_commission'
  );
  v_net_estime := pg_catalog.array_position(v_order, 'dec_net_estime');

  IF v_rist IS NULL
     OR v_anti IS NULL
     OR v_finance IS NULL
     OR v_commission IS NULL
     OR v_net_estime IS NULL
     OR NOT (
       v_rist < v_anti
       AND v_anti < v_finance
       AND v_finance < v_commission
       AND v_commission < v_net_estime
     ) THEN
    RAISE EXCEPTION 'Ordre financier missions incorrect : %', v_order;
  END IF;
  IF pg_catalog.array_position(v_order, 'trg_anti_seed_mission') IS NOT NULL
     OR pg_catalog.array_position(
       v_order,
       'dec_mission_commission'
     ) IS NOT NULL
     OR pg_catalog.array_position(
       v_order,
       'trg_auto_heures_majorees'
     ) IS NOT NULL THEN
    RAISE EXCEPTION 'Un ancien trigger financier reste actif : %', v_order;
  END IF;
  IF pg_catalog.to_regprocedure(
       'public.fn_trg_auto_heures_majorees()'
     ) IS NOT NULL THEN
    RAISE EXCEPTION
      'La fonction financière historique fn_trg_auto_heures_majorees existe encore';
  END IF;
END;
$verification_ordre_financier$;

-- Recette migrationnelle transactionnelle. Les fixtures vivent dans une
-- sous-transaction volontairement annulée : aucune donnée de test ne persiste
-- et aucun événement AFTER INSERT ne peut être publié au commit.
DO $verification_fonctionnelle$
DECLARE
  v_etablissement_id uuid := gen_random_uuid();
  v_mission_api_id uuid := gen_random_uuid();
  v_mission_nuit_id uuid := gen_random_uuid();
  v_siret text := pg_catalog.lpad(
    (pg_catalog.floor(pg_catalog.random() * 100000000000000))::bigint::text,
    14,
    '0'
  );
  v_api record;
  v_nuit record;
BEGIN
  BEGIN
    PERFORM pg_catalog.set_config(
      'jolene.creer_mission_context',
      '',
      true
    );

    INSERT INTO public.etablissements (
      id,
      nom,
      siret,
      type,
      adresse_rue,
      adresse_ville,
      adresse_code_postal,
      email_contact,
      statut_verification,
      peut_publier_missions,
      siret_verifie,
      finess_verifie,
      representant_identite_verifiee,
      rattachement_verifie,
      contrat_service_signe,
      est_compte_test,
      taux_majoration_nuit_pourcent,
      taux_majoration_dimanche_pourcent,
      taux_majoration_ferie_pourcent
    ) VALUES (
      v_etablissement_id,
      'Fixture migration finance 0915',
      v_siret,
      'CLINIQUE_PRIVEE',
      '1 rue de la Recette',
      'Paris',
      '75001',
      'fixture-finance-0915-' || v_etablissement_id::text || '@test.local',
      'VERIFIE',
      true,
      true,
      true,
      true,
      true,
      true,
      true,
      25,
      25,
      50
    );

    -- Payload identique au POST /api-v1/missions : ni durée ni snapshot. Les
    -- DEFAULT 0/0 doivent être acceptés puis remplacés par le moteur financier.
    INSERT INTO public.missions (
      id,
      etablissement_id,
      intitule,
      profession_requise,
      debut_le,
      fin_le,
      taux_horaire_base,
      statut,
      type_contrat_recherche,
      mode_attribution
    ) VALUES (
      v_mission_api_id,
      v_etablissement_id,
      'Fixture API sans snapshot',
      'IDE',
      '2099-06-15 09:00:00+02'::timestamptz,
      '2099-06-15 17:00:00+02'::timestamptz,
      20,
      'OUVERTE',
      'SALARIE',
      'CANDIDATURE'
    )
    RETURNING
      total_brut,
      montant_ifm,
      montant_icp,
      net_a_payer,
      heures_nuit,
      montant_majoration_nuit
    INTO v_api;

    IF v_api.total_brut IS DISTINCT FROM 160.00::numeric
       OR v_api.montant_ifm IS DISTINCT FROM 16.00::numeric
       OR v_api.montant_icp IS DISTINCT FROM 17.60::numeric
       OR v_api.net_a_payer IS DISTINCT FROM 193.60::numeric
       OR v_api.heures_nuit IS DISTINCT FROM 0.00::numeric
       OR v_api.montant_majoration_nuit IS DISTINCT FROM 0.00::numeric THEN
      RAISE EXCEPTION
        'INSERT API sans snapshot non canonique : %',
        pg_catalog.row_to_json(v_api);
    END IF;

    -- Une mission mono-jour de nuit n'a pas de mission_creneaux au moment de
    -- l'INSERT. Ses heures et ses montants doivent néanmoins rester cohérents.
    INSERT INTO public.missions (
      id,
      etablissement_id,
      intitule,
      profession_requise,
      debut_le,
      fin_le,
      taux_horaire_base,
      statut,
      type_contrat_recherche,
      mode_attribution
    ) VALUES (
      v_mission_nuit_id,
      v_etablissement_id,
      'Fixture mission de nuit',
      'IDE',
      '2099-06-15 22:00:00+02'::timestamptz,
      '2099-06-16 02:00:00+02'::timestamptz,
      20,
      'OUVERTE',
      'SALARIE',
      'CANDIDATURE'
    )
    RETURNING
      heures_nuit,
      montant_majoration_nuit,
      heures_dimanche,
      montant_majoration_dimanche,
      heures_ferie,
      montant_majoration_ferie,
      total_brut,
      montant_ifm,
      montant_icp,
      net_a_payer
    INTO v_nuit;

    IF v_nuit.heures_nuit IS DISTINCT FROM 4.00::numeric
       OR v_nuit.montant_majoration_nuit IS DISTINCT FROM 20.00::numeric
       OR v_nuit.heures_dimanche IS DISTINCT FROM 0.00::numeric
       OR v_nuit.montant_majoration_dimanche IS DISTINCT FROM 0.00::numeric
       OR v_nuit.heures_ferie IS DISTINCT FROM 0.00::numeric
       OR v_nuit.montant_majoration_ferie IS DISTINCT FROM 0.00::numeric
       OR v_nuit.total_brut IS DISTINCT FROM 100.00::numeric
       OR v_nuit.montant_ifm IS DISTINCT FROM 10.00::numeric
       OR v_nuit.montant_icp IS DISTINCT FROM 11.00::numeric
       OR v_nuit.net_a_payer IS DISTINCT FROM 121.00::numeric THEN
      RAISE EXCEPTION
        'Mission de nuit non canonique : %',
        pg_catalog.row_to_json(v_nuit);
    END IF;

    RAISE EXCEPTION USING
      ERRCODE = 'J1599',
      MESSAGE = 'ROLLBACK_FIXTURES_FINANCE_0915';
  EXCEPTION
    WHEN SQLSTATE 'J1599' THEN NULL;
  END;

  IF EXISTS (
       SELECT 1
       FROM public.etablissements e
       WHERE e.id = v_etablissement_id
     )
     OR EXISTS (
       SELECT 1
       FROM public.missions m
       WHERE m.id IN (v_mission_api_id, v_mission_nuit_id)
     ) THEN
    RAISE EXCEPTION
      'Les fixtures financières 0915 n''ont pas été annulées';
  END IF;
END;
$verification_fonctionnelle$;
