-- Suppression du compte soignant : les pièces vérifiées ne bloquent plus l'anonymisation.
--
-- Constat (job SQL du staging, 27/11/2026, puis production relue en lecture
-- seule) : un soignant qui a au moins une pièce VERIFIE ne peut pas supprimer
-- son compte. Le chemin web et natif est le même : edge delete-account, puis
-- fn_supprimer_compte_rate_limited et fn_supprimer_mon_compte, en session
-- utilisateur. L'anonymisation change nom, prénom et date de naissance ; le
-- déclencheur trg_invalider_preuves_identite_sur_changement repasse alors les
-- pièces VERIFIE en EN_ATTENTE, écriture que fn_proteger_ecriture_document_soignant
-- refuse en session utilisateur (42501), et toute la suppression est annulée.
-- La suppression de compte (droit à l'effacement, exigence des stores) n'aboutit
-- donc pas pour un soignant vérifié.
--
-- Correctif, au point de coupure le plus étroit : dans
-- public.fn_invalider_preuves_identite_sur_changement, seul l'UPDATE des
-- pièces (repasse en EN_ATTENTE) est sauté quand la ligne soignant passe à
-- l'état supprimé dans la même mise à jour (OLD.supprime_le NULL,
-- NEW.supprime_le posé). Les pièces n'ont plus d'objet à re-vérifier : la
-- suppression les marque elle-même supprimées. Le reste du déclencheur est
-- conservé tel quel, car il fait partie de l'anonymisation de toute
-- suppression : noms RPPS et ADELI, spécialité et détails de cohérence remis à
-- NULL, drapeaux de vérification remis à faux, audit. fn_supprimer_mon_compte
-- ne les vide pas elle-même. Cette transition est réservée aux fonctions
-- serveur : fn_protect_soignant_verification rétablit supprime_le pour toute
-- écriture d'un utilisateur (empreinte verrouillée ci-dessous). En production,
-- deux fonctions la posent en changeant l'identité : fn_supprimer_mon_compte
-- (suppression par le soignant) et fn_rgpd_purge_automatique_inactifs (purge,
-- sans identité).
-- Inchangés : fn_proteger_ecriture_document_soignant (aucune autre écriture
-- relâchée), fn_supprimer_mon_compte, tout changement d'identité hors
-- suppression (re-vérification demandée comme avant), y compris pour un profil
-- déjà marqué supprimé (suspension).
--
-- Redéfinition : corps LIVE relu en lecture seule le 27/11/2026
-- (md5 121864acbb7a1bd4c800de32eaa75292, identique à 20260713223000 et à
-- supabase/schema/public.sql) ; seul l'UPDATE des pièces est placé sous la
-- condition citée (réindenté, inchangé). Préflight
-- fail-closed et post-condition sur md5(prosrc) ; en-tête, SECURITY DEFINER,
-- search_path, propriétaire et ACL conservés par CREATE OR REPLACE. Fonction de
-- déclencheur hors inventaire SECURITY DEFINER (EXECUTE : postgres, service_role).
--
-- Contrôles : tests/security/suppression-compte-soignant-preuves.test.sql
-- (staging, ROLLBACK ; même suite sur PostgreSQL 17 et PGlite par
-- tests/postgres/suppression-compte-soignant-preuves.pg17.mjs), garde statique
-- tests/node/suppression-compte-soignant-preuves.node.mjs.
-- B9 (suppression de données personnelles) : go écrits de Gabrielle du 24/11/2026 et du 26/11/2026.
-- Aucun BEGIN/COMMIT : la CLI ou le banc appelant possède la transaction.
SET LOCAL lock_timeout = '5s';

-- ── 0. Préflight fail-closed : corps LIVE et déclencheurs attendus ─────────
DO $suppression_preuves_avant$
DECLARE
  v_attendu record;
  v_proc record;
