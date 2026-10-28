SELECT jsonb_build_object(
  'routines', (SELECT jsonb_agg(jsonb_build_object(
    'signature', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
    'definition_md5', md5(pg_get_functiondef(p.oid)), 'owner', pg_get_userbyid(p.proowner),
    'acl', p.proacl::text) ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE (n.nspname,p.proname) IN (
      ('public','fn_supprimer_compte_rate_limited'),('public','fn_supprimer_compte_etablissement_rate_limited'),
      ('public','fn_supprimer_mon_compte'),('public','fn_supprimer_mon_compte_etablissement'),
      ('public','fn_anonymisation_compte_confirmee'),('private','fn_anonymisation_compte_confirmee'),
      ('public','fn_verifier_rate_limit'))),
  'psc_routines', (SELECT jsonb_agg(jsonb_build_object('signature', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
      'definition_md5', md5(pg_get_functiondef(p.oid))) ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','private') AND (position('psc_auth_sessions' in p.prosrc)>0 OR position('fn_nettoyer_psc_sessions_expirees' in p.prosrc)>0)),
  'psc_constraints', (SELECT coalesce(jsonb_agg(pg_get_constraintdef(c.oid) ORDER BY c.conname),'[]'::jsonb)
    FROM pg_constraint c WHERE c.conrelid='public.psc_auth_sessions'::regclass OR c.confrelid='public.psc_auth_sessions'::regclass)
) AS catalogue;
