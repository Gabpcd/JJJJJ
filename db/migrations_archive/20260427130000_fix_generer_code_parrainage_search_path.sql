-- Fix register-soignant 500 :
--
-- fn_generer_code_parrainage utilise gen_random_bytes() de pgcrypto
-- (installé dans le schéma 'extensions' sur Supabase) mais son search_path
-- est restreint à 'public'. Résultat : la fonction ne trouve pas
-- gen_random_bytes() et plante avec :
--   ERROR: function gen_random_bytes(integer) does not exist | SQLSTATE=42883
--
-- Cette fonction est appelée par le trigger trg_auto_code_parrainage qui
-- fire BEFORE INSERT sur tous les INSERT INTO soignants. Donc l'edge
-- function register-soignant retourne systématiquement 500
-- ("Erreur lors de la création du profil soignant.") et aucune inscription
-- soignant n'est possible.
--
-- Fix chirurgical : ajouter 'extensions' au search_path. Pas de changement
-- de logique. Vérifié par test INSERT après migration → "INSERT OK".

CREATE OR REPLACE FUNCTION public.fn_generer_code_parrainage()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_code TEXT;
BEGIN
    v_code := 'JO-' || UPPER(SUBSTRING(encode(gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    WHILE EXISTS (SELECT 1 FROM soignants WHERE code_parrainage = v_code) LOOP
        v_code := 'JO-' || UPPER(SUBSTRING(encode(gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    END LOOP;
    RETURN v_code;
END;
$function$;
