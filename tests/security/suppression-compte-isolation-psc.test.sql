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

-- Identifiants fictifs à effacer : l'utilisateur ne doit pas garder les champs
-- que les protections rétablissent normalement lors d'une édition directe.
UPDATE public.soignants SET numero_rpps='10000000001', iban_virement='FR7612345678901234567890123',
  iban_titulaire='Compte À supprimer', iban_last4='0123', stripe_account_id='acct_recette_suppression'
WHERE id='69400000-0000-4000-8000-000000000001';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"69400000-0000-4000-8000-000000000001","role":"authenticated"}',true);
DO $anonymisation$
DECLARE resultat jsonb;
BEGIN
  resultat := public.fn_supprimer_compte_rate_limited();
  IF resultat->>'success' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Anonymisation utilisateur refusée : %', resultat;
  END IF;
  IF COALESCE(current_setting('jolene.system_update',true),'') <> ''
    OR COALESCE(current_setting('jolene.bank_server_update',true),'') <> ''
    OR COALESCE(current_setting('jolene.liberal_transition',true),'') <> ''
    OR COALESCE(current_setting('jolene.siret_liberal_reset',true),'') <> '' THEN
    RAISE EXCEPTION 'Le contexte interne a fui après suppression';
  END IF;
  -- La protection des champs reste active après la RPC.
  BEGIN
    UPDATE public.soignants SET supprime_le=NULL, identite_verifiee=true,
      stripe_account_id='acct_interdit' WHERE id='69400000-0000-4000-8000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN
    -- Les GRANT de colonne peuvent refuser la requête avant même le trigger.
    NULL;
  END;
END;
$anonymisation$;
RESET ROLE;
DO $isolation$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.soignants WHERE id='69400000-0000-4000-8000-000000000001'
    AND supprime_le IS NOT NULL AND nom='Supprimé' AND email LIKE '%@supprime.jolene.app'
    AND numero_rpps IS NULL AND iban_virement IS NULL AND iban_titulaire IS NULL
    AND iban_last4 IS NULL AND stripe_account_id IS NULL AND identite_verifiee=false) THEN
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
