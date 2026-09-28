-- À exécuter seulement après revue, sur base de test/staging. Aucune exécution
-- automatique ajoutée ici. Fixtures privées, non vérifiées, sans mission.
BEGIN;
INSERT INTO auth.users(id,instance_id,email,role,aud,raw_app_meta_data,email_confirmed_at)
SELECT ('97600000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'recette-parrainage-' || n || '@example.invalid','authenticated','authenticated',
  '{"role":"SOIGNANT","is_test_playwright":true}'::jsonb,now()
FROM generate_series(1,8) n;
INSERT INTO public.soignants(id,email,prenom,nom,profession,type_exercice,est_compte_test,code_parrainage)
SELECT ('97600000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  'recette-parrainage-' || n || '@example.invalid','Recette','Parrainage','AS','SALARIE',true,
  'RECETTE-976-' || n
FROM generate_series(1,8) n;
-- Préconditions des refus, limitées à ces fixtures et annulées avec la transaction.
UPDATE public.soignants SET statut_compte='SUSPENDU' WHERE id='97600000-0000-4000-8000-000000000004';
UPDATE public.soignants SET supprime_le=now() WHERE id='97600000-0000-4000-8000-000000000005';
UPDATE auth.users SET banned_until=now()+interval '1 day' WHERE id='97600000-0000-4000-8000-000000000006';
UPDATE auth.users SET deleted_at=now() WHERE id='97600000-0000-4000-8000-000000000007';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"97600000-0000-4000-8000-000000000002","role":"authenticated"}',true);
DO $preuve$
DECLARE r jsonb; s public.soignants; avant public.soignants; n integer; insertion_refusee boolean := false;
BEGIN
  IF has_table_privilege('authenticated', 'public.parrainages', 'INSERT')
    OR has_any_column_privilege('authenticated', 'public.parrainages', 'INSERT')
    OR has_table_privilege('anon', 'public.parrainages', 'INSERT')
    OR NOT has_table_privilege('authenticated', 'public.parrainages', 'SELECT')
    OR NOT has_function_privilege('authenticated', 'public.fn_appliquer_parrainage(text)', 'EXECUTE')
    OR NOT has_table_privilege('service_role', 'public.parrainages', 'INSERT')
    OR NOT has_function_privilege('service_role', 'public.fn_appliquer_parrainage(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'ACL parrainage incorrectes'; END IF;
  -- Choisir parrain_id=auth.uid(), qui passait l'ancienne politique RLS.
  BEGIN
    INSERT INTO public.parrainages(parrain_id,filleul_id,code_parrainage,statut)
    VALUES(auth.uid(),'97600000-0000-4000-8000-000000000001','RECETTE-976-2','EN_ATTENTE');
  EXCEPTION WHEN insufficient_privilege THEN insertion_refusee := true;
  END;
  IF NOT insertion_refusee THEN RAISE EXCEPTION 'INSERT direct authenticated accepté'; END IF;
  SELECT * INTO avant FROM public.soignants WHERE id=auth.uid();
  -- Modification directe : ni parrain ni vérification ne doivent être acceptés.
  UPDATE public.soignants SET parraine_par='97600000-0000-4000-8000-000000000001',
    identite_verifiee=true,diplome_verifie=true,heures_cumulees=999999,heures_plateforme=999999 WHERE id=auth.uid();
  SELECT * INTO s FROM public.soignants WHERE id=auth.uid();
  IF s.parraine_par IS NOT NULL OR s.identite_verifiee OR s.diplome_verifie
    OR s.heures_cumulees IS DISTINCT FROM avant.heures_cumulees
    OR s.heures_plateforme IS DISTINCT FROM avant.heures_plateforme THEN
    RAISE EXCEPTION 'Protection directe affaiblie'; END IF;
  -- Un faux contexte ne suffit pas sans relation correspondante.
  PERFORM set_config('jolene.parrainage_attribution_id','97600000-0000-4000-8000-000000000099',true);
  UPDATE public.soignants SET parraine_par='97600000-0000-4000-8000-000000000001' WHERE id=auth.uid();
  IF (SELECT parraine_par FROM public.soignants WHERE id=auth.uid()) IS NOT NULL THEN
    RAISE EXCEPTION 'Contexte sans relation accepté'; END IF;
  PERFORM set_config('jolene.parrainage_attribution_id','',true);
  -- Première attribution dans la branche normale (sans rpc_update).
  r := public.fn_appliquer_parrainage('RECETTE-976-1');
  IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Attribution refusée'; END IF;
  SELECT * INTO s FROM public.soignants WHERE id=auth.uid();
  IF s.parraine_par IS DISTINCT FROM '97600000-0000-4000-8000-000000000001'::uuid
    OR s.est_compte_test IS DISTINCT FROM true OR s.identite_verifiee OR s.diplome_verifie
    OR s.rpps_verifie OR s.tous_documents_valides THEN RAISE EXCEPTION 'Lien ou protections non persistés'; END IF;
  IF COALESCE(current_setting('jolene.parrainage_attribution_id',true),'') <> '' THEN
    RAISE EXCEPTION 'Contexte laissé ouvert'; END IF;
  r := public.fn_appliquer_parrainage('RECETTE-976-1');
  IF r->>'error' IS DISTINCT FROM 'Vous avez déjà appliqué un code de parrainage' THEN
    RAISE EXCEPTION 'Rejeu non refusé'; END IF;
  SELECT count(*) INTO n FROM public.parrainages WHERE filleul_id=auth.uid();
  IF n <> 1 THEN RAISE EXCEPTION 'Attribution dupliquée'; END IF;
  IF EXISTS (SELECT 1 FROM public.parrainages WHERE filleul_id=auth.uid()
    AND (statut <> 'EN_ATTENTE' OR prime_versee_le IS NOT NULL OR valide_le IS NOT NULL
      OR commission_cumulee_filleul <> 0)) THEN RAISE EXCEPTION 'Qualification ou prime inattendue'; END IF;
  UPDATE public.soignants SET parraine_par=NULL,identite_verifiee=true WHERE id=auth.uid();
  SELECT * INTO s FROM public.soignants WHERE id=auth.uid();
  IF s.parraine_par IS DISTINCT FROM '97600000-0000-4000-8000-000000000001'::uuid OR s.identite_verifiee THEN
    RAISE EXCEPTION 'Attribution réécrite hors contexte'; END IF;
END;
$preuve$;
-- Deuxième attribution indépendante dans la branche rpc_update, avec un
-- contexte préexistant à restaurer au lieu de l'effacer systématiquement.
SELECT set_config('request.jwt.claims','{"sub":"97600000-0000-4000-8000-000000000003","role":"authenticated"}',true);
DO $preuve_rpc$
DECLARE r jsonb; s public.soignants; avant public.soignants;
BEGIN
  SELECT * INTO avant FROM public.soignants WHERE id=auth.uid();
  PERFORM set_config('jolene.rpc_update','true',true);
  PERFORM set_config('jolene.parrainage_attribution_id','contexte-preexistant-recette',true);
  r := public.fn_appliquer_parrainage('RECETTE-976-1');
  IF r->>'success' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Attribution branche RPC refusée'; END IF;
  IF current_setting('jolene.parrainage_attribution_id',true) IS DISTINCT FROM 'contexte-preexistant-recette' THEN
    RAISE EXCEPTION 'Contexte préexistant non restauré'; END IF;
  UPDATE public.soignants SET identite_verifiee=true,diplome_verifie=true,parraine_par=NULL,
    heures_cumulees=999999,heures_plateforme=999999 WHERE id=auth.uid();
  SELECT * INTO s FROM public.soignants WHERE id=auth.uid();
  IF s.parraine_par IS DISTINCT FROM '97600000-0000-4000-8000-000000000001'::uuid
    OR s.identite_verifiee IS DISTINCT FROM false OR s.diplome_verifie IS DISTINCT FROM false
    OR s.heures_cumulees IS DISTINCT FROM avant.heures_cumulees
    OR s.heures_plateforme IS DISTINCT FROM avant.heures_plateforme THEN
    RAISE EXCEPTION 'Protection branche RPC affaiblie'; END IF;
  PERFORM set_config('jolene.rpc_update','',true);
  PERFORM set_config('jolene.parrainage_attribution_id','',true);
END;
$preuve_rpc$;
-- Contexte dédié valide : relation créée uniquement comme fixture privilégiée.
-- Il autorise le lien exact, jamais une réécriture des heures ni une activation
-- libérale pour un AS. Aucun trigger métier n'est désactivé.
RESET ROLE;
INSERT INTO public.parrainages(id,parrain_id,filleul_id,code_parrainage,statut)
VALUES('97600000-0000-4000-8000-000000000108','97600000-0000-4000-8000-000000000001',
  '97600000-0000-4000-8000-000000000008','RECETTE-976-1','EN_ATTENTE');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"97600000-0000-4000-8000-000000000008","role":"authenticated"}',true);
DO $preuve_heures_liberal$
DECLARE avant public.soignants; apres public.soignants;
BEGIN
  SELECT * INTO avant FROM public.soignants WHERE id=auth.uid();
  PERFORM set_config('jolene.parrainage_attribution_id','97600000-0000-4000-8000-000000000108',true);
  UPDATE public.soignants SET parraine_par='97600000-0000-4000-8000-000000000001',
    heures_cumulees=999999,heures_plateforme=999999,identite_verifiee=true,diplome_verifie=true
    WHERE id=auth.uid();
  SELECT * INTO apres FROM public.soignants WHERE id=auth.uid();
  IF apres.parraine_par IS DISTINCT FROM '97600000-0000-4000-8000-000000000001'::uuid
    OR apres.heures_cumulees IS DISTINCT FROM avant.heures_cumulees
    OR apres.heures_plateforme IS DISTINCT FROM avant.heures_plateforme
    OR apres.identite_verifiee IS DISTINCT FROM avant.identite_verifiee
    OR apres.diplome_verifie IS DISTINCT FROM avant.diplome_verifie THEN
    RAISE EXCEPTION 'Contexte parrainage a déverrouillé des données professionnelles'; END IF;
  BEGIN
    UPDATE public.soignants SET type_exercice='LIBERAL',statut_liberal='ACTIF' WHERE id=auth.uid();
  EXCEPTION WHEN insufficient_privilege OR check_violation OR raise_exception THEN
    NULL; -- Refus métier permis ; les valeurs sont impérativement relues ensuite.
  END;
  SELECT * INTO apres FROM public.soignants WHERE id=auth.uid();
  IF apres.type_exercice IS DISTINCT FROM avant.type_exercice
    OR apres.statut_liberal IS DISTINCT FROM avant.statut_liberal
    OR apres.profession IS DISTINCT FROM 'AS' THEN
    RAISE EXCEPTION 'Activation libérale AS acceptée via le contexte parrainage'; END IF;
  PERFORM set_config('jolene.parrainage_attribution_id','',true);
END;
$preuve_heures_liberal$;
-- Appels directs à SECURITY DEFINER : le pré-hook PostgREST ne doit pas être
-- leur seule défense contre un ancien JWT suspendu ou un profil supprimé.
DO $preuve_inactifs$
DECLARE n integer; uid uuid; r jsonb;
BEGIN
  FOR n IN 4..7 LOOP
    uid := ('97600000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid;
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
    r := public.fn_appliquer_parrainage('RECETTE-976-1');
    IF r->>'success' = 'true' OR NOT (r ? 'error') THEN RAISE EXCEPTION 'Compte inactif accepté'; END IF;
  END LOOP;
END;
$preuve_inactifs$;
RESET ROLE;
-- Le backend conserve INSERT mais ne peut attribuer un deuxième parrain au
-- même filleul, même avec une paire différente qui passait l'ancienne unicité.
SET LOCAL ROLE service_role;
DO $preuve_unicite_backend$
DECLARE doublon_refuse boolean := false; contrainte text; n integer;
BEGIN
  BEGIN
    INSERT INTO public.parrainages(parrain_id,filleul_id,code_parrainage,statut)
    VALUES('97600000-0000-4000-8000-000000000003','97600000-0000-4000-8000-000000000002','RECETTE-976-3','EN_ATTENTE');
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS contrainte = CONSTRAINT_NAME;
    doublon_refuse := contrainte = 'parrainages_filleul_id_key';
  END;
  IF NOT doublon_refuse THEN RAISE EXCEPTION 'Unicité du filleul non appliquée au backend'; END IF;
  SELECT count(*) INTO n FROM public.parrainages
    WHERE filleul_id IN ('97600000-0000-4000-8000-000000000002','97600000-0000-4000-8000-000000000003');
  IF n <> 2 THEN RAISE EXCEPTION 'Relations légitimes altérées'; END IF;
  IF EXISTS (SELECT 1 FROM public.soignants WHERE id IN
      ('97600000-0000-4000-8000-000000000002','97600000-0000-4000-8000-000000000003')
      AND (parraine_par IS DISTINCT FROM '97600000-0000-4000-8000-000000000001'::uuid
        OR identite_verifiee IS DISTINCT FROM false OR diplome_verifie IS DISTINCT FROM false
        OR rpps_verifie IS DISTINCT FROM false OR tous_documents_valides IS DISTINCT FROM false
        OR est_compte_test IS DISTINCT FROM true)) THEN
    RAISE EXCEPTION 'Identités ou protections modifiées par un refus'; END IF;
  IF EXISTS (SELECT 1 FROM public.parrainages WHERE filleul_id IN
      ('97600000-0000-4000-8000-000000000002','97600000-0000-4000-8000-000000000003')
      AND (statut IS DISTINCT FROM 'EN_ATTENTE' OR prime_versee_le IS NOT NULL
        OR valide_le IS NOT NULL OR commission_cumulee_filleul IS DISTINCT FROM 0)) THEN
    RAISE EXCEPTION 'Prime ou validation modifiée par un refus'; END IF;
END;
$preuve_unicite_backend$;
RESET ROLE;
DO $preuve_aucun_effet$
BEGIN
  IF EXISTS (SELECT 1 FROM public.parrainages WHERE filleul_id IN
    ('97600000-0000-4000-8000-000000000004','97600000-0000-4000-8000-000000000005',
     '97600000-0000-4000-8000-000000000006','97600000-0000-4000-8000-000000000007')) THEN
    RAISE EXCEPTION 'Attribution créée pour un compte inactif'; END IF;
END;
$preuve_aucun_effet$;
ROLLBACK;
