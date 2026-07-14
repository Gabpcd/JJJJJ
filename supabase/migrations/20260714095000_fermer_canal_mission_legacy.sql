-- messages_mission était un ancien canal parallèle qui permettait encore un
-- INSERT client direct, donc un contournement de messagerie-validate. Aucune
-- interface active ne l'utilise plus : les données historiques sont conservées
-- pour l'export RGPD, mais seul le backend privilégié peut désormais y accéder.

DROP POLICY IF EXISTS pol_msg_insert ON public.messages_mission;
DROP POLICY IF EXISTS pol_msg_miss_update ON public.messages_mission;
DROP POLICY IF EXISTS pol_msg_miss_delete ON public.messages_mission;
DROP POLICY IF EXISTS pol_msg_select ON public.messages_mission;

REVOKE ALL ON TABLE public.messages_mission
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.messages_mission TO service_role;

-- Le fil de litige reste actif, mais son INSERT doit lui aussi passer par la
-- RPC fn_ajouter_message_litige qui revalide le dossier et calcule le rôle de
-- l'auteur. La policy historique permettait d'usurper type_auteur='ADMIN'.
DROP POLICY IF EXISTS pol_messages_litige_insert
  ON public.messages_litige;
REVOKE INSERT ON TABLE public.messages_litige
  FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.messages_mission IS
  'Canal historique en lecture backend uniquement; les conversations actives utilisent conversations/messages_chat et messagerie-validate.';

NOTIFY pgrst, 'reload schema';
