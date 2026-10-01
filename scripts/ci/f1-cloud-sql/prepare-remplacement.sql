-- CANDIDAT NON EXECUTE. Meme transaction que le preflight et le manifeste.
-- Emet seulement le document comptable BROUILLON par le vrai resolveur.
-- Un seul POST generate-invoice revient ensuite au runner, jamais a pg_net.
DO $correction$
DECLARE
  v jsonb := current_setting('jolene.recette_f1_manifest')::jsonb;
  s uuid := (v#>>'{actors,soignant,id}')::uuid;
  e uuid := (v#>>'{actors,etablissement,id}')::uuid;
  a uuid := (v#>>'{sqlActors,admin,id}')::uuid;
  m uuid := (v#>>'{ids,mission}')::uuid;
  team uuid := (v#>>'{ids,equipeAdmin}')::uuid;
  l uuid := (v#>>'{ids,litige}')::uuid;
  presence uuid := (v#>>'{ids,presence}')::uuid;
  original uuid := (v#>>'{documents,original,id}')::uuid;
  f public.factures_honoraires%ROWTYPE;
  r jsonb;
  nouveau uuid;
BEGIN
  IF v->>'projectRef' IS DISTINCT FROM 'mejpriaetwgtcstbgfid'
    OR session_user NOT IN ('postgres','supabase_admin')
    OR EXISTS(SELECT 1 FROM cron.job WHERE active)
    OR md5(pg_get_functiondef('public.fn_preparer_commission_remplacement_honoraires(uuid)'::regprocedure))
      IS DISTINCT FROM 'c793ac81eaef0fe18fb5920c9264c675'
    OR EXISTS(SELECT 1 FROM public.parametres_litiges WHERE cle='generate_invoice_url' AND COALESCE(length(valeur),0)>0)
    OR COALESCE((SELECT NULLIF(btrim(decrypted_secret),'')='https://mejpriaetwgtcstbgfid.supabase.co'
      FROM vault.decrypted_secrets WHERE name='supabase_url' LIMIT 1),false) IS NOT TRUE
  THEN RAISE EXCEPTION 'F1 route/cron/contexte non autorise'; END IF;
  IF (SELECT count(*) FROM auth.users WHERE id IN(s,e,a)
    AND raw_app_meta_data->>'jolene_f1_owner'=v->>'ownerMarker'
    AND raw_app_meta_data->'est_compte_test'='true'::jsonb)<>3
    OR NOT EXISTS(SELECT 1 FROM public.soignants WHERE id=s AND est_compte_test AND NOT defacto_opt_in AND iban_virement IS NULL)
    OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=e AND est_compte_test AND NOT est_secteur_public AND NOT chorus_pro_actif)
    OR presence IS NULL OR (SELECT count(DISTINCT x) FROM unnest(ARRAY[s,e,a,m,team,l,presence,original]) x)<>8
    OR EXISTS(SELECT 1 FROM public.presences WHERE id=presence OR mission_id=m)
    OR EXISTS(SELECT 1 FROM public.litiges WHERE id=l OR mission_id=m)
    OR EXISTS(SELECT 1 FROM public.stripe_transfers WHERE mission_id=m)
    OR EXISTS(SELECT 1 FROM public.paiements_escrow WHERE mission_id=m)
  THEN RAISE EXCEPTION 'F1 filiation/cohorte/effets incorrects'; END IF;
  SELECT * INTO STRICT f FROM public.factures_honoraires WHERE id=original AND mission_id=m
    AND soignant_id=s AND etablissement_id=e AND statut='EMISE' AND type_document='FACTURE'
    AND nature_correction='ORIGINALE' AND montant_ht=80 AND montant_ttc=80 AND montant_tva=0
    AND quantite_heures_snapshot=4 AND taux_horaire_snapshot=20
    AND NOT est_facture_finale_mission AND NOT is_public_sector
    AND pdf_s3_key IS NOT NULL AND facturx_xml_url IS NOT NULL
    AND stripe_payment_intent_id IS NULL AND date_paiement IS NULL FOR UPDATE;
  IF (SELECT count(*) FROM public.factures_honoraires_documents WHERE facture_honoraire_id=original)<>1
    OR NOT EXISTS(SELECT 1 FROM public.missions WHERE id=m AND statut='EN_COURS' AND duree_heures=8 AND taux_horaire_base=20)
  THEN RAISE EXCEPTION 'F1 original/mission non conforme'; END IF;
  -- Meme presence minimale que le cinquieme temoin SQL vert : historique
  -- synthetique de 4 h, sans scan, GPS, depart ni validation etablissement.
  -- L'ID appartient au manifeste persiste AVANT cette transaction.
  INSERT INTO public.presences(id,mission_id,soignant_id,heures_reelles)
  VALUES(presence,m,s,4);
  IF NOT EXISTS(SELECT 1 FROM public.presences WHERE id=presence AND mission_id=m AND soignant_id=s
    AND heures_reelles=4 AND heures_ajustees_litige IS NULL
    AND pointage_arrivee_le IS NULL AND pointage_depart_le IS NULL
    AND COALESCE(valide_par_etablissement,false)=false)
  THEN RAISE EXCEPTION 'F1 presence synthetique incorrecte'; END IF;
  UPDATE public.equipe_admin SET actif=true WHERE id=team AND user_id=a AND NOT actif;
  IF NOT FOUND THEN RAISE EXCEPTION 'F1 admin hors manifeste ou deja actif'; END IF;
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','aal','aal2')::text,true);
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'F1 claims serveur synthetiques invalides'; END IF;
  INSERT INTO public.litiges(id,mission_id,soignant_id,etablissement_id,initie_par,motif,
    statut,type_litige,facture_id,gel_facture_scope,periode_debut,periode_fin)
  VALUES(l,m,s,e,'SOIGNANT','RECETTE SYNTHETIQUE '||(v->>'ownerMarker')||' : correction du taux de premiere periode',
    'OUVERT','DESACCORD_MONTANT_FACTURE',original,'FACTURE_UNIQUE',f.periode_debut,f.periode_fin);
  r:=public.fn_admin_resoudre_litige_intelligent(l,
    'RECETTE SYNTHETIQUE sans prestation reelle : taux 20 vers 18','ETABLISSEMENT',4,18,'ANNULER_REEMETTRE');
  nouveau:=NULLIF(r->>'nouvelle_facture_id','')::uuid;
  IF r->'success' IS DISTINCT FROM 'true'::jsonb OR nouveau IS NULL
    OR r->>'action_financiere' IS DISTINCT FROM 'ANNULER_REEMETTRE'
    OR NOT EXISTS(SELECT 1 FROM public.presences WHERE id=presence AND mission_id=m AND soignant_id=s
      AND heures_reelles=4 AND heures_ajustees_litige=4 AND ajustement_litige_id=l
      AND pointage_arrivee_le IS NULL AND pointage_depart_le IS NULL
      AND COALESCE(valide_par_etablissement,false)=false)
    OR COALESCE(r->'regen_pdf_request_ids','[]'::jsonb) IS DISTINCT FROM '[]'::jsonb
    OR NOT EXISTS(SELECT 1 FROM public.factures_honoraires WHERE id=nouveau AND statut='BROUILLON'
      AND nature_correction='REMPLACEMENT' AND type_document='FACTURE' AND facture_precedente_id=original
      AND montant_ht=72 AND montant_ttc=72 AND montant_tva=0
      AND quantite_heures_snapshot=4 AND taux_horaire_snapshot=18
      AND periode_debut=f.periode_debut AND periode_fin=f.periode_fin)
  THEN RAISE EXCEPTION 'F1 correction canonique incorrecte ou double initiateur: %',r; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  UPDATE public.equipe_admin SET actif=false WHERE id=team AND user_id=a;
  PERFORM set_config('jolene.recette_f1_receipt',jsonb_build_object('runId',v->>'runId','id',nouveau,
    'originalId',original,'litigeId',l,'presenceId',presence,'typeDocument','FACTURE','natureCorrection','REMPLACEMENT',
    'initiation',jsonb_build_object('type','runner'),'regenPdfRequestIds','[]'::jsonb)::text,true);
END $correction$;
SELECT current_setting('jolene.recette_f1_receipt')::jsonb AS receipt;
