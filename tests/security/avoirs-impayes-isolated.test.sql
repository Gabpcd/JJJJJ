-- Banc PG17 isolé : vrais corps LIVE avant correction puis vraie migration.
-- Tables minimales et helpers de contexte seulement ; pas de transport email,
-- de Stripe, de RLS complète ni de preuve frontend dans ce banc.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'avoirs_impayes'
    OR current_user <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public')
    OR to_regnamespace('auth') IS NOT NULL
  THEN RAISE EXCEPTION 'AVOIRS_REQUIRES_EMPTY_ISOLATED_PG17'; END IF;
END $guard$;
SET LOCAL TIME ZONE 'Europe/Paris';
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
CREATE FUNCTION public.mon_etablissement_id() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT auth.uid(); $$;
CREATE FUNCTION public.est_admin() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT coalesce(current_setting('jolene.test_admin', true), '') = 'on';
$$;
CREATE FUNCTION public.est_admin_valide() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT public.est_admin();
$$;
CREATE FUNCTION public.fn_param_num(text, numeric) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('jolene.test_seuil', true), '')::numeric, $2);
$$;
CREATE FUNCTION public.fn_pool_urgence_etablissement(uuid) RETURNS TABLE(id uuid) LANGUAGE sql AS $$
  SELECT NULL::uuid WHERE false;
$$;
CREATE TABLE private.security_definer_inventory (
  signature text PRIMARY KEY, categorie text, definition_md5 text,
  justification text, recense_le timestamptz
);
CREATE TABLE public.etablissements (
  id uuid PRIMARY KEY, nom text, email_contact text, est_compte_test boolean DEFAULT false,
  supprime_le timestamptz, cree_le timestamptz DEFAULT now(),
  peut_publier_missions boolean DEFAULT true, statut_verification text DEFAULT 'VERIFIE',
  contrat_service_signe boolean DEFAULT true, bloque_auto_le timestamptz, bloque_auto_raisons jsonb,
  finess_verifie boolean DEFAULT true, siret_verifie boolean DEFAULT true,
  representant_identite_verifiee boolean DEFAULT true, rattachement_verifie boolean DEFAULT true
);
CREATE TABLE public.factures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), etablissement_id uuid,
  numero_facture text UNIQUE, montant_ht numeric, montant_tva numeric, montant_ttc numeric,
  type_document text NOT NULL DEFAULT 'FACTURE'
    CHECK (type_document IN ('FACTURE','AVOIR','FACTURE_COMPLEMENTAIRE')),
  statut text, date_emission timestamptz, date_echeance date, date_paiement timestamptz,
  nombre_missions integer DEFAULT 1, stripe_hosted_url text, est_secteur_public boolean DEFAULT false,
  chorus_pro_statut text, chorus_pro_numero_flux text, mode_paiement text,
  virement_reference text, stripe_payment_intent_id text, mission_id uuid,
  facture_honoraire_id uuid, facture_precedente_id uuid, relance_1_le timestamptz, relance_2_le timestamptz,
  montant_signe numeric GENERATED ALWAYS AS (CASE WHEN type_document='AVOIR' THEN -montant_ht ELSE montant_ht END) STORED
);
CREATE TABLE public.soignants (
  id uuid PRIMARY KEY, prenom text, nom text, profession text, type_exercice text,
  stripe_account_id text, score_fiabilite numeric, est_compte_test boolean DEFAULT false,
  supprime_le timestamptz, cree_le timestamptz DEFAULT now()
);
CREATE TABLE public.missions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), etablissement_id uuid, soignant_assigne_id uuid,
  intitule text, debut_le timestamptz, fin_le timestamptz, total_brut numeric, net_a_payer numeric,
  montant_commission_ht numeric, montant_commission_ttc numeric, statut text,
  type_contrat_applique text, type_paiement_soignant text, mode_paiement_soignant text,
  cree_le timestamptz DEFAULT now(), relance_paiement_1_le timestamptz, relance_paiement_2_le timestamptz
);
CREATE TABLE public.paiements_soignant (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid, etablissement_id uuid,
  statut text, montant_net numeric, facture_honoraire_id uuid, methode text, reference_virement text,
  date_paiement timestamptz, confirme_par_soignant boolean DEFAULT false,
  confirme_par_soignant_le timestamptz, cree_le timestamptz DEFAULT now(), relance_1_le timestamptz
);
CREATE TABLE public.factures_honoraires (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), etablissement_id uuid, mission_id uuid, soignant_id uuid,
  periode_debut date, periode_fin date, est_facture_finale_mission boolean, montant_ttc numeric,
  type_document text, statut text, date_emission timestamptz
);
CREATE TABLE public.stripe_connect_onboarding (soignant_id uuid, charges_enabled boolean, payouts_enabled boolean);
CREATE TABLE public.stripe_transfers (facture_honoraire_id uuid, statut text);
CREATE TABLE public.litiges (mission_id uuid, etablissement_id uuid, statut text);
CREATE TABLE public.documents_soignants (soignant_id uuid, statut_verification text);
CREATE TABLE public.conversations (id uuid, participant_1_id uuid, participant_2_id uuid);
CREATE TABLE public.messages_chat (conversation_id uuid, auteur_id uuid, lu boolean);
CREATE TABLE public.candidatures (id uuid, mission_id uuid, soignant_id uuid, statut text, cree_le timestamptz);
CREATE TABLE public.email_queue (type text, destinataire_id uuid, destinataire_email text, data jsonb);
CREATE TABLE public.notifications (
  destinataire_id uuid, type text, titre text, corps text, lien text,
  type_destinataire text, type_ressource text, id_ressource uuid
);
CREATE TABLE public.emails_envoyes (type text, sujet text, cree_le timestamptz);
CREATE TABLE public.historique_blocages_etablissements (etablissement_id uuid, action text, raisons jsonb);

