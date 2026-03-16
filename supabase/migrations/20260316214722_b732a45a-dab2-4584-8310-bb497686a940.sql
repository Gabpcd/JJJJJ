-- Fix missing table grants for messages_mission
GRANT SELECT, INSERT ON TABLE public.messages_mission TO authenticated;
GRANT SELECT, INSERT ON TABLE public.messages_mission TO anon;
GRANT ALL ON TABLE public.messages_mission TO service_role;