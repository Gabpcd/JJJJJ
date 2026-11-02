-- Banc commun (schéma minimal, corps LIVE, inventaire, données synthétiques)
-- des tests visibilite-etablissement-permission-*.test.sql. Inclus par \ir
-- après le garde « base vide » de chaque test ; aucune donnée cliente.
SET LOCAL TIME ZONE 'Europe/Paris';
CREATE SCHEMA auth;
CREATE SCHEMA private;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $uid$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$uid$;

CREATE TABLE auth.users (
  id uuid PRIMARY KEY, raw_app_meta_data jsonb, deleted_at timestamptz,
  banned_until timestamptz, email_confirmed_at timestamptz
);
CREATE TABLE public.equipe_admin (user_id uuid, actif boolean, acces_groupes text[]);
CREATE TABLE public.soignants (
  id uuid PRIMARY KEY, prenom text, nom text, profession text,
  score_fiabilite numeric, supprime_le timestamptz
);
CREATE TABLE public.groupes_sante (id uuid PRIMARY KEY, nom text, taux_commission_negocie numeric);
CREATE TABLE public.paliers_commission (id uuid PRIMARY KEY, nom text, taux_commission numeric, missions_min integer);
CREATE TABLE public.etablissements (
  id uuid PRIMARY KEY, nom text, siret text, finess text, type text, groupe_sante_id uuid,
  adresse_rue text, adresse_ville text, adresse_code_postal text, adresse_departement text,
  adresse_lat numeric, adresse_lng numeric, email_contact text, telephone_contact text,
  stripe_customer_id text, stripe_account_id text, taux_commission_negocie numeric,
  mode_facturation text, mode_paiement_commission text, palier_commission_id uuid,
  missions_mois_precedent integer, palier_recalcule_le timestamptz, chorus_pro_actif boolean,
  chorus_pro_identifiant text, delai_paiement_jours integer, formule_abonnement text,
  convention_collective text, couleur_theme text, logo_url text, contrat_url text,
  contrat_uploade_le timestamptz, contrat_valide boolean, contrat_service_signe boolean,
  contrat_service_signe_le timestamptz, rib_s3_key text, rib_ia_coherent boolean,
  iban_last4 text, sms_actif boolean, taux_majoration_nuit_pourcent numeric,
  taux_majoration_dimanche_pourcent numeric, taux_majoration_ferie_pourcent numeric,
  est_secteur_public boolean, peut_publier_missions boolean, statut_verification text,
  note_moyenne numeric, nb_evaluations integer, description text, horaires_ouverture jsonb,
  rist_plafond_actif boolean, rist_taux_base_horaire numeric, bloque_auto_le timestamptz,
  bloque_auto_raisons jsonb, cree_le timestamptz, modifie_le timestamptz, supprime_le timestamptz
);
CREATE TABLE public.membres_etablissement (user_id uuid, etablissement_id uuid, role text, actif boolean);
CREATE TABLE public.missions (
  id uuid PRIMARY KEY, etablissement_id uuid, soignant_assigne_id uuid, statut text,
  code_pointage_actif text, prochain_type_scan text, nb_scans smallint, intitule text,
  debut_le timestamptz, fin_le timestamptz
);
CREATE TABLE public.mission_creneaux (
  id uuid PRIMARY KEY, mission_id uuid, debut timestamptz, fin timestamptz, type_creneau text
);
CREATE TABLE public.conversations (id uuid PRIMARY KEY, participant_1_id uuid, participant_2_id uuid);
CREATE TABLE public.messages_chat (id uuid PRIMARY KEY, conversation_id uuid, auteur_id uuid, lu boolean);
CREATE TABLE public.paiements_soignant (mission_id uuid, statut text);
CREATE TABLE public.factures (
  id uuid PRIMARY KEY, etablissement_id uuid, statut text, type_document text,
  montant_a_payer numeric, montant_ht numeric, rapprochement_paiement_requis boolean
);
CREATE TABLE public.litiges (etablissement_id uuid, statut text);
CREATE TABLE public.candidatures (
  id uuid PRIMARY KEY, mission_id uuid, soignant_id uuid, statut text, cree_le timestamptz
);
CREATE TABLE private.security_definer_inventory (
  signature text PRIMARY KEY, categorie text, definition_md5 text,
  justification text, recense_le timestamptz
);
-- Dépendance hors sujet du compteur pool_urgence_count : vivier vide, identique
-- avant et après (la valeur 0 est comparée comme toutes les autres).
CREATE FUNCTION public.fn_pool_urgence_etablissement(p_etablissement_id uuid)
RETURNS TABLE(soignant_id uuid) LANGUAGE sql STABLE AS $pool$
  SELECT NULL::uuid WHERE false;
