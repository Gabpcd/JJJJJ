-- Pré-lancement Jolene :
--   1. toutes les lignes opérationnelles créées avant le lancement sont des
--      fixtures de test, sans modifier les annuaires/prospects ;
--   2. le statut test d'une mission reste dérivé de ses deux parties (pas de
--      colonne redondante susceptible de diverger) ;
--   3. les KPI publics/réels et les envois externes ignorent ces fixtures ;
--   4. aucun administrateur Jolene n'est soumis à MFA/TOTP/AAL2.
--
-- Cette migration est appliquée avant toute ouverture au public : le stock
-- présent au moment du déploiement est donc intégralement de test. Le défaut
-- et le trigger ferment ensuite la fenêtre de course jusqu'à une migration
-- explicite de bascule en production.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Requalifier le stock opérationnel présent avant lancement
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.soignants
   SET est_compte_test = true
 WHERE est_compte_test IS DISTINCT FROM true;

-- Ces deux triggers contrôlent les preuves et le droit de publication. Le
-- marquage administratif ne doit ni invalider ni auto-valider une fixture.
ALTER TABLE public.etablissements
  DISABLE TRIGGER trg_invalider_verifications_etablissement;
ALTER TABLE public.etablissements
  DISABLE TRIGGER trg_auto_valider_etablissement;

UPDATE public.etablissements
   SET est_compte_test = true
 WHERE est_compte_test IS DISTINCT FROM true;

ALTER TABLE public.etablissements
  ENABLE TRIGGER trg_auto_valider_etablissement;
ALTER TABLE public.etablissements
  ENABLE TRIGGER trg_invalider_verifications_etablissement;

COMMENT ON COLUMN public.soignants.est_compte_test IS
  'Compte de recette, démonstration ou audit interne. Exclu des KPI réels et de tout effet externe.';
COMMENT ON COLUMN public.etablissements.est_compte_test IS
  'Établissement de recette, démonstration ou audit interne. Ses missions sont dérivées test et exclues des effets externes.';