BEGIN
  FOR v_attendu IN
    SELECT * FROM (VALUES
      ('public.fn_invalider_preuves_identite_sur_changement()', '121864acbb7a1bd4c800de32eaa75292', 'search_path=pg_catalog, public'),
      ('public.fn_proteger_ecriture_document_soignant()', 'c490ce823768b0a23cd264ab17601155', 'search_path=pg_catalog, public'),
      ('public.fn_protect_soignant_verification()', 'ff5e753f785f2c7ca08ae22771812e95', 'search_path=pg_catalog, public'),
      ('public.fn_supprimer_mon_compte()', 'f3af23aeeb4e30aba07e422c0e819aeb', 'search_path=public, extensions'),
      ('public.fn_supprimer_compte_rate_limited()', 'f283e828e173bf12d8f633be28431c97', 'search_path=""')
    ) AS t(signature, empreinte, config)
  LOOP
    SELECT p.prosrc, p.prosecdef, p.provolatile::text AS volatilite, p.proconfig,
           pg_catalog.pg_get_userbyid(p.proowner) AS proprietaire
      INTO v_proc
      FROM pg_catalog.pg_proc p
     WHERE p.oid = pg_catalog.to_regprocedure(v_attendu.signature);
    IF NOT FOUND
      OR pg_catalog.md5(v_proc.prosrc) IS DISTINCT FROM v_attendu.empreinte
      OR v_proc.prosecdef IS NOT TRUE
      OR v_proc.volatilite IS DISTINCT FROM 'v'
      OR v_proc.proconfig IS DISTINCT FROM ARRAY[v_attendu.config]::text[]
      OR v_proc.proprietaire IS DISTINCT FROM 'postgres'
    THEN
      RAISE EXCEPTION 'SUPPRESSION_PREUVES_SOURCE_DIVERGENTE : % en base (md5 %) ne correspond plus au corps LIVE relu le 27/11/2026 (md5 %). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        v_attendu.signature, COALESCE(pg_catalog.md5(v_proc.prosrc), 'fonction absente'), v_attendu.empreinte;
    END IF;
  END LOOP;
  IF (SELECT pg_catalog.count(*) FROM pg_catalog.pg_trigger t
       WHERE t.tgenabled = 'O' AND NOT t.tgisinternal AND (
         (t.tgname = 'trg_invalider_preuves_identite_sur_changement' AND t.tgrelid = 'public.soignants'::pg_catalog.regclass
          AND t.tgfoid = 'public.fn_invalider_preuves_identite_sur_changement()'::pg_catalog.regprocedure)
         OR (t.tgname = 'trg_protect_soignant_verification' AND t.tgrelid = 'public.soignants'::pg_catalog.regclass
          AND t.tgfoid = 'public.fn_protect_soignant_verification()'::pg_catalog.regprocedure)
         OR (t.tgname = 'trg_proteger_ecriture_document_soignant' AND t.tgrelid = 'public.documents_soignants'::pg_catalog.regclass
          AND t.tgfoid = 'public.fn_proteger_ecriture_document_soignant()'::pg_catalog.regprocedure))) <> 3
  THEN
    RAISE EXCEPTION 'SUPPRESSION_PREUVES_DECLENCHEURS_DIVERGENTS : déclencheurs d''invalidation ou de protection absents, désactivés ou rattachés à une autre fonction.';
  END IF;
END
$suppression_preuves_avant$;

-- ── 1. Redéfinition (corps LIVE + bloc cité) ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_invalider_preuves_identite_sur_changement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn_invalider_preuves_identite_sur_changement$
DECLARE
  v_previous_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
  v_previous_siret_reset text := COALESCE(current_setting('jolene.siret_liberal_reset', true), '');
  v_documents_invalides integer := 0;
  v_champs text[] := ARRAY[]::text[];
  v_nom_prenom_modifie boolean;
