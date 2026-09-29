-- Copies de documents employeur : aucune écriture dans la paie, les paiements
-- ou les contrats. Pas de remise légale exclusive ni de calcul de salaire.
CREATE TABLE IF NOT EXISTS public.copies_bulletins_paie (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id),
  soignant_id uuid NOT NULL REFERENCES public.soignants(id),
  periode_debut date NOT NULL,
  periode_fin date NOT NULL CHECK (periode_fin >= periode_debut),
  -- Snapshot historique volontaire : une correction reste possible après
  -- modification/suppression des missions. Pas de FK vers leur état vivant.
  mission_ids uuid[] NOT NULL CHECK (cardinality(mission_ids) BETWEEN 1 AND 100),
  idempotence uuid NOT NULL,
  cree_par uuid NOT NULL REFERENCES auth.users(id),
  cree_le timestamptz NOT NULL DEFAULT now(),
  expire_le timestamptz NOT NULL DEFAULT now() + interval '24 hours',
  statut text NOT NULL DEFAULT 'RESERVEE' CHECK (statut IN ('RESERVEE','PUBLIEE','REMPLACEE','RETIREE')),
  version integer NOT NULL CHECK (version >= 1),
  remplace_id uuid REFERENCES public.copies_bulletins_paie(id),
  motif_remplacement text CHECK (motif_remplacement IN ('CONTENU','AUTRE')),
  storage_path text NOT NULL UNIQUE,
  sha256_attendu text NOT NULL CHECK (sha256_attendu ~ '^[0-9a-f]{64}$'),
  taille_attendue bigint NOT NULL CHECK (taille_attendue BETWEEN 1 AND 10485760),
  sha256 text CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  taille_octets bigint CHECK (taille_octets BETWEEN 1 AND 10485760),
  publie_le timestamptz,
  retire_le timestamptz,
  UNIQUE(cree_par,idempotence),
  CHECK ((remplace_id IS NULL AND motif_remplacement IS NULL AND version = 1)
    OR (remplace_id IS NOT NULL AND motif_remplacement IS NOT NULL AND version > 1)),
  CHECK ((statut = 'RESERVEE' AND publie_le IS NULL AND sha256 IS NULL AND taille_octets IS NULL)
    OR (statut <> 'RESERVEE' AND publie_le IS NOT NULL AND sha256 IS NOT NULL AND taille_octets IS NOT NULL
      AND sha256 = sha256_attendu AND taille_octets = taille_attendue))
);
CREATE UNIQUE INDEX IF NOT EXISTS copies_bulletins_version_active
  ON public.copies_bulletins_paie(etablissement_id,soignant_id,periode_debut,periode_fin)
  WHERE statut = 'PUBLIEE';
CREATE UNIQUE INDEX IF NOT EXISTS copies_bulletins_remplacement_unique
  ON public.copies_bulletins_paie(remplace_id) WHERE publie_le IS NOT NULL AND remplace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS copies_bulletins_soignant ON public.copies_bulletins_paie(soignant_id,publie_le DESC);