-- Dépendances minimales du vrai parcours d'anonymisation, uniquement dans cette
-- base vide. La preuve privée remplace ici les contrôles de production étendus.
ALTER TABLE etablissements
  ADD COLUMN siret text, ADD COLUMN finess text, ADD COLUMN telephone_contact text,
  ADD COLUMN adresse_rue text, ADD COLUMN adresse_ville text, ADD COLUMN adresse_code_postal text,
  ADD COLUMN adresse_departement text, ADD COLUMN adresse_lat numeric, ADD COLUMN adresse_lng numeric,
  ADD COLUMN description text, ADD COLUMN logo_url text, ADD COLUMN horaires_ouverture jsonb,
  ADD COLUMN contrat_url text, ADD COLUMN siret_raison_sociale text, ADD COLUMN siret_categorie_juridique text,
  ADD COLUMN siret_code_naf text, ADD COLUMN siret_est_actif boolean, ADD COLUMN chorus_pro_actif boolean,
  ADD COLUMN chorus_pro_identifiant text, ADD COLUMN sms_actif boolean, ADD COLUMN sms_consent_le timestamptz,
  ADD COLUMN stripe_sepa_payment_method_id text;
ALTER TABLE messages_chat ADD COLUMN contenu text;
CREATE TABLE private.suppression_etablissement_context (backend_pid integer, transaction_id bigint, utilisateur_id uuid);
CREATE TABLE private.suppressions_compte_confirmees (
  utilisateur_id uuid, type_profil text, anonymise_le timestamptz, email_anonymise text,
  PRIMARY KEY(utilisateur_id,type_profil)
);
CREATE FUNCTION private.fn_anonymisation_compte_confirmee(uuid,text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS(SELECT FROM private.suppressions_compte_confirmees c
    JOIN public.etablissements e ON e.id=c.utilisateur_id
    WHERE c.utilisateur_id=$1 AND c.type_profil=$2 AND e.supprime_le=c.anonymise_le
      AND e.email_contact=c.email_anonymise);
$$;
CREATE TABLE public.admins_groupe_sante (utilisateur_id uuid);
CREATE TABLE public.tokens_push (utilisateur_id uuid);
CREATE TABLE public.messages_mission (auteur_id uuid, contenu text);
CREATE TABLE public.messages_litige (auteur_id uuid, contenu text);
CREATE TABLE public.evaluations (evaluateur_id uuid, evalue_id uuid, commentaire text);
CREATE TABLE public.exclusions (exclu_par uuid, exclu_id uuid);
CREATE TABLE public.partages_rib (etablissement_id uuid, actif boolean, expire_le timestamptz);
CREATE TABLE public.contrats_mission (
  etablissement_id uuid, signature_ip_etablissement text,
  signature_navigateur_etablissement text, signature_image_etablissement text
);
CREATE TABLE public.sms_envoyes (telephone text, destinataire_id uuid);
CREATE TABLE public.calendar_events_sync (connection_id uuid);
CREATE TABLE public.calendar_connections (id uuid, utilisateur_id uuid);
CREATE TABLE public.api_keys (etablissement_id uuid);
CREATE TABLE public.journaux_audit (
  acteur_id uuid, type_acteur text, action text, type_ressource text, id_ressource uuid, details jsonb
);
-- Contexte minimal de suspension/réactivation : le helper admin est simulé,
-- la vraie RPC et ses mises à jour auth/membres/audit sont exécutées.
CREATE TABLE auth.users (id uuid PRIMARY KEY, banned_until timestamptz, deleted_at timestamptz, updated_at timestamptz);
ALTER TABLE etablissements ADD COLUMN modifie_le timestamptz;
ALTER TABLE soignants ADD COLUMN email text, ADD COLUMN modifie_le timestamptz;
CREATE TABLE public.suspensions_profils_admin (
  type_ressource text, id_ressource uuid, supprime_le_avant timestamptz,
  suspendu_le timestamptz, suspendu_par uuid, motif text, PRIMARY KEY(type_ressource,id_ressource)
);
CREATE TABLE public.suspensions_auth_admin (
  type_ressource text, id_ressource uuid, user_id uuid, banned_until_avant timestamptz,
  banned_until_pose timestamptz, suspendu_le timestamptz, suspendu_par uuid, motif text,
  PRIMARY KEY(type_ressource,id_ressource,user_id)
);
CREATE TABLE public.suspensions_etablissement_admin (
  etablissement_id uuid PRIMARY KEY, peut_publier_avant boolean,
  suspendu_le timestamptz, suspendu_par uuid, motif text
);
CREATE TABLE public.membres_etablissement (
  id uuid PRIMARY KEY, etablissement_id uuid, user_id uuid, actif boolean, maj_le timestamptz
);
CREATE TABLE public.suspensions_membres_etablissement_admin (
  etablissement_id uuid, membre_id uuid, user_id uuid, actif_avant boolean,
  desactive_le timestamptz, suspendu_par uuid, motif text, PRIMARY KEY(etablissement_id,membre_id)
);

\ir fixtures/avoirs-impayes-before.sql
CREATE TRIGGER dec_facture_impayee BEFORE INSERT ON public.missions
FOR EACH ROW EXECUTE FUNCTION public.dec_bloquer_si_facture_impayee();

INSERT INTO public.etablissements(id,nom,email_contact) VALUES
 ('a0170000-0000-4000-8000-000000000001','Établissement A','avoir-a@example.invalid'),
 ('a0170000-0000-4000-8000-000000000002','Établissement B','avoir-b@example.invalid');
INSERT INTO auth.users(id) SELECT id FROM etablissements;
INSERT INTO membres_etablissement(id,etablissement_id,user_id,actif,maj_le)
VALUES('a0170000-0000-4000-8000-000000000004','a0170000-0000-4000-8000-000000000001',
  'a0170000-0000-4000-8000-000000000005',true,now()-interval '1 day');
SELECT set_config('request.jwt.claim.sub','a0170000-0000-4000-8000-000000000001',true);
INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,date_emission,date_echeance,date_paiement) VALUES
 ('a0170000-0000-4000-8000-000000000011','a0170000-0000-4000-8000-000000000001','AV-EMISE','AVOIR','EMISE',3,0.6,3.6,now(),current_date-90,NULL),
 ('a0170000-0000-4000-8000-000000000012','a0170000-0000-4000-8000-000000000001','AV-RETARD','AVOIR','EN_RETARD',4,0.8,4.8,now()-interval '1 day',current_date-90,NULL),
 ('a0170000-0000-4000-8000-000000000013','a0170000-0000-4000-8000-000000000001','FAC-PAYEE','FACTURE','PAYEE',14.52,2.90,17.42,now()-interval '20 days',current_date-10,now()-interval '10 days'),
 ('a0170000-0000-4000-8000-000000000014','a0170000-0000-4000-8000-000000000002','AV-AUTRE','AVOIR','EMISE',100,20,120,now(),current_date-90,NULL);
