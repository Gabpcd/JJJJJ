-- Fresh local DB only: no job, secret or outgoing request is inserted.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault CASCADE;
-- Jolene extension parity is NOT asserted here. In particular pgjwt is absent
-- from current PG17 images; it remains an explicit future import dependency.
