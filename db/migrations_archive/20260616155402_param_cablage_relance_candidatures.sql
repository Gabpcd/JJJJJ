-- Câblage des paramètres système : seul delai_relance_candidatures_h est
-- réellement consommé par le code à ce stade. Les autres seront branchés
-- un par un (cablee passera à true au fur et à mesure).
UPDATE public.parametres_systeme SET cablee = (cle = 'delai_relance_candidatures_h');

-- Brancher fn_relancer_candidatures_en_attente sur le paramètre éditable.
-- Tant que l'admin ne change rien, fn_param_num renvoie 24 → comportement
-- identique à la version d'origine.
CREATE OR REPLACE FUNCTION public.fn_relancer_candidatures_en_attente()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  v_nb integer := 0;
  v_delai interval := (public.fn_param_num('delai_relance_candidatures_h', 24)::text || ' hours')::interval;
BEGIN
  FOR r IN
    SELECT m.id, m.etablissement_id, m.intitule,
           count(c.id) AS nb_attente,
           min(c.cree_le) AS plus_ancienne
    FROM missions m
    JOIN candidatures c ON c.mission_id = m.id AND c.statut = 'EN_ATTENTE'
    WHERE m.statut = 'OUVERTE'
    GROUP BY m.id, m.etablissement_id, m.intitule, m.derniere_relance_candidatures_le
    HAVING min(c.cree_le) < now() - v_delai
       AND (m.derniere_relance_candidatures_le IS NULL
            OR m.derniere_relance_candidatures_le < now() - v_delai)
  LOOP
    PERFORM public.fn_creer_notification(
      r.etablissement_id, 'ETABLISSEMENT', 'RAPPEL_CANDIDATURES',
      r.nb_attente || ' candidature(s) en attente',
      'Vous avez ' || r.nb_attente || ' candidature(s) à traiter sur « ' || r.intitule ||
        ' », dont la plus ancienne depuis plus de 24h. Répondez vite pour ne pas perdre le soignant.',
      '/etablissement/missions/' || r.id::text,
      'mission', r.id
    );
    UPDATE missions SET derniere_relance_candidatures_le = now() WHERE id = r.id;
    v_nb := v_nb + 1;
  END LOOP;
  RETURN v_nb;
END;
$function$;
