-- Fresh local DB only: no job, secret or outgoing request is inserted.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault CASCADE;
-- Installation does not prove Jolene extension parity. The separate comparison
-- requires nine exact available versions and checks every installed version/schema.
-- pgjwt and pg_trgm remain uninstalled here; availability is not restoration.
