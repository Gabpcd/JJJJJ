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
--    17/11. Sinon la migration entière est refusée avant toute écriture.
-- 1. Règle unique élargie : apicrypt.org et ses sous-domaines, en plus de
--    mssante.fr et ses sous-domaines (casse et blancs de bord ignorés ; NULL =
--    false). Le nom de la fonction et le motif d'expiration restent ceux de
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

  IF pg_catalog.to_regprocedure('private.fn_growth_expirer_brouillons_mssante()') IS NULL THEN
    RAISE EXCEPTION 'PROSPECTION_SANS_APICRYPT_EXPIRATION_ABSENTE : private.fn_growth_expirer_brouillons_mssante() (20261116143942) absente en base : expiration impossible. Redéfinition refusée.';
  END IF;
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
END;
$prospection_sans_apicrypt_expiration$;
