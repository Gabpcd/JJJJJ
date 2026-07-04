-- J2.3.B.2.2 — Fix : ajout GRANT SELECT à service_role sur serie_email_envois.
--
-- Symptôme : cron email-cron retournait { serie_envoyes: 0, serie_skipped: 0 }
-- même avec des rows PLANIFIE en attente. L'auth marchait, mais le SELECT
-- était silencieusement vide.
-- Cause : la migration j23b ne grantait que INSERT/UPDATE à service_role
-- (pas SELECT). Le client edge function utilisant service_role n'avait donc
-- pas le droit de lister les envois à traiter.

GRANT SELECT ON public.serie_email_envois TO service_role;
