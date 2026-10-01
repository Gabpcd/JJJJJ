-- Base éphémère CI seulement. Types/tables minimaux, aucune RLS simulée comme réelle.
-- Les fonctions et les deux triggers testés sont extraits des sources actuelles.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $jwt$
 SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb;
$jwt$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $uid$
 SELECT nullif(auth.jwt()->>'sub','')::uuid;
$uid$;
CREATE TABLE public.missions (
 id uuid PRIMARY KEY, soignant_assigne_id uuid, etablissement_id uuid,
 type_contrat_applique text, statut text, strategie_facturation text
);
CREATE TABLE public.factures_honoraires (
 id uuid PRIMARY KEY, mission_id uuid, soignant_id uuid, etablissement_id uuid,
 type_document text, statut text, montant_ttc numeric, est_facture_finale_mission boolean,
 periode_fin date, facture_precedente_id uuid, date_paiement date, modifie_le timestamptz
);
CREATE TABLE public.factures (
 id uuid PRIMARY KEY, mission_id uuid, etablissement_id uuid,
 facture_honoraire_id uuid, type_document text, statut text
);
CREATE TABLE public.paiements_soignant (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid,
 etablissement_id uuid, facture_honoraire_id uuid, montant_net numeric,
 montant_du_reference numeric, solde_restant numeric, est_partiel boolean DEFAULT false,
 source_montant_du text, stripe_transfer_id text, methode text DEFAULT 'VIREMENT',
 reference_virement text, date_paiement date, statut text DEFAULT 'DECLARE',
 confirme_par_etablissement boolean DEFAULT true, confirme_par_soignant boolean DEFAULT false,
 confirme_par_soignant_le timestamptz, modifie_le timestamptz
);
CREATE UNIQUE INDEX ON public.paiements_soignant(stripe_transfer_id) WHERE stripe_transfer_id IS NOT NULL;
CREATE TABLE public.stripe_transfers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid,
 etablissement_id uuid, facture_honoraire_id uuid, montant_soignant numeric, statut text,
 stripe_transfer_id text, stripe_checkout_session_id text, stripe_payment_intent_id text,
 stripe_charge_id text
);
CREATE TABLE public.stripe_payment_flow_claims (
 resource_key text PRIMARY KEY, flow text, owner_token text,
 stripe_checkout_session_id text, stripe_payment_intent_id text,
 cree_le timestamptz DEFAULT now(), modifie_le timestamptz DEFAULT now()
);

-- Colonnes utilisées par le vrai rapprochement legacy, sans ses autres triggers.
ALTER TABLE public.missions ADD net_a_payer numeric, ADD montant_commission_ht numeric, ADD montant_commission_tva numeric, ADD montant_commission_ttc numeric, ADD mode_paiement_soignant text, ADD commission_facturee boolean, ADD modifie_le timestamptz;
ALTER TABLE public.stripe_transfers ADD cree_le timestamptz DEFAULT now(), ADD transfere_le timestamptz, ADD montant_commission numeric, ADD montant_total numeric, ADD erreur text;
ALTER TABLE public.factures_honoraires ADD stripe_payment_intent_id text;
ALTER TABLE public.factures ADD numero_facture text UNIQUE, ADD montant_ht numeric, ADD montant_tva numeric, ADD montant_ttc numeric, ADD taux_tva numeric, ADD nombre_missions integer, ADD date_emission timestamptz, ADD date_paiement timestamptz, ADD mode_paiement text, ADD stripe_payment_intent_id text, ADD modifie_le timestamptz;
ALTER TABLE public.paiements_soignant ADD confirme_par_etablissement_le timestamptz;
CREATE TABLE public.journaux_audit(acteur_id uuid,type_acteur text,action text,type_ressource text,id_ressource uuid,details jsonb,navigateur_acteur text);