BEGIN
  IF NEW.prenom IS NOT DISTINCT FROM OLD.prenom
     AND NEW.nom IS NOT DISTINCT FROM OLD.nom
     AND NEW.date_naissance IS NOT DISTINCT FROM OLD.date_naissance THEN
    RETURN NEW;
  END IF;

  IF NEW.prenom IS DISTINCT FROM OLD.prenom THEN v_champs := array_append(v_champs, 'prenom'); END IF;
  IF NEW.nom IS DISTINCT FROM OLD.nom THEN v_champs := array_append(v_champs, 'nom'); END IF;
  IF NEW.date_naissance IS DISTINCT FROM OLD.date_naissance THEN v_champs := array_append(v_champs, 'date_naissance'); END IF;
  v_nom_prenom_modifie := NEW.prenom IS DISTINCT FROM OLD.prenom
    OR NEW.nom IS DISTINCT FROM OLD.nom;

  PERFORM set_config('jolene.system_update', 'true', true);
  PERFORM set_config('jolene.siret_liberal_reset', 'true', true);
  BEGIN
    -- Suppression du compte (supprime_le posé dans cette même mise à jour) : les
    -- pièces ne sont pas repassées en attente, elles n'ont plus d'objet à
    -- re-vérifier et la suppression les marque elle-même supprimées. Le
    -- nettoyage du profil ci-dessous (noms RPPS et ADELI, spécialité,
    -- cohérence, drapeaux de vérification) reste dû. Transition réservée aux
    -- fonctions serveur : fn_protect_soignant_verification rétablit
    -- supprime_le pour toute écriture d'un utilisateur (migration 20261127100000).
    IF NOT (OLD.supprime_le IS NULL AND NEW.supprime_le IS NOT NULL) THEN
      UPDATE public.documents_soignants
      SET statut_verification = 'EN_ATTENTE',
          motif_rejet = 'Profil d’identité modifié après vérification — nouvelle vérification de la preuve requise.',
          verifie_le = NULL,
          verifie_par = NULL,
          valide_depuis = NULL,
          valide_jusqua = NULL,
          modifie_le = now()
      WHERE soignant_id = NEW.id
        AND statut_verification = 'VERIFIE'
        AND supprime_le IS NULL;
      GET DIAGNOSTICS v_documents_invalides = ROW_COUNT;
    END IF;

    UPDATE public.soignants
    SET identite_verifiee = false,
        diplome_verifie = false,
        tous_documents_valides = false,
        statut_verification_aria = 'EN_ATTENTE',
        siret_liberal_verifie = false,
        siret_liberal_verifie_le = NULL,
        siret_liberal_raison_sociale = NULL,
        siret_liberal_coherence_identite = NULL,
        rpps_verifie = CASE WHEN v_nom_prenom_modifie THEN false ELSE rpps_verifie END,
        rpps_verifie_le = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_verifie_le END,
        rpps_nom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_nom_api END,
        rpps_prenom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_prenom_api END,
        rpps_profession_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE rpps_profession_api END,
        adeli_verifie = CASE WHEN v_nom_prenom_modifie THEN false ELSE adeli_verifie END,
        adeli_verifie_le = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_verifie_le END,
        adeli_nom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_nom_api END,
        adeli_prenom_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_prenom_api END,
        adeli_profession_api = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE adeli_profession_api END,
        specialite_verifiee = CASE WHEN v_nom_prenom_modifie THEN false ELSE specialite_verifiee END,
        specialite_verifiee_le = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_verifiee_le END,
        specialite_medicale = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_medicale END,
        specialite_code = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_code END,
        specialite_source = CASE WHEN v_nom_prenom_modifie THEN NULL ELSE specialite_source END,
        coherence_identite = 'EN_ATTENTE_REVUE',
        coherence_details = jsonb_build_object(
          'raison', 'PROFIL_IDENTITE_MODIFIE',
          'champs_modifies', to_jsonb(v_champs),
          'documents_invalides', v_documents_invalides,
          'invalide_le', now()
        ),
        modifie_le = now()
    WHERE id = NEW.id;
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('jolene.siret_liberal_reset', v_previous_siret_reset, true);
    PERFORM set_config('jolene.system_update', v_previous_system_update, true);
    RAISE;
  END;
  PERFORM set_config('jolene.siret_liberal_reset', v_previous_siret_reset, true);
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := NEW.id,
    p_type_acteur := CASE WHEN auth.uid() = NEW.id THEN 'SOIGNANT' ELSE 'SYSTEME' END,
    p_action := 'IDENTITE_PROFIL_MODIFIEE',
    p_type_ressource := 'soignant',
    p_id_ressource := NEW.id,
    p_details := jsonb_build_object(
      'champs_modifies', to_jsonb(v_champs),
      'preuves_identite_invalidees', v_documents_invalides
    )
  );
  RETURN NEW;
END;
$fn_invalider_preuves_identite_sur_changement$;

-- ── 2. Post-condition ──────────────────────────────────────────────────────
DO $suppression_preuves_apres$
BEGIN
  IF (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_invalider_preuves_identite_sur_changement()'::pg_catalog.regprocedure)
       IS DISTINCT FROM 'bb93c49d6187ee007b964acab6bf0809'
     OR (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_proteger_ecriture_document_soignant()'::pg_catalog.regprocedure)
       IS DISTINCT FROM 'c490ce823768b0a23cd264ab17601155'
     OR (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc
       WHERE oid = 'public.fn_protect_soignant_verification()'::pg_catalog.regprocedure)
       IS DISTINCT FROM 'ff5e753f785f2c7ca08ae22771812e95'
  THEN
    RAISE EXCEPTION 'SUPPRESSION_PREUVES_POSTCONDITION : corps installé inattendu.';
  END IF;
  IF pg_catalog.has_function_privilege('anon', 'public.fn_invalider_preuves_identite_sur_changement()', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'public.fn_invalider_preuves_identite_sur_changement()', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.fn_invalider_preuves_identite_sur_changement()', 'EXECUTE')
     OR (SELECT prosecdef FROM pg_catalog.pg_proc
          WHERE oid = 'public.fn_invalider_preuves_identite_sur_changement()'::pg_catalog.regprocedure) IS NOT TRUE
  THEN
    RAISE EXCEPTION 'SUPPRESSION_PREUVES_POSTCONDITION : droits ou attributs inattendus.';
  END IF;
END
$suppression_preuves_apres$;
