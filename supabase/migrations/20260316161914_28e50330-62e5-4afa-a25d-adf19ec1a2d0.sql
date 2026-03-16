
-- Allow admin to insert messages into mission chat
DROP POLICY IF EXISTS pol_msg_insert ON public.messages_mission;
CREATE POLICY pol_msg_insert ON public.messages_mission
  FOR INSERT TO authenticated
  WITH CHECK (
    (auteur_id = auth.uid()) AND (
      est_admin() OR
      (mission_id IN (
        SELECT missions.id FROM missions
        WHERE (
          (missions.soignant_assigne_id = auth.uid()) OR
          (missions.etablissement_id = mon_etablissement_id())
        ) AND (missions.statut = ANY (ARRAY['ASSIGNEE'::statut_mission, 'EN_COURS'::statut_mission]))
      ))
    )
  );
