-- La contrainte journaux_audit_type_acteur_check rejetait des valeurs
-- effectivement écrites par les fonctions en place :
--   'ADMIN'             (fn_admin_resoudre_litige, fn_admin_creer_litige_force,
--                        fn_admin_recategoriser_litige_legacy, fn_confirmer_remboursement_avoir)
--   'ETABLISSEMENT'     (fn_ouvrir_litige_rate_limited 3-arg, quand l'étab initie)
--   'SYSTEM'            (fn_auto_creation_litiges_presence, fn_litiges_escalader_auto)
--   'DEPRECATED_CALLER' (wrapper 2-arg fn_ouvrir_litige_rate_limited)
-- → résolution/ouverture de litige côté admin/étab + crons litiges + confirmation
--   de remboursement échouaient (23514). On aligne la contrainte sur le code.
ALTER TABLE public.journaux_audit DROP CONSTRAINT journaux_audit_type_acteur_check;
ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_type_acteur_check
  CHECK (type_acteur = ANY (ARRAY[
    'SOIGNANT'::text, 'ADMIN_ETABLISSEMENT'::text, 'ADMIN_PLATEFORME'::text,
    'ADMIN_GROUPE'::text, 'SYSTEME'::text, 'SERVICE_API'::text,
    'ADMIN'::text, 'ETABLISSEMENT'::text, 'SYSTEM'::text, 'DEPRECATED_CALLER'::text
  ]));