UPDATE public.factures SET facture_precedente_id='a0170000-0000-4000-8000-000000000013'
WHERE numero_facture IN ('AV-EMISE','AV-RETARD');

SAVEPOINT old_defect;
DO $before$
DECLARE r jsonb;
BEGIN
  r:=public.fn_obligations_financieres_internal_20260801();
  IF (r->>'total_commissions_du')::numeric IS DISTINCT FROM 8.4
    OR (r->>'nb_factures_impayees')::int IS DISTINCT FROM 2
    OR jsonb_array_length(r->'factures_impayees') <> 2
    OR (r->>'nb_factures_commission_historique')::int IS DISTINCT FROM 1
    OR (public.fn_stats_dashboard_etablissement()->>'commissions_impayees')::numeric IS DISTINCT FROM 8.4
    OR (SELECT count(*) FROM public.fn_email_factures_impayees()) <> 3
    OR public.fn_blocage_publication_etab(auth.uid())->>'error' IS DISTINCT FROM 'FACTURES_IMPAYEES'
  THEN RAISE EXCEPTION 'AVOIRS_OLD_DEBT_DEFECT_NOT_REPRODUCED'; END IF;
  PERFORM set_config('jolene.test_admin','on',true);
  IF (public.fn_admin_kpi()->>'factures_impayees')::int IS DISTINCT FROM 3
  THEN RAISE EXCEPTION 'AVOIRS_OLD_ADMIN_DEFECT_NOT_REPRODUCED'; END IF;
  PERFORM set_config('jolene.test_admin','off',true);
  r:=public.fn_supprimer_mon_compte_etablissement();
  IF r->>'success' IS DISTINCT FROM 'false'
    OR r->>'error' IS DISTINCT FROM '1 facture(s) impayée(s). Réglez-les avant suppression.'
  THEN RAISE EXCEPTION 'AVOIRS_OLD_DELETION_DEFECT_NOT_REPRODUCED'; END IF;
  PERFORM set_config('jolene.test_admin','on',true);
  PERFORM public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),true,'Témoin avoir');
  r:=public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),false,NULL);
  IF r->>'success' IS DISTINCT FROM 'true'
    OR (SELECT peut_publier_missions FROM etablissements WHERE id=auth.uid()) IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'AVOIRS_OLD_REACTIVATION_DEFECT_NOT_REPRODUCED'; END IF;
  PERFORM set_config('jolene.test_admin','off',true);
  BEGIN
    INSERT INTO missions(etablissement_id) VALUES(auth.uid());
    RAISE EXCEPTION 'AVOIRS_OLD_TRIGGER_DEFECT_NOT_REPRODUCED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Vous avez %facture(s) échue(s) impayée(s)%' THEN RAISE; END IF;
  END;
  r:=public.fn_alerter_paiements_retard();
  IF (r->>'factures_j7')::int<>3 OR (r->>'factures_j21')::int<>3
  THEN RAISE EXCEPTION 'AVOIRS_OLD_REMINDER_DEFECT_NOT_REPRODUCED'; END IF;
  r:=public.fn_gerer_blocage_etabs();
  IF (r->>'blocages')::int<>2 OR public.fn_reverifier_blocage_etab()->>'debloque'<>'false'
  THEN RAISE EXCEPTION 'AVOIRS_OLD_BLOCK_DEFECT_NOT_REPRODUCED'; END IF;
END $before$;
ROLLBACK TO SAVEPOINT old_defect;
RELEASE SAVEPOINT old_defect;
CREATE TEMP TABLE original_factures AS SELECT to_jsonb(f) AS document_row FROM public.factures f;
CREATE TEMP TABLE original_security AS
SELECT p.oid, p.proowner, p.proacl, p.prosecdef, p.provolatile, p.proconfig
FROM pg_proc p WHERE p.pronamespace='public'::regnamespace;
CREATE TEMP TABLE original_inventory AS SELECT * FROM private.security_definer_inventory;

