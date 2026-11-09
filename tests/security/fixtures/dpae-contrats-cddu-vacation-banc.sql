-- Banc commun des tests dpae-contrats-cddu-vacation-*.test.sql (PostgreSQL 17
-- isolé). Inclus par \ir après le garde « base vide » de chaque test.
-- Schéma minimal : seules les colonnes lues ou écrites par les cinq corps LIVE.
-- Les CHECK de type de contrat et de file externalisation_actions sont ceux de
-- production (pg_get_constraintdef relu le 08/11/2026). Volontairement absents :
-- le CHECK de statut des contrats et les triggers de protection
-- (fn_protect_contrat_integrity, dec_proteger_signature_contrat), qui en
-- production rétablissent le statut quand le soignant annule ; la branche
-- DPAE de fn_annuler_candidature_soignant lit le contrat AVANT cet UPDATE dans
-- les deux cas. Transport (net.http_post), coffre (vault) et identité
-- (auth.uid) sont des doublures locales ; aucune donnée cliente.
SET LOCAL TIME ZONE 'Europe/Paris';
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE SCHEMA net;
CREATE SCHEMA vault;
DO $roles$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
END $roles$;

CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $uid$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$uid$;

CREATE TABLE vault.decrypted_secrets (name text PRIMARY KEY, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES ('service_role_key', 'cle-factice-banc-dpae');

-- Doublure de pg_net : chaque appel est consigné avec la phase du banc.
CREATE TABLE net.appels (
  id bigserial PRIMARY KEY, phase text, url text, headers jsonb, body jsonb
);
CREATE FUNCTION net.http_post(
  url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{"Content-Type": "application/json"}'::jsonb,
  timeout_milliseconds integer DEFAULT 5000
) RETURNS bigint LANGUAGE sql AS $http_post$
  INSERT INTO net.appels (phase, url, headers, body)
  VALUES (current_setting('banc.phase', true), url, headers, body)
  RETURNING id;
$http_post$;

CREATE TABLE private.security_definer_inventory (
  signature text PRIMARY KEY, categorie text NOT NULL, definition_md5 text NOT NULL,
  justification text NOT NULL, recense_le timestamptz NOT NULL
);
-- Comptes de test : le banc n'en contient aucun (même réponse que la prod
-- pour un compte réel).
CREATE FUNCTION private.fn_contrat_lie_compte_test(
  p_mission_id uuid, p_soignant_id uuid, p_etablissement_id uuid
) RETURNS boolean LANGUAGE sql STABLE AS $compte_test$
  SELECT false;
$compte_test$;

CREATE TABLE public.etablissements (
  id uuid PRIMARY KEY, nom text, adresse_lat numeric, adresse_lng numeric,
  tolerance_pointage_m integer
);
CREATE TABLE public.missions (
  id uuid PRIMARY KEY, etablissement_id uuid NOT NULL, intitule text,
  debut_le timestamptz, fin_le timestamptz, statut text NOT NULL,
  soignant_assigne_id uuid, code_arrivee text, est_asap boolean DEFAULT false,
  modifie_le timestamptz
);
CREATE TABLE public.contrats_mission (
  id uuid PRIMARY KEY,
  mission_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  type_contrat text NOT NULL,
  numero_contrat text NOT NULL UNIQUE,
  statut text DEFAULT 'BROUILLON',
  signature_soignant_le timestamptz,
  dpae_effectuee boolean DEFAULT false,
  dpae_effectuee_le timestamptz,
  dpae_numero text,
  rappel_dpae_affiche boolean DEFAULT false,
  rappel_dpae_affiche_le timestamptz,
  mode_signature text DEFAULT 'CANVAS',
  modifie_le timestamptz DEFAULT now(),
  CONSTRAINT contrats_mission_type_contrat_check CHECK (type_contrat = ANY (ARRAY['CDDU'::text, 'VACATION'::text, 'REMPLACEMENT_LIBERAL'::text, 'CDD'::text]))
);
CREATE TABLE public.presences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), mission_id uuid, soignant_id uuid,
  pointage_arrivee_le timestamptz, arrivee_lat numeric, arrivee_lng numeric,
  arrivee_precision_gps_m numeric, arrivee_id_terminal text, arrivee_modele_terminal text,
  methode_pointage_arrivee text, distance_etablissement_m numeric, perimetre_gps_valide boolean
);
CREATE TABLE public.candidatures (
  id uuid PRIMARY KEY, mission_id uuid, soignant_id uuid, statut text,
  acceptee_a timestamptz, traite_le timestamptz, motif_refus text
);
CREATE TABLE public.externalisation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type_action text NOT NULL,
  payload jsonb NOT NULL,
  source text NOT NULL,
  source_id uuid,
  statut text NOT NULL DEFAULT 'PENDING',
  cree_le timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT externalisation_actions_source_check CHECK (source = ANY (ARRAY['LITIGE_EXEC'::text, 'ANNULATION_MISSION'::text, 'AUTRE'::text, 'CRON_ANTI_TRICHE'::text, 'CRON_ALERTES'::text, 'parrainage_soignant'::text, 'remboursement_avoir'::text])),
  CONSTRAINT externalisation_actions_type_action_check CHECK (type_action = ANY (ARRAY['STRIPE_REFUND_PARTIEL'::text, 'STRIPE_REFUND_TOTAL'::text, 'STRIPE_PAYMENT'::text, 'STRIPE_PAYOUT'::text, 'CHORUS_RECYCLER_FACTURE'::text, 'CHORUS_RECYCLE_FACTURE'::text, 'DPAE_ANNULATION'::text, 'DPAE_ANNULATION_NOTIF'::text, 'EMAIL_NOTIF'::text, 'SMS_NOTIF'::text, 'PUSH_NOTIF'::text, 'PUSH_CANDIDATURE_RECUE'::text, 'AVOIR_PDF_GENERATION'::text, 'RECOMPENSE_PARRAINAGE_SOIGNANT'::text, 'REMBOURSEMENT_AVOIR_SWAN'::text]))
);
CREATE TABLE public.evenements_score_soignant (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), soignant_id uuid, type_evenement text,
  points integer, motif text, contestable boolean, mission_id uuid, candidature_id uuid,
  justificatif_storage_path text, details jsonb
);
CREATE TABLE public.journaux_audit (
  id bigserial PRIMARY KEY, acteur_id uuid, type_acteur text, action text,
  type_ressource text, id_ressource uuid, details jsonb, cree_le timestamptz DEFAULT now()
);
-- Pénalité hors sujet : aucune (annulation sans impact), identique avant/après.
CREATE FUNCTION public.fn_calculer_penalite_annulation_soignant(
  p_acceptee_a timestamptz, p_debut_mission timestamptz, p_est_asap boolean
) RETURNS jsonb LANGUAGE sql STABLE AS $penalite$
  SELECT '{"libre": true, "points": 0, "motif": "BANC_SANS_PENALITE", "signalement_admin": false}'::jsonb;
