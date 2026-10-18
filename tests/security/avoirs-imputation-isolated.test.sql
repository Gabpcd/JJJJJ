-- Banc PG17 isolé : vraie migration, vrais corps LIVE, dépendances métier minimales.
-- Tables minimales et helpers de contexte seulement ; pas de transport email,
-- de Stripe, de RLS complète ni de preuve frontend dans ce banc.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$ BEGIN
  IF current_setting('jolene.isolated_sql_test', true) IS DISTINCT FROM 'on'
    OR current_database() <> 'avoirs_imputation'
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
\ir fixtures/avoirs-imputation-before.sql
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

\ir ../../supabase/migrations/20261018140952_imputer_avoirs_commission.sql

CREATE FUNCTION pg_temp.exiger(p_ok boolean,p_message text) RETURNS void LANGUAGE plpgsql AS $assert$
BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERTION: %',p_message; END IF; END $assert$;
CREATE FUNCTION pg_temp.refus(p_sql text,p_message text) RETURNS void LANGUAGE plpgsql AS $deny$
DECLARE refuse boolean:=false;
BEGIN BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN refuse:=true; END;
 PERFORM pg_temp.exiger(refuse,p_message); END $deny$;
CREATE FUNCTION pg_temp.document(p_id uuid,p_etab uuid,p_type text,p_ttc numeric,p_statut text DEFAULT 'EMISE',p_origine uuid DEFAULT NULL)
RETURNS void LANGUAGE sql AS $doc$
 INSERT INTO public.factures(id,etablissement_id,numero_facture,type_document,montant_ht,montant_tva,montant_ttc,
   statut,facture_precedente_id,date_emission,date_echeance,mode_paiement)
 VALUES(p_id,p_etab,p_id::text,p_type,round(p_ttc/1.2,2),p_ttc-round(p_ttc/1.2,2),p_ttc,
   p_statut,p_origine,now(),current_date+30,'STRIPE');
$doc$;
INSERT INTO public.etablissements(id,nom,email_contact) VALUES
 ('a0180000-0000-4000-8000-000000000001','A','a@example.invalid'),
 ('a0180000-0000-4000-8000-000000000002','B','b@example.invalid');