CREATE SCHEMA IF NOT EXISTS private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.fn_mission_lie_compte_test(
  p_mission_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE((
    SELECT e.est_compte_test IS TRUE
        OR COALESCE(s.est_compte_test, false)
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE m.id = p_mission_id
  ), true);
$function$;

COMMENT ON FUNCTION private.fn_mission_lie_compte_test(uuid) IS
  'Fail-closed : une mission est test si son établissement ou son soignant est test, ou si sa provenance est introuvable.';
REVOKE ALL ON FUNCTION private.fn_mission_lie_compte_test(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_mission_lie_compte_test(uuid)
  TO service_role;

-- Critère canonique et symétrique entre les deux cohortes. Toute donnée
-- absente ou tout marqueur NULL échoue fermé.
CREATE OR REPLACE FUNCTION private.fn_comptes_meme_cohorte_test(
  p_soignant_id uuid,
  p_etablissement_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT COALESCE((
    SELECT
      s.est_compte_test IS NOT NULL
      AND e.est_compte_test IS NOT NULL
      AND s.est_compte_test = e.est_compte_test
    FROM public.soignants s
    CROSS JOIN public.etablissements e
    WHERE s.id = p_soignant_id
      AND s.supprime_le IS NULL
      AND e.id = p_etablissement_id
      AND e.supprime_le IS NULL
  ), false);
$function$;

COMMENT ON FUNCTION private.fn_comptes_meme_cohorte_test(uuid, uuid) IS
  'Fail-closed : vrai uniquement si le soignant et l’établissement existent, sont actifs et portent exactement le même marqueur test/réel.';
REVOKE ALL ON FUNCTION private.fn_comptes_meme_cohorte_test(uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.fn_comptes_meme_cohorte_test(uuid, uuid)
  TO authenticated, service_role;

-- Tant que le lancement n'a pas fait l'objet d'une migration explicite, toute
-- nouvelle création et toute tentative de déclassement restent des fixtures.
ALTER TABLE public.soignants
  ALTER COLUMN est_compte_test SET DEFAULT true;
ALTER TABLE public.etablissements
  ALTER COLUMN est_compte_test SET DEFAULT true;

CREATE OR REPLACE FUNCTION private.fn_forcer_compte_test_prelaunch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  NEW.est_compte_test := true;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_forcer_compte_test_prelaunch()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_forcer_compte_test_prelaunch()
  TO service_role;

DROP TRIGGER IF EXISTS trg_forcer_compte_test_prelaunch
  ON public.soignants;
CREATE TRIGGER trg_forcer_compte_test_prelaunch
BEFORE INSERT OR UPDATE OF est_compte_test ON public.soignants
FOR EACH ROW EXECUTE FUNCTION private.fn_forcer_compte_test_prelaunch();

DROP TRIGGER IF EXISTS trg_forcer_compte_test_prelaunch
  ON public.etablissements;
CREATE TRIGGER trg_forcer_compte_test_prelaunch
BEFORE INSERT OR UPDATE OF est_compte_test ON public.etablissements
FOR EACH ROW EXECUTE FUNCTION private.fn_forcer_compte_test_prelaunch();

-- La politique restrictive historique était unidirectionnelle : un compte
-- test pouvait voir les missions réelles. Seuls les soignants sont cohortés ;
-- les administrateurs et membres d'établissement conservent leurs vues métier.
DROP POLICY IF EXISTS missions_masquer_etabs_test ON public.missions;
CREATE POLICY missions_masquer_etabs_test
ON public.missions
AS RESTRICTIVE
FOR SELECT TO authenticated
USING (
  NOT (SELECT public.est_soignant())
  OR private.fn_comptes_meme_cohorte_test(
    (SELECT auth.uid()),
    etablissement_id
  )
);

-- Ferme aussi l'INSERT direct dans candidatures : le RPC n'est pas la seule
-- barrière disponible via Data API.
DROP POLICY IF EXISTS pol_cand_insert ON public.candidatures;
CREATE POLICY pol_cand_insert
ON public.candidatures
FOR INSERT TO authenticated
WITH CHECK (
  (
    soignant_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.missions m
      WHERE m.id = mission_id
        AND private.fn_comptes_meme_cohorte_test(
          (SELECT auth.uid()),
          m.etablissement_id
        )
    )
  )
  OR (SELECT public.est_admin())
  OR EXISTS (
    SELECT 1
    FROM public.missions m
    WHERE m.id = mission_id
      AND m.etablissement_id = (SELECT public.mon_etablissement_id())
      AND private.fn_comptes_meme_cohorte_test(
        soignant_id,
        m.etablissement_id
      )
      AND (
        SELECT public.fn_a_permission_etablissement(
          'candidatures',
          m.etablissement_id
        )
      )
  )
);

CREATE OR REPLACE FUNCTION public.fn_resoudre_contrat_mission(
  p_mission_id uuid,
  p_soignant_id uuid,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_etablissement record;
  v_recherche text;
  v_choix text;
  v_mode jsonb;
  v_liberal_verifie boolean := false;
BEGIN
  SELECT id, profession_requise, type_contrat_recherche, etablissement_id
    INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Mission introuvable');
  END IF;

  SELECT
    id,
    COALESCE(type_exercice, 'SALARIE') AS type_exercice,
    preference_contrat_mixte
  INTO v_soignant
  FROM public.soignants
  WHERE id = p_soignant_id
    AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Profil soignant introuvable'
    );
  END IF;

  SELECT
    type::text AS type_etablissement,
    COALESCE(est_secteur_public, false) AS est_public
  INTO v_etablissement
  FROM public.etablissements
  WHERE id = v_mission.etablissement_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Établissement introuvable'
    );
  END IF;

  IF NOT private.fn_comptes_meme_cohorte_test(
    p_soignant_id,
    v_mission.etablissement_id
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Mission indisponible pour ce compte'
    );
  END IF;

  v_liberal_verifie :=
    public.fn_soignant_liberal_actif_verifie(p_soignant_id);

  IF p_choix_contrat IS NOT NULL
     AND upper(p_choix_contrat) NOT IN ('SALARIE', 'LIBERAL') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'Choix de contrat invalide'
    );
  END IF;

  v_recherche := CASE
    WHEN upper(COALESCE(
      v_mission.type_contrat_recherche::text,
      'SALARIE'
    )) IN ('SALARIE', 'LIBERAL', 'TOUS')
      THEN upper(COALESCE(
        v_mission.type_contrat_recherche::text,
        'SALARIE'
      ))
    ELSE 'SALARIE'
  END;

  IF v_recherche = 'SALARIE' THEN
    v_choix := 'SALARIE';
  ELSIF v_recherche = 'LIBERAL' THEN
    IF v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
       OR NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Cette mission est proposée en libéral ; activez un profil libéral avec SIRET et identité vérifiés.'
      );
    END IF;
    v_choix := 'LIBERAL';
  ELSE
    v_choix := upper(p_choix_contrat);

    IF v_choix = 'LIBERAL' AND NOT v_liberal_verifie THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil libéral doit être actif, avec SIRET et identité vérifiés.'
      );
    END IF;

    IF v_choix IS NULL THEN
      IF v_soignant.type_exercice = 'MIXTE' AND v_liberal_verifie THEN
        v_choix := CASE
          WHEN upper(COALESCE(
            v_soignant.preference_contrat_mixte,
            ''
          )) IN ('SALARIE', 'LIBERAL')
            THEN upper(v_soignant.preference_contrat_mixte)
          ELSE NULL
        END;
        IF v_choix IS NULL THEN
          RETURN jsonb_build_object(
            'ok', false,
            'choix_requis', true,
            'error', 'Choisissez votre mode de contrat.',
            'options', jsonb_build_array(
              jsonb_build_object(
                'value', 'SALARIE',
                'label', 'Salarié (CDD / bulletin de paie)'
              ),
              jsonb_build_object(
                'value', 'LIBERAL',
                'label', 'Libéral (note d''honoraires)'
              )
            )
          );
        END IF;
      ELSIF v_soignant.type_exercice = 'LIBERAL'
            AND v_liberal_verifie THEN
        v_choix := 'LIBERAL';
      ELSE
        v_choix := 'SALARIE';
      END IF;
    END IF;

    IF v_choix = 'LIBERAL'
       AND (
         v_soignant.type_exercice NOT IN ('LIBERAL', 'MIXTE')
         OR NOT v_liberal_verifie
       ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error',
          'Votre profil n''est pas activé pour un contrat libéral vérifié.'
      );
    END IF;
  END IF;

  IF v_choix = 'LIBERAL' THEN
    v_mode := public.fn_mode_exercice(
      v_mission.profession_requise::text,
      v_etablissement.type_etablissement,
      CASE
        WHEN v_etablissement.est_public THEN 'PUBLIC'
        ELSE NULL
      END
    );
    IF COALESCE(v_mode->>'niveau', 'NON_PROPOSE') <> 'AUTORISE' THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', COALESCE(
          v_mode->>'source_libelle',
          'Cette mission est proposée en salarié.'
        ),
        'niveau', COALESCE(v_mode->>'niveau', 'NON_PROPOSE')
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'type_contrat_recherche', v_recherche
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_postuler_mission(
  p_mission_id uuid,
  p_message text DEFAULT NULL,
  p_choix_contrat text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission record;
  v_soignant record;
  v_resolution jsonb;
  v_choix text;
  v_candidature_id uuid;
  v_docs_ok boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT * INTO v_mission
  FROM public.missions
  WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;
  IF v_mission.statut <> 'OUVERTE' THEN
    RETURN jsonb_build_object(
      'error',
      'Cette mission n''est plus disponible'
    );
  END IF;
  IF v_mission.mode_attribution <> 'CANDIDATURE' THEN
    RETURN jsonb_build_object(
      'error',
      'Cette mission n''accepte pas les candidatures'
    );
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = auth.uid()
    AND supprime_le IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profil soignant introuvable');
  END IF;
  IF COALESCE(v_soignant.statut_compte::text, 'ACTIF') <> 'ACTIF' THEN
    RETURN jsonb_build_object(
      'error',
      'Votre compte ne permet pas de candidater. Contactez bonjour@jolene.app.'
    );
  END IF;

  IF NOT private.fn_comptes_meme_cohorte_test(
    auth.uid(),
    v_mission.etablissement_id
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Mission indisponible pour ce compte'
    );
  END IF;

  IF NOT public.fn_soignant_compatible_mission(
    v_soignant.profession,
    v_soignant.specialite_medicale,
    v_mission.profession_requise,
    v_mission.specialite_medicale_requise,
    COALESCE(v_mission.accepte_non_specialises, true)
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Votre profession ne correspond pas à la mission requise ('
        || v_mission.profession_requise::text
        || ').'
    );
  END IF;
  IF public.fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN
    RETURN jsonb_build_object('error', 'Accès refusé.');
  END IF;

  v_resolution := public.fn_resoudre_contrat_mission(
    p_mission_id,
    auth.uid(),
    p_choix_contrat
  );
  IF COALESCE((v_resolution->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN v_resolution - 'ok';
  END IF;
  v_choix := v_resolution->>'contrat';

  IF EXISTS (
    SELECT 1
    FROM public.candidatures
    WHERE mission_id = p_mission_id
      AND soignant_id = auth.uid()
  ) THEN
    RETURN jsonb_build_object(
      'error',
      'Vous avez déjà postulé à cette mission'
    );
  END IF;

  v_docs_ok := public.fn_documents_ok_pour_mission(
    auth.uid(),
    v_choix
  );
  IF v_choix = 'LIBERAL' AND NOT v_docs_ok THEN
    RETURN jsonb_build_object(
      'error',
        'Les documents requis pour candidater en libéral sont manquants ou expirés.',
      'documents_requis_pour', 'LIBERAL',
      'lien_documents', '/soignant/mes-documents'
    );
  END IF;

  INSERT INTO public.candidatures (
    mission_id,
    soignant_id,
    message,
    statut,
    type_contrat_choisi
  ) VALUES (
    p_mission_id,
    auth.uid(),
    public.fn_html_escape(p_message),
    'EN_ATTENTE',
    v_choix
  )
  RETURNING id INTO v_candidature_id;

  INSERT INTO public.notifications (
    destinataire_id,
    type_destinataire,
    type,
    titre,
    corps,
    lien
  ) VALUES (
    v_mission.etablissement_id,
    'ETABLISSEMENT',
    'CANDIDATURE_RECUE',
    '📋 Nouvelle candidature reçue',
    COALESCE(v_soignant.prenom, 'Un soignant')
      || ' a postulé à votre mission « '
      || public.fn_html_escape(v_mission.intitule)
      || ' ».',
    '/etablissement/missions/' || p_mission_id
  );

  IF NOT v_docs_ok THEN
    INSERT INTO public.notifications (
      destinataire_id,
      type,
      titre,
      corps,
      lien,
      type_destinataire
    )
    SELECT
      auth.uid(),
      'RAPPEL_DOCUMENTS',
      'Complétez vos documents salariés',
      'Votre candidature est envoyée. Les documents requis pour le CDD doivent être validés avant que l''établissement puisse vous accepter.',
      '/soignant/mes-documents',
      'SOIGNANT'
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.notifications
      WHERE destinataire_id = auth.uid()
        AND type = 'RAPPEL_DOCUMENTS'
        AND cree_le > now() - interval '24 hours'
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'candidature_id', v_candidature_id,
    'choix_contrat', v_choix,
    'profession_requise', v_mission.profession_requise::text,
    'docs_a_completer', NOT v_docs_ok,
    'documents_requis_pour', v_choix
  );
END;
$function$;

DO $assert_requalification$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM public.soignants
     WHERE est_compte_test IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION 'Requalification incomplète des soignants pré-lancement';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.etablissements
     WHERE est_compte_test IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION 'Requalification incomplète des établissements pré-lancement';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.missions m
     WHERE private.fn_mission_lie_compte_test(m.id) IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION 'Requalification incomplète des missions pré-lancement';
  END IF;

  -- Vérification nominative demandée. L'absence d'une fixture sur un
  -- environnement vide/staging est valide ; sa présence non marquée ne l'est pas.
  IF EXISTS (
    SELECT 1 FROM public.etablissements
     WHERE lower(nom) IN (
       lower('Hôpital Saint-Louis'),
       lower('EHPAD Les Jardins de Belleville'),
       lower('Clinique du Parc Monceau')
     )
       AND est_compte_test IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION 'Un établissement de démonstration nommé reste classé réel';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.soignants
     WHERE (
       (lower(prenom) = 'julie' AND lower(nom) = 'martin')
       OR (lower(prenom) = 'thomas' AND lower(nom) = 'bernard')
       OR (lower(prenom) = 'léa' AND lower(nom) = 'petit')
     )
       AND est_compte_test IS DISTINCT FROM true
  ) THEN
    RAISE EXCEPTION 'Un soignant de démonstration nommé reste classé réel';
  END IF;
END
$assert_requalification$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Les KPI historiques utilisés par les écrans principaux deviennent réels
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_admin_kpi()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
  debut_semaine timestamptz := date_trunc('week', now());
  debut_mois timestamptz := date_trunc('month', now());
  fin_mois timestamptz := date_trunc('month', now()) + interval '1 month';
BEGIN
  IF NOT public.est_admin() THEN
    RETURN '{"error":"Accès réservé aux administrateurs"}'::jsonb;
  END IF;

  WITH missions_reelles AS (
    SELECT m.*
      FROM public.missions m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
     WHERE e.est_compte_test IS FALSE
       AND COALESCE(s.est_compte_test, false) IS FALSE
  ),
  factures_reelles AS (
    SELECT f.*
      FROM public.factures f
      JOIN public.etablissements e ON e.id = f.etablissement_id
     WHERE e.est_compte_test IS FALSE
  )
  SELECT jsonb_build_object(
    'soignants_total', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
    ),
    'etablissements_total', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
    ),
    'missions_terminees_total', (
      SELECT count(*) FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'missions_terminees_mois', (
      SELECT count(*) FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'missions_ouvertes', (
      SELECT count(*) FROM missions_reelles
       WHERE statut IN ('OUVERTE', 'ASSIGNEE', 'EN_COURS')
    ),
    'soignants_semaine', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= debut_semaine
    ),
    'etablissements_semaine', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= debut_semaine
    ),
    'litiges_ouverts', (
      SELECT count(*)
        FROM public.litiges l
        JOIN missions_reelles m ON m.id = l.mission_id
       WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE')
    ),
    'ca_commissions_ht_mois', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'ca_potentiel_mois', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles
       WHERE fin_le >= debut_mois AND fin_le < fin_mois
         AND statut IN ('TERMINEE', 'ASSIGNEE', 'EN_COURS')
    ),
    'ca_encaisse_total', (
      SELECT COALESCE(sum(montant_ht), 0)
        FROM factures_reelles WHERE statut = 'PAYEE'
    ),
    'ca_potentiel_total', (
      SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'gmv_mois', (
      SELECT COALESCE(sum(total_brut), 0)
        FROM missions_reelles
       WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
    ),
    'gmv_total', (
      SELECT COALESCE(sum(total_brut), 0)
        FROM missions_reelles WHERE statut = 'TERMINEE'
    ),
    'taux_acceptation_mois', (
      SELECT CASE
        WHEN count(*) FILTER (WHERE cree_le >= debut_mois) = 0 THEN 0
        ELSE round(
          100.0 * count(*) FILTER (
            WHERE statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
              AND cree_le >= debut_mois
          ) / NULLIF(count(*) FILTER (WHERE cree_le >= debut_mois), 0)
        )
      END
      FROM missions_reelles
    ),
    'factures_impayees', (
      SELECT count(*) FROM factures_reelles WHERE statut IN ('EMISE', 'EN_RETARD')
    ),
    'docs_en_attente', (
      SELECT count(*)
        FROM public.documents_soignants d
        JOIN public.soignants s ON s.id = d.soignant_id
       WHERE d.statut_verification = 'EN_ATTENTE'
         AND s.est_compte_test IS FALSE
    ),
    'etab_en_attente', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL
         AND est_compte_test IS FALSE
         AND COALESCE(rattachement_verifie, false) = false
         AND COALESCE(statut_verification, '') <> 'REJETE'
    )
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_kpi() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_kpi() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_admin_graphiques()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN '{"error":"Accès réservé aux administrateurs"}'::jsonb;
  END IF;

  SELECT jsonb_build_object(
    'missions_par_semaine', COALESCE((
      SELECT jsonb_agg(row_to_json(t) ORDER BY t.semaine)
      FROM (
        SELECT date_trunc('week', m.cree_le)::date AS semaine, count(*) AS total
          FROM public.missions m
          JOIN public.etablissements e ON e.id = m.etablissement_id
          LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
         WHERE m.cree_le >= now() - interval '12 weeks'
           AND e.est_compte_test IS FALSE
           AND COALESCE(s.est_compte_test, false) IS FALSE
         GROUP BY date_trunc('week', m.cree_le)
      ) t
    ), '[]'::jsonb),
    'ca_par_mois', COALESCE((
      SELECT jsonb_agg(row_to_json(t) ORDER BY t.mois)
      FROM (
        SELECT date_trunc('month', f.date_emission)::date AS mois,
               sum(f.montant_ht) AS ca_ht
          FROM public.factures f
          JOIN public.etablissements e ON e.id = f.etablissement_id
         WHERE f.date_emission >= now() - interval '6 months'
           AND f.statut <> 'ANNULEE'
           AND e.est_compte_test IS FALSE
         GROUP BY date_trunc('month', f.date_emission)
      ) t
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_graphiques() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_graphiques() TO authenticated, service_role;

-- La file de validation est un indicateur réel : les fixtures restent
-- consultables dans leurs vues dédiées mais ne gonflent pas le compteur.
CREATE OR REPLACE FUNCTION public.fn_admin_metriques_argent()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  result jsonb;
  debut_mois timestamptz := date_trunc('month', now());
  fin_mois timestamptz := date_trunc('month', now()) + interval '1 month';
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès réservé aux administrateurs');
  END IF;

  WITH m AS (
    SELECT
      mi.montant_commission_ht,
      mi.montant_commission_tva,
      mi.total_brut,
      mi.fin_le,
      NOT (
        COALESCE(e.est_compte_test, false)
        OR COALESCE(s.est_compte_test, false)
      ) AS est_reel
    FROM missions mi
    LEFT JOIN etablissements e ON e.id = mi.etablissement_id
    LEFT JOIN soignants s ON s.id = mi.soignant_assigne_id
    WHERE mi.statut = 'TERMINEE'
  ),
  f AS (
    SELECT
      fa.montant_ht,
      fa.montant_ttc,
      fa.statut,
      NOT COALESCE(e.est_compte_test, false) AS est_reel
    FROM factures fa
    LEFT JOIN etablissements e ON e.id = fa.etablissement_id
  ),
  esc AS (
    SELECT
      pe.commission_cents,
      pe.debite_le,
      NOT (
        COALESCE(e.est_compte_test, false)
        OR COALESCE(s.est_compte_test, false)
      ) AS est_reel
    FROM paiements_escrow pe
    LEFT JOIN etablissements e ON e.id = pe.etablissement_id
    LEFT JOIN soignants s ON s.id = pe.soignant_id
  )
  SELECT jsonb_build_object(
    'commission', jsonb_build_object(
      'unite', 'HT',
      'total_reel', (
        SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM m WHERE est_reel
      ),
      'total_test', (
        SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM m WHERE NOT est_reel
      ),
      'mois_reel', (
        SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM m
        WHERE est_reel AND fin_le >= debut_mois AND fin_le < fin_mois
      ),
      'mois_test', (
        SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM m
        WHERE NOT est_reel AND fin_le >= debut_mois AND fin_le < fin_mois
      ),
      'tva_reel', (
        SELECT COALESCE(sum(montant_commission_tva), 0)
        FROM m WHERE est_reel
      )
    ),
    'encaisse', jsonb_build_object(
      'ht_reel', round((
        SELECT COALESCE(sum(montant_ht), 0)
        FROM f WHERE statut = 'PAYEE' AND est_reel
      ) + (
        SELECT COALESCE(sum(commission_cents), 0) / 100.0
        FROM esc WHERE debite_le IS NOT NULL AND est_reel
      ), 2),
      'ttc_reel', round((
        SELECT COALESCE(sum(montant_ttc), 0)
        FROM f WHERE statut = 'PAYEE' AND est_reel
      ) + (
        SELECT COALESCE(sum(commission_cents), 0) / 100.0
        FROM esc WHERE debite_le IS NOT NULL AND est_reel
      ), 2),
      'ht_test', round((
        SELECT COALESCE(sum(montant_ht), 0)
        FROM f WHERE statut = 'PAYEE' AND NOT est_reel
      ) + (
        SELECT COALESCE(sum(commission_cents), 0) / 100.0
        FROM esc WHERE debite_le IS NOT NULL AND NOT est_reel
      ), 2)
    ),
    'facturable', jsonb_build_object(
      'unite', 'HT',
      'ht_reel', (
        SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM m WHERE est_reel
      ),
      'ht_test', (
        SELECT COALESCE(sum(montant_commission_ht), 0)
        FROM m WHERE NOT est_reel
      )
    ),
    'gmv', jsonb_build_object(
      'unite', 'brut',
      'total_reel', (
        SELECT COALESCE(sum(total_brut), 0) FROM m WHERE est_reel
      ),
      'total_test', (
        SELECT COALESCE(sum(total_brut), 0) FROM m WHERE NOT est_reel
      ),
      'mois_reel', (
        SELECT COALESCE(sum(total_brut), 0)
        FROM m
        WHERE est_reel AND fin_le >= debut_mois AND fin_le < fin_mois
      ),
      'mois_test', (
        SELECT COALESCE(sum(total_brut), 0)
        FROM m
        WHERE NOT est_reel AND fin_le >= debut_mois AND fin_le < fin_mois
      )
    ),
    'nb_missions_terminees_reel', (
      SELECT count(*) FROM m WHERE est_reel
    ),
    'nb_missions_terminees_test', (
      SELECT count(*) FROM m WHERE NOT est_reel
    ),
    'etab_a_valider', (
      SELECT count(*)
      FROM etablissements e
      WHERE e.supprime_le IS NULL
        AND e.est_compte_test IS FALSE
        AND (
          COALESCE(e.statut_verification, 'EN_ATTENTE')
            IN ('EN_ATTENTE', 'EN_COURS')
          OR (
            e.statut_verification = 'VERIFIE'
            AND (
              e.siret_verifie IS NOT TRUE
              OR e.finess_verifie IS NOT TRUE
              OR e.representant_identite_verifiee IS NOT TRUE
              OR e.rattachement_verifie IS NOT TRUE
              OR e.contrat_service_signe IS NOT TRUE
            )
          )
        )
    ),
    'a_des_donnees_test', (
      SELECT EXISTS(
        SELECT 1 FROM etablissements WHERE est_compte_test IS TRUE
      ) OR EXISTS(
        SELECT 1 FROM soignants WHERE est_compte_test IS TRUE
      )
    )
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_metriques_argent()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_metriques_argent()
  TO authenticated, service_role;

-- Surface anonyme utilisée pour alimenter les cartes et filtres publics.
CREATE OR REPLACE FUNCTION public.fn_etablissements_avec_missions_ouvertes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', e.id,
      'nom', e.nom,
      'type', e.type::text,
      'adresse_ville', e.adresse_ville,
      'adresse_code_postal', e.adresse_code_postal,
      'adresse_departement', e.adresse_departement,
      'adresse_rue', e.adresse_rue,
      'adresse_lat', e.adresse_lat,
      'adresse_lng', e.adresse_lng,
      'note_moyenne', e.note_moyenne,
      'convention_collective', e.convention_collective,
      'est_secteur_public', e.est_secteur_public,
      'finess', e.finess
    )), '[]'::jsonb)
    FROM etablissements e
    WHERE e.supprime_le IS NULL
      AND e.est_compte_test IS FALSE
      AND e.statut_verification = 'VERIFIE'
      AND EXISTS (
        SELECT 1
        FROM missions m
        WHERE m.etablissement_id = e.id
          AND m.statut = 'OUVERTE'
          AND private.fn_mission_lie_compte_test(m.id) IS FALSE
      )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_apercu_marche_profession(
  p_profession text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_rayon_km integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_geo boolean :=
    p_lat IS NOT NULL
    AND p_lng IS NOT NULL
    AND COALESCE(p_rayon_km, 0) > 0;
  v_nb_missions integer;
  v_taux_max numeric;
  v_taux_moyen numeric;
  v_nb_etabs integer;
BEGIN
  SELECT
    count(*)::integer,
    max(m.taux_horaire_base),
    round(avg(m.taux_horaire_base), 2)
  INTO v_nb_missions, v_taux_max, v_taux_moyen
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE'
    AND m.debut_le > now()
    AND e.supprime_le IS NULL
    AND e.est_compte_test IS FALSE
    AND private.fn_mission_lie_compte_test(m.id) IS FALSE
    AND (
      p_profession IS NULL
      OR btrim(p_profession) = ''
      OR m.profession_requise::text = btrim(p_profession)
    )
    AND (
      NOT v_geo
      OR (
        e.adresse_lat IS NOT NULL
        AND e.adresse_lng IS NOT NULL
        AND public.fn_haversine_distance_m(
          e.adresse_lat,
          e.adresse_lng,
          p_lat::numeric,
          p_lng::numeric
        ) <= p_rayon_km * 1000
      )
    );

  SELECT count(*)::integer
  INTO v_nb_etabs
  FROM etablissements e
  WHERE e.supprime_le IS NULL
    AND e.est_compte_test IS FALSE
    AND (
      NOT v_geo
      OR (
        e.adresse_lat IS NOT NULL
        AND e.adresse_lng IS NOT NULL
        AND public.fn_haversine_distance_m(
          e.adresse_lat,
          e.adresse_lng,
          p_lat::numeric,
          p_lng::numeric
        ) <= p_rayon_km * 1000
      )
    );

  RETURN jsonb_build_object(
    'nb_missions', COALESCE(v_nb_missions, 0),
    'taux_max', v_taux_max,
    'taux_moyen', v_taux_moyen,
    'nb_etablissements', COALESCE(v_nb_etabs, 0),
    'zone', CASE WHEN v_geo THEN 'rayon' ELSE 'national' END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_missions_publiques_etablissement(
  p_etablissement_id uuid
) RETURNS TABLE (
  id uuid,
  intitule text,
  profession_requise public.type_profession,
  debut_le timestamptz,
  fin_le timestamptz,
  taux_horaire_base numeric,
  service text,
  nom_etablissement text,
  ville_etablissement text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    m.id,
    m.intitule,
    m.profession_requise,
    m.debut_le,
    m.fin_le,
    m.taux_horaire_base,
    m.service,
    e.nom,
    e.adresse_ville
  FROM missions m
  JOIN etablissements e ON e.id = m.etablissement_id
  WHERE m.etablissement_id = p_etablissement_id
    AND m.statut = 'OUVERTE'
    AND e.supprime_le IS NULL
    AND e.est_compte_test IS FALSE
    AND private.fn_mission_lie_compte_test(m.id) IS FALSE
  ORDER BY m.debut_le
  LIMIT 10;
$function$;

REVOKE ALL ON FUNCTION public.fn_missions_publiques_etablissement(uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_missions_publiques_etablissement(uuid)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_etablissement_public(
  p_etablissement_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (
    SELECT jsonb_build_object(
      'id', e.id,
      'nom', e.nom,
      'type', e.type::text,
      'adresse_ville', e.adresse_ville,
      'adresse_code_postal', e.adresse_code_postal,
      'adresse_departement', e.adresse_departement,
      'adresse_rue', e.adresse_rue,
      'adresse_lat', e.adresse_lat,
      'adresse_lng', e.adresse_lng,
      'note_moyenne', e.note_moyenne,
      'convention_collective', e.convention_collective,
      'est_secteur_public', e.est_secteur_public,
      'finess', e.finess,
      'logo_url', e.logo_url,
      'couleur_theme', e.couleur_theme
    )
    FROM etablissements e
    WHERE e.id = p_etablissement_id
      AND e.supprime_le IS NULL
      AND e.est_compte_test IS FALSE
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_etablissements_safe(
  p_ids uuid[]
) RETURNS TABLE (
  id uuid,
  nom text,
  adresse_rue text,
  adresse_code_postal text,
  adresse_ville text,
  adresse_departement text,
  adresse_lat numeric,
  adresse_lng numeric,
  type text,
  finess text,
  taux_majoration_nuit_pourcent numeric,
  taux_majoration_dimanche_pourcent numeric,
  taux_majoration_ferie_pourcent numeric,
  logo_url text,
  couleur_theme text,
  paiement_rapide boolean,
  jour_paie_habituel smallint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT DISTINCT
    e.id,
    e.nom::text,
    e.adresse_rue::text,
    e.adresse_code_postal::text,
    e.adresse_ville::text,
    e.adresse_departement::text,
    e.adresse_lat,
    e.adresse_lng,
    e.type::text,
    e.finess::text,
    e.taux_majoration_nuit_pourcent,
    e.taux_majoration_dimanche_pourcent,
    e.taux_majoration_ferie_pourcent,
    e.logo_url::text,
    e.couleur_theme::text,
    (
      public.fn_param_num('feature_paiement_rapide_actif', 0) = 1
      AND e.mode_paiement_commission = 'SEPA_DEBIT'
      AND e.stripe_sepa_payment_method_id IS NOT NULL
      AND public.fn_escrow_etab_eligible(e.id)
    ) AS paiement_rapide,
    e.jour_paie_habituel
  FROM etablissements e
  WHERE e.id = ANY(p_ids)
    AND (
      est_admin()
      OR e.id = mon_etablissement_id()
      OR (
        est_soignant()
        AND private.fn_comptes_meme_cohorte_test(auth.uid(), e.id)
        AND (
          EXISTS (
            SELECT 1
            FROM missions m
            WHERE m.etablissement_id = e.id
              AND m.soignant_assigne_id = auth.uid()
          )
          OR EXISTS (
            SELECT 1
            FROM missions m
            WHERE m.etablissement_id = e.id
              AND m.statut = 'OUVERTE'
          )
        )
      )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_compteur_soignants_disponibles(
  p_etablissement_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer;
BEGIN
  IF NOT est_admin()
     AND public.fn_a_permission_etablissement(
       'lecture_missions',
       p_etablissement_id
     ) IS NOT TRUE THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT count(DISTINCT s.id)
  INTO v_count
  FROM soignants s
  WHERE s.supprime_le IS NULL
    AND private.fn_comptes_meme_cohorte_test(
      s.id,
      p_etablissement_id
    )
    AND s.derniere_activite_le > now() - interval '7 days'
    AND fn_documents_ok_pour_mission(s.id, 'TOUS')
    AND s.profession IN (
      SELECT DISTINCT profession_requise
      FROM missions
      WHERE etablissement_id = p_etablissement_id
        AND statut = 'OUVERTE'
    )
    AND NOT fn_est_exclu(s.id, p_etablissement_id);

  RETURN jsonb_build_object('disponibles', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_vivier_disponibilites(
  p_jour date,
  p_profession text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_etab_id uuid := mon_etablissement_id();
  v_etab record;
  v_nb integer;
  v_echantillon jsonb;
BEGIN
  IF v_etab_id IS NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Réservé aux établissements');
  END IF;
  IF p_jour IS NULL
     OR p_jour < current_date
     OR p_jour > current_date + 90 THEN
    RETURN jsonb_build_object('nb', 0);
  END IF;

  SELECT adresse_lat, adresse_lng
  INTO v_etab
  FROM etablissements
  WHERE id = v_etab_id;

  WITH dispo AS (
    SELECT DISTINCT
      s.id,
      s.prenom,
      s.score_fiabilite
    FROM soignants s
    JOIN disponibilites_soignant d
      ON d.soignant_id = s.id
     AND d.jour = p_jour
    WHERE s.supprime_le IS NULL
      AND (
        (
          v_etab_id IS NULL
          AND s.est_compte_test IS FALSE
        )
        OR (
          v_etab_id IS NOT NULL
          AND private.fn_comptes_meme_cohorte_test(s.id, v_etab_id)
        )
      )
      AND COALESCE(s.statut_compte::text, 'ACTIF') = 'ACTIF'
      AND COALESCE(s.tous_documents_valides, false)
      AND (
        p_profession IS NULL
        OR s.profession::text = p_profession
      )
      AND (
        v_etab_id IS NULL
        OR NOT fn_est_exclu(s.id, v_etab_id)
      )
      AND (
        s.adresse_lat IS NULL
        OR v_etab.adresse_lat IS NULL
        OR fn_haversine_distance_m(
          s.adresse_lat,
          s.adresse_lng,
          v_etab.adresse_lat,
          v_etab.adresse_lng
        ) <= COALESCE(s.rayon_deplacement_km, 50) * 1000
      )
  )
  SELECT
    count(*),
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'prenom', prenom,
          'score_fiabilite', score_fiabilite
        )
        ORDER BY score_fiabilite DESC NULLS LAST
      ) FILTER (WHERE rn <= 5),
      '[]'::jsonb
    )
  INTO v_nb, v_echantillon
  FROM (
    SELECT
      *,
      row_number() OVER (
        ORDER BY score_fiabilite DESC NULLS LAST
      ) AS rn
    FROM dispo
  ) t;

  RETURN jsonb_build_object(
    'nb', COALESCE(v_nb, 0),
    'echantillon', COALESCE(v_echantillon, '[]'::jsonb)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_rechercher_soignants_etab(
  p_profession text DEFAULT NULL,
  p_specialites text[] DEFAULT NULL,
  p_ville text DEFAULT NULL,
  p_distance_max_km integer DEFAULT NULL,
  p_type_exercice text DEFAULT NULL,
  p_note_min numeric DEFAULT NULL,
  p_score_min integer DEFAULT NULL,
  p_experience_min integer DEFAULT NULL,
  p_disponible_urgence boolean DEFAULT NULL,
  p_documents_valides boolean DEFAULT NULL,
  p_recherche_texte text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id uuid;
  v_etab_lat numeric;
  v_etab_lng numeric;
  v_limit integer;
  v_offset integer;
  v_result jsonb;
BEGIN
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL THEN
      RETURN jsonb_build_object(
        'error',
        'Accès refusé : étab requis'
      );
    END IF;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  IF v_etab_id IS NOT NULL
     AND p_distance_max_km IS NOT NULL THEN
    SELECT adresse_lat, adresse_lng
    INTO v_etab_lat, v_etab_lng
    FROM etablissements
    WHERE id = v_etab_id;
  END IF;

  WITH filtered AS (
    SELECT
      s.id,
      s.prenom,
      s.nom,
      s.profession,
      s.specialite_medicale,
      s.type_exercice,
      s.score_fiabilite,
      s.note_moyenne,
      s.nb_evaluations,
      s.total_missions_terminees,
      s.annees_experience,
      s.specialites,
      s.bio,
      s.avatar_url,
      s.rpps_verifie,
      s.tous_documents_valides,
      s.disponible_urgence,
      s.adresse_ville,
      s.priorite_missions_urgentes,
      s.badge_ambassadeur,
      CASE
        WHEN v_etab_lat IS NOT NULL
             AND s.adresse_lat IS NOT NULL THEN
          round((
            6371 * 2 * asin(sqrt(
              power(sin(radians(s.adresse_lat - v_etab_lat) / 2), 2)
              + cos(radians(v_etab_lat))
                * cos(radians(s.adresse_lat))
                * power(
                  sin(radians(s.adresse_lng - v_etab_lng) / 2),
                  2
                )
            ))
          )::numeric, 1)
        ELSE NULL
      END AS distance_km
    FROM soignants s
    WHERE s.supprime_le IS NULL
      AND (
        (
          v_etab_id IS NULL
          AND s.est_compte_test IS FALSE
        )
        OR (
          v_etab_id IS NOT NULL
          AND private.fn_comptes_meme_cohorte_test(s.id, v_etab_id)
        )
      )
      AND (
        p_profession IS NULL
        OR p_profession = ''
        OR s.profession::text = p_profession
      )
      AND (
        p_specialites IS NULL
        OR array_length(p_specialites, 1) IS NULL
        OR s.specialites && p_specialites
      )
      AND (
        p_ville IS NULL
        OR p_ville = ''
        OR s.adresse_ville ILIKE '%' || p_ville || '%'
      )
      AND (
        p_type_exercice IS NULL
        OR p_type_exercice = ''
        OR COALESCE(s.type_exercice, 'SALARIE') = p_type_exercice
      )
      AND (
        p_note_min IS NULL
        OR (
          COALESCE(s.nb_evaluations, 0) >= 3
          AND COALESCE(s.note_moyenne, 0) >= p_note_min
        )
      )
      AND (
        p_score_min IS NULL
        OR (
          COALESCE(s.total_missions_terminees, 0) >= 3
          AND COALESCE(s.score_fiabilite, 0) >= p_score_min
        )
      )
      AND (
        p_experience_min IS NULL
        OR COALESCE(s.annees_experience, 0) >= p_experience_min
      )
      AND (
        p_disponible_urgence IS NULL
        OR COALESCE(s.disponible_urgence, false) =
          p_disponible_urgence
      )
      AND (
        p_documents_valides IS NULL
        OR COALESCE(s.tous_documents_valides, false) =
          p_documents_valides
      )
      AND (
        p_recherche_texte IS NULL
        OR p_recherche_texte = ''
        OR s.prenom ILIKE '%' || p_recherche_texte || '%'
        OR COALESCE(s.bio, '') ILIKE
          '%' || p_recherche_texte || '%'
      )
  ),
  with_distance AS (
    SELECT *
    FROM filtered
    WHERE p_distance_max_km IS NULL
      OR distance_km IS NULL
      OR distance_km <= p_distance_max_km
  ),
  ranked AS (
    SELECT
      *,
      row_number() OVER (
        ORDER BY
          CASE
            WHEN COALESCE(total_missions_terminees, 0) >= 3
              THEN score_fiabilite
            ELSE -1
          END DESC NULLS LAST,
          CASE
            WHEN COALESCE(nb_evaluations, 0) >= 3
              THEN note_moyenne
            ELSE -1
          END DESC NULLS LAST,
          COALESCE(total_missions_terminees, 0) DESC,
          id
      ) AS rn,
      count(*) OVER () AS total_count
    FROM with_distance
  ),
  paged AS (
    SELECT *
    FROM ranked
    WHERE rn > v_offset
      AND rn <= v_offset + v_limit
  )
  SELECT jsonb_build_object(
    'soignants',
    COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'prenom', p.prenom,
      'nom_initiale', left(p.nom, 1) || '.',
      'profession', p.profession::text,
      'specialite_medicale', p.specialite_medicale,
      'type_exercice', COALESCE(p.type_exercice, 'SALARIE'),
      'score_fiabilite', CASE
        WHEN COALESCE(p.total_missions_terminees, 0) >= 3
          THEN p.score_fiabilite
        ELSE NULL
      END,
      'note_moyenne', CASE
        WHEN COALESCE(p.nb_evaluations, 0) >= 3
          THEN p.note_moyenne
        ELSE NULL
      END,
      'nb_evaluations', COALESCE(p.nb_evaluations, 0),
      'total_missions_terminees',
        COALESCE(p.total_missions_terminees, 0),
      'annees_experience', p.annees_experience,
      'specialites', COALESCE(p.specialites, ARRAY[]::text[]),
      'bio_extrait', left(COALESCE(p.bio, ''), 200),
      'avatar_url', p.avatar_url,
      'rpps_verifie', COALESCE(p.rpps_verifie, false),
      'tous_documents_valides',
        COALESCE(p.tous_documents_valides, false),
      'disponible_urgence', COALESCE(p.disponible_urgence, false),
      'ville', p.adresse_ville,
      'distance_km', p.distance_km,
      'priorite_missions_urgentes',
        COALESCE(p.priorite_missions_urgentes, false),
      'badge_ambassadeur',
        COALESCE(p.badge_ambassadeur, false)
    ) ORDER BY p.rn), '[]'::jsonb),
    'count_total', COALESCE(max(p.total_count), 0),
    'limit', v_limit,
    'offset', v_offset
  )
  INTO v_result
  FROM paged p;

  RETURN COALESCE(
    v_result,
    jsonb_build_object(
      'soignants', '[]'::jsonb,
      'count_total', 0,
      'limit', v_limit,
      'offset', v_offset
    )
  );
END;
$function$;

-- La fonction privée historique calcule encore quelques volumes toutes
-- données. Le wrapper conserve sa forme de réponse mais remplace chaque KPI
-- de pilotage par sa valeur réelle, ainsi que la série d'acquisition.
CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_fondateur()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public, auth
AS $function$
DECLARE
  v_result jsonb;
  v_argent jsonb;
  v_total_soignants integer;
  v_total_etabs integer;
  v_missions_terminees integer;
  v_acquisition_mensuelle jsonb;
  v_taux_activation_soignant numeric;
  v_taux_activation_etab numeric;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse au lancement' USING ERRCODE = '42501';
  END IF;

  v_result := private.fn_admin_cockpit_fondateur_interne_lancement();
  v_argent := public.fn_admin_metriques_argent();

  SELECT count(*) INTO v_total_soignants
    FROM public.soignants
   WHERE supprime_le IS NULL AND est_compte_test IS FALSE;
  SELECT count(*) INTO v_total_etabs
    FROM public.etablissements
   WHERE supprime_le IS NULL AND est_compte_test IS FALSE;
  SELECT count(*) INTO v_missions_terminees
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
   WHERE m.statut = 'TERMINEE'
     AND e.est_compte_test IS FALSE
     AND COALESCE(s.est_compte_test, false) IS FALSE;

  SELECT CASE WHEN v_total_soignants = 0 THEN 0 ELSE round(
    100.0 * count(DISTINCT c.soignant_id) / v_total_soignants, 1
  ) END
    INTO v_taux_activation_soignant
    FROM public.candidatures c
    JOIN public.soignants s ON s.id = c.soignant_id
    JOIN public.missions m ON m.id = c.mission_id
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE s.est_compte_test IS FALSE AND e.est_compte_test IS FALSE;

  SELECT CASE WHEN v_total_etabs = 0 THEN 0 ELSE round(
    100.0 * count(DISTINCT m.etablissement_id) / v_total_etabs, 1
  ) END
    INTO v_taux_activation_etab
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
   WHERE e.est_compte_test IS FALSE;

  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.mois), '[]'::jsonb)
    INTO v_acquisition_mensuelle
    FROM (
      SELECT to_char(gs.mois, 'YYYY-MM') AS mois,
        (
          SELECT count(*) FROM public.soignants s
           WHERE date_trunc('month', s.cree_le) = gs.mois
             AND s.est_compte_test IS FALSE
        ) AS soignants,
        (
          SELECT count(*) FROM public.etablissements e
           WHERE date_trunc('month', e.cree_le) = gs.mois
             AND e.supprime_le IS NULL
             AND e.est_compte_test IS FALSE
        ) AS etablissements
      FROM generate_series(
        date_trunc('month', now()) - interval '11 months',
        date_trunc('month', now()),
        interval '1 month'
      ) AS gs(mois)
    ) t;

  RETURN v_result || jsonb_build_object(
    'total_soignants', v_total_soignants,
    'total_etabs', v_total_etabs,
    'soignants_7j', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= now() - interval '7 days'
    ),
    'etabs_7j', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= now() - interval '7 days'
    ),
    'soignants_30j', (
      SELECT count(*) FROM public.soignants
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= now() - interval '30 days'
    ),
    'etabs_30j', (
      SELECT count(*) FROM public.etablissements
       WHERE supprime_le IS NULL AND est_compte_test IS FALSE
         AND cree_le >= now() - interval '30 days'
    ),
    'missions_terminees', v_missions_terminees,
    'missions_mois', (
      SELECT count(*)
        FROM public.missions m
        JOIN public.etablissements e ON e.id = m.etablissement_id
        LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
       WHERE m.statut = 'TERMINEE'
         AND m.debut_le >= date_trunc('month', now())
         AND e.est_compte_test IS FALSE
         AND COALESCE(s.est_compte_test, false) IS FALSE
    ),
    'gmv_total', COALESCE((v_argent #>> '{gmv,total_reel}')::numeric, 0),
    'revenue_total', COALESCE((v_argent #>> '{commission,total_reel}')::numeric, 0),
    'revenue_mois', COALESCE((v_argent #>> '{commission,mois_reel}')::numeric, 0),
    'taux_activation_soignant', COALESCE(v_taux_activation_soignant, 0),
    'taux_activation_etab', COALESCE(v_taux_activation_etab, 0),
    'acquisition_mensuelle', v_acquisition_mensuelle
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_cockpit_fondateur()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_cockpit_fondateur()
  TO authenticated, service_role;

-- Une invitation reste visible dans l'application de recette mais ne doit pas
-- déclencher d'email vers une adresse externe depuis un établissement test.
CREATE OR REPLACE FUNCTION public.dec_email_invitation_equipe_etab()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_etab_nom text;
  v_invite_par_email text;
  v_invite_par_nom text;
BEGIN
  IF NEW.statut <> 'EN_ATTENTE' THEN
    RETURN NEW;
  END IF;

  SELECT e.nom
    INTO v_etab_nom
    FROM public.etablissements e
   WHERE e.id = NEW.etablissement_id
     AND e.est_compte_test IS FALSE;
  IF v_etab_nom IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT u.email INTO v_invite_par_email
    FROM auth.users u WHERE u.id = NEW.invite_par;
  v_invite_par_nom := COALESCE(v_invite_par_email, 'Un administrateur');

  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret FROM vault.decrypted_secrets
           WHERE name = 'service_role_key' LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'type', 'INVITATION_EQUIPE_ETAB',
        'destinataire_email', NEW.email_invite,
        'idempotency_key', 'invitation-equipe-etab:' || NEW.id::text,
        'data', jsonb_build_object(
          'token', NEW.token,
          'nom_etablissement', v_etab_nom,
          'role', NEW.role_propose,
          'invite_par_nom', v_invite_par_nom,
          'expire_le', to_char(
            NEW.expire_le AT TIME ZONE 'Europe/Paris',
            'DD/MM/YYYY à HH24:MI'
          )
        )
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    NEW.invite_par, 'SYSTEME', 'SYSTEM', 'invitation_etab', NEW.id,
    jsonb_build_object(
      'evenement', 'EMAIL_INVITATION_EQUIPE_ENVOYE',
      'destinataire_email', NEW.email_invite,
      'etablissement_id', NEW.etablissement_id,
      'role_propose', NEW.role_propose
    )
  );

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.dec_email_invitation_equipe_etab()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dec_email_invitation_equipe_etab()
  TO service_role;

-- Réservation atomique avant mise en file et clé stable côté send-email :
-- deux exécutions concurrentes du cron ne peuvent plus produire deux rappels.
CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_notation_j1()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_url text;
  v_token text;
  v_mission record;
  v_count_etab integer := 0;
  v_count_soignant integer := 0;
  v_send_email_called boolean;
  v_reserved boolean;
BEGIN
  IF NOT (
    est_admin()
    OR COALESCE(
      current_setting('request.jwt.claim.role', true),
      ''
    ) = 'service_role'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  BEGIN
    SELECT NULLIF(btrim(ds.decrypted_secret), '')
      INTO v_url
      FROM vault.decrypted_secrets ds
     WHERE ds.name = 'supabase_url'
     LIMIT 1;
    v_token := public.fn_lire_secret_cron();
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL;
    v_token := NULL;
  END;

  FOR v_mission IN
    SELECT
      m.id,
      m.intitule,
      m.fin_le,
      m.etablissement_id,
      m.soignant_assigne_id
    FROM missions m
    JOIN etablissements e ON e.id = m.etablissement_id
    JOIN soignants s ON s.id = m.soignant_assigne_id
    WHERE m.statut = 'TERMINEE'
      AND m.fin_le >= now() - interval '48 hours'
      AND m.fin_le < now() - interval '24 hours'
      AND e.est_compte_test IS FALSE
      AND s.est_compte_test IS FALSE
  LOOP
    -- Côté établissement : le conflit unique constitue la réservation.
    IF NOT EXISTS (
      SELECT 1
      FROM notations_missions
      WHERE mission_id = v_mission.id
        AND sens = 'ETAB_VERS_SOIGNANT'
    ) AND public.fn_doit_notifier(
      v_mission.etablissement_id,
      'NOTATION_RAPPEL'::type_evenement_notification,
      'EMAIL'::canal_notification
    ) THEN
      v_reserved := false;
      INSERT INTO notifications_notation_j1 (
        mission_id,
        sens,
        destinataire_id
      ) VALUES (
        v_mission.id,
        'ETAB_VERS_SOIGNANT',
        v_mission.etablissement_id
      )
      ON CONFLICT (mission_id, sens) DO NOTHING
      RETURNING true INTO v_reserved;

      IF COALESCE(v_reserved, false) THEN
        v_send_email_called := false;
        IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
          BEGIN
            PERFORM net.http_post(
              url := v_url || '/functions/v1/send-email',
              headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || v_token
              ),
              body := jsonb_build_object(
                'type', 'RAPPEL_NOTATION_ETAB',
                'destinataire_id', v_mission.etablissement_id,
                'idempotency_key',
                  'notation-j1:etab-vers-soignant:' || v_mission.id::text,
                'data', jsonb_build_object(
                  'mission_id', v_mission.id,
                  'mission_intitule', v_mission.intitule,
                  'fin_le', v_mission.fin_le
                )
              )
            );
            v_send_email_called := true;
          EXCEPTION WHEN OTHERS THEN
            DELETE FROM notifications_notation_j1
             WHERE mission_id = v_mission.id
               AND sens = 'ETAB_VERS_SOIGNANT';
          END;
        ELSE
          DELETE FROM notifications_notation_j1
           WHERE mission_id = v_mission.id
             AND sens = 'ETAB_VERS_SOIGNANT';
        END IF;

        IF v_send_email_called THEN
          PERFORM public.fn_ecrire_audit_safe(
            p_acteur_id := v_mission.etablissement_id,
            p_type_acteur := 'SYSTEME',
            p_action := 'RAPPEL_NOTATION_J1_ENVOYE',
            p_type_ressource := 'mission',
            p_id_ressource := v_mission.id,
            p_details := jsonb_build_object(
              'sens', 'ETAB_VERS_SOIGNANT',
              'send_email_called', true,
              'idempotency_key',
                'notation-j1:etab-vers-soignant:' || v_mission.id::text
            )
          );
          v_count_etab := v_count_etab + 1;
        END IF;
      END IF;
    END IF;

    -- Côté soignant : même réservation, avec une clé indépendante par sens.
    IF NOT EXISTS (
      SELECT 1
      FROM notations_missions
      WHERE mission_id = v_mission.id
        AND sens = 'SOIGNANT_VERS_ETAB'
    ) AND public.fn_doit_notifier(
      v_mission.soignant_assigne_id,
      'NOTATION_RAPPEL'::type_evenement_notification,
      'EMAIL'::canal_notification
    ) THEN
      v_reserved := false;
      INSERT INTO notifications_notation_j1 (
        mission_id,
        sens,
        destinataire_id
      ) VALUES (
        v_mission.id,
        'SOIGNANT_VERS_ETAB',
        v_mission.soignant_assigne_id
      )
      ON CONFLICT (mission_id, sens) DO NOTHING
      RETURNING true INTO v_reserved;

      IF COALESCE(v_reserved, false) THEN
        v_send_email_called := false;
        IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
          BEGIN
            PERFORM net.http_post(
              url := v_url || '/functions/v1/send-email',
              headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || v_token
              ),
              body := jsonb_build_object(
                'type', 'RAPPEL_NOTATION_SOIGNANT',
                'destinataire_id', v_mission.soignant_assigne_id,
                'idempotency_key',
                  'notation-j1:soignant-vers-etab:' || v_mission.id::text,
                'data', jsonb_build_object(
                  'mission_id', v_mission.id,
                  'mission_intitule', v_mission.intitule,
                  'fin_le', v_mission.fin_le
                )
              )
            );
            v_send_email_called := true;
          EXCEPTION WHEN OTHERS THEN
            DELETE FROM notifications_notation_j1
             WHERE mission_id = v_mission.id
               AND sens = 'SOIGNANT_VERS_ETAB';
          END;
        ELSE
          DELETE FROM notifications_notation_j1
           WHERE mission_id = v_mission.id
             AND sens = 'SOIGNANT_VERS_ETAB';
        END IF;

        IF v_send_email_called THEN
          PERFORM public.fn_ecrire_audit_safe(
            p_acteur_id := v_mission.soignant_assigne_id,
            p_type_acteur := 'SYSTEME',
            p_action := 'RAPPEL_NOTATION_J1_ENVOYE',
            p_type_ressource := 'mission',
            p_id_ressource := v_mission.id,
            p_details := jsonb_build_object(
              'sens', 'SOIGNANT_VERS_ETAB',
              'send_email_called', true,
              'idempotency_key',
                'notation-j1:soignant-vers-etab:' || v_mission.id::text
            )
          );
          v_count_soignant := v_count_soignant + 1;
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'count_etab', v_count_etab,
    'count_soignant', v_count_soignant
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_envoyer_rappels_notation_j1()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_rappels_notation_j1()
  TO service_role;

-- Suivi durable du résultat HTTP pg_net. Une ligne notifications_notation_j1
-- n'est désormais créée qu'après réponse 2xx de send-email, jamais au simple
-- enqueue. La clé stable protège aussi les reprises après perte de réponse.
CREATE TABLE IF NOT EXISTS private.notation_email_dispatch (
  mission_id uuid NOT NULL
    REFERENCES public.missions(id) ON DELETE CASCADE,
  sens public.sens_notation NOT NULL,
  destinataire_id uuid NOT NULL,
  idempotency_key text NOT NULL UNIQUE
    CHECK (idempotency_key ~
      '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'),
  statut text NOT NULL DEFAULT 'A_ENVOYER'
    CHECK (statut IN (
      'A_ENVOYER',
      'EN_ATTENTE',
      'REESSAI',
      'ENVOYE',
      'ANNULE',
      'ECHEC'
    )),
  tentatives integer NOT NULL DEFAULT 0
    CHECK (tentatives BETWEEN 0 AND 5),
  request_id bigint,
  demande_le timestamptz,
  prochaine_tentative_le timestamptz NOT NULL DEFAULT now(),
  statut_http integer,
  erreur_transport text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (mission_id, sens)
);

CREATE INDEX IF NOT EXISTS idx_notation_email_dispatch_a_traiter
  ON private.notation_email_dispatch (
    statut,
    prochaine_tentative_le
  )
  WHERE statut IN ('A_ENVOYER', 'REESSAI', 'EN_ATTENTE');

ALTER TABLE private.notation_email_dispatch ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.notation_email_dispatch FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.notation_email_dispatch
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE private.notation_email_dispatch TO service_role;

CREATE OR REPLACE FUNCTION private.fn_controler_rappels_notation_j1()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_dispatch record;
  v_count_etab integer := 0;
  v_count_soignant integer := 0;
  v_reessais integer := 0;
  v_echecs integer := 0;
  v_delai interval;
BEGIN
  FOR v_dispatch IN
    SELECT
      q.mission_id,
      q.sens,
      q.destinataire_id,
      q.idempotency_key,
      q.tentatives,
      q.demande_le,
      r.status_code,
      r.timed_out,
      r.error_msg
    FROM private.notation_email_dispatch q
    LEFT JOIN net._http_response r ON r.id = q.request_id
    WHERE q.statut = 'EN_ATTENTE'
      AND (
        r.id IS NOT NULL
        OR q.demande_le < now() - interval '10 minutes'
      )
    ORDER BY q.demande_le
    FOR UPDATE OF q SKIP LOCKED
  LOOP
    IF v_dispatch.status_code BETWEEN 200 AND 299
       AND COALESCE(v_dispatch.timed_out, false) IS FALSE
       AND v_dispatch.error_msg IS NULL THEN
      INSERT INTO public.notifications_notation_j1 (
        mission_id,
        sens,
        destinataire_id
      ) VALUES (
        v_dispatch.mission_id,
        v_dispatch.sens,
        v_dispatch.destinataire_id
      )
      ON CONFLICT (mission_id, sens) DO NOTHING;

      UPDATE private.notation_email_dispatch
      SET statut = 'ENVOYE',
          statut_http = v_dispatch.status_code,
          erreur_transport = NULL,
          modifie_le = now()
      WHERE mission_id = v_dispatch.mission_id
        AND sens = v_dispatch.sens;

      PERFORM public.fn_ecrire_audit_safe(
        p_acteur_id := v_dispatch.destinataire_id,
        p_type_acteur := 'SYSTEME',
        p_action := 'RAPPEL_NOTATION_J1_ENVOYE',
        p_type_ressource := 'mission',
        p_id_ressource := v_dispatch.mission_id,
        p_details := jsonb_build_object(
          'sens', v_dispatch.sens,
          'statut_http', v_dispatch.status_code,
          'tentatives', v_dispatch.tentatives,
          'idempotency_key', v_dispatch.idempotency_key
        )
      );

      IF v_dispatch.sens = 'ETAB_VERS_SOIGNANT' THEN
        v_count_etab := v_count_etab + 1;
      ELSE
        v_count_soignant := v_count_soignant + 1;
      END IF;
    ELSE
      IF v_dispatch.tentatives >= 5 THEN
        UPDATE private.notation_email_dispatch
        SET statut = 'ECHEC',
            statut_http = v_dispatch.status_code,
            erreur_transport = left(
              COALESCE(
                v_dispatch.error_msg,
                'Réponse HTTP absente ou non 2xx'
              ),
              500
            ),
            modifie_le = now()
        WHERE mission_id = v_dispatch.mission_id
          AND sens = v_dispatch.sens;
        v_echecs := v_echecs + 1;

        BEGIN
          PERFORM public.fn_emettre_alerte_monitoring(
            'RAPPEL_NOTATION_HTTP_FAILED',
            'CRITICAL',
            v_dispatch.mission_id::text || ':' || v_dispatch.sens::text,
            format(
              'Rappel notation en échec après %s tentatives (HTTP %s)',
              v_dispatch.tentatives,
              COALESCE(v_dispatch.status_code::text, 'aucune réponse')
            ),
            jsonb_build_object(
              'mission_id', v_dispatch.mission_id,
              'sens', v_dispatch.sens,
              'status_code', v_dispatch.status_code,
              'error_msg', v_dispatch.error_msg
            )
          );
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      ELSE
        v_delai := CASE v_dispatch.tentatives
          WHEN 1 THEN interval '5 minutes'
          WHEN 2 THEN interval '15 minutes'
          WHEN 3 THEN interval '30 minutes'
          ELSE interval '1 hour'
        END;

        UPDATE private.notation_email_dispatch
        SET statut = 'REESSAI',
            statut_http = v_dispatch.status_code,
            erreur_transport = left(
              COALESCE(
                v_dispatch.error_msg,
                'Réponse HTTP absente ou non 2xx'
              ),
              500
            ),
            prochaine_tentative_le = now() + v_delai,
            modifie_le = now()
        WHERE mission_id = v_dispatch.mission_id
          AND sens = v_dispatch.sens;
        v_reessais := v_reessais + 1;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'count_etab', v_count_etab,
    'count_soignant', v_count_soignant,
    'reessais', v_reessais,
    'echecs', v_echecs
  );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_controler_rappels_notation_j1()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_controler_rappels_notation_j1()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_envoyer_rappels_notation_j1()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_url text;
  v_token text;
  v_dispatch record;
  v_request_id bigint;
  v_nouvelles integer := 0;
  v_enfilees integer := 0;
  v_echecs_enfilement integer := 0;
  v_controle jsonb;
BEGIN
  IF NOT (
    est_admin()
    OR COALESCE(
      current_setting('request.jwt.claim.role', true),
      ''
    ) = 'service_role'
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès refusé');
  END IF;

  v_controle := private.fn_controler_rappels_notation_j1();

  INSERT INTO private.notation_email_dispatch (
    mission_id,
    sens,
    destinataire_id,
    idempotency_key
  )
  SELECT
    m.id,
    cible.sens::public.sens_notation,
    cible.destinataire_id,
    CASE cible.sens
      WHEN 'ETAB_VERS_SOIGNANT'
        THEN 'notation-j1:etab-vers-soignant:' || m.id::text
      ELSE 'notation-j1:soignant-vers-etab:' || m.id::text
    END
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  JOIN public.soignants s ON s.id = m.soignant_assigne_id
  CROSS JOIN LATERAL (
    VALUES
      ('ETAB_VERS_SOIGNANT', m.etablissement_id),
      ('SOIGNANT_VERS_ETAB', m.soignant_assigne_id)
  ) AS cible(sens, destinataire_id)
  WHERE m.statut = 'TERMINEE'
    AND m.fin_le >= now() - interval '48 hours'
    AND m.fin_le < now() - interval '24 hours'
    AND e.est_compte_test IS FALSE
    AND s.est_compte_test IS FALSE
    AND NOT EXISTS (
      SELECT 1
      FROM public.notations_missions n
      WHERE n.mission_id = m.id
        AND n.sens = cible.sens::public.sens_notation
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.notifications_notation_j1 j
      WHERE j.mission_id = m.id
        AND j.sens = cible.sens::public.sens_notation
    )
    AND public.fn_doit_notifier(
      cible.destinataire_id,
      'NOTATION_RAPPEL'::public.type_evenement_notification,
      'EMAIL'::public.canal_notification
    )
  ON CONFLICT (mission_id, sens) DO NOTHING;
  GET DIAGNOSTICS v_nouvelles = ROW_COUNT;

  -- Une notation déposée entre la réservation et l'envoi annule le rappel.
  UPDATE private.notation_email_dispatch q
  SET statut = 'ANNULE',
      modifie_le = now()
  WHERE q.statut IN ('A_ENVOYER', 'REESSAI')
    AND (
      EXISTS (
        SELECT 1
        FROM public.notations_missions n
        WHERE n.mission_id = q.mission_id
          AND n.sens = q.sens
      )
      OR NOT EXISTS (
        SELECT 1
        FROM public.missions m
        JOIN public.etablissements e ON e.id = m.etablissement_id
        JOIN public.soignants s ON s.id = m.soignant_assigne_id
        WHERE m.id = q.mission_id
          AND e.est_compte_test IS FALSE
          AND s.est_compte_test IS FALSE
      )
    );

  BEGIN
    SELECT NULLIF(btrim(ds.decrypted_secret), '')
    INTO v_url
    FROM vault.decrypted_secrets ds
    WHERE ds.name = 'supabase_url'
    LIMIT 1;
    v_token := public.fn_lire_secret_cron();
  EXCEPTION WHEN OTHERS THEN
    v_url := NULL;
    v_token := NULL;
  END;

  IF v_url IS NULL OR v_token IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Configuration email cron indisponible',
      'nouvelles', v_nouvelles,
      'controle', v_controle
    );
  END IF;

  FOR v_dispatch IN
    SELECT
      q.mission_id,
      q.sens,
      q.destinataire_id,
      q.idempotency_key,
      q.tentatives,
      m.intitule,
      m.fin_le
    FROM private.notation_email_dispatch q
    JOIN public.missions m ON m.id = q.mission_id
    JOIN public.etablissements e ON e.id = m.etablissement_id
    JOIN public.soignants s ON s.id = m.soignant_assigne_id
    WHERE q.statut IN ('A_ENVOYER', 'REESSAI')
      AND q.prochaine_tentative_le <= now()
      AND q.tentatives < 5
      AND e.est_compte_test IS FALSE
      AND s.est_compte_test IS FALSE
    ORDER BY q.prochaine_tentative_le, q.cree_le
    LIMIT 200
    FOR UPDATE OF q SKIP LOCKED
  LOOP
    BEGIN
      SELECT net.http_post(
        url := v_url || '/functions/v1/send-email',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_token
        ),
        body := jsonb_build_object(
          'type', CASE v_dispatch.sens
            WHEN 'ETAB_VERS_SOIGNANT'
              THEN 'RAPPEL_NOTATION_ETAB'
            ELSE 'RAPPEL_NOTATION_SOIGNANT'
          END,
          'destinataire_id', v_dispatch.destinataire_id,
          'idempotency_key', v_dispatch.idempotency_key,
          'data', jsonb_build_object(
            'mission_id', v_dispatch.mission_id,
            'mission_intitule', v_dispatch.intitule,
            'fin_le', v_dispatch.fin_le
          )
        ),
        timeout_milliseconds := 55000
      ) INTO v_request_id;

      UPDATE private.notation_email_dispatch
      SET statut = 'EN_ATTENTE',
          tentatives = tentatives + 1,
          request_id = v_request_id,
          demande_le = now(),
          statut_http = NULL,
          erreur_transport = NULL,
          modifie_le = now()
      WHERE mission_id = v_dispatch.mission_id
        AND sens = v_dispatch.sens;
      v_enfilees := v_enfilees + 1;
    EXCEPTION WHEN OTHERS THEN
      IF v_dispatch.tentatives >= 4 THEN
        UPDATE private.notation_email_dispatch
        SET statut = 'ECHEC',
            tentatives = 5,
            erreur_transport = left(SQLERRM, 500),
            modifie_le = now()
        WHERE mission_id = v_dispatch.mission_id
          AND sens = v_dispatch.sens;
        v_echecs_enfilement := v_echecs_enfilement + 1;

        BEGIN
          PERFORM public.fn_emettre_alerte_monitoring(
            'RAPPEL_NOTATION_ENQUEUE_FAILED',
            'CRITICAL',
            v_dispatch.mission_id::text || ':' || v_dispatch.sens::text,
            'Impossible de remettre le rappel notation dans pg_net après 5 tentatives',
            jsonb_build_object(
              'mission_id', v_dispatch.mission_id,
              'sens', v_dispatch.sens,
              'erreur', left(SQLERRM, 500)
            )
          );
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      ELSE
        UPDATE private.notation_email_dispatch
        SET statut = 'REESSAI',
            tentatives = tentatives + 1,
            erreur_transport = left(SQLERRM, 500),
            prochaine_tentative_le = now() + interval '5 minutes',
            modifie_le = now()
        WHERE mission_id = v_dispatch.mission_id
          AND sens = v_dispatch.sens;
      END IF;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'count_etab', COALESCE((v_controle->>'count_etab')::integer, 0),
    'count_soignant',
      COALESCE((v_controle->>'count_soignant')::integer, 0),
    'nouvelles', v_nouvelles,
    'enfilees', v_enfilees,
    'reessais_planifies',
      COALESCE((v_controle->>'reessais')::integer, 0),
    'echecs',
      COALESCE((v_controle->>'echecs')::integer, 0)
      + v_echecs_enfilement
  );
END;
$function$;

-- Les alertes de litige portent la mission : notify-support peut ainsi
-- classifier les deux parties avant tout email à l'équipe support.
CREATE OR REPLACE FUNCTION public.fn_trg_litige_notify_support()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_url text;
  v_token text;
BEGIN
  BEGIN
    SELECT NULLIF(btrim(ds.decrypted_secret), '')
      INTO v_url
      FROM vault.decrypted_secrets ds
     WHERE ds.name = 'supabase_url'
     LIMIT 1;
    v_token := public.fn_lire_secret_cron();

    IF v_token IS NOT NULL AND v_url IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-support',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_token
        ),
        body := jsonb_build_object(
          'sujet',
            'Nouveau litige ouvert ('
              || COALESCE(NEW.type_litige::text, '')
              || ')',
          'corps', COALESCE(NEW.motif, '(sans motif)'),
          'source', 'Litige',
          'lien', '/admin/litiges',
          'mission_id', NEW.mission_id
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_trg_litige_notify_support()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_litige_notify_support()
  TO service_role;

-- Les tripwires « premier euro » n'ont par nature aucun expéditeur. Leur seul
-- contournement du résolveur est une classe système explicite, transmise avec
-- une source fixe que l'Edge place sur liste blanche après authentification.
CREATE OR REPLACE FUNCTION public.fn_tripwire_alerte(
  p_sujet text,
  p_corps text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_url text;
  v_token text;
BEGIN
  IF public.fn_param_num('alertes_tripwire_actives', 1) <> 1 THEN
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.alertes_systeme (
      type_alerte,
      severite,
      source,
      message,
      details,
      occurrences,
      derniere_occurrence,
      email_envoye_le
    ) VALUES (
      'TRIPWIRE_PREMIER_EURO',
      'CRITICAL',
      p_sujet,
      p_sujet,
      jsonb_build_object('corps', p_corps),
      1,
      now(),
      now()
    )
    ON CONFLICT (source, type_alerte) WHERE resolu_le IS NULL
    DO UPDATE SET
      occurrences = alertes_systeme.occurrences + 1,
      derniere_occurrence = now(),
      email_envoye_le = now(),
      details = EXCLUDED.details;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  BEGIN
    SELECT NULLIF(btrim(ds.decrypted_secret), '')
      INTO v_url
      FROM vault.decrypted_secrets ds
     WHERE ds.name = 'supabase_url'
     LIMIT 1;
    v_token := public.fn_lire_secret_cron();

    IF v_token IS NOT NULL AND v_url IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/notify-support',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_token
        ),
        body := jsonb_build_object(
          'sujet', p_sujet,
          'corps', p_corps,
          'source', 'tripwire-paiement',
          'system_alert', true
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_tripwire_alerte(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_tripwire_alerte(text, text)
  TO service_role;

-- Les trois tripwires ne représentent que le premier événement d'une cohorte
-- réelle. Une fixture ne déclenche aucune alerte et ne consomme pas non plus le
-- « premier » événement dans le NOT EXISTS historique.
CREATE OR REPLACE FUNCTION public.fn_trg_tripwire_premier_mandat_sepa()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.stripe_sepa_payment_method_id IS NULL
     OR NEW.est_compte_test IS DISTINCT FROM false
  THEN
    RETURN NEW;
  END IF;
  IF TG_OP <> 'INSERT' THEN
    IF OLD.stripe_sepa_payment_method_id IS NOT NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.etablissements e
     WHERE e.stripe_sepa_payment_method_id IS NOT NULL
       AND e.est_compte_test IS FALSE
       AND e.id <> NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM public.fn_tripwire_alerte(
    '[TRIPWIRE] Premier mandat SEPA posé',
    'Le premier établissement vient de poser son mandat SEPA (paiement rapide ⚡). Établissement id: '
      || NEW.id
      || '. Le rail d''encaissement est désormais actif — à surveiller.'
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_trg_tripwire_premier_mandat_sepa()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_tripwire_premier_mandat_sepa()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_trg_tripwire_premier_connect_complet()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.statut IS DISTINCT FROM 'COMPLET' THEN
    RETURN NEW;
  END IF;
  IF TG_OP <> 'INSERT' THEN
    IF OLD.statut IS NOT DISTINCT FROM 'COMPLET' THEN
      RETURN NEW;
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.soignants s
     WHERE s.id = NEW.soignant_id
       AND s.est_compte_test IS FALSE
  ) THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.stripe_connect_onboarding o
      JOIN public.soignants s ON s.id = o.soignant_id
     WHERE o.statut = 'COMPLET'
       AND s.est_compte_test IS FALSE
       AND o.id <> NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM public.fn_tripwire_alerte(
    '[TRIPWIRE] Premier compte Connect complété',
    'Le premier soignant vient de compléter son onboarding Stripe Connect. Soignant id: '
      || NEW.soignant_id
      || '. Il peut désormais recevoir des virements — à surveiller.'
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_trg_tripwire_premier_connect_complet()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_tripwire_premier_connect_complet()
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_trg_tripwire_premier_payment_intent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.stripe_payment_intent_id IS NULL
     OR NEW.stripe_payment_intent_id LIKE 'pi_pwtest%'
  THEN
    RETURN NEW;
  END IF;
  IF TG_OP <> 'INSERT' THEN
    IF OLD.stripe_payment_intent_id IS NOT NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM public.missions m
      JOIN public.etablissements e
        ON e.id = m.etablissement_id
      JOIN public.soignants s
        ON s.id = m.soignant_assigne_id
     WHERE m.id = NEW.mission_id
       AND m.etablissement_id = NEW.etablissement_id
       AND m.soignant_assigne_id = NEW.soignant_id
       AND e.est_compte_test IS FALSE
       AND s.est_compte_test IS FALSE
  ) THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.paiements_escrow p
      JOIN public.missions m
        ON m.id = p.mission_id
       AND m.etablissement_id = p.etablissement_id
       AND m.soignant_assigne_id = p.soignant_id
      JOIN public.etablissements e
        ON e.id = m.etablissement_id
      JOIN public.soignants s
        ON s.id = m.soignant_assigne_id
     WHERE p.stripe_payment_intent_id IS NOT NULL
       AND p.stripe_payment_intent_id NOT LIKE 'pi_pwtest%'
       AND e.est_compte_test IS FALSE
       AND s.est_compte_test IS FALSE
       AND p.id <> NEW.id
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM public.fn_tripwire_alerte(
    '[TRIPWIRE] Premier PaymentIntent réel créé',
    'Le premier débit escrow réel vient d''être initié. Escrow id: '
      || NEW.id
      || ', mission: '
      || NEW.mission_id
      || ', PI: '
      || NEW.stripe_payment_intent_id
      || '. Le premier euro réel circule — À REGARDER.'
  );
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_trg_tripwire_premier_payment_intent()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_tripwire_premier_payment_intent()
  TO service_role;

-- Deux producteurs SQL historiques appellent désormais les dispatchers
-- internes qui exigent une clé d'idempotence. Ils sont recapturés ici afin
-- qu'aucun OTP ni aucune alerte urgente ne casse ou ne soit rejoué.
CREATE OR REPLACE FUNCTION public.fn_envoyer_otp_signature(
  p_contrat_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_contrat record;
  v_role text;
  v_otp text;
  v_otp_hash text;
  v_telephone text;
  v_sig_existante record;
  v_sms_count integer;
  v_sms_window_start timestamptz;
  v_ip inet;
  v_rate_check jsonb;
  v_idempotency_key text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'NON_AUTHENTIFIE',
      'error', 'Non authentifié'
    );
  END IF;

  v_ip := NULLIF(
    current_setting('request.headers', true)::jsonb->>'x-forwarded-for',
    ''
  )::inet;
  v_rate_check := public.fn_check_rate_limit_ip_signature(v_ip);
  IF NOT (v_rate_check->>'allowed')::boolean THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TROP_DE_SMS_IP',
      'error', 'Trop de demandes de signature depuis votre IP. Réessayez dans 1h.',
      'envois_courant', v_rate_check->>'envois_courant',
      'max', v_rate_check->>'max'
    );
  END IF;

  SELECT
    cm.id,
    cm.soignant_id,
    cm.etablissement_id,
    cm.contenu_html,
    cm.statut,
    cm.signature_soignant,
    cm.signature_etablissement
    INTO v_contrat
    FROM public.contrats_mission cm
   WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'CONTRAT_INTROUVABLE',
      'error', 'Contrat introuvable'
    );
  END IF;
  IF v_contrat.statut IN ('ANNULE', 'EXPIRE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'CONTRAT_INACTIF',
      'error', 'Ce contrat n''est plus actif (statut : '
        || v_contrat.statut || ').'
    );
  END IF;
  IF v_contrat.statut = 'SIGNE_COMPLET' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'CONTRAT_DEJA_COMPLET',
      'error', 'Ce contrat est déjà entièrement signé.'
    );
  END IF;

  IF v_contrat.soignant_id = v_uid THEN
    v_role := 'soignant';
    SELECT telephone
      INTO v_telephone
      FROM public.soignants
     WHERE id = v_uid;
  ELSIF v_contrat.etablissement_id = v_uid
     OR public.mon_etablissement_id() = v_contrat.etablissement_id THEN
    v_role := 'etablissement';
    SELECT telephone_contact
      INTO v_telephone
      FROM public.etablissements
     WHERE id = v_contrat.etablissement_id;
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'NON_AUTORISE',
      'error', 'Non autorisé à signer ce contrat'
    );
  END IF;

  IF v_role = 'etablissement'
     AND v_contrat.signature_soignant IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'ETAB_AVANT_SOIGNANT',
      'error', 'Le soignant doit signer en premier. Vous serez notifié(e) par email dès qu''il aura signé.'
    );
  END IF;
  IF v_telephone IS NULL OR v_telephone = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'TELEPHONE_MANQUANT',
      'error', 'Numéro de téléphone manquant. Mettez à jour votre profil avant de signer.'
    );
  END IF;

  -- Deux requêtes simultanées ne peuvent plus écraser le code envoyé par
  -- l'autre ni réutiliser la même clé avec un contenu différent.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_contrat_id::text || ':' || v_role,
      618337
    )
  );

  SELECT
    sms_envoyes_count,
    sms_premier_envoi_a,
    statut_signature
    INTO v_sig_existante
    FROM public.signatures_contrats
   WHERE contrat_id = p_contrat_id
     AND signataire_role = v_role;

  IF FOUND THEN
    IF v_sig_existante.statut_signature = 'signe' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error_code', 'DEJA_SIGNE',
        'error', 'Vous avez déjà signé ce contrat.'
      );
    END IF;
    IF v_sig_existante.sms_premier_envoi_a IS NULL
       OR v_sig_existante.sms_premier_envoi_a
          < now() - interval '24 hours' THEN
      v_sms_count := 1;
      v_sms_window_start := now();
    ELSE
      v_sms_count := COALESCE(v_sig_existante.sms_envoyes_count, 0) + 1;
      v_sms_window_start := v_sig_existante.sms_premier_envoi_a;
      IF v_sms_count > 3 THEN
        RETURN jsonb_build_object(
          'success', false,
          'error_code', 'TROP_DE_SMS',
          'error', 'Trop de SMS envoyés (3 max / 24h).',
          'sms_envoyes', v_sms_count - 1,
          'reset_le',
            (
              v_sig_existante.sms_premier_envoi_a
              + interval '24 hours'
            )::text
        );
      END IF;
    END IF;
  ELSE
    v_sms_count := 1;
    v_sms_window_start := now();
  END IF;

  v_otp := lpad(floor(random() * 1000000)::text, 6, '0');
  v_otp_hash := encode(
    digest(
      v_otp || '|' || p_contrat_id::text || '|' || v_uid::text,
      'sha256'
    ),
    'hex'
  );

  INSERT INTO public.signatures_contrats (
    contrat_id,
    signataire_user_id,
    signataire_role,
    otp_envoye_a,
    otp_code_hash,
    statut_signature,
    audit_trail,
    sms_envoyes_count,
    sms_premier_envoi_a
  ) VALUES (
    p_contrat_id,
    v_uid,
    v_role,
    now(),
    v_otp_hash,
    'otp_envoye',
    jsonb_build_object(
      'otp_envoye_le', now()::text,
      'sms_count', v_sms_count,
      'ip', v_ip::text
    ),
    v_sms_count,
    v_sms_window_start
  )
  ON CONFLICT (contrat_id, signataire_role) DO UPDATE SET
    otp_envoye_a = now(),
    otp_code_hash = EXCLUDED.otp_code_hash,
    otp_tentatives = 0,
    statut_signature = 'otp_envoye',
    sms_envoyes_count = v_sms_count,
    sms_premier_envoi_a = v_sms_window_start,
    modifie_le = now(),
    audit_trail =
      COALESCE(signatures_contrats.audit_trail, '{}'::jsonb)
      || jsonb_build_object(
        'otp_renvoye_le', now()::text,
        'sms_count', v_sms_count,
        'ip', v_ip::text
      );

  v_idempotency_key :=
    'otp-signature.'
    || p_contrat_id::text
    || '.'
    || v_uid::text
    || '.'
    || v_role
    || '.'
    || extract(epoch FROM v_sms_window_start)::bigint::text
    || '.'
    || v_sms_count::text;

  BEGIN
    PERFORM net.http_post(
      url := 'https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/send-sms',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
            FROM vault.decrypted_secrets
           WHERE name = 'service_role_key'
           LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'telephone', v_telephone,
        'type', 'OTP_SIGNATURE',
        'contenu', 'Code de signature Jolene : '
          || v_otp
          || ' (valide 10 min). Ne le partagez avec personne.',
        'destinataire_id', v_uid,
        'prefix_type', 'SIGNATURE',
        'idempotency_key', v_idempotency_key,
        'data', jsonb_build_object('contrat_id', p_contrat_id)
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'role', v_role,
    'telephone_masked',
      regexp_replace(v_telephone, '\d(?=\d{2})', '*', 'g'),
    'expire_dans_minutes', 10,
    'sms_envoyes', v_sms_count,
    'sms_restants', greatest(0, 3 - v_sms_count)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_envoyer_otp_signature(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_envoyer_otp_signature(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_trg_auto_notify_mission_urgente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab record;
  v_count integer := 0;
  v_soignant record;
  v_url text := 'https://flripxtsyegjshnhzjkz.supabase.co';
  v_token text;
  v_should_fire boolean := false;
  v_corps text;
  v_notification_id uuid;
BEGIN
  IF TG_OP = 'INSERT'
     AND COALESCE(NEW.est_urgente, false)
     AND NEW.statut = 'OUVERTE' THEN
    v_should_fire := true;
  ELSIF TG_OP = 'UPDATE'
        AND COALESCE(NEW.est_urgente, false)
        AND NEW.statut = 'OUVERTE'
        AND (
          COALESCE(OLD.est_urgente, false)
            IS DISTINCT FROM COALESCE(NEW.est_urgente, false)
          OR (OLD.statut = 'ASSIGNEE' AND NEW.statut = 'OUVERTE')
        ) THEN
    v_should_fire := true;
  END IF;
  IF NOT v_should_fire THEN
    RETURN NEW;
  END IF;

  SELECT
    e.id,
    e.nom,
    e.adresse_lat,
    e.adresse_lng,
    e.adresse_ville,
    e.est_compte_test
    INTO v_etab
    FROM public.etablissements e
   WHERE e.id = NEW.etablissement_id;

  -- La garde précède même la notification in-app. Une mission de recette ne
  -- contacte jamais un soignant réel et n'altère aucune statistique d'envoi.
  IF v_etab.id IS NULL
     OR v_etab.est_compte_test IS DISTINCT FROM false THEN
    RETURN NEW;
  END IF;

  BEGIN
    v_token := (
      SELECT decrypted_secret
        FROM vault.decrypted_secrets
       WHERE name = 'service_role_key'
       LIMIT 1
    );
  EXCEPTION WHEN OTHERS THEN
    v_token := NULL;
  END;
  IF COALESCE(current_setting('app.test_mode', true), '') = 'true' THEN
    v_token := NULL;
  END IF;

  FOR v_soignant IN
    SELECT
      s.id,
      s.email,
      s.prenom,
      s.telephone,
      COALESCE(s.pool_urgence_sms_opt_in, false) AS sms_opt_in,
      CASE
        WHEN v_etab.adresse_lat IS NOT NULL
         AND s.adresse_lat IS NOT NULL THEN
          6371 * 2 * asin(sqrt(
            power(
              sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2),
              2
            )
            + cos(radians(v_etab.adresse_lat))
              * cos(radians(s.adresse_lat))
              * power(
                sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2),
                2
              )
          ))
        ELSE NULL
      END AS distance_km
    FROM public.soignants s
    WHERE s.est_compte_test IS FALSE
      AND COALESCE(s.disponible_urgence, false)
      AND public.fn_soignant_eligible_mission(s.id, NEW.id, true)
      AND NOT public.fn_est_exclu(s.id, NEW.etablissement_id)
      AND NOT EXISTS (
        SELECT 1
          FROM public.candidatures c
         WHERE c.mission_id = NEW.id
           AND c.soignant_id = s.id
      )
      AND NOT EXISTS (
        SELECT 1
          FROM public.missions m2
         WHERE m2.soignant_assigne_id = s.id
           AND m2.id <> NEW.id
           AND m2.statut IN ('ASSIGNEE', 'EN_COURS')
           AND m2.debut_le < NEW.fin_le
           AND m2.fin_le > NEW.debut_le
      )
      AND (
        v_etab.adresse_lat IS NULL
        OR s.adresse_lat IS NULL
        OR 6371 * 2 * asin(sqrt(
          power(
            sin(radians(s.adresse_lat - v_etab.adresse_lat) / 2),
            2
          )
          + cos(radians(v_etab.adresse_lat))
            * cos(radians(s.adresse_lat))
            * power(
              sin(radians(s.adresse_lng - v_etab.adresse_lng) / 2),
              2
            )
        )) <= COALESCE(s.urgence_rayon_km, 30)
      )
    ORDER BY
      distance_km ASC NULLS LAST,
      COALESCE(s.score_fiabilite, 0) DESC
  LOOP
    v_corps :=
      'Mission '
      || COALESCE(NEW.intitule, NEW.profession_requise::text)
      || ' à '
      || COALESCE(v_etab.adresse_ville, 'votre zone')
      || CASE
        WHEN v_soignant.distance_km IS NOT NULL THEN
          ' (' || round(v_soignant.distance_km::numeric, 1) || ' km)'
        ELSE ''
      END
      || ' · '
      || COALESCE(NEW.taux_horaire_base::text, '?')
      || '€/h. Acceptez en 1 clic.';

    INSERT INTO public.notifications (
      destinataire_id,
      type_destinataire,
      type,
      titre,
      corps,
      lien,
      type_ressource,
      id_ressource
    ) VALUES (
      v_soignant.id,
      'SOIGNANT',
      'MISSION_URGENTE',
      '🚨 Mission urgente près de chez vous',
      v_corps,
      '/soignant/pool-urgence',
      'mission',
      NEW.id
    )
    RETURNING id INTO v_notification_id;

    IF v_token IS NOT NULL THEN
      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-push',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_token
          ),
          body := jsonb_build_object(
            'destinataire_id', v_soignant.id,
            'type_evenement', 'MISSION_URGENTE',
            'titre', '🚨 Mission urgente près de chez vous',
            'corps', v_corps,
            'idempotency_key',
              'mission-urgente.push.' || v_notification_id::text,
            'data', jsonb_build_object(
              'mission_id', NEW.id,
              'notification_id', v_notification_id,
              'lien', '/soignant/pool-urgence'
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;

      BEGIN
        PERFORM net.http_post(
          url := v_url || '/functions/v1/send-email',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || v_token
          ),
          body := jsonb_build_object(
            'type', 'MISSION_URGENTE_POOL',
            'destinataire_id', v_soignant.id,
            'idempotency_key',
              'mission-urgente.email.' || v_notification_id::text,
            'data', jsonb_build_object(
              'prenom', v_soignant.prenom,
              'mission_id', NEW.id,
              'notification_id', v_notification_id,
              'mission_intitule', NEW.intitule,
              'profession', NEW.profession_requise::text,
              'ville', v_etab.adresse_ville,
              'distance_km', v_soignant.distance_km,
              'taux_horaire', NEW.taux_horaire_base,
              'debut_le', NEW.debut_le
            )
          )
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;

      IF v_soignant.sms_opt_in
         AND COALESCE(v_soignant.telephone, '') <> '' THEN
        BEGIN
          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-sms',
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || v_token
            ),
            body := jsonb_build_object(
              'destinataire_id', v_soignant.id,
              'telephone', v_soignant.telephone,
              'type', 'MISSION_URGENTE',
              'prefix_type', 'MISSION_URGENTE',
              'idempotency_key',
                'mission-urgente.sms.' || v_notification_id::text,
              'data', jsonb_build_object(
                'mission_id', NEW.id,
                'notification_id', v_notification_id
              ),
              'message',
                'URGENT - Mission '
                || COALESCE(NEW.profession_requise::text, '')
                || ' '
                || COALESCE(v_etab.adresse_ville, '')
                || ' '
                || to_char(
                  NEW.debut_le AT TIME ZONE 'Europe/Paris',
                  'DD/MM HH24h'
                )
                || ' - '
                || COALESCE(NEW.taux_horaire_base::text, '?')
                || '€/h - Acceptez sur jolene.app/pool-urgence'
            )
          );
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      END IF;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    PERFORM public.fn_ecrire_audit_safe(
      p_acteur_id := NEW.etablissement_id,
      p_type_acteur := 'SYSTEME',
      p_action := 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES',
      p_type_ressource := 'mission',
      p_id_ressource := NEW.id,
      p_details := jsonb_build_object(
        'count', v_count,
        'mission_intitule', NEW.intitule,
        'event', TG_OP,
        'filtre', 'fn_soignant_eligible_mission',
        'canaux',
          jsonb_build_array('in_app', 'push', 'email', 'sms_opt_in')
      )
    );
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_trg_auto_notify_mission_urgente()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_trg_auto_notify_mission_urgente()
  TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Idempotence durable des emails externes