\ir ../../supabase/migrations/20261017191635_exclure_avoirs_des_impayes.sql

DO $credit_only$
DECLARE r jsonb;
BEGIN
  IF EXISTS(SELECT document_row FROM original_factures EXCEPT SELECT to_jsonb(f) FROM factures f)
    OR EXISTS(SELECT to_jsonb(f) FROM factures f EXCEPT SELECT document_row FROM original_factures)
  THEN RAISE EXCEPTION 'AVOIRS_MIGRATION_CHANGED_DOCUMENTS'; END IF;
  r:=public.fn_obligations_financieres_internal_20260801();
  IF (r->>'total_du')::numeric IS DISTINCT FROM 0
    OR (r->>'nb_factures_impayees')::int IS DISTINCT FROM 0
    OR r->'factures_impayees' IS DISTINCT FROM '[]'::jsonb
    OR (r->>'nb_factures_commission_historique')::int IS DISTINCT FROM 3
    OR r#>>'{factures_commission_historique,0,numero_facture}' IS DISTINCT FROM 'AV-EMISE'
    OR r#>>'{factures_commission_historique,0,type_document}' IS DISTINCT FROM 'AVOIR'
    OR (r#>>'{factures_commission_historique,0,montant_ttc}')::numeric IS DISTINCT FROM 3.6
    OR (public.fn_stats_dashboard_etablissement()->>'commissions_impayees')::numeric IS DISTINCT FROM 0
    OR (public.fn_stats_dashboard_etablissement()->>'nb_factures_impayees')::int IS DISTINCT FROM 0
    OR (SELECT count(*) FROM public.fn_email_factures_impayees()) <> 0
    OR public.fn_blocage_publication_etab(auth.uid()) IS NOT NULL
  THEN RAISE EXCEPTION 'AVOIRS_CREDIT_STILL_DEBT_OR_MISSING_HISTORY'; END IF;
  PERFORM set_config('jolene.test_admin','on',true);
  IF (public.fn_admin_kpi()->>'factures_impayees')::int IS DISTINCT FROM 0
  THEN RAISE EXCEPTION 'AVOIRS_ADMIN_CREDIT_STILL_DEBT'; END IF;
  PERFORM set_config('jolene.test_admin','off',true);
  IF NOT public.fn_admin_kpi() ? 'error' THEN RAISE EXCEPTION 'AVOIRS_ADMIN_GUARD_LOST'; END IF;
  INSERT INTO missions(etablissement_id,statut) VALUES(auth.uid(),'BROUILLON');
  PERFORM public.fn_alerter_paiements_retard();
  PERFORM public.fn_gerer_blocage_etabs();
  IF EXISTS(SELECT FROM email_queue) OR EXISTS(SELECT FROM notifications)
    OR EXISTS(SELECT FROM factures WHERE relance_1_le IS NOT NULL OR relance_2_le IS NOT NULL)
    OR EXISTS(SELECT FROM etablissements WHERE bloque_auto_le IS NOT NULL)
  THEN RAISE EXCEPTION 'AVOIRS_CREDIT_REMINDER_OR_BLOCK'; END IF;
  -- Un ancien blocage dû aux seuls avoirs est levé par les chemins existants.
  UPDATE etablissements SET bloque_auto_le=now(), bloque_auto_raisons='{}';
  IF public.fn_reverifier_blocage_etab()->>'debloque' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'AVOIRS_REVERIFY_DID_NOT_UNBLOCK'; END IF;
  IF (public.fn_gerer_blocage_etabs()->>'deblocages')::int IS DISTINCT FROM 1
  THEN RAISE EXCEPTION 'AVOIRS_CRON_DID_NOT_UNBLOCK'; END IF;
  PERFORM set_config('request.jwt.claim.sub','a0170000-0000-4000-8000-000000000002',true);
  r:=public.fn_obligations_financieres_internal_20260801();
  IF (r->>'nb_factures_commission_historique')::int<>1
    OR r#>>'{factures_commission_historique,0,numero_facture}'<>'AV-AUTRE'
  THEN RAISE EXCEPTION 'AVOIRS_HISTORY_TENANCY_LOST'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  IF NOT public.fn_obligations_financieres_internal_20260801() ? 'error'
    OR NOT public.fn_reverifier_blocage_etab() ? 'error'
    OR NOT public.fn_stats_dashboard_etablissement() ? 'error'
  THEN RAISE EXCEPTION 'AVOIRS_MISSING_IDENTITY_GUARD'; END IF;
  PERFORM set_config('request.jwt.claim.sub','a0170000-0000-4000-8000-000000000001',true);
END $credit_only$;

-- Le vrai corps d'anonymisation s'exécute seulement dans le banc transactionnel.
-- Les documents comptables restent inchangés et le SAVEPOINT restaure le compte.
SAVEPOINT credit_account_deletion;
DO $credit_deletion$
DECLARE r jsonb;
BEGIN
  PERFORM set_config('app.internal_operation','fixture-previous-value',true);
  r:=public.fn_supprimer_mon_compte_etablissement();
  IF r->>'success' IS DISTINCT FROM 'true'
    OR NOT EXISTS(SELECT FROM etablissements WHERE id=auth.uid() AND supprime_le IS NOT NULL
      AND nom='Établissement supprimé' AND peut_publier_missions=false)
    OR NOT EXISTS(SELECT FROM journaux_audit WHERE acteur_id=auth.uid() AND action='RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT')
    OR EXISTS(SELECT document_row FROM original_factures EXCEPT SELECT to_jsonb(f) FROM factures f)
    OR EXISTS(SELECT to_jsonb(f) FROM factures f EXCEPT SELECT document_row FROM original_factures)
    OR EXISTS(SELECT FROM private.suppression_etablissement_context)
    OR current_setting('app.internal_operation') IS DISTINCT FROM 'fixture-previous-value'
  THEN RAISE EXCEPTION 'AVOIRS_CREDIT_BLOCKS_DELETION_OR_DOCUMENTS_CHANGED'; END IF;
  IF public.fn_supprimer_mon_compte_etablissement()->>'deja_anonymise' IS DISTINCT FROM 'true'
  THEN RAISE EXCEPTION 'AVOIRS_DELETION_IDEMPOTENCE_CHANGED'; END IF;
END $credit_deletion$;
ROLLBACK TO SAVEPOINT credit_account_deletion;
RELEASE SAVEPOINT credit_account_deletion;

SAVEPOINT genuine_debt_account_deletion;
DO $debt_deletion$
DECLARE r jsonb; document_type text;
BEGIN
  FOREACH document_type IN ARRAY ARRAY['FACTURE','FACTURE_COMPLEMENTAIRE'] LOOP
    INSERT INTO factures(etablissement_id,numero_facture,type_document,statut,montant_ttc,date_echeance)
    VALUES(auth.uid(),'DELETION-'||document_type,document_type,'EN_RETARD',12,current_date-7);
    r:=public.fn_supprimer_mon_compte_etablissement();
    IF r->>'success' IS DISTINCT FROM 'false'
      OR r->>'error' IS DISTINCT FROM '1 facture(s) impayée(s). Réglez-les avant suppression.'
      OR EXISTS(SELECT FROM etablissements WHERE id=auth.uid() AND supprime_le IS NOT NULL)
      OR EXISTS(SELECT FROM journaux_audit WHERE acteur_id=auth.uid())
    THEN RAISE EXCEPTION 'AVOIRS_REAL_DEBT_DELETION_GUARD_LOST: %',document_type; END IF;
    DELETE FROM factures WHERE numero_facture='DELETION-'||document_type;
  END LOOP;
  -- L'avoir ne dispense pas d'une mission encore en cours.
  INSERT INTO missions(etablissement_id,statut,fin_le) VALUES(auth.uid(),'EN_COURS',now()+interval '1 hour');
  r:=public.fn_supprimer_mon_compte_etablissement();
  IF r->>'success' IS DISTINCT FROM 'false'
    OR r->>'error' IS DISTINCT FROM 'Vous avez 1 mission(s) ouverte(s) ou en cours.'
  THEN RAISE EXCEPTION 'AVOIRS_ACTIVE_MISSION_DELETION_GUARD_LOST'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  IF public.fn_supprimer_mon_compte_etablissement()->>'error' IS DISTINCT FROM 'Non authentifié'
  THEN RAISE EXCEPTION 'AVOIRS_DELETION_AUTH_GUARD_LOST'; END IF;
END $debt_deletion$;
ROLLBACK TO SAVEPOINT genuine_debt_account_deletion;
RELEASE SAVEPOINT genuine_debt_account_deletion;

SAVEPOINT administrative_reactivation;
DO $reactivation$
DECLARE r jsonb; document_type text; n integer;
BEGIN
  r:=public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),false,NULL);
  IF r->>'error' IS DISTINCT FROM 'Accès refusé — admin AAL2 uniquement'
  THEN RAISE EXCEPTION 'AVOIRS_REACTIVATION_ADMIN_GUARD_LOST'; END IF;
  PERFORM set_config('jolene.test_admin','on',true);
  SELECT count(*) INTO n FROM journaux_audit;
  PERFORM public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),true,'Témoin avoir');
  IF (SELECT peut_publier_missions FROM etablissements WHERE id=auth.uid()) IS DISTINCT FROM false
    OR NOT EXISTS(SELECT FROM auth.users WHERE id=auth.uid() AND banned_until>now())
    OR EXISTS(SELECT FROM membres_etablissement WHERE etablissement_id=auth.uid() AND actif)
  THEN RAISE EXCEPTION 'AVOIRS_ADMIN_SUSPENSION_CHANGED'; END IF;
  r:=public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),false,NULL);
  IF r->>'success' IS DISTINCT FROM 'true'
    OR (SELECT peut_publier_missions FROM etablissements WHERE id=auth.uid()) IS DISTINCT FROM true
    OR EXISTS(SELECT FROM etablissements WHERE id=auth.uid() AND supprime_le IS NOT NULL)
    OR EXISTS(SELECT FROM auth.users WHERE id=auth.uid() AND banned_until IS NOT NULL)
    OR NOT EXISTS(SELECT FROM membres_etablissement WHERE etablissement_id=auth.uid() AND actif)
    OR (SELECT count(*) FROM journaux_audit)<>n+2
    OR NOT EXISTS(SELECT FROM journaux_audit WHERE action='REACTIVATION_COMPTE' AND id_ressource=auth.uid())
  THEN RAISE EXCEPTION 'AVOIRS_CREDIT_BLOCKS_REACTIVATION_OR_AUDIT_CHANGED'; END IF;
  FOREACH document_type IN ARRAY ARRAY['FACTURE','FACTURE_COMPLEMENTAIRE'] LOOP
    INSERT INTO factures(etablissement_id,numero_facture,type_document,statut,montant_ttc,date_echeance)
    VALUES(auth.uid(),'REACTIVATION-'||document_type,document_type,'EN_RETARD',12,current_date-7);
    PERFORM public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),true,'Témoin dette');
    r:=public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),false,NULL);
    -- Le compte redevient actif ; la publication reste suspendue tant que la dette est échue.
    IF r->>'success' IS DISTINCT FROM 'true'
      OR (SELECT peut_publier_missions FROM etablissements WHERE id=auth.uid()) IS DISTINCT FROM false
      OR EXISTS(SELECT FROM etablissements WHERE id=auth.uid() AND supprime_le IS NOT NULL)
    THEN RAISE EXCEPTION 'AVOIRS_REAL_DEBT_REACTIVATION_GUARD_LOST: %',document_type; END IF;
    DELETE FROM factures WHERE numero_facture='REACTIVATION-'||document_type;
    UPDATE etablissements SET peut_publier_missions=true WHERE id=auth.uid();
  END LOOP;
  UPDATE etablissements SET siret_verifie=false WHERE id=auth.uid();
  PERFORM public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),true,'Témoin qualification');
  PERFORM public.fn_admin_suspendre_utilisateur('etablissements',auth.uid(),false,NULL);
  IF (SELECT peut_publier_missions FROM etablissements WHERE id=auth.uid()) IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'AVOIRS_REACTIVATION_QUALIFICATION_GUARD_LOST'; END IF;
