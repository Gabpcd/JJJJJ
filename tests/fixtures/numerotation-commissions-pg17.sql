-- Annexes minimales du témoin de verrous, uniquement PostgreSQL CI éphémère.
-- Les quatre préparateurs, leurs tables de pièces et leurs calculs sont réels ;
-- ni ces profils ni ces agrégats ne représentent les triggers/RLS Supabase.
ALTER TABLE public.missions
  ADD statut text DEFAULT 'EN_COURS',
  ADD taux_commission numeric DEFAULT 15,
  ADD taux_commission_fige numeric DEFAULT 15,
  ADD taux_horaire_base numeric DEFAULT 20,
  ADD total_brut numeric DEFAULT 160,
  ADD net_a_payer numeric DEFAULT 160,
  ADD montant_commission_ht numeric DEFAULT 24,
  ADD montant_commission_tva numeric DEFAULT 4.8,
  ADD montant_commission_ttc numeric DEFAULT 28.8,
  ADD commission_a_recalculer boolean DEFAULT false,
  ADD commission_facturee boolean DEFAULT false,
  ADD facture_id uuid,
  ADD modifie_le timestamptz;
ALTER TABLE private.security_definer_inventory ADD recense_le timestamptz;
CREATE TABLE public.etablissements(id uuid PRIMARY KEY,est_secteur_public boolean DEFAULT false);
CREATE TABLE public.journaux_audit(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  acteur_id uuid,type_acteur text,action text,type_ressource text,id_ressource uuid,
  cle_s3_ressource text,details jsonb,ip_acteur inet,navigateur_acteur text);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULL::uuid $$;
CREATE FUNCTION public.est_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