$pool$;

\ir visibilite-etablissement-permission-live.sql

-- Inventaire tel qu'en production avant la migration (catégories de
-- 20260729121443 / 20261016125632 / 20261018140952, empreintes LIVE).
INSERT INTO private.security_definer_inventory VALUES
  ('fn_etat_pointage_mission(uuid)', 'MIXTE_TENANT_ADMIN', '3fe46580ddb6d871b4331e41a31a9e05', 'fixture etat', now()),
  ('fn_stats_dashboard_etablissement()', 'RPC_UTILISATEUR_AUTH_INTERNE', '3b6e1d770f15c3d788236f2b57b77a9a', 'fixture stats', now()),
  ('fn_mon_etablissement_complet()', 'RPC_UTILISATEUR_AUTH_INTERNE', 'adec3cf8c4d9bc8c317500222ed2675d', 'fixture profil', now());

-- Acteurs : les cinq rôles d'équipe de l'établissement E, le propriétaire
-- historique (compte = établissement L), l'admin plateforme, un membre d'un
-- autre établissement, le soignant affecté, un soignant tiers, une session
-- sans identité.
INSERT INTO auth.users VALUES
  ('b5b00000-0000-4000-8000-0000000000a1', '{"role":"ADMIN_PLATEFORME"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000b1', '{"role":"ADMIN_ETABLISSEMENT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000b2', '{"role":"ADMIN_ETABLISSEMENT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000b3', '{"role":"ADMIN_ETABLISSEMENT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000b4', '{"role":"ADMIN_ETABLISSEMENT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000b5', '{"role":"ADMIN_ETABLISSEMENT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000c1', '{"role":"ETABLISSEMENT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000d1', '{"role":"ADMIN_ETABLISSEMENT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000f1', '{"role":"SOIGNANT"}', NULL, NULL, now()),
  ('b5b00000-0000-4000-8000-0000000000f2', '{"role":"SOIGNANT"}', NULL, NULL, now());
INSERT INTO public.equipe_admin VALUES ('b5b00000-0000-4000-8000-0000000000a1', true,
  ARRAY['Dashboard','Utilisateurs','Missions','Litiges & contrats','Finances','Messagerie','Conformité & Technique','Fondateur']);
INSERT INTO public.soignants(id, prenom, nom, profession, score_fiabilite) VALUES
  ('b5b00000-0000-4000-8000-0000000000f1', 'Alice', 'Affectée', 'IDE', 4.5),
  ('b5b00000-0000-4000-8000-0000000000f2', 'Bruno', 'Candidat', 'AS', 4.1);
INSERT INTO public.groupes_sante VALUES ('b5b00000-0000-4000-8000-0000000009a1', 'Groupe fixture', 12);
INSERT INTO public.paliers_commission VALUES ('b5b00000-0000-4000-8000-0000000009b1', 'Palier fixture', 14, 0);
INSERT INTO public.etablissements(
  id, nom, siret, type, groupe_sante_id, stripe_customer_id, stripe_account_id,
  mode_paiement_commission, palier_commission_id, rib_s3_key, rib_ia_coherent, iban_last4,
  peut_publier_missions, statut_verification, cree_le, modifie_le
) VALUES
  ('b5b00000-0000-4000-8000-0000000000e1', 'Clinique E', 'siret-fixture-e', 'CLINIQUE_PRIVEE',
   'b5b00000-0000-4000-8000-0000000009a1', 'client-fixture-e', 'compte-fixture-e', 'SEPA_DEBIT',
   'b5b00000-0000-4000-8000-0000000009b1', 'e1/rib-fixture.pdf', true, '0042', true, 'VERIFIE', now(), now()),
  ('b5b00000-0000-4000-8000-0000000000c1', 'Cabinet historique L', 'siret-fixture-l', 'EHPAD_PRIVE',
   NULL, 'client-fixture-l', 'compte-fixture-l', 'FACTURE_MENSUELLE',
   NULL, 'c1/rib-fixture.pdf', NULL, '0077', true, 'VERIFIE', now(), now()),
  ('b5b00000-0000-4000-8000-0000000000e2', 'Clinique E2', 'siret-fixture-e2', 'CLINIQUE_PRIVEE',
   NULL, NULL, NULL, 'FACTURE_MENSUELLE', NULL, NULL, NULL, NULL, true, 'VERIFIE', now(), now());