END $reactivation$;
ROLLBACK TO SAVEPOINT administrative_reactivation;
RELEASE SAVEPOINT administrative_reactivation;

-- Tous les états restent distincts ; un complément reste une dette positive.
INSERT INTO factures(etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,date_emission,date_echeance)
SELECT 'a0170000-0000-4000-8000-000000000001', 'FAC-'||etat, 'FACTURE', etat, 10,2,12,now(),current_date+5
FROM unnest(ARRAY['EMISE','EN_RETARD','VIREMENT_DECLARE','BROUILLON','REMPLACEE','ERREUR_GENERATION','ANNULEE']) etat;
INSERT INTO factures(etablissement_id,numero_facture,type_document,statut,montant_ht,montant_tva,montant_ttc,date_emission,date_echeance)
VALUES ('a0170000-0000-4000-8000-000000000001','COMPLEMENT','FACTURE_COMPLEMENTAIRE','EMISE',2,0.4,2.4,now(),current_date+5);
DO $mixed$
DECLARE r jsonb;
BEGIN
  r:=public.fn_obligations_financieres_internal_20260801();
  IF (r->>'total_commissions_du')::numeric IS DISTINCT FROM 26.4
    OR (r->>'nb_factures_impayees')::int IS DISTINCT FROM 3
    OR jsonb_array_length(r->'factures_impayees')<>4
    OR (r->>'nb_factures_commission_historique')::int<>4
    OR NOT EXISTS(SELECT FROM jsonb_array_elements(r->'factures_impayees') f WHERE f->>'type_document'='FACTURE_COMPLEMENTAIRE')
    OR EXISTS(SELECT FROM jsonb_array_elements(r->'factures_impayees') f WHERE f->>'type_document'='AVOIR')
    OR (public.fn_stats_dashboard_etablissement()->>'commissions_impayees')::numeric IS DISTINCT FROM 26.4
  THEN RAISE EXCEPTION 'AVOIRS_MIXED_STATES_OR_COMPLEMENT_CHANGED'; END IF;
  PERFORM set_config('jolene.test_admin','on',true);
  IF (public.fn_admin_kpi()->>'factures_impayees')::int<>3 THEN RAISE EXCEPTION 'AVOIRS_ADMIN_MIXED_COUNT'; END IF;
  PERFORM set_config('jolene.test_admin','off',true);
  -- La présence d'un avoir ne doit pas masquer une dette d'un autre établissement.
  PERFORM set_config('request.jwt.claim.sub','a0170000-0000-4000-8000-000000000002',true);
  IF (public.fn_obligations_financieres_internal_20260801()->>'total_commissions_du')::numeric<>0
  THEN RAISE EXCEPTION 'AVOIRS_DEBT_TENANCY_LOST'; END IF;
  PERFORM set_config('request.jwt.claim.sub','a0170000-0000-4000-8000-000000000001',true);
