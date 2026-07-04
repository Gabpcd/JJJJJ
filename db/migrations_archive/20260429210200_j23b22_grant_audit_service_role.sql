-- J2.3.B.2.2 — Fix : grant INSERT sur journaux_audit à service_role.
--
-- Symptôme : aucune entrée d'audit SERIE_EMAIL_ENVOYE / SERIE_EMAIL_SKIPPED /
-- SERIE_EMAIL_ERREUR_DEFINITIVE écrite par email-cron, alors que le code
-- les insère explicitement.
-- Cause : `service_role` n'avait pas de GRANT INSERT (uniquement SELECT
-- pour des RPC d'admin). Les `.from('journaux_audit').insert(...).catch(()=>{})`
-- du cron étouffaient silencieusement l'erreur de permission.
--
-- Cet audit étant requis pour les obligations RGPD (traçabilité des actions
-- système qui touchent aux données utilisateurs), on l'ouvre à service_role.

GRANT SELECT, INSERT ON public.journaux_audit TO service_role;
