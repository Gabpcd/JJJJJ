-- Banc PG17 isolé : vraie migration, vrais corps LIVE, dépendances métier minimales.
-- Tables minimales et helpers de contexte seulement ; pas de transport email,
-- de Stripe, de RLS complète ni de preuve frontend dans ce banc.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'avoirs_imputation_concurrence'
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

-- Dépendances structurelles ; aucune fonction d'allocation/remboursement simulée.
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $jwt$
 SELECT jsonb_build_object('role',current_setting('request.jwt.claim.role',true));
$jwt$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $role$
 SELECT current_setting('request.jwt.claim.role',true);
$role$;
CREATE FUNCTION public.fn_ecrire_audit_safe(p_acteur_id uuid,p_type_acteur text,p_action text,
 p_type_ressource text,p_id_ressource uuid,p_details jsonb) RETURNS void LANGUAGE sql AS $audit$
 INSERT INTO public.journaux_audit(acteur_id,type_acteur,action,type_ressource,id_ressource,details)
 VALUES(p_acteur_id,p_type_acteur,p_action,p_type_ressource,p_id_ressource,p_details);
$audit$;
ALTER TABLE public.factures ADD COLUMN taux_tva numeric DEFAULT 20,
 ADD COLUMN stripe_invoice_id text,ADD COLUMN virement_confirme_par uuid,
 ADD COLUMN virement_confirme_le timestamptz,ADD COLUMN chorus_pro_id text,
 ADD COLUMN chorus_pro_deposee_le timestamptz,ADD COLUMN periode_debut date,ADD COLUMN periode_fin date,
 ADD COLUMN cree_le timestamptz DEFAULT now(),ADD COLUMN modifie_le timestamptz DEFAULT now(),
 ADD CONSTRAINT factures_mode_paiement_check CHECK(mode_paiement IN('STRIPE','VIREMENT','CHORUS_PRO'));
ALTER TABLE public.missions ADD COLUMN facture_id uuid,ADD COLUMN commission_facturee boolean DEFAULT false,
 ADD COLUMN montant_commission_tva numeric,ADD COLUMN mode_remuneration text,ADD COLUMN honoraires_confirmes_le timestamptz;
ALTER TABLE public.stripe_transfers ADD COLUMN mission_id uuid,ADD COLUMN facture_id uuid;
CREATE TABLE public.paiements_escrow(id uuid PRIMARY KEY,mission_id uuid);
CREATE TABLE public.presences(id uuid PRIMARY KEY);
CREATE TABLE public.cotisations_sociales(id uuid PRIMARY KEY);
CREATE TABLE public.bulletins_paie(id uuid PRIMARY KEY);
CREATE TABLE public.stripe_payment_flow_claims(resource_key text PRIMARY KEY,flow text,owner_token text,
 stripe_checkout_session_id text,stripe_payment_intent_id text,cree_le timestamptz DEFAULT now(),modifie_le timestamptz DEFAULT now());
CREATE TABLE public.parrainages_etablissements(id uuid,filleul_etab_id uuid,statut text,palier2_atteint_le timestamptz);
CREATE TABLE private.facturation_email_livraisons(email_id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
 famille text,document_id uuid,destinataire_id uuid,evenement text DEFAULT 'EMISSION',corps jsonb,idempotency_key text,
 prochaine_tentative_le timestamptz DEFAULT now(),premiere_tentative_le timestamptz,tentatives integer DEFAULT 0,reservation uuid,
 UNIQUE(famille,document_id,destinataire_id,evenement));
CREATE TABLE private.email_dispatch_idempotency(idempotency_key text,statut text);
ALTER TABLE public.email_queue ADD COLUMN id uuid,ADD COLUMN statut text,ADD COLUMN erreur text,
 ADD COLUMN envoye boolean,ADD COLUMN envoye_le timestamptz;
ALTER TABLE public.etablissements ADD COLUMN est_secteur_public boolean DEFAULT false,
 ADD COLUMN mode_paiement_commission text;
\ir avoirs-imputation-before.sql
CREATE TRIGGER dec_idempotence_facture BEFORE UPDATE ON public.factures
 FOR EACH ROW EXECUTE FUNCTION public.dec_idempotence_facture_payee();
CREATE TRIGGER dec_bloquer_paiement_manuel BEFORE UPDATE ON public.factures
 FOR EACH ROW EXECUTE FUNCTION public.dec_bloquer_paiement_manuel_facture();
CREATE TRIGGER dec_valider_paiement BEFORE UPDATE ON public.factures
 FOR EACH ROW EXECUTE FUNCTION public.dec_valider_paiement_facture();
CREATE TRIGGER trg_email_emission_commission AFTER INSERT OR UPDATE OF statut ON public.factures
 FOR EACH ROW EXECUTE FUNCTION private.mettre_emission_facture_en_file();
CREATE TRIGGER trg_email_paiement_commission AFTER UPDATE OF statut ON public.factures
 FOR EACH ROW EXECUTE FUNCTION private.mettre_paiement_facture_en_file();
CREATE TRIGGER trg_parrainage_commission_encaissee AFTER INSERT OR UPDATE OF statut ON public.factures
 FOR EACH ROW EXECUTE FUNCTION public.fn_trg_parrainage_commission_encaissee();
CREATE TRIGGER trg_valider_parrainage_etab_commission AFTER INSERT OR UPDATE ON public.factures
 FOR EACH ROW EXECUTE FUNCTION public.fn_trg_valider_parrainage_etab_commission();

\ir ../../../supabase/migrations/20261018140952_imputer_avoirs_commission.sql


COMMIT; -- Base CI éphémère uniquement : les deux écrivains doivent voir les vraies fonctions.