CREATE TABLE IF NOT EXISTS public.signalements_copies_bulletins (
  copie_id uuid NOT NULL REFERENCES public.copies_bulletins_paie(id),
  auteur_id uuid NOT NULL REFERENCES auth.users(id),
  motif text NOT NULL CHECK (motif IN ('DESTINATAIRE','CONTENU','AUTRE')),
  cree_le timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(copie_id,auteur_id,motif)
);
CREATE TABLE IF NOT EXISTS private.audit_copies_bulletins (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  copie_id uuid NOT NULL REFERENCES public.copies_bulletins_paie(id),
  acteur_id uuid NOT NULL REFERENCES auth.users(id),
  action text NOT NULL CHECK(action IN ('PUBLICATION','REMPLACEMENT','SIGNALEMENT','RETRAIT')),
  cree_le timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.copies_bulletins_paie ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.signalements_copies_bulletins ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.audit_copies_bulletins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.copies_bulletins_paie,public.signalements_copies_bulletins FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private.audit_copies_bulletins FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE private.audit_copies_bulletins_id_seq FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.copies_bulletins_paie,public.signalements_copies_bulletins TO service_role;
-- Les mutations restent exclusivement dans les fonctions ci-dessous ; pas de
-- GRANT direct service nécessaire pour l'Edge. Les octets publiés sont immuables.

CREATE OR REPLACE FUNCTION private.fn_gestion_copie_bulletin(p_etab uuid,p_acteur uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $gestion$
  SELECT EXISTS (
    SELECT 1 FROM auth.users u JOIN public.etablissements e ON e.id=p_etab
    WHERE u.id=p_acteur AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until<=now()) AND e.supprime_le IS NULL
      AND NOT EXISTS(SELECT 1 FROM public.soignants s WHERE s.id=u.id AND s.supprime_le IS NOT NULL)
      AND NOT EXISTS(SELECT 1 FROM public.etablissements propre WHERE propre.id=u.id AND propre.supprime_le IS NOT NULL)
      AND (EXISTS(SELECT 1 FROM public.membres_etablissement m
        WHERE m.user_id=u.id AND m.etablissement_id=e.id AND m.actif
          AND m.role IN ('PROPRIETAIRE','ADMIN_GROUPE'))
        OR (u.id=e.id AND u.raw_app_meta_data->>'role' IN ('ADMIN_ETABLISSEMENT','ETABLISSEMENT')
          -- Une appartenance explicite, même inactive/rétrogradée, prime
          -- toujours sur la compatibilité historique Auth ID = établissement.
          AND NOT EXISTS(SELECT 1 FROM public.membres_etablissement explicite
            WHERE explicite.user_id=u.id AND explicite.etablissement_id=e.id)))
  );
$gestion$;
REVOKE ALL ON FUNCTION private.fn_gestion_copie_bulletin(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_reserver_copie_bulletin(
  p_etablissement_id uuid,p_soignant_id uuid,p_periode_debut date,p_periode_fin date,
  p_mission_ids uuid[],p_idempotence uuid,p_sha256_attendu text,p_taille_attendue bigint,
  p_remplace_id uuid DEFAULT NULL,p_motif_remplacement text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $reserve$
DECLARE v public.copies_bulletins_paie; precedent public.copies_bulletins_paie;
  ids uuid[]; nouvel_id uuid := gen_random_uuid();
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif()
    OR NOT private.fn_gestion_copie_bulletin(p_etablissement_id,auth.uid()) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  IF p_idempotence IS NULL OR p_soignant_id IS NULL OR p_periode_debut IS NULL
    OR p_periode_fin IS NULL OR p_periode_fin<p_periode_debut
    OR p_periode_fin-p_periode_debut>366 OR p_sha256_attendu IS NULL
    OR p_sha256_attendu !~ '^[0-9a-f]{64}$' OR p_taille_attendue IS NULL
    OR p_taille_attendue NOT BETWEEN 1 AND 10485760
    OR p_mission_ids IS NULL OR cardinality(p_mission_ids) NOT BETWEEN 1 AND 100
    OR array_position(p_mission_ids,NULL) IS NOT NULL
    OR (p_remplace_id IS NULL AND p_motif_remplacement IS NOT NULL)
    OR (p_remplace_id IS NOT NULL AND (p_motif_remplacement IS NULL OR p_motif_remplacement NOT IN ('CONTENU','AUTRE'))) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='COPIE_PARAMETRES_INVALIDES'; END IF;
  SELECT array_agg(DISTINCT x ORDER BY x) INTO ids FROM unnest(p_mission_ids) x;
  IF cardinality(ids)<>cardinality(p_mission_ids) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='COPIE_MISSIONS_INVALIDES'; END IF;
  -- Sérialise les intentions identiques, même en cas de double clic simultané.
  PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_idempotence::text,0));
  SELECT * INTO v FROM public.copies_bulletins_paie
    WHERE cree_par=auth.uid() AND idempotence=p_idempotence FOR UPDATE;
  IF v.id IS NOT NULL THEN
    IF (v.etablissement_id,v.soignant_id,v.periode_debut,v.periode_fin,v.mission_ids,
        v.sha256_attendu,v.taille_attendue,v.remplace_id,v.motif_remplacement)
      IS DISTINCT FROM (p_etablissement_id,p_soignant_id,p_periode_debut,p_periode_fin,ids,
        p_sha256_attendu,p_taille_attendue,p_remplace_id,p_motif_remplacement) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='COPIE_IDEMPOTENCE_CONFLIT'; END IF;
    IF v.statut='RETIREE' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='COPIE_RETIREE'; END IF;
    IF v.statut='RESERVEE' THEN
      UPDATE public.copies_bulletins_paie SET expire_le=now()+interval '24 hours' WHERE id=v.id;
    END IF;
    RETURN jsonb_build_object('id',v.id,'statut',v.statut,'version',v.version,
      'bucket','copies-bulletins-paie','storage_path',v.storage_path);
  END IF;
  IF p_remplace_id IS NOT NULL THEN
    SELECT * INTO precedent FROM public.copies_bulletins_paie WHERE id=p_remplace_id FOR UPDATE;
    IF precedent.id IS NULL OR precedent.statut<>'PUBLIEE'
      OR (precedent.etablissement_id,precedent.soignant_id,precedent.periode_debut,precedent.periode_fin,precedent.mission_ids)
        IS DISTINCT FROM (p_etablissement_id,p_soignant_id,p_periode_debut,p_periode_fin,ids) THEN
      RAISE EXCEPTION USING ERRCODE='40001',MESSAGE='COPIE_VERSION_CONFLIT'; END IF;
  ELSE
    -- La première copie doit être justifiée par les missions vivantes. Le
    -- verrou ferme la course avec UPDATE/DELETE entre validation et commit.
    PERFORM m.id FROM public.missions m WHERE m.id=ANY(ids) ORDER BY m.id FOR SHARE;
    IF (SELECT count(*) FROM public.missions m WHERE m.id=ANY(ids)
      AND m.etablissement_id=p_etablissement_id AND m.soignant_assigne_id=p_soignant_id
      AND m.type_contrat_applique='SALARIE' AND m.statut::text NOT IN ('OUVERTE','EXPIREE')
      AND (m.debut_le AT TIME ZONE 'Europe/Paris')::date<=p_periode_fin
      AND (m.fin_le AT TIME ZONE 'Europe/Paris')::date>=p_periode_debut) <> cardinality(ids) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='COPIE_MISSIONS_INVALIDES'; END IF;
    IF EXISTS(SELECT 1 FROM public.copies_bulletins_paie WHERE etablissement_id=p_etablissement_id
      AND soignant_id=p_soignant_id AND periode_debut=p_periode_debut AND periode_fin=p_periode_fin AND statut='PUBLIEE') THEN
      RAISE EXCEPTION USING ERRCODE='40001',MESSAGE='COPIE_VERSION_CONFLIT'; END IF;
  END IF;
  INSERT INTO public.copies_bulletins_paie(id,etablissement_id,soignant_id,periode_debut,periode_fin,
    mission_ids,idempotence,cree_par,version,remplace_id,motif_remplacement,storage_path,sha256_attendu,taille_attendue)
  VALUES(nouvel_id,p_etablissement_id,p_soignant_id,p_periode_debut,p_periode_fin,ids,p_idempotence,auth.uid(),
    COALESCE(precedent.version+1,1),p_remplace_id,p_motif_remplacement,nouvel_id::text||'/original.pdf',p_sha256_attendu,p_taille_attendue)
  RETURNING * INTO v;
  RETURN jsonb_build_object('id',v.id,'statut',v.statut,'version',v.version,'bucket','copies-bulletins-paie','storage_path',v.storage_path);
END;
$reserve$;

CREATE OR REPLACE FUNCTION public.fn_autoriser_upload_copie_bulletin(p_path text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $upload$
 SELECT public.fn_compte_auth_actif() AND EXISTS(SELECT 1 FROM public.copies_bulletins_paie c
  WHERE c.storage_path=p_path AND c.cree_par=auth.uid() AND c.statut='RESERVEE'
    AND c.expire_le>now() AND private.fn_gestion_copie_bulletin(c.etablissement_id,auth.uid()));
$upload$;

CREATE OR REPLACE FUNCTION public.fn_acces_copie_bulletin(p_copie_id uuid,p_action text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $acces$
DECLARE v public.copies_bulletins_paie;
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif() OR p_action NOT IN ('finaliser','telecharger') OR p_action IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  SELECT * INTO v FROM public.copies_bulletins_paie WHERE id=p_copie_id;
  IF v.id IS NULL OR NOT (
    (p_action='finaliser' AND v.cree_par=auth.uid() AND private.fn_gestion_copie_bulletin(v.etablissement_id,auth.uid()))
    OR (p_action='telecharger'
      AND (v.soignant_id=auth.uid() OR private.fn_gestion_copie_bulletin(v.etablissement_id,auth.uid())))) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  IF v.statut='RETIREE' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='COPIE_RETIREE'; END IF;
  IF p_action='telecharger' AND v.statut NOT IN ('PUBLIEE','REMPLACEE') THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  IF p_action='finaliser' AND v.statut='RESERVEE' AND v.expire_le<=now() THEN
    RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='COPIE_RESERVATION_EXPIREE'; END IF;
  RETURN jsonb_build_object('id',v.id,'statut',v.statut,'storage_path',v.storage_path,
    'sha256_attendu',v.sha256_attendu,'taille_attendue',v.taille_attendue);
END;
$acces$;

CREATE OR REPLACE FUNCTION public.fn_publier_copie_bulletin_interne(p_copie_id uuid,p_acteur_id uuid,p_sha256 text,p_taille bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $publier$
DECLARE v public.copies_bulletins_paie; precedent public.copies_bulletins_paie;
BEGIN
  -- Seule l'Edge authentifiée, après parsing des octets, possède EXECUTE.
  IF COALESCE(auth.role(),'')<>'service_role' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  SELECT * INTO v FROM public.copies_bulletins_paie WHERE id=p_copie_id FOR UPDATE;
  IF v.id IS NULL OR p_acteur_id IS DISTINCT FROM v.cree_par
    OR NOT private.fn_gestion_copie_bulletin(v.etablissement_id,p_acteur_id) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  IF p_sha256 IS DISTINCT FROM v.sha256_attendu OR p_taille IS DISTINCT FROM v.taille_attendue THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='COPIE_INTEGRITE_INVALIDE'; END IF;
  IF v.statut='RETIREE' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='COPIE_RETIREE'; END IF;
  IF v.statut IN ('PUBLIEE','REMPLACEE') THEN
    RETURN jsonb_build_object('ok',true,'id',v.id,'statut',v.statut); END IF;
  IF v.expire_le<=now() THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='COPIE_RESERVATION_EXPIREE'; END IF;
  IF v.remplace_id IS NULL THEN
    PERFORM m.id FROM public.missions m WHERE m.id=ANY(v.mission_ids) ORDER BY m.id FOR SHARE;
    IF (SELECT count(*) FROM public.missions m WHERE m.id=ANY(v.mission_ids)
      AND m.etablissement_id=v.etablissement_id AND m.soignant_assigne_id=v.soignant_id AND m.type_contrat_applique='SALARIE'
      AND m.statut::text NOT IN ('OUVERTE','EXPIREE')
      AND (m.debut_le AT TIME ZONE 'Europe/Paris')::date<=v.periode_fin
      AND (m.fin_le AT TIME ZONE 'Europe/Paris')::date>=v.periode_debut)<>cardinality(v.mission_ids) THEN
      RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='COPIE_MISSIONS_INVALIDES'; END IF;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='copies-bulletins-paie' AND name=v.storage_path) THEN
    RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='COPIE_FICHIER_ABSENT'; END IF;
  -- Verrou période : empêche deux premières publications concurrentes et
  -- sérialise les replacements, avant l'unicité partielle qui ferme la course.
  PERFORM pg_advisory_xact_lock(hashtextextended(v.etablissement_id::text||v.soignant_id::text||v.periode_debut::text||v.periode_fin::text,0));
  IF v.remplace_id IS NOT NULL THEN
    SELECT * INTO precedent FROM public.copies_bulletins_paie WHERE id=v.remplace_id FOR UPDATE;
    IF precedent.statut IS DISTINCT FROM 'PUBLIEE'
      OR (precedent.etablissement_id,precedent.soignant_id,precedent.periode_debut,precedent.periode_fin,precedent.mission_ids,precedent.version+1)
        IS DISTINCT FROM (v.etablissement_id,v.soignant_id,v.periode_debut,v.periode_fin,v.mission_ids,v.version) THEN
      RAISE EXCEPTION USING ERRCODE='40001',MESSAGE='COPIE_VERSION_CONFLIT'; END IF;
    UPDATE public.copies_bulletins_paie SET statut='REMPLACEE' WHERE id=precedent.id;
  ELSIF EXISTS(SELECT 1 FROM public.copies_bulletins_paie c WHERE c.etablissement_id=v.etablissement_id
    AND c.soignant_id=v.soignant_id AND c.periode_debut=v.periode_debut AND c.periode_fin=v.periode_fin AND c.statut='PUBLIEE') THEN
    RAISE EXCEPTION USING ERRCODE='40001',MESSAGE='COPIE_VERSION_CONFLIT'; END IF;
  UPDATE public.copies_bulletins_paie SET statut='PUBLIEE',publie_le=now(),sha256=p_sha256,taille_octets=p_taille WHERE id=v.id;
  INSERT INTO private.audit_copies_bulletins(copie_id,acteur_id,action)
    VALUES(v.id,p_acteur_id,CASE WHEN v.remplace_id IS NULL THEN 'PUBLICATION' ELSE 'REMPLACEMENT' END);
  INSERT INTO public.notifications(destinataire_id,type_destinataire,type,titre,corps,lien,type_ressource,id_ressource)
    VALUES(v.soignant_id,'SOIGNANT','SYSTEM','Document disponible',
      'Une copie de document de paie est disponible dans Jolene.',
      '/soignant/mes-gains?tab=bulletins','COPIE_BULLETIN',v.id);
  RETURN jsonb_build_object('ok',true,'id',v.id,'statut','PUBLIEE');
END;
$publier$;

CREATE OR REPLACE FUNCTION public.fn_lister_copies_bulletins(p_etablissement_id uuid DEFAULT NULL,p_mission_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $liste$
BEGIN
  IF auth.uid() IS NULL OR NOT public.fn_compte_auth_actif()
    OR (p_etablissement_id IS NOT NULL AND NOT private.fn_gestion_copie_bulletin(p_etablissement_id,auth.uid())) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',c.id,'etablissement_id',c.etablissement_id,
    'etablissement_nom',e.nom,'soignant_id',c.soignant_id,'soignant_nom',s.nom,'soignant_prenom',s.prenom,
    'periode_debut',c.periode_debut,'periode_fin',c.periode_fin,'statut',c.statut,'version',c.version,
    'publie_le',c.publie_le,'remplace_id',c.remplace_id,'motif_remplacement',c.motif_remplacement,
    'mission_ids',c.mission_ids,'taille_octets',c.taille_octets,'sha256',c.sha256,
    'signalee',EXISTS(SELECT 1 FROM public.signalements_copies_bulletins x WHERE x.copie_id=c.id))
    ORDER BY c.periode_fin DESC,c.publie_le DESC),'[]'::jsonb)
    FROM public.copies_bulletins_paie c JOIN public.etablissements e ON e.id=c.etablissement_id
    JOIN public.soignants s ON s.id=c.soignant_id WHERE c.statut<>'RESERVEE'
      AND ((p_etablissement_id IS NULL AND c.soignant_id=auth.uid()) OR c.etablissement_id=p_etablissement_id)
      AND (p_mission_id IS NULL OR p_mission_id=ANY(c.mission_ids)));