-- ─────────────────────────────────────────────────────────────────────────────

-- La table historique n'acceptait qu'une poignée de types 2025 : la plupart
-- des notifications actuelles étaient donc envoyées mais leur audit échouait
-- silencieusement. La contrainte conserve les anciens types déjà persistés et
-- couvre le registre actuel de send-email.
ALTER TABLE public.emails_envoyes
  DROP CONSTRAINT IF EXISTS emails_envoyes_type_check;
ALTER TABLE public.emails_envoyes
  ADD CONSTRAINT emails_envoyes_type_check CHECK (
    type = ANY (ARRAY[
      'BIENVENUE_SOIGNANT',
      'BIENVENUE_ETABLISSEMENT',
      'MISSION_ACCEPTEE',
      'MISSION_ANNULEE',
      'MISSION_TERMINEE',
      'MISSION_RAPPEL',
      'FACTURE_MENSUELLE',
      'FACTURE_PAYEE',
      'DOCUMENT_EXPIRANT',
      'RECAP_HEBDO_SOIGNANT',
      'RECAP_HEBDO_ETABLISSEMENT',
      'CONVERSION_LIBERAL',
      'RESET_MOT_DE_PASSE',
      'GENERAL',
      'MISSION_ACCEPTEE_SOIGNANT',
      'MISSION_ACCEPTEE_ETABLISSEMENT',
      'RAPPEL_MISSION',
      'CONTRAT_A_SIGNER',
      'CONTRAT_SIGNE',
      'FACTURE_EMISE',
      'RAPPEL_FACTURE',
      'ELIGIBLE_LIBERAL',
      'RECAP_HEBDO',
      'RAPPEL_DOCUMENTS',
      'MISSION_URGENTE',
      'MISSION_PROPOSEE',
      'EVALUATION_RECUE',
      'PAIEMENT_CONFIRME',
      'PARRAINAGE_PRIME_VERSEE',
      'ADMIN_BROADCAST',
      'MISSION_NON_POURVUE',
      'PAIEMENT_RAPIDE_RECU',
      'LITIGE_OUVERTURE',
      'LITIGE_NOUVEAU_MESSAGE',
      'LITIGE_ESCALADE_ADMIN',
      'LITIGE_RESOLU_AJUSTE',
      'AVOIR_EMIS',
      'REMBOURSEMENT_CONFIRME',
      'LITIGE_RAPPEL_J1',
      'LITIGE_RAPPEL_J3',
      'LITIGE_RAPPEL_J5',
      'REGULARISATION_SOCIALE_REQUISE',
      'LITIGE_MEDIATION_PRIORITAIRE',
      'COMMISSION_AJUSTEE',
      'CHARGE_FAILED_ETAB',
      'DISPUTE_OUVERTE_ADMIN',
      'DISPUTE_CLOSE_ADMIN',
      'PAYOUT_FAILED_ADMIN',
      'PAYOUT_FAILED_SOIGNANT',
      'PAYOUT_CANCELED_ADMIN',
      'REFUND_ECHEC_ADMIN',
      'PAIEMENT_SOIGNANT_DECLARE',
      'RAPPEL_PAIEMENT_J7',
      'PAIEMENT_RETARD_J21',
      'PUBLICATION_SUSPENDUE',
      'PUBLICATION_REACTIVEE',
      'CONTRAT_TRAVAIL_DEPOSE',
      'CONTRAT_TRAVAIL_RAPPEL_ETAB',
      'CONTRAT_TRAVAIL_MANQUANT_SOIGNANT',
      'SERIE_SOIGNANT_J0',
      'SERIE_SOIGNANT_J1',
      'SERIE_SOIGNANT_J3',
      'SERIE_SOIGNANT_J7',
      'SERIE_ETAB_J0',
      'SERIE_ETAB_J1',
      'SERIE_ETAB_J3',
      'SERIE_ETAB_J7',
      'NOUVELLES_MISSIONS_FILTRE',
      'NOUVEAUX_SOIGNANTS_FILTRE',
      'MISSION_URGENTE_POOL',
      'FAVORI_NOUVELLE_MISSION',
      'COMPTE_SUSPENDU',
      'COMPTE_REACTIVE',
      'RAPPEL_NOTATION_ETAB',
      'RAPPEL_NOTATION_SOIGNANT',
      'INVITATION_EQUIPE_ETAB',
      'DPAE_DECLAREE_SOIGNANT',
      'DPAE_ANNULATION_RAPPEL',
      'NOTIFICATION_PUSH_FALLBACK',
      'CONFIRMATION_EMAIL_PRO_ETAB'
    ]::text[])
  );

