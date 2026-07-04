-- 6c.4 (Lot 6c) — Boucle quotidienne : un match de recherche sauvegardée
-- envoie AUSSI une notification in-app/push (en plus de l'email), avec
-- deep-link direct dans le deck de swipe pré-filtré par le profil.
CREATE OR REPLACE FUNCTION public.fn_evaluer_alertes_filtres(p_frequence text DEFAULT NULL::text)
 RETURNS TABLE(filtre_id uuid, utilisateur_id uuid, audience filtre_audience, nom text, nb_nouveaux integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  r RECORD;
  v_count integer;
BEGIN
  FOR r IN
    SELECT * FROM filtres_sauvegardes
    WHERE alerte_active = true
      AND (
        (p_frequence IS NULL OR frequence_alerte::text = p_frequence)
        AND (
          (frequence_alerte = 'QUOTIDIENNE'   AND dernier_check_le < now() - interval '23 hours') OR
          (frequence_alerte = 'HEBDOMADAIRE'  AND dernier_check_le < now() - interval '6 days 23 hours') OR
          (frequence_alerte = 'IMMEDIATE'     AND dernier_check_le < now() - interval '55 minutes')
        )
      )
  LOOP
    v_count := fn_compter_nouveaux_pour_filtre(r.id, r.dernier_check_le);
    UPDATE filtres_sauvegardes
    SET dernier_check_le = now(),
        nb_resultats_dernier_check = v_count
    WHERE id = r.id;
    IF v_count > 0 THEN
      -- 6c.4 : notification in-app/push (soignant) avec deep-link direct dans
      -- le deck de swipe. L'email (pipeline existant) part en parallèle via
      -- les lignes retournées par cette fonction.
      IF r.audience = 'SOIGNANT_RECHERCHE_MISSIONS' THEN
        INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
        VALUES (
          r.utilisateur_id, 'SOIGNANT', 'MISSION_A_POURVOIR',
          '✨ ' || v_count || ' nouvelle' || CASE WHEN v_count > 1 THEN 's' ELSE '' END
            || ' mission' || CASE WHEN v_count > 1 THEN 's' ELSE '' END
            || ' pour « ' || r.nom || ' »',
          'De nouvelles missions correspondent à ta recherche sauvegardée — découvre-les avant les autres.',
          '/soignant/recherche-missions?vue=swipe'
        );
      END IF;

      filtre_id := r.id;
      utilisateur_id := r.utilisateur_id;
      audience := r.audience;
      nom := r.nom;
      nb_nouveaux := v_count;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$function$;