END $mixed$;

-- Limite de 10 documents : les avoirs récents ne passent pas après les anciennes factures payées.
INSERT INTO factures(etablissement_id,numero_facture,type_document,statut,montant_ttc,date_emission,date_paiement)
SELECT 'a0170000-0000-4000-8000-000000000001','HIST-'||n,'FACTURE','PAYEE',12,
  now()-make_interval(days=>20+n),now()-make_interval(days=>10+n) FROM generate_series(1,12)n;
DO $history$ DECLARE r jsonb; BEGIN
  r:=public.fn_obligations_financieres_internal_20260801();
  IF jsonb_array_length(r->'factures_commission_historique')<>10
    OR (r->>'nb_factures_commission_historique')::int<>16
    OR NOT EXISTS(SELECT FROM jsonb_array_elements(r->'factures_commission_historique') f WHERE f->>'numero_facture'='AV-EMISE')
    OR NOT EXISTS(SELECT FROM jsonb_array_elements(r->'factures_commission_historique') f WHERE f->>'numero_facture'='AV-RETARD')
  THEN RAISE EXCEPTION 'AVOIRS_RECENT_CREDIT_EVICTED_FROM_HISTORY'; END IF;
END $history$;

-- Seuils de relance et déduplication inchangés, y compris les compléments.
TRUNCATE email_queue, notifications;
UPDATE factures SET date_echeance=current_date-7 WHERE numero_facture='FAC-EMISE';
UPDATE factures SET date_echeance=current_date-21 WHERE numero_facture='COMPLEMENT';
DO $reminders$
DECLARE r jsonb; n integer;
BEGIN
  r:=public.fn_alerter_paiements_retard();
  IF (r->>'factures_j7')::int<>2 OR (r->>'factures_j21')::int<>1
    OR EXISTS(SELECT FROM factures WHERE type_document='AVOIR' AND (relance_1_le IS NOT NULL OR relance_2_le IS NOT NULL))
    OR (SELECT count(*) FROM email_queue)<>3
    OR (SELECT count(*) FROM public.fn_email_factures_impayees())<>2
  THEN RAISE EXCEPTION 'AVOIRS_REMINDER_THRESHOLDS_CHANGED'; END IF;
  PERFORM public.fn_alerter_paiements_retard();
  IF (SELECT count(*) FROM email_queue)<>3 THEN RAISE EXCEPTION 'AVOIRS_REMINDER_DUPLICATE'; END IF;
  INSERT INTO emails_envoyes(type,sujet,cree_le) VALUES('RAPPEL_FACTURE','Rappel COMPLEMENT',now());
  IF (SELECT count(*) FROM public.fn_email_factures_impayees())<>1 THEN RAISE EXCEPTION 'AVOIRS_EMAIL_DEDUP_CHANGED'; END IF;
  UPDATE emails_envoyes SET cree_le=now()-interval '8 days';
  IF (SELECT count(*) FROM public.fn_email_factures_impayees())<>2 THEN RAISE EXCEPTION 'AVOIRS_EMAIL_DEDUP_EXPIRY_CHANGED'; END IF;
