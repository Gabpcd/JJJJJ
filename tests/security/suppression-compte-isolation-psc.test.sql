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

-- Une suspension garde les identifiants : le marqueur seul et même un audit
-- public imitant RGPD ne constituent jamais une preuve de nettoyage.
SELECT set_config('request.jwt.claims','{}',true);
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
VALUES ('69400000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','suspendu-soignant@example.invalid','authenticated','authenticated','{"role":"SOIGNANT"}',now()),
 ('69400000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','suspendu-etab@example.invalid','authenticated','authenticated','{"role":"ADMIN_ETABLISSEMENT"}',now()),
 ('69400000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','limite-etab@example.invalid','authenticated','authenticated','{"role":"ADMIN_ETABLISSEMENT"}',now());
INSERT INTO public.soignants(id,prenom,nom,email,profession,est_compte_test,supprime_le)
VALUES ('69400000-0000-4000-8000-000000000003','Compte','Suspendu','suspendu-soignant@example.invalid','AS',true,now());
INSERT INTO public.etablissements(id,nom,siret,type,adresse_rue,adresse_ville,adresse_code_postal,email_contact,est_compte_test,supprime_le)
VALUES ('69400000-0000-4000-8000-000000000004','Structure suspendue','69400000000004','CLINIQUE_PRIVEE','1 rue Test','Paris','75001','suspendu-etab@example.invalid',true,now()),
 ('69400000-0000-4000-8000-000000000005','Structure témoin','69400000000005','CLINIQUE_PRIVEE','1 rue Test','Paris','75001','limite-etab@example.invalid',true,NULL);
INSERT INTO public.journaux_audit(acteur_id,type_acteur,action,type_ressource,id_ressource,details)
VALUES('69400000-0000-4000-8000-000000000003','SOIGNANT','RGPD_SUPPRESSION_COMPTE','soignant','69400000-0000-4000-8000-000000000003','{"anonymise":true}');
DO $preuves_privees$
BEGIN
 IF private.fn_anonymisation_compte_confirmee('69400000-0000-4000-8000-000000000003','SOIGNANT')
 OR private.fn_anonymisation_compte_confirmee('69400000-0000-4000-8000-000000000004','ETABLISSEMENT')
 THEN RAISE EXCEPTION 'Suspension/audit public pris pour une anonymisation'; END IF;
 IF has_table_privilege('authenticated','private.suppressions_compte_confirmees','INSERT')
 OR has_table_privilege('service_role','private.suppressions_compte_confirmees','UPDATE')
 OR has_function_privilege('authenticated','public.fn_anonymisation_compte_confirmee(uuid,text)','execute')
 OR has_function_privilege('anon','public.fn_anonymisation_compte_confirmee(uuid,text)','execute')
 THEN RAISE EXCEPTION 'Preuve privée exposée aux clients'; END IF;
END $preuves_privees$;

-- Sans reçu valide, le plafond existant reste 1 demande par 86 400 secondes.
-- Une demande antérieure est réservée sur deux témoins non anonymisés.
DO $reservation_limite$
BEGIN
 IF public.fn_verifier_rate_limit('69400000-0000-4000-8000-000000000002','supprimer_compte',1,86400) IS DISTINCT FROM true
 OR public.fn_verifier_rate_limit('69400000-0000-4000-8000-000000000005','supprimer_compte_etablissement',1,86400) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Réservation du plafond de recette impossible'; END IF;
END $reservation_limite$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"69400000-0000-4000-8000-000000000002","role":"authenticated"}',true);
DO $limite_soignant$
DECLARE resultat jsonb;
BEGIN
 resultat:=public.fn_supprimer_compte_rate_limited();
 IF resultat->>'error' IS DISTINCT FROM 'Demande de suppression déjà en cours.' OR resultat->>'success'='true'
 THEN RAISE EXCEPTION 'Plafond soignant non anonymisé contourné : %',resultat; END IF;