END;
$liste$;

CREATE OR REPLACE FUNCTION public.fn_retirer_copie_bulletin(p_copie_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $retirer$
DECLARE v public.copies_bulletins_paie;
BEGIN
  SELECT * INTO v FROM public.copies_bulletins_paie WHERE id=p_copie_id FOR UPDATE;
  IF v.id IS NULL OR auth.uid() IS NULL OR NOT public.fn_compte_auth_actif()
    OR NOT private.fn_gestion_copie_bulletin(v.etablissement_id,auth.uid()) THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  IF v.statut='RESERVEE' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='COPIE_NON_PUBLIEE'; END IF;
  IF v.statut<>'RETIREE' THEN
    UPDATE public.copies_bulletins_paie SET statut='RETIREE',retire_le=now() WHERE id=v.id;
    INSERT INTO private.audit_copies_bulletins(copie_id,acteur_id,action) VALUES(v.id,auth.uid(),'RETRAIT');
  END IF;
  RETURN jsonb_build_object('ok',true);
END;
$retirer$;

CREATE OR REPLACE FUNCTION public.fn_signaler_copie_bulletin(p_copie_id uuid,p_motif text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $signaler$
DECLARE v public.copies_bulletins_paie; ajoute integer;
BEGIN
  SELECT * INTO v FROM public.copies_bulletins_paie WHERE id=p_copie_id FOR UPDATE;
  IF v.id IS NULL OR auth.uid() IS NULL OR NOT public.fn_compte_auth_actif()
    OR v.soignant_id<>auth.uid() OR v.statut='RESERVEE' THEN
    RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='COPIE_ACCES_REFUSE'; END IF;
  IF p_motif IS NULL OR p_motif NOT IN ('DESTINATAIRE','CONTENU','AUTRE') THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='COPIE_MOTIF_INVALIDE'; END IF;
  INSERT INTO public.signalements_copies_bulletins(copie_id,auteur_id,motif) VALUES(v.id,auth.uid(),p_motif) ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS ajoute=ROW_COUNT;
  IF ajoute>0 THEN
    INSERT INTO private.audit_copies_bulletins(copie_id,acteur_id,action) VALUES(v.id,auth.uid(),'SIGNALEMENT');
    INSERT INTO public.notifications(destinataire_id,type_destinataire,type,titre,corps,lien,type_ressource,id_ressource)
      SELECT v.cree_par,'ETABLISSEMENT','SYSTEM','Document à vérifier',
        'Une copie de document de paie a été signalée. Consultez les copies dans Jolene.',
        '/etablissement/export-paie','COPIE_BULLETIN',v.id
      WHERE private.fn_gestion_copie_bulletin(v.etablissement_id,v.cree_par);
  END IF;
  IF p_motif='DESTINATAIRE' AND v.statut<>'RETIREE' THEN
    UPDATE public.copies_bulletins_paie SET statut='RETIREE',retire_le=now() WHERE id=v.id;
    INSERT INTO private.audit_copies_bulletins(copie_id,acteur_id,action) VALUES(v.id,auth.uid(),'RETRAIT');
  END IF;
  RETURN jsonb_build_object('ok',true);
END;
$signaler$;

REVOKE ALL ON FUNCTION public.fn_reserver_copie_bulletin(uuid,uuid,date,date,uuid[],uuid,text,bigint,uuid,text),
  public.fn_autoriser_upload_copie_bulletin(text), public.fn_acces_copie_bulletin(uuid,text),
  public.fn_lister_copies_bulletins(uuid,uuid), public.fn_retirer_copie_bulletin(uuid),
  public.fn_signaler_copie_bulletin(uuid,text), public.fn_publier_copie_bulletin_interne(uuid,uuid,text,bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fn_reserver_copie_bulletin(uuid,uuid,date,date,uuid[],uuid,text,bigint,uuid,text),
  public.fn_autoriser_upload_copie_bulletin(text), public.fn_acces_copie_bulletin(uuid,text),
  public.fn_lister_copies_bulletins(uuid,uuid), public.fn_retirer_copie_bulletin(uuid),
  public.fn_signaler_copie_bulletin(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_publier_copie_bulletin_interne(uuid,uuid,text,bigint) TO service_role;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('copies-bulletins-paie','copies-bulletins-paie',false,10485760,ARRAY['application/pdf'])
ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=EXCLUDED.file_size_limit,allowed_mime_types=EXCLUDED.allowed_mime_types;
DROP POLICY IF EXISTS copies_bulletins_upload ON storage.objects;
CREATE POLICY copies_bulletins_upload ON storage.objects FOR INSERT TO authenticated
WITH CHECK(bucket_id='copies-bulletins-paie' AND public.fn_autoriser_upload_copie_bulletin(name));
-- Défense contre toute politique permissive globale future (les permissives
-- sont combinées par OR). Lecture binaire uniquement via l'Edge authentifiée.
DROP POLICY IF EXISTS copies_bulletins_insert_guard ON storage.objects;
CREATE POLICY copies_bulletins_insert_guard ON storage.objects AS RESTRICTIVE FOR INSERT TO authenticated
WITH CHECK(bucket_id<>'copies-bulletins-paie' OR public.fn_autoriser_upload_copie_bulletin(name));
DROP POLICY IF EXISTS copies_bulletins_anon_insert_guard ON storage.objects;
CREATE POLICY copies_bulletins_anon_insert_guard ON storage.objects AS RESTRICTIVE FOR INSERT TO anon
WITH CHECK(bucket_id<>'copies-bulletins-paie');
DROP POLICY IF EXISTS copies_bulletins_select_guard ON storage.objects;
CREATE POLICY copies_bulletins_select_guard ON storage.objects AS RESTRICTIVE FOR SELECT TO authenticated,anon
USING(bucket_id<>'copies-bulletins-paie');
DROP POLICY IF EXISTS copies_bulletins_update_guard ON storage.objects;
CREATE POLICY copies_bulletins_update_guard ON storage.objects AS RESTRICTIVE FOR UPDATE TO authenticated,anon
USING(bucket_id<>'copies-bulletins-paie') WITH CHECK(bucket_id<>'copies-bulletins-paie');
DROP POLICY IF EXISTS copies_bulletins_delete_guard ON storage.objects;
CREATE POLICY copies_bulletins_delete_guard ON storage.objects AS RESTRICTIVE FOR DELETE TO authenticated,anon
USING(bucket_id<>'copies-bulletins-paie');

-- Corps revus, empreintes littérales (pas de classification auto de pg_proc).
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification) VALUES
  ('fn_reserver_copie_bulletin(uuid,uuid,date,date,uuid[],uuid,text,bigint,uuid,text)','RPC_UTILISATEUR_AUTH_INTERNE','5b1bd0c472c44e63f6a501b198ca73f1','Copies employeur : droits explicites, compte actif, perimetre documentaire et aucun mouvement financier.'),
  ('fn_autoriser_upload_copie_bulletin(text)','RPC_UTILISATEUR_AUTH_INTERNE','80db0f5b3897561b56e1e4145c67d12f','Copies employeur : droits explicites, compte actif, perimetre documentaire et aucun mouvement financier.'),
  ('fn_acces_copie_bulletin(uuid,text)','RPC_UTILISATEUR_AUTH_INTERNE','4396dd2947dcb1ad242fb7a05cb94661','Copies employeur : droits explicites, compte actif, perimetre documentaire et aucun mouvement financier.'),
  ('fn_publier_copie_bulletin_interne(uuid,uuid,text,bigint)','SERVICE_ONLY_REVOQUE','59a0b25ad8d1570cd16f3152d85a613a','Copies employeur : droits explicites, compte actif, perimetre documentaire et aucun mouvement financier.'),
  ('fn_lister_copies_bulletins(uuid,uuid)','RPC_UTILISATEUR_AUTH_INTERNE','8334830787d5132c275a5ddbc367e5e7','Copies employeur : droits explicites, compte actif, perimetre documentaire et aucun mouvement financier.'),
  ('fn_retirer_copie_bulletin(uuid)','RPC_UTILISATEUR_AUTH_INTERNE','38888e3e7f244f838f5427c2fc3ed62d','Copies employeur : droits explicites, compte actif, perimetre documentaire et aucun mouvement financier.'),
  ('fn_signaler_copie_bulletin(uuid,text)','RPC_UTILISATEUR_AUTH_INTERNE','1e089214d4f35b3581a3638ebd907eea','Copies employeur : droits explicites, compte actif, perimetre documentaire et aucun mouvement financier.')
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification;