INSERT INTO public.membres_etablissement VALUES
  ('b5b00000-0000-4000-8000-0000000000b1', 'b5b00000-0000-4000-8000-0000000000e1', 'PROPRIETAIRE', true),
  ('b5b00000-0000-4000-8000-0000000000b2', 'b5b00000-0000-4000-8000-0000000000e1', 'ADMIN_GROUPE', true),
  ('b5b00000-0000-4000-8000-0000000000b3', 'b5b00000-0000-4000-8000-0000000000e1', 'RH', true),
  ('b5b00000-0000-4000-8000-0000000000b4', 'b5b00000-0000-4000-8000-0000000000e1', 'POINTAGE_ONLY', true),
  ('b5b00000-0000-4000-8000-0000000000b5', 'b5b00000-0000-4000-8000-0000000000e1', 'LECTURE_SEULE', true),
  ('b5b00000-0000-4000-8000-0000000000d1', 'b5b00000-0000-4000-8000-0000000000e2', 'RH', true);
-- M1 : mission en cours de E, segment ouvert ; M2 : mission ouverte de E avec
-- candidature ; ML : mission assignée de l'établissement historique L.
INSERT INTO public.missions VALUES
  ('b5b00000-0000-4000-8000-00000000a001', 'b5b00000-0000-4000-8000-0000000000e1',
   'b5b00000-0000-4000-8000-0000000000f1', 'EN_COURS', '123456', 'FERMETURE', 1, 'Nuit IDE',
   now() - interval '2 hours', now() + interval '6 hours'),
  ('b5b00000-0000-4000-8000-00000000a002', 'b5b00000-0000-4000-8000-0000000000e1',
   NULL, 'OUVERTE', NULL, 'OUVERTURE', 0, 'Jour AS',
   now() + interval '2 days', now() + interval '2 days 8 hours'),
  ('b5b00000-0000-4000-8000-00000000a003', 'b5b00000-0000-4000-8000-0000000000c1',
   'b5b00000-0000-4000-8000-0000000000f1', 'ASSIGNEE', '654321', 'OUVERTURE', 0, 'Matin IDE',
   now() + interval '1 day', now() + interval '1 day 7 hours');
INSERT INTO public.mission_creneaux VALUES
  ('b5b00000-0000-4000-8000-00000000c001', 'b5b00000-0000-4000-8000-00000000a001',
   now() - interval '2 hours', NULL, 'EFFECTIF'),
  ('b5b00000-0000-4000-8000-00000000c002', 'b5b00000-0000-4000-8000-00000000a001',
   now() - interval '2 hours', now() + interval '6 hours', 'PREVISIONNEL');
INSERT INTO public.candidatures VALUES
  ('b5b00000-0000-4000-8000-00000000d001', 'b5b00000-0000-4000-8000-00000000a002',
   'b5b00000-0000-4000-8000-0000000000f2', 'EN_ATTENTE', now() - interval '1 hour'),
  ('b5b00000-0000-4000-8000-00000000d002', 'b5b00000-0000-4000-8000-00000000a003',
   'b5b00000-0000-4000-8000-0000000000f2', 'REFUSEE', now() - interval '3 hours');
INSERT INTO public.factures VALUES
  ('b5b00000-0000-4000-8000-00000000e001', 'b5b00000-0000-4000-8000-0000000000e1', 'EMISE', 'FACTURE', 12.5, 10.42, false),
  ('b5b00000-0000-4000-8000-00000000e002', 'b5b00000-0000-4000-8000-0000000000e1', 'PAYEE', 'FACTURE', 0, 20, false),
  ('b5b00000-0000-4000-8000-00000000e003', 'b5b00000-0000-4000-8000-0000000000c1', 'EN_RETARD', 'FACTURE', 30, 25, false);
INSERT INTO public.litiges VALUES ('b5b00000-0000-4000-8000-0000000000e1', 'OUVERT');
INSERT INTO public.conversations VALUES
  ('b5b00000-0000-4000-8000-00000000f001', 'b5b00000-0000-4000-8000-0000000000e1', 'b5b00000-0000-4000-8000-0000000000f1');
INSERT INTO public.messages_chat VALUES
  ('b5b00000-0000-4000-8000-00000000f101', 'b5b00000-0000-4000-8000-00000000f001', 'b5b00000-0000-4000-8000-0000000000f1', false);
