-- Rappels daily : aucune invocation Edge par destinataire. File + reçu atomiques.
-- Sélections relevées LIVE le 25/09 : J-1 selon CURRENT_DATE, contrat dans les
-- 36 heures via la fonction canonique. Aucun changement de cadence cron.
CREATE TABLE IF NOT EXISTS private.rappels_quotidiens_livraisons (
 email_id uuid PRIMARY KEY DEFAULT gen_random_uuid()
   REFERENCES public.email_queue(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
 mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
 destinataire_id uuid NOT NULL,
 nature text NOT NULL CHECK(nature IN ('MISSION_EMAIL','MISSION_SMS','CONTRAT_ETAB','CONTRAT_SOIGNANT')),
 jour date NOT NULL,
 debut_le timestamptz NOT NULL,
 soignant_id uuid NOT NULL,
 etablissement_id uuid NOT NULL,
 scope text NOT NULL,
 identite jsonb NOT NULL,
 corps jsonb NOT NULL,
 tentatives integer NOT NULL DEFAULT 0,
 prochaine_tentative_le timestamptz NOT NULL DEFAULT now(),
 UNIQUE(mission_id,destinataire_id,nature,jour)
);
ALTER TABLE private.rappels_quotidiens_livraisons ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.rappels_quotidiens_livraisons FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX IF NOT EXISTS idx_rappels_quotidiens_reprise
 ON private.rappels_quotidiens_livraisons(prochaine_tentative_le,email_id);

CREATE OR REPLACE FUNCTION public.fn_preparer_rappels_quotidiens()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE resultat jsonb;
BEGIN
 WITH j1 AS (
   -- Même sélection que fn_email_rappels_j1 LIVE, enrichie uniquement de l'ID.
   SELECT m.id mission_id,m.debut_le,m.etablissement_id,s.id soignant_id,
     s.prenom,m.intitule mission,e.nom etablissement,
     to_char(m.debut_le AT TIME ZONE 'Europe/Paris','HH24:MI') heure_debut,
     s.telephone,s.sms_actif,s.sms_alertes_actives,s.est_compte_test
   FROM public.missions m JOIN public.soignants s ON s.id=m.soignant_assigne_id
   JOIN public.etablissements e ON e.id=m.etablissement_id
   WHERE m.statut='ASSIGNEE' AND m.debut_le::date=CURRENT_DATE+1 AND s.email IS NOT NULL
 ), contrats AS (
   SELECT * FROM jsonb_to_recordset(public.fn_lister_missions_contrat_travail_manquant())
     AS c(mission_id uuid,etablissement_id uuid,soignant_id uuid,intitule text,debut_le timestamptz,
       nom_etablissement text,prenom_soignant text,nom_soignant text)
 ), souhaites AS (
   SELECT j.mission_id,j.debut_le,j.etablissement_id,j.soignant_id,j.soignant_id destinataire_id,
     'MISSION_EMAIL'::text nature,'rappel_mission_j1'::text scope,
     jsonb_build_object('soignant_id',j.soignant_id,'jour',to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD')) identite,
     jsonb_build_object('type','RAPPEL_MISSION','destinataire_id',j.soignant_id,'data',
       jsonb_build_object('prenom',j.prenom,'mission',j.mission,'etablissement',j.etablissement,'heure_debut',j.heure_debut)) corps
   FROM j1 j
   UNION ALL
   SELECT j.mission_id,j.debut_le,j.etablissement_id,j.soignant_id,j.soignant_id,
     'MISSION_SMS','sms_rappel_mission_j1',
     jsonb_build_object('soignant_id',j.soignant_id,'jour',to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD'),
       'mission',j.mission,'etablissement',j.etablissement,'heure_debut',j.heure_debut),
     jsonb_build_object('type','RAPPEL_MISSION_J1','destinataire_id',j.soignant_id,'telephone',j.telephone,
       'contenu','📅 Rappel : votre mission '||left(coalesce(j.mission,''),40)||' démarre demain à '||j.heure_debut||' chez '||left(coalesce(j.etablissement,''),30)||'. Bonne journée !',
       'prefix_type','RAPPEL_MISSION_J1')
   FROM j1 j WHERE coalesce(j.telephone,'')<>'' AND j.sms_actif IS DISTINCT FROM false
     AND j.sms_alertes_actives IS DISTINCT FROM false AND j.est_compte_test IS DISTINCT FROM true
   UNION ALL
   SELECT c.mission_id,c.debut_le,c.etablissement_id,c.soignant_id,c.etablissement_id,
     'CONTRAT_ETAB','contrat_travail_etab',jsonb_build_object('mission_id',c.mission_id,'cible','etablissement'),
     jsonb_build_object('type','CONTRAT_TRAVAIL_RAPPEL_ETAB','destinataire_id',c.etablissement_id,'data',
       jsonb_build_object('intitule_mission',coalesce(nullif(c.intitule,''),'mission'),'prenom_soignant',c.prenom_soignant,
         'nom_soignant',c.nom_soignant,'date_debut',to_char(c.debut_le AT TIME ZONE 'UTC','DD/MM/YYYY'),'mission_id',c.mission_id))
   FROM contrats c
   UNION ALL
   SELECT c.mission_id,c.debut_le,c.etablissement_id,c.soignant_id,c.soignant_id,
     'CONTRAT_SOIGNANT','contrat_travail_soignant',jsonb_build_object('mission_id',c.mission_id,'cible','soignant'),
     jsonb_build_object('type','CONTRAT_TRAVAIL_MANQUANT_SOIGNANT','destinataire_id',c.soignant_id,'data',
       jsonb_build_object('prenom',c.prenom_soignant,'nom_etablissement',c.nom_etablissement,
         'intitule_mission',coalesce(nullif(c.intitule,''),'mission'),'date_debut',to_char(c.debut_le AT TIME ZONE 'UTC','DD/MM/YYYY'),'mission_id',c.mission_id))
   FROM contrats c
 ), recus AS (
   INSERT INTO private.rappels_quotidiens_livraisons(mission_id,debut_le,etablissement_id,soignant_id,destinataire_id,nature,scope,identite,corps,jour)
   SELECT mission_id,debut_le,etablissement_id,soignant_id,destinataire_id,nature,scope,identite,corps,CURRENT_DATE FROM souhaites
   ON CONFLICT(mission_id,destinataire_id,nature,jour) DO NOTHING RETURNING *
 ), files AS (
   INSERT INTO public.email_queue(id,type,destinataire_id,data,statut)
   SELECT email_id,'CRON_DAILY_'||nature,destinataire_id,corps,'EN_ATTENTE' FROM recus RETURNING type
 )
 SELECT jsonb_build_object('total',count(*),'mission_email',count(*) FILTER(WHERE type='CRON_DAILY_MISSION_EMAIL'),
   'mission_sms',count(*) FILTER(WHERE type='CRON_DAILY_MISSION_SMS'),
   'contrat_etab',count(*) FILTER(WHERE type='CRON_DAILY_CONTRAT_ETAB'),
   'contrat_soignant',count(*) FILTER(WHERE type='CRON_DAILY_CONTRAT_SOIGNANT')) INTO resultat FROM files;
 RETURN resultat;
END $fn$;

CREATE OR REPLACE FUNCTION public.fn_lire_rappel_quotidien(p_email_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE l private.rappels_quotidiens_livraisons; m public.missions; s public.soignants;
BEGIN
 SELECT * INTO l FROM private.rappels_quotidiens_livraisons WHERE email_id=p_email_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('valide',false); END IF;
 SELECT * INTO m FROM public.missions WHERE id=l.mission_id;
 SELECT * INTO s FROM public.soignants WHERE id=l.soignant_id;
 IF m.id IS NULL OR s.id IS NULL OR s.supprime_le IS NOT NULL OR m.debut_le<=now()
   OR m.debut_le IS DISTINCT FROM l.debut_le OR m.soignant_assigne_id IS DISTINCT FROM l.soignant_id
   OR m.etablissement_id IS DISTINCT FROM l.etablissement_id
   OR NOT EXISTS(SELECT 1 FROM public.etablissements WHERE id=l.etablissement_id AND supprime_le IS NULL)
   OR NOT EXISTS(SELECT 1 FROM public.email_queue WHERE id=p_email_id AND statut='EN_ATTENTE'
     AND destinataire_id=l.destinataire_id AND type='CRON_DAILY_'||l.nature AND data=l.corps)
 THEN RETURN jsonb_build_object('valide',false); END IF;
 -- Le texte « demain » ne peut traverser minuit dans une file en retard.
 IF l.nature LIKE 'MISSION_%' AND (m.statut<>'ASSIGNEE' OR l.jour<>CURRENT_DATE OR m.debut_le::date<>CURRENT_DATE+1)
 THEN RETURN jsonb_build_object('valide',false); END IF;
 IF l.nature LIKE 'CONTRAT_%' AND (m.statut NOT IN ('ASSIGNEE','EN_COURS') OR m.type_contrat_applique IS DISTINCT FROM 'SALARIE'
   OR EXISTS(SELECT 1 FROM public.contrats_travail_missions WHERE mission_id=l.mission_id))
 THEN RETURN jsonb_build_object('valide',false); END IF;
 -- Ne jamais envoyer à un ancien téléphone après une modification de profil.
 IF l.nature='MISSION_SMS' AND (s.telephone IS DISTINCT FROM l.corps->>'telephone'
   OR s.sms_actif=false OR s.sms_alertes_actives=false OR s.est_compte_test=true)
 THEN RETURN jsonb_build_object('valide',false); END IF;
 RETURN jsonb_build_object('valide',true,'canal',CASE WHEN l.nature='MISSION_SMS' THEN 'SMS' ELSE 'EMAIL' END,
   'scope',l.scope,'identite',l.identite,'corps',l.corps);
END $fn$;

CREATE OR REPLACE FUNCTION public.fn_acquitter_rappel_quotidien(p_email_id uuid,p_resultat text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE l private.rappels_quotidiens_livraisons; n integer;
BEGIN
 IF p_resultat NOT IN ('ENVOYE','ANNULE','ERREUR') OR p_resultat IS NULL THEN RAISE EXCEPTION 'Résultat invalide'; END IF;
 SELECT * INTO l FROM private.rappels_quotidiens_livraisons WHERE email_id=p_email_id FOR UPDATE;
 -- Une mission supprimée peut avoir retiré le reçu ; seule son annulation reste permise.
 IF NOT FOUND AND p_resultat<>'ANNULE' THEN RAISE EXCEPTION 'Livraison absente'; END IF;
 UPDATE public.email_queue SET statut=p_resultat,envoye=(p_resultat='ENVOYE'),
   envoye_le=CASE WHEN p_resultat='ENVOYE' THEN now() ELSE NULL END,
   erreur=CASE p_resultat WHEN 'ERREUR' THEN 'Transport à reprendre' WHEN 'ANNULE' THEN 'Rappel devenu inutile ou refusé par les préférences' ELSE NULL END
 WHERE id=p_email_id AND statut='EN_ATTENTE' AND type LIKE 'CRON_DAILY_%';
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n=0 THEN RETURN; END IF;
 IF p_resultat='ERREUR' THEN
   UPDATE private.rappels_quotidiens_livraisons SET tentatives=tentatives+1,
     prochaine_tentative_le=now()+make_interval(mins=>least(60,power(2,least(tentatives,6))::integer)) WHERE email_id=p_email_id;
 ELSIF p_resultat='ENVOYE' AND l.nature LIKE 'CONTRAT_%' THEN
   -- Acquittement et comptabilisation du contrat sont indivisibles, à la date du lot.
   INSERT INTO public.rappels_contrat_travail(mission_id,envoye_le,cible_etab,cible_soignant)
   VALUES(l.mission_id,l.jour,l.nature='CONTRAT_ETAB',l.nature='CONTRAT_SOIGNANT')
   ON CONFLICT(mission_id,envoye_le) DO UPDATE SET
     cible_etab=public.rappels_contrat_travail.cible_etab OR excluded.cible_etab,
     cible_soignant=public.rappels_contrat_travail.cible_soignant OR excluded.cible_soignant;
 END IF;
END $fn$;

CREATE OR REPLACE FUNCTION public.fn_reprendre_rappels_quotidiens()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE n integer;
BEGIN
 UPDATE public.email_queue q SET statut='EN_ATTENTE'
 FROM private.rappels_quotidiens_livraisons l
 WHERE q.id=l.email_id AND q.statut='ERREUR' AND l.prochaine_tentative_le<=now();
 GET DIAGNOSTICS n=ROW_COUNT;
 RETURN n;
END $fn$;

REVOKE ALL ON FUNCTION public.fn_preparer_rappels_quotidiens(),public.fn_lire_rappel_quotidien(uuid),
 public.fn_acquitter_rappel_quotidien(uuid,text),public.fn_reprendre_rappels_quotidiens() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_preparer_rappels_quotidiens(),public.fn_lire_rappel_quotidien(uuid),
 public.fn_acquitter_rappel_quotidien(uuid,text),public.fn_reprendre_rappels_quotidiens() TO service_role;