SELECT set_config('request.jwt.claim.sub','a0180000-0000-4000-8000-000000000001',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $cases$
DECLARE e uuid:='a0180000-0000-4000-8000-000000000001'; e2 uuid:='a0180000-0000-4000-8000-000000000002';
 original uuid:='a0180000-0000-4000-8000-000000000010'; m uuid:='a0180000-0000-4000-8000-000000000011';
 a1 uuid:='a0180000-0000-4000-8000-000000000012';a2 uuid:='a0180000-0000-4000-8000-000000000013';
 f1 uuid:='a0180000-0000-4000-8000-000000000020';f2 uuid:='a0180000-0000-4000-8000-000000000021';
 f3 uuid:='a0180000-0000-4000-8000-000000000022';f4 uuid:='a0180000-0000-4000-8000-000000000023';
 r jsonb; avant jsonb; v_email_id uuid; compteur integer;
BEGIN
 PERFORM pg_temp.document(original,e,'FACTURE',120);
 INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(m,e,'SALARIE',original);
 PERFORM pg_temp.document(a1,e,'AVOIR',7.20,'EMISE',original);
 PERFORM pg_temp.document(a2,e,'AVOIR',4.80,'EMISE',original);
 -- Aucun avoir historique/ad hoc n'est consommé sans inscription positive.
 PERFORM pg_temp.exiger(NOT EXISTS(SELECT 1 FROM private.avoirs_commission_sources),'pas adoption historique');
 r:=private.fn_inscrire_avoir_commission(a1,m,'LITIGE_SALARIE');
 PERFORM pg_temp.exiger((r->>'eligible')::boolean,'origine non payée admissible sans la réécrire');
 PERFORM private.fn_inscrire_avoir_commission(a2,m,'LITIGE_SALARIE');
 PERFORM private.fn_inscrire_avoir_commission(a1,m,'LITIGE_SALARIE');
 PERFORM pg_temp.exiger((SELECT count(*)=2 FROM private.avoirs_commission_sources),'inscription idempotente');
 SELECT to_jsonb(f) INTO avant FROM factures f WHERE id=original;
 PERFORM pg_temp.document(f1,e,'FACTURE',10,'BROUILLON');
 INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(gen_random_uuid(),e,'SALARIE',f1);
 r:=private.fn_emettre_facture_mensuelle_avec_avoirs(f1);
 PERFORM pg_temp.exiger((r->>'montant_a_payer')::numeric=0,'zéro exact');
 PERFORM pg_temp.exiger((SELECT statut='PAYEE' AND mode_paiement='AVOIR' AND date_paiement IS NOT NULL
   AND stripe_payment_intent_id IS NULL AND montant_ttc=10 AND montant_avoirs_imputes=10 FROM factures WHERE id=f1),'solde avoir sans Stripe ni altération TTC');
 PERFORM pg_temp.exiger((SELECT to_jsonb(f)=avant FROM factures f WHERE id=original),'originale inchangée');
 PERFORM pg_temp.exiger((SELECT sum(montant_cents)=1000 FROM private.avoirs_commission_mouvements WHERE facture_id=f1),'total ledger');
 PERFORM pg_temp.exiger((private.fn_avoirs_commission_detail(a2)->>'avoir_reliquat')::numeric=2,'reliquat conservé');
 PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(f1);
 PERFORM pg_temp.exiger((SELECT count(*)=2 FROM private.avoirs_commission_mouvements WHERE facture_id=f1),'replay sans double consommation');
 SELECT l.email_id INTO v_email_id FROM private.facturation_email_livraisons l WHERE document_id=f1;
 PERFORM pg_temp.exiger((SELECT corps#>>'{data,mode_paiement}'='AVOIR' AND corps#>>'{data,montant_a_payer}'='0.00'
   AND corps#>>'{data,montant_ttc}'='10.00' FROM private.facturation_email_livraisons l WHERE l.email_id=v_email_id),'email émission soldée net/brut');
 PERFORM pg_temp.exiger((public.fn_reserver_email_facturation(v_email_id)->>'statut')='RESERVE','réservation corps exact zéro');
 PERFORM pg_temp.exiger(NOT EXISTS(SELECT 1 FROM private.facturation_email_livraisons WHERE document_id=f1 AND evenement='PAIEMENT'),'pas reçu Stripe fictif');
 PERFORM pg_temp.document(f2,e,'FACTURE',2.01,'BROUILLON');
 INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(gen_random_uuid(),e,'SALARIE',f2);
 PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(f2);
 PERFORM pg_temp.exiger((SELECT montant_a_payer=0.01 AND montant_avoirs_imputes=2 AND statut='EMISE' FROM factures WHERE id=f2),'aucun centime abandonné sous minimum Stripe');
 PERFORM pg_temp.refus(format('UPDATE factures SET montant_avoirs_imputes=0 WHERE id=%L',f2),'imputé non modifiable');
 PERFORM pg_temp.refus(format('UPDATE factures SET montant_ttc=3 WHERE id=%L',f2),'TTC documentaire immuable');
 PERFORM pg_temp.refus('UPDATE private.avoirs_commission_mouvements SET montant_cents=1','journal non modifiable');
 PERFORM pg_temp.refus('DELETE FROM private.avoirs_commission_mouvements','journal non effaçable');
 PERFORM pg_temp.refus(format('UPDATE factures SET statut=''ANNULEE'' WHERE id=%L',f1),'pas restitution avoir déjà soldé');
 UPDATE factures SET statut='ANNULEE' WHERE id=f2;
 PERFORM pg_temp.exiger((SELECT count(*)=1 FROM private.avoirs_commission_mouvements WHERE facture_id=f2 AND nature='RESTITUTION'),'annulation non payée restitue une seule fois');
 UPDATE factures SET statut='ANNULEE' WHERE id=f2;
 PERFORM pg_temp.exiger((private.fn_avoirs_commission_detail(a2)->>'avoir_reliquat')::numeric=2,'restitution exacte source');
 PERFORM pg_temp.exiger((SELECT montant_a_payer=0.01 FROM factures WHERE id=f2),'montant externe historique conservé après annulation');
 PERFORM pg_temp.refus(format('UPDATE factures SET statut=''EMISE'' WHERE id=%L',f2),'pas réactivation dette après restitution');
 PERFORM pg_temp.document(f3,e2,'FACTURE',10,'BROUILLON');
 INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(gen_random_uuid(),e2,'SALARIE',f3);
 PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(f3);
 PERFORM pg_temp.exiger((SELECT montant_a_payer=10 AND montant_avoirs_imputes=0 FROM factures WHERE id=f3),'pas transfert entre établissements');
 PERFORM pg_temp.document(f4,e,'FACTURE',5,'BROUILLON');
 INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(gen_random_uuid(),e,'SALARIE',f4);
 PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(f4);
 PERFORM set_config('request.jwt.claim.sub','',true);
 UPDATE factures SET statut='PAYEE',date_paiement=now(),stripe_payment_intent_id='pi_test_exact' WHERE id=f4;
 PERFORM pg_temp.exiger((SELECT montant_a_payer=3 FROM factures WHERE id=f4),'montant externe stable après paiement');
 UPDATE factures SET rapprochement_paiement_requis=true WHERE id=f4;
 PERFORM pg_temp.exiger((SELECT statut='PAYEE' AND montant_a_payer=3 AND montant_avoirs_imputes=2
   AND stripe_payment_intent_id='pi_test_exact' AND rapprochement_paiement_requis FROM factures WHERE id=f4),'remboursement externe ne crée pas nouvelle dette');
 PERFORM pg_temp.refus(format('UPDATE factures SET statut=''EN_RETARD'' WHERE id=%L',f4),'pas réouverture après signalement');
 PERFORM pg_temp.refus(format('UPDATE factures SET rapprochement_paiement_requis=false WHERE id=%L',f4),'signalement non effaçable sans rapprochement');
 PERFORM pg_temp.exiger(NOT has_function_privilege('authenticated','private.fn_emettre_facture_mensuelle_avec_avoirs(uuid)','EXECUTE')
   AND NOT has_table_privilege('authenticated','private.avoirs_commission_mouvements','SELECT,INSERT,UPDATE,DELETE'),'droits clients fermés');
 PERFORM pg_temp.exiger(NOT has_function_privilege('service_role','private.fn_inscrire_avoir_commission(uuid,uuid,text)','EXECUTE'),'pas RPC service superflue');
END $cases$;
DO $provenance$
DECLARE e uuid:='a0180000-0000-4000-8000-000000000001';
 o uuid:='a0180000-0000-4000-8000-000000000030'; m uuid:='a0180000-0000-4000-8000-000000000031';
 a uuid:='a0180000-0000-4000-8000-000000000032'; ambigu uuid:='a0180000-0000-4000-8000-000000000033';
 r jsonb; before_count integer; q uuid;
BEGIN
 PERFORM pg_temp.document(o,e,'FACTURE',24);
 INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(m,e,'LIBERAL',o);
 PERFORM pg_temp.document(a,e,'AVOIR',3.60,'EMISE',o);
 r:=private.fn_inscrire_avoir_commission(a,m,'RECALCUL_COMMISSION');
 PERFORM pg_temp.exiger((r->>'eligible')::boolean IS FALSE,'libéral sans preuve règlement séparé refusé');
 UPDATE factures SET statut='PAYEE',mode_paiement='VIREMENT',date_paiement=now(),
   virement_reference='FIXTURE-SEPARE',virement_confirme_le=now(),virement_confirme_par=e WHERE id=o;
 r:=private.fn_inscrire_avoir_commission(a,m,'RECALCUL_COMMISSION');
 PERFORM pg_temp.exiger((r->>'eligible')::boolean IS TRUE,'libéral virement séparé confirmé admissible');
 PERFORM pg_temp.document(ambigu,e,'AVOIR',1,'EMISE',o);
 INSERT INTO stripe_transfers(mission_id,facture_id,statut) VALUES(m,o,'REMBOURSE');
 r:=private.fn_inscrire_avoir_commission(ambigu,m,'LITIGE_HONORAIRES');
 PERFORM pg_temp.exiger((r->>'eligible')::boolean IS FALSE,'avoir Connect remboursé jamais crédité');
 PERFORM pg_temp.exiger((private.fn_avoirs_commission_detail(a)->>'avoir_eligible')::boolean IS FALSE,'trace ultérieure ferme source inscrite');
 UPDATE factures SET rapprochement_paiement_requis=true WHERE id=o;
 PERFORM pg_temp.exiger((SELECT statut='PAYEE' AND montant_avoirs_imputes=0 AND rapprochement_paiement_requis FROM factures WHERE id=o),
   'origine déjà réglée signalée sans réouvrir dette');
 PERFORM pg_temp.refus(format('INSERT INTO stripe_payment_flow_claims(resource_key,flow,owner_token) VALUES(%L,''CHECKOUT_INVOICE'',''test'')','FACTURE:'||o),
   'nouveau claim origine à rapprocher refusé');
 PERFORM pg_temp.refus('INSERT INTO stripe_payment_flow_claims(resource_key,flow,owner_token) VALUES(''FACTURE:a0180000-0000-4000-8000-000000000020'',''CHECKOUT_INVOICE'',''test'')',
   'nouveau claim cible zéro refusé');
 PERFORM set_config('request.jwt.claim.sub',e::text,true);
 PERFORM pg_temp.exiger((public.fn_mes_factures_internal_20260801()->0) ? 'montant_a_payer','projection net');
 PERFORM pg_temp.exiger((public.fn_mes_factures_internal_20260801()->0) ? 'rapprochement_paiement_requis','projection signalement');
 -- Le fallback historique ne réécrit jamais le corps réservé et exige zéro allocation.
 SELECT l.email_id INTO q FROM private.facturation_email_livraisons l
   WHERE document_id='a0180000-0000-4000-8000-000000000023' AND evenement='EMISSION';
 UPDATE private.facturation_email_livraisons SET corps=jsonb_set(corps,'{data}',
   (corps->'data')-'montant_avoirs_imputes'-'montant_a_payer'-'mode_paiement'-'rapprochement_paiement_requis')
   WHERE email_id=q;
 UPDATE email_queue SET data=(SELECT corps FROM private.facturation_email_livraisons WHERE email_id=q) WHERE id=q;
 PERFORM pg_temp.exiger((public.fn_reserver_email_facturation(q)->>'statut')='ANNULE','ancien corps sur facture créditée refusé');
 SELECT l.email_id INTO q FROM private.facturation_email_livraisons l
   WHERE document_id='a0180000-0000-4000-8000-000000000021' AND evenement='EMISSION';
 PERFORM pg_temp.exiger((public.fn_reserver_email_facturation(q)->>'statut')='ANNULE','email facture annulée non envoyé');
END $provenance$;
DO $sepa_petits_soldes$
DECLARE e uuid:='a0180100-0000-4000-8000-000000000001';
 o uuid:='a0180100-0000-4000-8000-000000000010'; m uuid:='a0180100-0000-4000-8000-000000000011';
 a uuid; f uuid; c record; r jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO public.etablissements(id,nom,email_contact,mode_paiement_commission)
 VALUES(e,'Petits soldes SEPA','sepa-petits-soldes@example.invalid','SEPA_DEBIT');
 PERFORM pg_temp.document(o,e,'FACTURE',120);
 INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(m,e,'SALARIE',o);
 FOR c IN SELECT * FROM (VALUES(1,0.01::numeric),(2,0.49::numeric),(3,0.50::numeric)) t(numero,net) LOOP
  a:=('a0180100-0000-4000-8000-'||lpad((100+c.numero)::text,12,'0'))::uuid;
  f:=('a0180100-0000-4000-8000-'||lpad((200+c.numero)::text,12,'0'))::uuid;
  PERFORM pg_temp.document(a,e,'AVOIR',1,'EMISE',o);
  PERFORM private.fn_inscrire_avoir_commission(a,m,'LITIGE_SALARIE');
  PERFORM pg_temp.document(f,e,'FACTURE',1+c.net,'BROUILLON');
  INSERT INTO missions(id,etablissement_id,type_contrat_applique,facture_id) VALUES(gen_random_uuid(),e,'SALARIE',f);
  PERFORM private.fn_emettre_facture_mensuelle_avec_avoirs(f);
  r:=private.fn_admission_virement_commission(f);
  IF c.net<0.50 THEN
   PERFORM pg_temp.exiger(r->>'virement_autorise'='true','virement petit solde SEPA après avoir '||c.net);
   UPDATE factures SET stripe_payment_intent_id='pi_fixture_petit_solde' WHERE id=f;
   PERFORM pg_temp.exiger(private.fn_admission_virement_commission(f)->>'motif'='PAIEMENT_EN_LIGNE_ENGAGE',
     'exception SEPA conserve refus PI '||c.net);
   UPDATE factures SET stripe_payment_intent_id=NULL WHERE id=f;
   INSERT INTO stripe_payment_flow_claims(resource_key,flow,owner_token)
   VALUES('FACTURE:'||f::text,'CHECKOUT_INVOICE','fixture:'||f::text);
   PERFORM pg_temp.exiger(private.fn_admission_virement_commission(f)->>'motif'='PAIEMENT_EN_LIGNE_ENGAGE',
     'exception SEPA conserve refus claim '||c.net);
  ELSE
   PERFORM pg_temp.exiger(r->>'virement_autorise'='false' AND r->>'motif'='PAIEMENT_SEPA_AUTOMATIQUE',
     'SEPA 50 centimes garde refus virement');
  END IF;
 END LOOP;
 -- Sans imputation, même un petit TTC reste soumis à la règle SEPA existante.
 f:='a0180100-0000-4000-8000-000000000299';
 PERFORM pg_temp.document(f,e,'FACTURE',0.01);
 PERFORM pg_temp.exiger(private.fn_admission_virement_commission(f)->>'motif'='PAIEMENT_SEPA_AUTOMATIQUE',
   'exception jamais étendue à un TTC sans avoir');
END $sepa_petits_soldes$;
DO $propagation$
DECLARE source_id uuid:='a0180000-0000-4000-8000-000000000010'; avant jsonb; apres jsonb; nb integer;
BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 SELECT jsonb_agg(to_jsonb(f)-'rapprochement_paiement_requis' ORDER BY id) INTO avant
 FROM public.factures f WHERE id IN ('a0180000-0000-4000-8000-000000000020',
   'a0180000-0000-4000-8000-000000000021','a0180000-0000-4000-8000-000000000023');
 UPDATE public.factures SET rapprochement_paiement_requis=true WHERE id=source_id;
 SELECT jsonb_agg(to_jsonb(f)-'rapprochement_paiement_requis' ORDER BY id) INTO apres
 FROM public.factures f WHERE id IN ('a0180000-0000-4000-8000-000000000020',
   'a0180000-0000-4000-8000-000000000021','a0180000-0000-4000-8000-000000000023');
 PERFORM pg_temp.exiger(avant=apres,'propagation ne modifie aucune preuve ni montant');
 PERFORM pg_temp.exiger((SELECT rapprochement_paiement_requis FROM factures
   WHERE id='a0180000-0000-4000-8000-000000000020'),'cible active soldée par avoir signalée');
 PERFORM pg_temp.exiger((SELECT NOT rapprochement_paiement_requis FROM factures
   WHERE id='a0180000-0000-4000-8000-000000000021'),'allocation restituée non propagée');
 SELECT count(*) INTO nb FROM journaux_audit WHERE details->>'evenement'='AVOIR_ORIGINE_A_RAPPROCHER';
 UPDATE factures SET rapprochement_paiement_requis=true WHERE id=source_id;
 PERFORM pg_temp.exiger((SELECT count(*)=nb FROM journaux_audit WHERE details->>'evenement'='AVOIR_ORIGINE_A_RAPPROCHER'),
   'rejeu sans récursion ni nouvel audit');
END $propagation$;
ROLLBACK;
