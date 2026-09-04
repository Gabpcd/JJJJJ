-- Une notification déjà ouverte doit rester utile depuis l'historique.
UPDATE public.notifications n
SET lien = '/contrat/' || (
  SELECT contrat.id::text
  FROM public.contrats_mission contrat
  WHERE contrat.mission_id = n.id_ressource
    AND contrat.soignant_id = n.destinataire_id
    AND contrat.statut NOT IN ('ANNULE', 'EXPIRE')
  ORDER BY contrat.cree_le DESC, contrat.id DESC
  LIMIT 1
)
WHERE n.type = 'CANDIDATURE_ACCEPTEE'
  AND n.type_destinataire = 'SOIGNANT'
  AND n.type_ressource = 'mission'
  AND EXISTS (
    SELECT 1
    FROM public.contrats_mission contrat
    WHERE contrat.mission_id = n.id_ressource
      AND contrat.soignant_id = n.destinataire_id
      AND contrat.statut NOT IN ('ANNULE', 'EXPIRE')
  );
