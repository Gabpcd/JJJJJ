-- Écouler des petits lots sans dépasser le budget Edge→Edge ni pg_net.
-- La fréquence des recherches reste 1 h / 24 h / 7 j, indépendamment du drain.
BEGIN;
CREATE INDEX IF NOT EXISTS idx_email_queue_attente_date_id
 ON public.email_queue(cree_le,id) WHERE statut='EN_ATTENTE';
CREATE INDEX IF NOT EXISTS idx_filtres_sauvegardes_alertes_echeance
 ON public.filtres_sauvegardes(dernier_check_le,id) WHERE alerte_active;

CREATE OR REPLACE FUNCTION public.fn_evaluer_alertes_filtres(p_frequence text DEFAULT NULL::text)
 RETURNS TABLE(filtre_id uuid, utilisateur_id uuid, audience public.filtre_audience, nom text, nb_nouveaux integer)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE r record; n integer; items jsonb; payload jsonb; email_type text; email_id uuid; etab uuid;
 v_cap_h integer:=greatest(1,public.fn_param_num('alerte_filtre_cap_h',20)::int);
BEGIN
 FOR r IN SELECT f.* FROM public.filtres_sauvegardes f
 WHERE f.alerte_active AND (p_frequence IS NULL OR f.frequence_alerte::text=p_frequence)
 AND f.dernier_check_le <= now()-CASE f.frequence_alerte WHEN 'IMMEDIATE' THEN interval '1 hour' WHEN 'QUOTIDIENNE' THEN interval '1 day' ELSE interval '7 days' END
 ORDER BY f.dernier_check_le, f.id
 LIMIT least(500,greatest(1,public.fn_param_num('alertes_filtres_lot',100)::integer))
 FOR UPDATE OF f SKIP LOCKED
 LOOP
  n:=public.fn_compter_nouveaux_pour_filtre(r.id,r.dernier_check_le);
  IF n>0 THEN
   items:=public.fn_obtenir_apercu_filtre(r.id,r.dernier_check_le,5);
   IF jsonb_array_length(items)=0 THEN RAISE EXCEPTION 'Compteur et aperçu divergents pour %',r.id; END IF;
   payload:=jsonb_build_object('nom_filtre',r.nom,'count',n);
   etab:=NULL;
   IF r.audience='SOIGNANT_RECHERCHE_MISSIONS' THEN
    email_type:='NOUVELLES_MISSIONS_FILTRE';
    payload:=payload||jsonb_build_object('prenom',coalesce((SELECT s.prenom FROM public.soignants s WHERE s.id=r.utilisateur_id),''),'missions',items);
   ELSE
    email_type:='NOUVEAUX_SOIGNANTS_FILTRE';
    etab:=private.fn_etablissement_destinataire_alerte(r.utilisateur_id);
    payload:=payload||jsonb_build_object('nom_etab',(SELECT e.nom FROM public.etablissements e WHERE e.id=etab),'soignants',items);
   END IF;
   -- A retry of the same transaction/window never creates a second queue row.
   IF NOT EXISTS(SELECT 1 FROM private.alertes_filtres_livraisons l WHERE l.filtre_id=r.id AND l.fenetre_debut=r.dernier_check_le AND l.fenetre_fin=now()) THEN
    INSERT INTO public.email_queue(type,destinataire_id,data,statut) VALUES(email_type,r.utilisateur_id,payload,'EN_ATTENTE') RETURNING id INTO email_id;
    INSERT INTO private.alertes_filtres_livraisons(email_id,filtre_id,fenetre_debut,fenetre_fin,filtres,etablissement_id)
    VALUES(email_id,r.id,r.dernier_check_le,now(),r.filtres,etab);
    IF r.audience='SOIGNANT_RECHERCHE_MISSIONS' AND NOT EXISTS(SELECT 1 FROM public.notifications no WHERE no.destinataire_id=r.utilisateur_id AND no.type='MISSION_A_POURVOIR' AND no.cree_le>now()-make_interval(hours=>v_cap_h)) THEN
     INSERT INTO public.notifications(destinataire_id,type_destinataire,type,titre,corps,lien)
     VALUES(r.utilisateur_id,'SOIGNANT','MISSION_A_POURVOIR',n||' nouvelle(s) mission(s) pour « '||r.nom||' »','De nouvelles missions correspondent à votre recherche sauvegardée.','/soignant/parametres/recherches-sauvegardees');
    END IF;
   END IF;
  END IF;
  UPDATE public.filtres_sauvegardes f SET dernier_check_le=now(),nb_resultats_dernier_check=n WHERE f.id=r.id;
 END LOOP;
 -- Le contrat de retour reste compatible avec l'ancien worker : aucune ligne
 -- à envoyer en parallèle. Il sait déjà consommer email_queue une seule fois.
 RETURN;
