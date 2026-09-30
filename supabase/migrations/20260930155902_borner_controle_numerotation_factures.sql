-- Source LIVE relue le 30/09/2026 : md5(prosrc)
-- 8673036776b1bdc1e3647d688b507230, md5(pg_get_functiondef)
-- 977fb78fd9077c00d3d72073721c2ebe (staging et production identiques).
-- Fonction INVOKER : aucun changement de privilège ni d'inventaire DEFINER.
DO $preflight$
DECLARE p record;
BEGIN
  SELECT * INTO p FROM pg_catalog.pg_proc
  WHERE oid = 'public.dec_verifier_numerotation_facture()'::regprocedure;
  IF NOT FOUND OR md5(p.prosrc) NOT IN ('8673036776b1bdc1e3647d688b507230', '28e45c95fead8a886f594f163a67961a')
    OR p.prosecdef IS DISTINCT FROM false
    OR pg_get_userbyid(p.proowner) IS DISTINCT FROM 'postgres'
    OR p.proconfig IS DISTINCT FROM ARRAY['search_path=public']::text[]
    OR p.proacl IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'::aclitem[] THEN
    RAISE EXCEPTION 'Numérotation factures : définition ou droits inattendus';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
    WHERE tgrelid='public.factures'::regclass AND tgname='dec_num_facture'
      AND tgfoid=p.oid AND tgenabled='O' AND tgtype=7 AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Numérotation factures : trigger inattendu';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.dec_verifier_numerotation_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_dernier_numero TEXT;
    v_dernier_seq NUMERIC;
    v_nouveau_seq NUMERIC;
    v_mois TEXT := TO_CHAR(NOW(), 'YYYYMM');
BEGIN
    -- Seule la série mensuelle numérique SD/JOL partage ce compteur.
    -- H, HC, HR, avoirs et autres formats conservent leurs générateurs propres.
    IF NEW.numero_facture IS NULL OR
       NEW.numero_facture !~ ('^(SD|JOL)-' || v_mois || '-[0-9]+$') THEN
        RETURN NEW;
    END IF;

    SELECT numero_facture INTO v_dernier_numero
    FROM factures
    WHERE numero_facture ~ ('^(SD|JOL)-' || v_mois || '-[0-9]+$')
    ORDER BY cree_le DESC LIMIT 1;

    IF v_dernier_numero IS NOT NULL THEN
        v_dernier_seq := SPLIT_PART(v_dernier_numero, '-', 3)::NUMERIC;
        v_nouveau_seq := SPLIT_PART(NEW.numero_facture, '-', 3)::NUMERIC;
        IF v_nouveau_seq != v_dernier_seq + 1 THEN
            RAISE WARNING 'Saut de numérotation facture détecté : % → %', v_dernier_numero, NEW.numero_facture;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;
