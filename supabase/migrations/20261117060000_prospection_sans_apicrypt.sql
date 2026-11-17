-- Prospection sans adresses Apicrypt (17/11/2026).
--
-- Constat prod (passage du 17/11 à 05:50 UTC, le premier après
-- 20261116143942) : les 7 brouillons de prospection préparés visent tous une
-- adresse @interop-mssante.apicrypt.org. Ce sont les adresses que les
-- utilisateurs d'Apicrypt, messagerie de santé sécurisée, publient dans
-- l'annuaire national MSSanté pour échanger avec l'espace de confiance
-- (FAQ Apicrypt, https://www.apicrypt.org/files/FAQ_mars2019_BD.pdf :
-- « prenom.nom@interop-mssante.apicrypt.org ») : messagerie fermée, un email
-- envoyé depuis le Gmail de la fondatrice n'y parvient pas, comme pour
-- mssante.fr. La règle de 20261116143942 ne reconnaissait que mssante.fr et ses
-- sous-domaines ; prospects_etablissements compte 554 adresses
-- interop-mssante.apicrypt.org au 17/11.
--
-- 0. Préflight fail-closed (CLAUDE.md, garde-fous 9.0 n°2 : toute
--    redéfinition part de la définition LIVE) : private.fn_growth_email_mssante
--    doit être, en base, exactement celle de 20261116143942 (md5(prosrc),
--    SECURITY INVOKER, IMMUTABLE, search_path vide). Empreinte = md5 du texte
--    compris entre les deux délimiteurs $body$ de 20261116143942, recalculée
--    par tests/node/prospection-sans-apicrypt.node.mjs et relue en prod le
--    17/11. Les quatre fonctions de 20261116143942 qui portent l'effet de la
--    règle sont verrouillées de même (revue B8 de #1134, m1) : le prédicat
--    fn_growth_destinataire_bloque et l'agent fn_growth_agent_prospection, qui
--    doivent l'appeler, l'expiration qui écrit en prod et le motif que relit le
--    quota du jour. Sinon la migration entière est refusée avant toute écriture.
-- 1. Règle unique élargie : apicrypt.org et ses sous-domaines, en plus de
--    mssante.fr et ses sous-domaines (casse et blancs de bord ignorés ; NULL =
--    false). Force des sources : la FAQ Apicrypt fonde interop-mssante.apicrypt.org
--    (adresse MSSanté des apicrypteurs) ; le reste d'apicrypt.org (messagerie
--    chiffrée entre apicrypteurs) est un CHOIX DE CONFORMITÉ JOLENE, prudent :
--    aucune adresse de prospects_etablissements n'en relève au 17/11, et une
--    adresse joignable bloquée à tort coûte moins qu'un envoi rejeté. Le nom de la fonction et le motif d'expiration restent ceux de
--    20261116143942 : les adresses interop-mssante sont des adresses MSSanté,
--    et le quota du jour de l'agent relit ce motif à l'identique. Le prédicat
--    fn_growth_destinataire_bloque (validation et constat d'envoi), l'agent de
--    prospection et l'expiration appellent cette règle : aucun d'eux n'est
--    redéfini.
-- 2. REVOKE d'origine rejoué (CREATE OR REPLACE conserve propriétaire et ACL).
-- 3. private.fn_growth_expirer_brouillons_mssante() (20261116143942) : expire
--    les brouillons Apicrypt de l'agent encore en file (BROUILLON ou VALIDE),
--    sans DELETE.
-- Non bloqué faute de source primaire : gmsi-mssante.fr (1 adresse au 17/11).
-- Aucune fonction SECURITY DEFINER, aucun GRANT : rien à inventorier dans
-- private.security_definer_inventory.

DO $prospection_sans_apicrypt_avant$
DECLARE
  p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = pg_catalog.to_regprocedure('private.fn_growth_email_mssante(text)');
  IF NOT FOUND
    OR pg_catalog.md5(p.prosrc) <> 'b3e53f83ac32ed999ced5d7e66c83d4a'
    OR p.prosecdef IS DISTINCT FROM false
    OR p.provolatile <> 'i'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
  THEN
    RAISE EXCEPTION 'PROSPECTION_SANS_APICRYPT_SOURCE_AVANT_DIVERGENTE : private.fn_growth_email_mssante(text) en base (md5 %, prosecdef %, volatilité %, search_path %) ne correspond plus au corps de 20261116143942 (md5 b3e53f83ac32ed999ced5d7e66c83d4a, SECURITY INVOKER, IMMUTABLE, search_path vide). Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
      COALESCE(pg_catalog.md5(p.prosrc), 'fonction absente'), p.prosecdef, p.provolatile, p.proconfig;
  END IF;

  -- Fonctions de 20261116143942 qui appliquent la règle : corps LIVE = corps du
  -- dépôt (md5 relus en prod le 17/11), SECURITY INVOKER, search_path vide.
  FOR p IN
    SELECT v.signature, v.empreinte, v.volatilite, f.prosrc, f.prosecdef, f.provolatile, f.proconfig
    FROM (VALUES
      ('private.fn_growth_destinataire_bloque(text,text,text,text,text)', 'dd7d2f13403693c74fde8ece09452928', 's'),
      ('private.fn_growth_agent_prospection()', '2ccf9311871dfc416d609f0112da9a5b', 'v'),
      ('private.fn_growth_expirer_brouillons_mssante()', '4d3cf88d3acbc31eafbe0366231c9d10', 'v'),
      ('private.fn_growth_motif_expiration_mssante()', '07b4d85eaf6cf499c62e4f9d6590e693', 'i')
    ) AS v(signature, empreinte, volatilite)
    LEFT JOIN pg_catalog.pg_proc f ON f.oid = pg_catalog.to_regprocedure(v.signature)
  LOOP
    IF p.prosrc IS NULL
      OR pg_catalog.md5(p.prosrc) <> p.empreinte
      OR p.prosecdef IS DISTINCT FROM false
      OR p.provolatile::text <> p.volatilite
      OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
    THEN
      RAISE EXCEPTION 'PROSPECTION_SANS_APICRYPT_APPELANT_DIVERGENT : % en base (md5 %, prosecdef %, volatilité %, search_path %) ne correspond plus au corps de 20261116143942 (md5 %, SECURITY INVOKER, search_path vide) : l''effet de la règle n''est plus garanti. Redéfinition refusée : repartir de la définition LIVE (CLAUDE.md, garde-fous 9.0 n°2).',
        p.signature, COALESCE(pg_catalog.md5(p.prosrc), 'fonction absente'), p.prosecdef, p.provolatile, p.proconfig, p.empreinte;
    END IF;
  END LOOP;
END;
$prospection_sans_apicrypt_avant$;

-- ---------------------------------------------------------------------------
-- 1. Règle unique : messageries de santé fermées (MSSanté, Apicrypt)
-- ---------------------------------------------------------------------------
-- true si l'adresse relève de mssante.fr ou d'apicrypt.org (domaine ou
-- sous-domaine). Faux amis non exclus : pasmssante.fr, mssante.fr.exemple.com,
-- mssante-fr.fr, pasapicrypt.org, apicrypt.org.exemple.com, apicrypt-org.fr.
CREATE OR REPLACE FUNCTION private.fn_growth_email_mssante(p_email text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $body$
  SELECT COALESCE(lower(btrim(p_email, E' \t\r\n')) ~ '[@.](mssante\.fr|apicrypt\.org)$', false);
$body$;

REVOKE ALL ON FUNCTION private.fn_growth_email_mssante(text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Expiration des brouillons Apicrypt encore en file
-- ---------------------------------------------------------------------------
DO $prospection_sans_apicrypt_expiration$
DECLARE
  v_n integer;
BEGIN
  v_n := private.fn_growth_expirer_brouillons_mssante();
  RAISE NOTICE 'Brouillons Apicrypt de l''agent de prospection expirés : %', v_n;

  -- Post-condition : le prédicat unique refuse une adresse interop-mssante, un
  -- faux ami reste joignable, et plus aucun brouillon de prospection en file ne
  -- relève de la règle (sinon toute la migration est annulée).
  IF private.fn_growth_destinataire_bloque('PUBLIC', NULL, 'postcondition@interop-mssante.apicrypt.org', NULL, NULL) IS DISTINCT FROM 'MSSANTE'
     OR private.fn_growth_destinataire_bloque('PUBLIC', NULL, 'postcondition@pasapicrypt.org', NULL, NULL) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.growth_brouillons b
                WHERE b.agent = 'PROSPECTION_ETABLISSEMENT' AND b.statut IN ('BROUILLON', 'VALIDE')
                  AND private.fn_growth_email_mssante(b.destinataire_email)) THEN
    RAISE EXCEPTION 'PROSPECTION_SANS_APICRYPT_POSTCONDITION : prédicat inexact ou brouillon Apicrypt encore en file après l''expiration.';
  END IF;
END;
$prospection_sans_apicrypt_expiration$;