END $fn$;


-- Définition LIVE : seule la cadence du drain change. La primitive canonique
-- doit conserver cette cadence après reset staging, où cron.job est d'abord vide.
CREATE OR REPLACE FUNCTION private.fn_reconcilier_crons_edge_critiques_inactifs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_spec record;
  v_job_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron'
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'pg_cron_absent'
    );
  END IF;

  FOR v_spec IN
    SELECT *
      FROM (VALUES
        ('litige-escalation-cron', '0 7 * * *'),
        ('email-cron-hourly-immediate', '* * * * *'),
        ('email-cron-daily', '17 5 * * *'),
        ('process-stripe-refunds-15min', '3,18,33,48 * * * *'),
        ('escrow-debit-echeance', '11 * * * *'),
        ('escrow-release', '8,23,38,53 * * * *'),
        ('jolene_process_externalisations', '1-59/5 * * * *'),
        -- Deux créneaux UTC et une condition Europe/Paris assurent 06:00
        -- toute l'année malgré les changements heure d'été/heure d'hiver.
        ('weekly-invoicing-cron', '0 4,5 * * *')
      ) AS specs(job_name, schedule)
  LOOP
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = v_spec.job_name) THEN
      PERFORM cron.unschedule(v_spec.job_name);
    END IF;

    v_job_id := cron.schedule(
      v_spec.job_name,
      v_spec.schedule,
      CASE
        WHEN v_spec.job_name = 'weekly-invoicing-cron' THEN format(
          'SELECT private.fn_appeler_edge_critique(%L, false) WHERE EXTRACT(HOUR FROM now() AT TIME ZONE %L) = 6',
          v_spec.job_name,
          'Europe/Paris'
        )
        ELSE format(
          'SELECT private.fn_appeler_edge_critique(%L, false)',
          v_spec.job_name
        )
      END
    );
    PERFORM cron.alter_job(job_id := v_job_id, active := false);
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM cron.job
     WHERE jobname = 'jolene-monitor-crons-edge-critiques'
  ) THEN
    PERFORM cron.unschedule('jolene-monitor-crons-edge-critiques');
  END IF;
  v_job_id := cron.schedule(
    'jolene-monitor-crons-edge-critiques',
    '4-59/5 * * * *',
    'SELECT private.fn_controler_crons_edge_critiques()'
  );
  PERFORM cron.alter_job(job_id := v_job_id, active := false);

  -- Le lancement n'a pas besoin des traitements d'acquisition. On conserve
  -- leur définition pour une réactivation future revue, mais aucun d'eux ne
  -- doit repartir implicitement avec les crons métier critiques.
  FOR v_job_id IN
    SELECT j.jobid
      FROM cron.job j
     WHERE j.jobname IN (
       'warm-edge-functions',
       'jolene_acquisition_brouillons',
       'jolene_sourcing_rpps_hebdo',
       'jolene_sourcing_finess_hebdo',
       'enrich-prospects-etab',
       'enrich-prospects-soignant',
       'jolene_sourcing_rpps_watchdog',
       'jolene_prospection_compteurs_quotidien',
       'jolene_crm_generer_taches',
       'jolene_acquisition_bmo_mensuel',
       'jolene_acquisition_boamp_quotidien'
     )
  LOOP
    PERFORM cron.alter_job(job_id := v_job_id, active := false);
  END LOOP;

  IF EXISTS (
    SELECT 1
      FROM cron.job
     WHERE jobname IN (
       'litige-escalation-cron',
       'email-cron-hourly-immediate',
       'email-cron-daily',
       'process-stripe-refunds-15min',
       'escrow-debit-echeance',
       'escrow-release',
       'jolene_process_externalisations',
       'weekly-invoicing-cron',
       'jolene-monitor-crons-edge-critiques'
     )
       AND active IS TRUE
  ) THEN
    RAISE EXCEPTION 'Un job Edge critique a été activé avant les sondes';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'jobs_critiques', 9,
    'jobs_actifs', 0
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name OR insufficient_privilege THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'pg_cron_indisponible',
      'sqlstate', SQLSTATE
    );
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_reconcilier_crons_edge_critiques_inactifs() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.fn_reconcilier_crons_edge_critiques_inactifs() TO service_role;
DO $cron$
DECLARE resultat jsonb;
BEGIN
 resultat:=private.fn_reconcilier_crons_edge_critiques_inactifs();
 IF (resultat->>'success')::boolean IS DISTINCT FROM true THEN
  RAISE NOTICE 'Recapture des crons différée au bootstrap : %',resultat;
 END IF;
END $cron$;
COMMIT;
