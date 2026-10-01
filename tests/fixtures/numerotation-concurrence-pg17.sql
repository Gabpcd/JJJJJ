-- PostgreSQL officiel éphémère uniquement. Frontières Auth et tables annexes
-- minimales : ce schéma ne représente ni RLS Supabase ni le graphe métier.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE EXTENSION "uuid-ossp" WITH SCHEMA extensions;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS
  $$ SELECT COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
GRANT USAGE ON SCHEMA public,auth TO anon,authenticated,service_role;
CREATE TABLE public.soignants(id uuid PRIMARY KEY,siret_liberal text);
CREATE TABLE public.missions(id uuid PRIMARY KEY,soignant_assigne_id uuid,
  etablissement_id uuid,type_contrat_applique text);
CREATE TABLE private.security_definer_inventory(signature text PRIMARY KEY,
  categorie text,definition_md5 text,justification text);
CREATE TABLE public.parametres_litiges(cle text PRIMARY KEY,valeur text);
INSERT INTO public.parametres_litiges VALUES('delai_contestation_facture_liberal_h','48');
CREATE TABLE public.notifications(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  destinataire_id uuid,type_destinataire text,type text,titre text,corps text,
  lien text,type_ressource text,id_ressource uuid);
CREATE TABLE public.invoice_audit_log(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid,action text,actor_id uuid,payload_before jsonb,payload_after jsonb);
CREATE TABLE public.stripe_refunds_queue(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  avoir_id uuid UNIQUE,facture_origine_id uuid,stripe_payment_intent_id text,montant_cts integer);
