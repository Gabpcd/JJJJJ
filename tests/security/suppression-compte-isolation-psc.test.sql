-- Vraie anonymisation via la RPC utilisateur, sans appel réseau, puis ROLLBACK.
BEGIN;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES ('69400000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','suppression-recette@example.invalid','authenticated','authenticated','{"role":"SOIGNANT"}',now()),
       ('69400000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','temoin-recette@example.invalid','authenticated','authenticated','{"role":"SOIGNANT"}',now());
INSERT INTO public.soignants(id,prenom,nom,email,profession,est_compte_test)
VALUES ('69400000-0000-4000-8000-000000000001','Compte','À supprimer','suppression-recette@example.invalid','AS',true),
       ('69400000-0000-4000-8000-000000000002','Compte','Témoin','temoin-recette@example.invalid','AS',true);
INSERT INTO public.psc_auth_sessions(state,nonce,code_verifier,intention,cree_le,expire_le)
VALUES ('recette-suppression-psc-active','nonce-recette','verifier-recette','login',now()-interval '1 minute',now()+interval '9 minutes'),
       ('recette-suppression-psc-expiree','nonce-recette-expiree','verifier-recette-expiree','login',now()-interval '20 minutes',now()-interval '10 minutes');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"69400000-0000-4000-8000-000000000001","role":"authenticated"}',true);
DO $anonymisation$
DECLARE resultat jsonb;
BEGIN
  resultat := public.fn_supprimer_compte_rate_limited();
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Anonymisation utilisateur refusée : %', resultat;
  END IF;
END;
$anonymisation$;
RESET ROLE;
DO $isolation$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.soignants WHERE id='69400000-0000-4000-8000-000000000001'
    AND supprime_le IS NOT NULL AND nom='Supprimé' AND email LIKE '%@supprime.jolene.app') THEN
    RAISE EXCEPTION 'Profil cible non anonymisé';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.soignants WHERE id='69400000-0000-4000-8000-000000000002'
    AND supprime_le IS NULL AND nom='Témoin' AND email='temoin-recette@example.invalid') THEN
    RAISE EXCEPTION 'La suppression a touché un autre compte';
  END IF;
  IF (SELECT count(*) FROM public.psc_auth_sessions WHERE state IN ('recette-suppression-psc-active','recette-suppression-psc-expiree')) <> 2 THEN
    RAISE EXCEPTION 'La suppression a interrompu une authentification PSC indépendante';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.journaux_audit WHERE acteur_id='69400000-0000-4000-8000-000000000001'
    AND action='RGPD_SUPPRESSION_COMPTE') THEN RAISE EXCEPTION 'Preuve anonymisation absente'; END IF;
END;
$isolation$;
ROLLBACK;
