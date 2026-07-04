-- Fix trigger sync types_contrat : CDDU → CDD (aligne sur le frontend + base existante)
-- Le frontend propose CDD (pas CDDU), et toutes les données en base utilisent CDD.
-- Le trigger écrivait CDDU → mismatch silencieux.
CREATE OR REPLACE FUNCTION public.dec_sync_types_contrat_exercice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.type_exercice IS DISTINCT FROM OLD.type_exercice THEN
        CASE NEW.type_exercice
            WHEN 'MIXTE' THEN NEW.types_contrat_acceptes := 'CDD,LIBERAL';
            WHEN 'LIBERAL' THEN NEW.types_contrat_acceptes := 'LIBERAL';
            WHEN 'SALARIE' THEN NEW.types_contrat_acceptes := 'CDD';
            ELSE NULL;
        END CASE;
    END IF;
    RETURN NEW;
END;
$function$;

-- Fix données : format JSON stringifié → CSV
UPDATE soignants
SET types_contrat_acceptes = REPLACE(REPLACE(REPLACE(types_contrat_acceptes, '["', ''), '"]', ''), '","', ',')
WHERE types_contrat_acceptes LIKE '[%';
