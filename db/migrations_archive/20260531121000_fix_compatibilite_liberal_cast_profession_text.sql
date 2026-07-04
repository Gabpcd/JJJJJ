-- BUG (bloqueur libéral) : dec_valider_compatibilite_mission_liberal appelait
-- peut_exercer_liberal(NEW.profession_requise, v_type_etab) en passant
-- profession_requise (enum type_profession) à une fonction (text, text) → pas de
-- cast implicite enum→text en résolution de fonction → 42883 « function does not
-- exist ». Toute mission passée en type_contrat_recherche='LIBERAL' échouait
-- (jamais exercé : 0 mission libérale en prod). Fix : cast ::text.
CREATE OR REPLACE FUNCTION public.dec_valider_compatibilite_mission_liberal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_type_etab text;
BEGIN
  IF NEW.type_contrat_recherche IS DISTINCT FROM 'LIBERAL' THEN
    RETURN NEW;
  END IF;

  SELECT type::text INTO v_type_etab FROM public.etablissements
  WHERE id = NEW.etablissement_id;

  IF NEW.profession_requise IS NOT NULL AND v_type_etab IS NOT NULL THEN
    IF NOT public.peut_exercer_liberal(NEW.profession_requise::text, v_type_etab) THEN
      RAISE EXCEPTION
        '[CODE DU TRAVAIL] La profession % ne peut pas exercer en libéral en % '
        '(cas de salariat déguisé, art. L8221-1 Code travail + Conseil d''Etat 11/02/2025). '
        'Proposez la mission en CDD ou Vacation.',
        NEW.profession_requise, v_type_etab;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