END $reminders$;

-- Publication : le complément est le seul document débiteur échu.
UPDATE factures SET date_echeance=current_date+5 WHERE numero_facture='FAC-EMISE';
-- Les deux barrières doivent donc le bloquer, indépendamment des factures ordinaires.
DO $publication$ BEGIN
  IF public.fn_blocage_publication_etab(auth.uid())->>'error' IS DISTINCT FROM 'FACTURES_IMPAYEES'
  THEN RAISE EXCEPTION 'AVOIRS_PUBLICATION_DEBT_GUARD_LOST'; END IF;
  BEGIN
    INSERT INTO missions(etablissement_id) VALUES(auth.uid());
    RAISE EXCEPTION 'AVOIRS_TRIGGER_DEBT_GUARD_LOST';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Vous avez %facture(s) échue(s) impayée(s)%' THEN RAISE; END IF;
  END;
  PERFORM set_config('jolene.test_admin','on',true);
  IF public.fn_blocage_publication_etab(auth.uid()) IS NOT NULL THEN RAISE EXCEPTION 'AVOIRS_ADMIN_BYPASS_CHANGED'; END IF;
  INSERT INTO missions(etablissement_id,statut) VALUES(auth.uid(),'BROUILLON');
  PERFORM set_config('jolene.test_admin','off',true);
  UPDATE etablissements SET siret_verifie=false WHERE id=auth.uid();
  IF public.fn_blocage_publication_etab(auth.uid())->>'error' IS DISTINCT FROM 'VERIFICATION_INCOMPLETE'
  THEN RAISE EXCEPTION 'AVOIRS_QUALIFICATION_GUARD_CHANGED'; END IF;
  UPDATE etablissements SET siret_verifie=true,contrat_service_signe=false WHERE id=auth.uid();
  IF public.fn_blocage_publication_etab(auth.uid())->>'error' IS DISTINCT FROM 'CONTRAT_SERVICE_REQUIS'
  THEN RAISE EXCEPTION 'AVOIRS_CONTRACT_GUARD_CHANGED'; END IF;
  UPDATE etablissements SET contrat_service_signe=true WHERE id=auth.uid();
END $publication$;

DO $blocking$
DECLARE r jsonb;
BEGIN
  -- Strictement supérieur à 45 jours ; émission ancienne ne suffit pas.
  UPDATE factures SET date_emission=now()-interval '100 days',date_echeance=current_date-45 WHERE numero_facture='COMPLEMENT';
  PERFORM public.fn_gerer_blocage_etabs();
  IF EXISTS(SELECT FROM etablissements WHERE bloque_auto_le IS NOT NULL) THEN RAISE EXCEPTION 'AVOIRS_BLOCKED_AT_THRESHOLD'; END IF;
  UPDATE factures SET date_echeance=current_date-46 WHERE numero_facture='COMPLEMENT';
  PERFORM public.fn_gerer_blocage_etabs();
  r:=public.fn_reverifier_blocage_etab();
  IF r->>'debloque' IS DISTINCT FROM 'false' OR (r->>'factures_retard_nb')::int IS DISTINCT FROM 1
    OR (SELECT (bloque_auto_raisons->>'factures_retard_montant')::numeric FROM etablissements WHERE id=auth.uid()) IS DISTINCT FROM 2.4
  THEN RAISE EXCEPTION 'AVOIRS_COMPLEMENT_BLOCKING_LOST'; END IF;
  -- Échéance manquante : émission +30 jours reste la référence.
  UPDATE factures SET date_echeance=NULL,date_emission=now()-interval '10 days' WHERE numero_facture='COMPLEMENT';
  IF public.fn_reverifier_blocage_etab()->>'debloque' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'AVOIRS_FALLBACK_FUTURE'; END IF;
  UPDATE factures SET date_emission=now()-interval '76 days' WHERE numero_facture='COMPLEMENT';
  PERFORM public.fn_gerer_blocage_etabs();
  IF public.fn_reverifier_blocage_etab()->>'debloque' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'AVOIRS_FALLBACK_OVERDUE'; END IF;
  UPDATE factures SET date_emission=NULL WHERE numero_facture='COMPLEMENT';
  IF public.fn_reverifier_blocage_etab()->>'debloque' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'AVOIRS_NULL_DATES'; END IF;
  -- Le paramétrage n'est pas remplacé par une constante.
  PERFORM set_config('jolene.test_seuil','15',true);
  UPDATE factures SET date_echeance=current_date-16 WHERE numero_facture='COMPLEMENT';
  PERFORM public.fn_gerer_blocage_etabs();
  IF public.fn_reverifier_blocage_etab()->>'debloque' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'AVOIRS_CUSTOM_THRESHOLD_LOST'; END IF;
  UPDATE factures SET statut='PAYEE' WHERE type_document IN ('FACTURE','FACTURE_COMPLEMENTAIRE') AND statut IN ('EMISE','EN_RETARD');
  PERFORM public.fn_reverifier_blocage_etab();
  PERFORM set_config('jolene.test_seuil','45',true);