ALTER TABLE public.emails_envoyes
  ADD COLUMN IF NOT EXISTS idempotency_key text;

DO $email_audit_constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conrelid = 'public.emails_envoyes'::regclass
       AND conname = 'emails_envoyes_idempotency_key_check'
  ) THEN
    ALTER TABLE public.emails_envoyes
      ADD CONSTRAINT emails_envoyes_idempotency_key_check CHECK (
        idempotency_key IS NULL
        OR idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conrelid = 'public.emails_envoyes'::regclass
       AND conname = 'emails_envoyes_idempotency_key_key'
  ) THEN
    ALTER TABLE public.emails_envoyes
      ADD CONSTRAINT emails_envoyes_idempotency_key_key
      UNIQUE (idempotency_key);
  END IF;
END
$email_audit_constraints$;

-- Registre de réservation hors du schéma Data API. La clé reste durable même
-- si l'audit public est purgé ; l'empreinte interdit la réutilisation d'une
-- même clé pour un autre destinataire ou un autre contenu.
CREATE TABLE IF NOT EXISTS private.email_dispatch_idempotency (
  idempotency_key text PRIMARY KEY
    CHECK (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'),
  request_fingerprint text NOT NULL
    CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  statut text NOT NULL
    CHECK (statut IN ('EN_COURS', 'ENVOYE', 'ERREUR')),
  provider_id text,
  derniere_erreur text,
  cree_le timestamptz NOT NULL DEFAULT now(),
  modifie_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE private.email_dispatch_idempotency ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.email_dispatch_idempotency FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.email_dispatch_idempotency
  FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE private.email_dispatch_idempotency IS
  'Registre durable et non exposé des réservations idempotentes envoyées à Resend.';

CREATE OR REPLACE FUNCTION public.fn_reserver_envoi_email_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_ligne private.email_dispatch_idempotency%ROWTYPE;
BEGIN
  IF p_idempotency_key IS NULL
     OR p_idempotency_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{7,199}$'
     OR p_request_fingerprint IS NULL
     OR p_request_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Clé ou empreinte idempotente invalide'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key, 746593)
  );

  SELECT *
    INTO v_ligne
    FROM private.email_dispatch_idempotency
   WHERE idempotency_key = p_idempotency_key
   FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO private.email_dispatch_idempotency (
      idempotency_key, request_fingerprint, statut
    ) VALUES (
      p_idempotency_key, p_request_fingerprint, 'EN_COURS'
    );
    RETURN jsonb_build_object('statut', 'RESERVE');
  END IF;

  IF v_ligne.request_fingerprint <> p_request_fingerprint THEN
    RETURN jsonb_build_object('statut', 'CONFLIT');
  END IF;

  IF v_ligne.statut = 'ENVOYE' THEN
    RETURN jsonb_build_object(
      'statut', 'DEJA_ENVOYE',
      'provider_id', v_ligne.provider_id
    );
  END IF;

  IF v_ligne.statut = 'EN_COURS'
     AND v_ligne.modifie_le > now() - interval '15 minutes' THEN
    RETURN jsonb_build_object('statut', 'EN_COURS');
  END IF;

  UPDATE private.email_dispatch_idempotency
     SET statut = 'EN_COURS',
         provider_id = NULL,
         derniere_erreur = NULL,
         modifie_le = now()
   WHERE idempotency_key = p_idempotency_key;

  RETURN jsonb_build_object('statut', 'RESERVE');
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_reserver_envoi_email_idempotent(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reserver_envoi_email_idempotent(text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.fn_finaliser_envoi_email_idempotent(
  p_idempotency_key text,
  p_request_fingerprint text,
  p_succes boolean,
  p_provider_id text DEFAULT NULL,
  p_erreur text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  UPDATE private.email_dispatch_idempotency
     SET statut = CASE WHEN p_succes THEN 'ENVOYE' ELSE 'ERREUR' END,
         provider_id = CASE WHEN p_succes THEN p_provider_id ELSE NULL END,
         derniere_erreur = CASE
           WHEN p_succes THEN NULL
           ELSE left(COALESCE(p_erreur, 'Erreur fournisseur'), 2000)
         END,
         modifie_le = now()
   WHERE idempotency_key = p_idempotency_key
     AND request_fingerprint = p_request_fingerprint;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Réservation idempotente introuvable ou incohérente'
      USING ERRCODE = 'P0002';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_finaliser_envoi_email_idempotent(
  text, text, boolean, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_finaliser_envoi_email_idempotent(
  text, text, boolean, text, text
) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Retrait définitif du MFA administrateur
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.est_admin_valide()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public, auth
AS $function$
  SELECT COALESCE(EXISTS (
    SELECT 1
      FROM auth.users u
     WHERE u.id = auth.uid()
       AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
       AND u.deleted_at IS NULL
       AND (u.banned_until IS NULL OR u.banned_until <= now())
       AND u.email_confirmed_at IS NOT NULL
       AND EXISTS (
         SELECT 1
           FROM public.equipe_admin ea
          WHERE ea.user_id = u.id
            AND ea.actif IS TRUE
            AND ARRAY[
              'Dashboard',
              'Utilisateurs',
              'Missions',
              'Litiges & contrats',
              'Finances',
              'Messagerie',
              'Conformité & Technique',
              'Fondateur'
            ]::text[] <@ COALESCE(ea.acces_groupes, ARRAY[]::text[])
       )
  ), false);
$function$;

REVOKE ALL ON FUNCTION public.est_admin_valide() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.est_admin_valide()
  TO authenticated, service_role;
COMMENT ON FUNCTION public.est_admin_valide() IS
  'Garde admin Jolene : compte Auth actif et confirmé, rôle ADMIN_PLATEFORME et registre equipe_admin actif avec les 8 groupes. Aucun MFA/AAL2 requis.';
COMMENT ON FUNCTION public.fn_get_my_role() IS
  'Résout la famille de compte. Les privilèges admin restent protégés par est_admin_valide(), sans MFA.';

-- Supprimer les facteurs déjà enrôlés pour éviter qu'un ancien écran ou une
-- ancienne session ne réaffiche un challenge TOTP.
DELETE FROM auth.mfa_factors f
USING auth.users u
 WHERE u.id = f.user_id
   AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME';

DROP FUNCTION IF EXISTS public.fn_lire_email_2fa(uuid);
DROP TABLE IF EXISTS public.admin_2fa_codes CASCADE;
DROP TABLE IF EXISTS public.admin_securite CASCADE;

DO $assert_no_admin_mfa$
DECLARE
  v_fonctions text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ')
    INTO v_fonctions
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND CASE
           WHEN p.prokind IN ('f', 'p')
             THEN pg_get_functiondef(p.oid) ILIKE '%auth.jwt()%aal%aal2%'
           ELSE FALSE
         END;

  IF v_fonctions IS NOT NULL THEN
    RAISE EXCEPTION 'Une exigence AAL2 admin subsiste dans : %', v_fonctions;
  END IF;

  IF to_regclass('public.admin_2fa_codes') IS NOT NULL
     OR to_regclass('public.admin_securite') IS NOT NULL THEN
    RAISE EXCEPTION 'Un registre MFA applicatif subsiste';
  END IF;
END
$assert_no_admin_mfa$;

-- Les quatre surfaces publiques canoniques doivent continuer à filtrer les
-- établissements test. Cela prouve aussi que la mission de démonstration
-- requalifiée n'est ni indexée ni exposée anonymement.
DO $assert_public_filters$
DECLARE
  v_signature regprocedure;
  v_definition text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.fn_mission_publique(uuid)'::regprocedure,
    'public.fn_missions_publiques_recherche(text,text)'::regprocedure,
    'public.fn_missions_ouvertes_sitemap()'::regprocedure,
    'public.fn_etablissements_avec_missions_ouvertes()'::regprocedure
  ]
  LOOP
    v_definition := pg_get_functiondef(v_signature);
    IF v_definition NOT ILIKE '%est_compte_test%' THEN
      RAISE EXCEPTION 'Filtre compte test absent de %', v_signature;
    END IF;
  END LOOP;
END
$assert_public_filters$;

DO $assert_test_cohorts$
DECLARE
  v_count integer;
  v_definition text;
  v_name text;
  v_security_definer boolean;
  v_private_inattendues text;
BEGIN
  IF NOT has_schema_privilege('authenticated', 'private', 'USAGE')
     OR NOT has_schema_privilege('service_role', 'private', 'USAGE')
     OR has_schema_privilege('anon', 'private', 'USAGE') THEN
    RAISE EXCEPTION
      'ACL du schéma private incompatible avec les politiques de cohorte';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'private.fn_comptes_meme_cohorte_test(uuid,uuid)',
    'EXECUTE'
  )
     OR NOT has_function_privilege(
       'service_role',
       'private.fn_comptes_meme_cohorte_test(uuid,uuid)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'anon',
       'private.fn_comptes_meme_cohorte_test(uuid,uuid)',
       'EXECUTE'
     ) THEN
    RAISE EXCEPTION
      'ACL de fn_comptes_meme_cohorte_test incorrecte';
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ')
  INTO v_private_inattendues
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.oid <>
      'private.fn_comptes_meme_cohorte_test(uuid,uuid)'::regprocedure
    AND (
      has_function_privilege('authenticated', p.oid, 'EXECUTE')
      OR has_function_privilege('anon', p.oid, 'EXECUTE')
    );
  IF v_private_inattendues IS NOT NULL THEN
    RAISE EXCEPTION
      'L’USAGE de private exposerait des fonctions inattendues : %',
      v_private_inattendues;
  END IF;

  SELECT p.prosecdef
  INTO v_security_definer
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.oid =
      'public.fn_resoudre_contrat_mission(uuid,uuid,text)'::regprocedure;
  IF v_security_definer IS DISTINCT FROM false THEN
    RAISE EXCEPTION
      'fn_resoudre_contrat_mission doit rester SECURITY INVOKER';
  END IF;

  SELECT count(*)
  INTO v_count
  FROM pg_catalog.pg_attribute a
  JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_attrdef d
    ON d.adrelid = a.attrelid
   AND d.adnum = a.attnum
  WHERE n.nspname = 'public'
    AND c.relname IN ('soignants', 'etablissements')
    AND a.attname = 'est_compte_test'
    AND pg_catalog.pg_get_expr(d.adbin, d.adrelid) ILIKE '%true%';

  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'Les créations pré-lancement ne sont pas test par défaut';
  END IF;

  SELECT count(*)
  INTO v_count
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname IN ('soignants', 'etablissements')
    AND t.tgname = 'trg_forcer_compte_test_prelaunch'
    AND NOT t.tgisinternal
    AND t.tgenabled <> 'D';

  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'Le garde de cohorte pré-lancement est absent ou désactivé';
  END IF;

  v_definition := pg_get_functiondef(
    'private.fn_comptes_meme_cohorte_test(uuid,uuid)'::regprocedure
  );
  IF v_definition NOT ILIKE '%s.est_compte_test = e.est_compte_test%'
     OR v_definition NOT ILIKE '%COALESCE(%false%' THEN
    RAISE EXCEPTION 'Le critère de cohorte test n’échoue pas fermé';
  END IF;

  SELECT COALESCE(qual, '') || ' ' || COALESCE(with_check, '')
  INTO v_definition
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'missions'
    AND policyname = 'missions_masquer_etabs_test';
  IF v_definition IS NULL
     OR v_definition NOT ILIKE '%fn_comptes_meme_cohorte_test%' THEN
    RAISE EXCEPTION
      'La lecture des missions ne sépare pas les cohortes';
  END IF;

  SELECT COALESCE(qual, '') || ' ' || COALESCE(with_check, '')
  INTO v_definition
  FROM pg_catalog.pg_policies
  WHERE schemaname = 'public'
    AND tablename = 'candidatures'
    AND policyname = 'pol_cand_insert';
  IF v_definition IS NULL OR (
    length(lower(v_definition))
    - length(replace(
      lower(v_definition),
      'fn_comptes_meme_cohorte_test',
      ''
    ))
  ) / length('fn_comptes_meme_cohorte_test') < 2 THEN
    RAISE EXCEPTION
      'Une branche d’insertion directe de candidature contourne la cohorte';
  END IF;

  FOREACH v_name IN ARRAY ARRAY[
    'fn_resoudre_contrat_mission',
    'fn_postuler_mission',
    'fn_etablissements_safe',
    'fn_compteur_soignants_disponibles',
    'fn_vivier_disponibilites',
    'fn_rechercher_soignants_etab'
  ]
  LOOP
    SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO v_definition
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = v_name;

    IF v_definition IS NULL
       OR v_definition NOT ILIKE '%fn_comptes_meme_cohorte_test%' THEN
      RAISE EXCEPTION 'Cohorte absente de public.%', v_name;
    END IF;
  END LOOP;

  FOREACH v_name IN ARRAY ARRAY[
    'fn_apercu_marche_profession',
    'fn_missions_publiques_etablissement',
    'fn_etablissement_public'
  ]
  LOOP
    SELECT string_agg(pg_get_functiondef(p.oid), E'\n')
    INTO v_definition
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = v_name;

    IF v_definition IS NULL
       OR v_definition NOT ILIKE '%est_compte_test IS FALSE%' THEN
      RAISE EXCEPTION 'Fixtures exposées par public.%', v_name;
    END IF;
  END LOOP;

  IF NOT has_function_privilege(
    'anon',
    'public.fn_missions_publiques_etablissement(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'Le widget public ne peut plus lire les missions réelles';
  END IF;
END
$assert_test_cohorts$;

DO $assert_external_effect_guards$
DECLARE
  v_definition text;
  v_constraintes text;
BEGIN
  v_definition := pg_get_functiondef(
    'public.fn_admin_metriques_argent()'::regprocedure
  );
  IF v_definition NOT ILIKE
    '%etab_a_valider%est_compte_test IS FALSE%' THEN
    RAISE EXCEPTION
      'Le compteur etab_a_valider inclut encore les comptes test';
  END IF;

  v_definition := pg_get_functiondef(
    'public.fn_envoyer_rappels_notation_j1()'::regprocedure
  );
  IF v_definition NOT ILIKE '%idempotency_key%'
     OR v_definition NOT ILIKE
       '%ON CONFLICT (mission_id, sens) DO NOTHING%'
     OR v_definition NOT ILIKE '%e.est_compte_test IS FALSE%'
     OR v_definition NOT ILIKE '%s.est_compte_test IS FALSE%'
     OR v_definition NOT ILIKE
       '%private.fn_controler_rappels_notation_j1()%' THEN
    RAISE EXCEPTION
      'Le rappel notation n’est pas atomique, idempotent et hors fixtures';
  END IF;

  v_definition := pg_get_functiondef(
    'private.fn_controler_rappels_notation_j1()'::regprocedure
  );
  IF v_definition NOT ILIKE '%net._http_response%'
     OR v_definition NOT ILIKE '%status_code BETWEEN 200 AND 299%'
     OR v_definition NOT ILIKE
       '%INSERT INTO public.notifications_notation_j1%'
     OR v_definition NOT ILIKE '%statut = ''REESSAI''%'
     OR v_definition NOT ILIKE '%statut = ''ECHEC''%' THEN
    RAISE EXCEPTION
      'Le rappel notation ne contrôle pas durablement les réponses HTTP';
  END IF;

  SELECT string_agg(pg_get_constraintdef(c.oid), E'\n')
  INTO v_constraintes
  FROM pg_catalog.pg_constraint c
  WHERE c.conrelid = 'public.emails_envoyes'::regclass;

  IF v_constraintes NOT ILIKE '%PARRAINAGE_PRIME_VERSEE%'
     OR v_constraintes NOT ILIKE '%CONFIRMATION_EMAIL_PRO_ETAB%'
     OR v_constraintes NOT ILIKE '%DPAE_ANNULATION_RAPPEL%' THEN
    RAISE EXCEPTION
      'Le journal email refuse encore un type réellement envoyé';
  END IF;
END
$assert_external_effect_guards$;

COMMIT;