END $limite_soignant$;
SELECT set_config('request.jwt.claims','{"sub":"69400000-0000-4000-8000-000000000005","role":"authenticated"}',true);
DO $limite_etab$
DECLARE resultat jsonb;
BEGIN
 resultat:=public.fn_supprimer_compte_etablissement_rate_limited();
 IF resultat->>'error' IS DISTINCT FROM 'Demande de suppression déjà en cours.' OR resultat->>'success'='true'
 THEN RAISE EXCEPTION 'Plafond établissement non anonymisé contourné : %',resultat; END IF;
END $limite_etab$;
RESET ROLE;
DO $temoins_limites$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.soignants WHERE id='69400000-0000-4000-8000-000000000002' AND supprime_le IS NULL AND email='temoin-recette@example.invalid')
 OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id='69400000-0000-4000-8000-000000000005' AND supprime_le IS NULL AND email_contact='limite-etab@example.invalid')
 OR EXISTS(SELECT 1 FROM private.suppressions_compte_confirmees WHERE utilisateur_id IN('69400000-0000-4000-8000-000000000002','69400000-0000-4000-8000-000000000005'))
 THEN RAISE EXCEPTION 'Un refus du plafond a néanmoins anonymisé un témoin'; END IF;
END $temoins_limites$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"69400000-0000-4000-8000-000000000003","role":"authenticated"}',true);
SELECT set_config('jolene.system_update','contexte-precedent',true),set_config('jolene.bank_server_update','contexte-precedent',true),
 set_config('jolene.liberal_transition','contexte-precedent',true),set_config('jolene.siret_liberal_reset','contexte-precedent',true);
DO $suspendu_soignant$
DECLARE resultat jsonb;
BEGIN
 resultat:=public.fn_supprimer_compte_rate_limited();
 IF resultat->>'success' IS DISTINCT FROM 'true' OR resultat->>'deja_anonymise'='true' THEN RAISE EXCEPTION 'Soignant suspendu non nettoyé : %',resultat; END IF;
 resultat:=public.fn_supprimer_compte_rate_limited();
 IF resultat->>'deja_anonymise' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Reprise finale bloquée par le rate limit malgré une preuve valide : %',resultat; END IF;
 IF current_setting('jolene.system_update')<>'contexte-precedent' OR current_setting('jolene.bank_server_update')<>'contexte-precedent'
 OR current_setting('jolene.liberal_transition')<>'contexte-precedent' OR current_setting('jolene.siret_liberal_reset')<>'contexte-precedent'
 THEN RAISE EXCEPTION 'Contexte antérieur non restauré'; END IF;
END $suspendu_soignant$;
SELECT set_config('request.jwt.claims','{"sub":"69400000-0000-4000-8000-000000000004","role":"authenticated"}',true);
SELECT set_config('app.internal_operation','contexte-precedent',true);
DO $suspendu_etab$
DECLARE resultat jsonb;
BEGIN
 resultat:=public.fn_supprimer_compte_etablissement_rate_limited();
 IF resultat->>'success' IS DISTINCT FROM 'true' OR resultat->>'deja_anonymise'='true' THEN RAISE EXCEPTION 'Établissement suspendu non nettoyé : %',resultat; END IF;
 resultat:=public.fn_supprimer_compte_etablissement_rate_limited();
 IF resultat->>'deja_anonymise' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Reprise établissement non idempotente : %',resultat; END IF;
 IF current_setting('app.internal_operation')<>'contexte-precedent' THEN RAISE EXCEPTION 'Contexte établissement non restauré'; END IF;
END $suspendu_etab$;
RESET ROLE;
DO $preuves_finales$
BEGIN
 IF NOT public.fn_anonymisation_compte_confirmee('69400000-0000-4000-8000-000000000003','SOIGNANT')
 OR NOT public.fn_anonymisation_compte_confirmee('69400000-0000-4000-8000-000000000004','ETABLISSEMENT')
 THEN RAISE EXCEPTION 'Anonymisation finale non prouvée pour les deux rôles'; END IF;
 IF (SELECT count(*) FROM public.psc_auth_sessions WHERE state IN ('recette-suppression-psc-active','recette-suppression-psc-expiree'))<>2
 THEN RAISE EXCEPTION 'Session PSC indépendante interrompue'; END IF;
END $preuves_finales$;
ROLLBACK;
