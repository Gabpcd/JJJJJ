-- Banc commun des tests gardes-null-security-definer-*.test.sql (PostgreSQL 17
-- isolé). Inclus par \ir APRÈS le banc B5b
-- (fixtures/visibilite-etablissement-permission-banc.sql : schémas auth et
-- private, rôles anon/authenticated/service_role, auth.uid() lu dans
-- request.jwt.claim.sub, tables minimales, helpers d'identité LIVE
-- mon_etablissement_id(), est_admin(), fn_role_etablissement_courant(),
-- acteurs et missions synthétiques). Aucune donnée cliente.
-- Ajouts : colonnes et tables lues par fn_presences_detail_mission, un membre
-- révoqué de l'établissement E, les 20 corps LIVE du lot (fixture
-- pg_get_functiondef), leurs ACL et leur inventaire tels qu'en production.
ALTER TABLE public.missions ADD COLUMN duree_heures numeric;
UPDATE public.missions SET duree_heures = 8;
CREATE TABLE public.presences (
  id uuid PRIMARY KEY, mission_id uuid, soignant_id uuid,
  pointage_arrivee_le timestamptz, valide_par_etablissement boolean
);
CREATE TABLE public.pauses_presence (
  id uuid PRIMARY KEY, presence_id uuid, debut_le timestamptz, fin_le timestamptz,
  duree_min integer, motif text
);
-- Membre révoqué (RH inactif) de E.
INSERT INTO auth.users VALUES
  ('b5b00000-0000-4000-8000-0000000000b9', '{"role":"ADMIN_ETABLISSEMENT"}', NULL, NULL, now());
INSERT INTO public.membres_etablissement VALUES
  ('b5b00000-0000-4000-8000-0000000000b9', 'b5b00000-0000-4000-8000-0000000000e1', 'RH', false);

\ir gardes-null-security-definer-live.sql

-- ACL et inventaire LIVE (09/11/2026) : EXECUTE à authenticated et
-- service_role, ni anon ni PUBLIC ; une ligne d'inventaire par fonction,
-- empreinte = md5 du corps (calculée).
DO $gardes_null_banc$
DECLARE
  r record;
  v_oid oid;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('fn_valider_alerte_presence(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_codes_pointage_mission(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_generer_code_secours_mission(uuid,text)', 'MIXTE_TENANT_ADMIN'),
      ('fn_generer_qr_mission(uuid,text)', 'MIXTE_TENANT_ADMIN'),
      ('fn_soignants_urgence(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_generer_donnees_dpae(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_enregistrer_numero_dpae(uuid,text)', 'MIXTE_TENANT_ADMIN'),
      ('fn_rebooker_soignant(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'MIXTE_TENANT_ADMIN'),
      ('fn_booster_mission(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_presences_detail_mission(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_activer_garantie_mission(uuid,boolean)', 'MIXTE_TENANT_ADMIN'),
      ('fn_deposer_chorus(uuid,text)', 'MIXTE_TENANT_ADMIN'),
      ('fn_generer_facture(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_diffuser_pool_urgence(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_etablissement_pour_mission(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_annuler_serie(uuid)', 'MIXTE_TENANT_ADMIN'),
      ('fn_assigner_mission_admin(uuid,uuid,text)', 'MIXTE_TENANT_ADMIN'),
      ('fn_creer_reclamation_score(uuid,text,text,text,text)', 'RPC_UTILISATEUR_AUTH_INTERNE'),
      ('fn_declarer_honoraires_retrocession(uuid,numeric,text)', 'MIXTE_TENANT_ADMIN'),
      ('fn_definir_retrocession_mission(uuid,numeric)', 'MIXTE_TENANT_ADMIN')
    ) AS v(signature, categorie)
  LOOP
    v_oid := pg_catalog.to_regprocedure('public.' || r.signature);
    IF v_oid IS NULL THEN RAISE EXCEPTION 'GARDES_NULL_BANC_FONCTION_ABSENTE: %', r.signature; END IF;
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', v_oid::regprocedure);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_oid::regprocedure);
    INSERT INTO private.security_definer_inventory
      SELECT r.signature, r.categorie, pg_catalog.md5(p.prosrc), 'fixture gardes NULL', now()
        FROM pg_catalog.pg_proc p WHERE p.oid = v_oid;
  END LOOP;
  IF (SELECT count(*) FROM private.security_definer_inventory
       WHERE justification = 'fixture gardes NULL') <> 20 THEN
    RAISE EXCEPTION 'GARDES_NULL_BANC_INVENTAIRE_INCOMPLET';
  END IF;
END
$gardes_null_banc$;