$penalite$;

\ir dpae-contrats-cddu-vacation-live.sql

-- ACL de production (proacl relus le 08/11/2026).
REVOKE ALL ON FUNCTION public.fn_mes_dpae() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mes_dpae() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_mes_dpae() TO service_role;
REVOKE ALL ON FUNCTION public.fn_rappel_dpae_quotidien() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_rappel_dpae_quotidien() TO service_role;
REVOKE ALL ON FUNCTION public.fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.fn_annuler_candidature_soignant(uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_annuler_candidature_soignant(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_annuler_candidature_soignant(uuid,text,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.dec_email_contrat_signe_complet() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dec_email_contrat_signe_complet() TO service_role;

-- Inventaire tel qu'en production : les trois RPC recensées, empreinte du
-- corps LIVE chargé (calculée), catégorie LIVE.
INSERT INTO private.security_definer_inventory
SELECT v.signature, 'RPC_UTILISATEUR_AUTH_INTERNE', md5(p.prosrc), 'fixture ' || v.signature, now()
  FROM (VALUES ('fn_mes_dpae()'),
               ('fn_pointer_arrivee(uuid,numeric,numeric,numeric,text,text,text)'),
               ('fn_annuler_candidature_soignant(uuid,text,text,text)')) AS v(signature)
  JOIN pg_proc p ON p.oid = to_regprocedure('public.' || v.signature);

CREATE TRIGGER trg_dec_email_contrat_signe_complet
  AFTER UPDATE OF statut ON public.contrats_mission
  FOR EACH ROW EXECUTE FUNCTION public.dec_email_contrat_signe_complet();

-- Identifiants : d9ae<groupe>-0000-4000-8000-0000000000<phase><cas>.
-- Groupes : 0001/0002 liste et rappel ; 0003/0004 pointage ; 0005/0006/0007
-- annulation (mission, candidature, contrat) ; 0008/0009 contrat signé.
CREATE FUNCTION pg_temp.banc_id(p_groupe text, p_phase integer, p_cas integer)
RETURNS uuid LANGUAGE sql IMMUTABLE AS $banc_id$
  SELECT ('d9ae' || p_groupe || '-0000-4000-8000-0000000000' || p_phase || p_cas)::uuid;
$banc_id$;

INSERT INTO public.etablissements VALUES
  ('d9ae0000-0000-4000-8000-0000000000e1', 'Clinique banc DPAE', 48.85, 2.35, 500);

-- Cas des groupes « liste » et « rappel » (lus avant et après, jamais modifiés).
CREATE TEMP TABLE banc_cas_liste (cas integer PRIMARY KEY, type_contrat text, statut text,
  dpae_effectuee boolean, dpae_numero text, signe_il_y_a interval);
INSERT INTO banc_cas_liste VALUES
  (1, 'CDD', 'SIGNE_COMPLET', false, NULL, interval '2 days'),
  (2, 'CDDU', 'SIGNE_COMPLET', false, NULL, interval '2 days'),
  (3, 'VACATION', 'SIGNE_COMPLET', false, NULL, interval '2 days'),
  (4, 'REMPLACEMENT_LIBERAL', 'SIGNE_COMPLET', false, NULL, interval '2 days'),
  (5, 'CDDU', 'EN_ATTENTE_SIGNATURES', false, NULL, interval '2 days'),
  (6, 'VACATION', 'SIGNE_COMPLET', true, 'DPAE12345678', interval '2 days'),
  (7, 'CDD', 'SIGNE_COMPLET', false, NULL, interval '10 days');
INSERT INTO public.missions(id, etablissement_id, intitule, debut_le, fin_le, statut, soignant_assigne_id)
VALUES (pg_temp.banc_id('0001', 0, 1), 'd9ae0000-0000-4000-8000-0000000000e1', 'Mission liste DPAE',
        now() + interval '3 days', now() + interval '3 days 8 hours', 'ASSIGNEE',
        'd9ae0000-0000-4000-8000-0000000000a1');
INSERT INTO public.contrats_mission(id, mission_id, etablissement_id, soignant_id, type_contrat,
  numero_contrat, statut, signature_soignant_le, dpae_effectuee, dpae_numero)
SELECT pg_temp.banc_id('0002', 0, c.cas), pg_temp.banc_id('0001', 0, 1),
       'd9ae0000-0000-4000-8000-0000000000e1', 'd9ae0000-0000-4000-8000-0000000000a1',
       c.type_contrat, 'BANC-LISTE-' || c.cas, c.statut, now() - c.signe_il_y_a,
       c.dpae_effectuee, c.dpae_numero
  FROM banc_cas_liste c;

-- Cas des groupes pointage (1 à 5), annulation et contrat signé (1 à 4), une
-- série par phase (1 = avant, 2 = après) : ces fonctions écrivent.
CREATE TEMP TABLE banc_cas_types (cas integer PRIMARY KEY, type_contrat text, dpae_numero text);
INSERT INTO banc_cas_types VALUES
  (1, 'CDD', NULL), (2, 'CDDU', NULL), (3, 'VACATION', NULL),
  (4, 'REMPLACEMENT_LIBERAL', NULL), (5, 'CDDU', 'DPAE87654321');
INSERT INTO public.missions(id, etablissement_id, intitule, debut_le, fin_le, statut,
  soignant_assigne_id, code_arrivee)
SELECT pg_temp.banc_id(g.groupe, ph, c.cas), 'd9ae0000-0000-4000-8000-0000000000e1',
       'Mission banc ' || g.groupe || '-' || ph || c.cas,
       now() + interval '10 days', now() + interval '10 days 8 hours', 'ASSIGNEE',
       g.soignant, '2468'
  FROM (VALUES ('0003', 'd9ae0000-0000-4000-8000-0000000000a2'::uuid, 5),
               ('0005', 'd9ae0000-0000-4000-8000-0000000000a3'::uuid, 4),
               ('0008', 'd9ae0000-0000-4000-8000-0000000000a4'::uuid, 4)) AS g(groupe, soignant, nb)
  CROSS JOIN generate_series(1, 2) AS ph
  JOIN banc_cas_types c ON c.cas <= g.nb;
INSERT INTO public.contrats_mission(id, mission_id, etablissement_id, soignant_id, type_contrat,
  numero_contrat, statut, dpae_numero)
SELECT pg_temp.banc_id(g.contrat, ph, c.cas), pg_temp.banc_id(g.mission, ph, c.cas),
       'd9ae0000-0000-4000-8000-0000000000e1', g.soignant, c.type_contrat,
       'BANC-' || g.contrat || '-' || ph || c.cas, g.statut,
       CASE WHEN g.contrat = '0004' THEN c.dpae_numero END
  FROM (VALUES ('0003', '0004', 'd9ae0000-0000-4000-8000-0000000000a2'::uuid, 5, 'SIGNE_COMPLET'),
               ('0005', '0007', 'd9ae0000-0000-4000-8000-0000000000a3'::uuid, 4, 'SIGNE_COMPLET'),
               ('0008', '0009', 'd9ae0000-0000-4000-8000-0000000000a4'::uuid, 4, 'SIGNE_ETABLISSEMENT'))
       AS g(mission, contrat, soignant, nb, statut)
  CROSS JOIN generate_series(1, 2) AS ph
  JOIN banc_cas_types c ON c.cas <= g.nb;
INSERT INTO public.candidatures(id, mission_id, soignant_id, statut, acceptee_a)
SELECT pg_temp.banc_id('0006', ph, c.cas), pg_temp.banc_id('0005', ph, c.cas),
       'd9ae0000-0000-4000-8000-0000000000a3', 'ACCEPTEE', now() - interval '2 days'
  FROM generate_series(1, 2) AS ph
  JOIN banc_cas_types c ON c.cas <= 4;