END $blocking$;

-- Les salaires directs gardent leurs propres obligations et relances.
INSERT INTO soignants(id,prenom,nom,profession,type_exercice)
VALUES('a0170000-0000-4000-8000-000000000003','Test','Salaire','IDE','SALARIE');
INSERT INTO missions(id,etablissement_id,soignant_assigne_id,intitule,statut,type_contrat_applique,debut_le,fin_le,total_brut,net_a_payer)
VALUES('a0170000-0000-4000-8000-000000000021','a0170000-0000-4000-8000-000000000001','a0170000-0000-4000-8000-000000000003',
 'Salaire témoin','TERMINEE','SALARIE',now()-interval '47 days',now()-interval '46 days',100,80);
DO $salary$ DECLARE r jsonb; BEGIN
  r:=public.fn_obligations_financieres_internal_20260801();
  IF (r->>'total_soignants_du')::numeric<>80 OR (r->>'total_commissions_du')::numeric<>0 THEN RAISE EXCEPTION 'AVOIRS_SALARY_AMOUNT_CHANGED'; END IF;
  r:=public.fn_alerter_paiements_retard();
  IF (r->>'missions_j7')::int<>1 OR (r->>'missions_j21')::int<>1 THEN RAISE EXCEPTION 'AVOIRS_SALARY_REMINDERS_CHANGED'; END IF;
  PERFORM public.fn_gerer_blocage_etabs();
  r:=public.fn_reverifier_blocage_etab();
  IF r->>'debloque' IS DISTINCT FROM 'false' OR (r->>'paiements_retard_nb')::int<>1 OR (r->>'factures_retard_nb')::int<>0
  THEN RAISE EXCEPTION 'AVOIRS_SALARY_BLOCK_CHANGED'; END IF;
  INSERT INTO paiements_soignant(mission_id,etablissement_id,soignant_id,statut,montant_net,date_paiement)
  VALUES('a0170000-0000-4000-8000-000000000021',auth.uid(),'a0170000-0000-4000-8000-000000000003','DECLARE',80,now());
  IF public.fn_reverifier_blocage_etab()->>'debloque' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'AVOIRS_SALARY_SETTLEMENT_CHANGED'; END IF;
END $salary$;

DO $security$ BEGIN
  IF EXISTS(SELECT FROM original_security old JOIN pg_proc p USING(oid)
    WHERE old.proowner IS DISTINCT FROM p.proowner OR old.proacl IS DISTINCT FROM p.proacl
      OR old.prosecdef IS DISTINCT FROM p.prosecdef OR old.provolatile IS DISTINCT FROM p.provolatile
      OR old.proconfig IS DISTINCT FROM p.proconfig)
    OR (SELECT count(*) FROM private.security_definer_inventory)<>5
    OR EXISTS(SELECT FROM original_inventory old LEFT JOIN private.security_definer_inventory i USING(signature)
      WHERE old.categorie IS DISTINCT FROM i.categorie OR old.justification IS DISTINCT FROM i.justification
        OR i.definition_md5 IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.'||i.signature)))
    OR EXISTS(SELECT FROM factures WHERE type_document='AVOIR' AND
      (relance_1_le IS NOT NULL OR relance_2_le IS NOT NULL OR montant_signe>=0 OR date_paiement IS NOT NULL))
  THEN RAISE EXCEPTION 'AVOIRS_SECURITY_OR_CREDIT_STATE_CHANGED'; END IF;
END $security$;
SELECT jsonb_build_object('postgres',17,'oldDefectReproduced',true,'realMigrationLoaded',true,
  'creditExcludedFromDebt',true,'creditHistoryVisible',true,'complementStillPayable',true,
  'statusesAndDueDateThresholdsPreserved',true,'salaryRulesPreserved',true,
  'creditAllowsAccountDeletion',true,'realDebtStillBlocksAccountDeletion',true,
  'creditAllowsAdministrativeReactivation',true,'realDebtStillPreventsPublicationAfterReactivation',true,
  'aclAndClassificationPreserved',true,'automaticCreditApplicationAdded',false,
  'transactionEnd','ROLLBACK') AS avoirs_impayes_proof;
ROLLBACK;
