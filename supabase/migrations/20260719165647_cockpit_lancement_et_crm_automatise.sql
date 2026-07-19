-- Cockpit de lancement + CRM automatise.
--
-- Principes :
--   * les donnees de demo restent visibles, mais chaque metrique est segmentee
--     REEL / TEST / TOUS ;
--   * aucune prospection froide n'est envoyee sans validation humaine ;
--   * le CRM automatise la priorisation, l'attribution, les echeances,
--     l'idempotence des relances et l'historique des actions ;
--   * toutes les surfaces sont reservees aux administrateurs valides.

-- ---------------------------------------------------------------------------
-- 1. Modele CRM : sequence, taches et journal immuable d'activite
-- ---------------------------------------------------------------------------

ALTER TABLE public.sales_contacts
  ADD COLUMN IF NOT EXISTS responsable_id uuid,
  ADD COLUMN IF NOT EXISTS prochaine_action_le timestamptz,
  ADD COLUMN IF NOT EXISTS sequence_etape smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sequence_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS ne_plus_contacter boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS derniere_action_type text;

DO $fk$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sales_contacts_responsable_id_fkey'
      AND conrelid = 'public.sales_contacts'::regclass
  ) THEN
    ALTER TABLE public.sales_contacts
      ADD CONSTRAINT sales_contacts_responsable_id_fkey
      FOREIGN KEY (responsable_id)
      REFERENCES public.equipe_admin(user_id)
      ON DELETE SET NULL;
  END IF;
END;
$fk$;

ALTER TABLE public.sales_contacts
  DROP CONSTRAINT IF EXISTS sales_contacts_sequence_etape_check;
ALTER TABLE public.sales_contacts
  ADD CONSTRAINT sales_contacts_sequence_etape_check
  CHECK (sequence_etape BETWEEN 0 AND 20);

CREATE INDEX IF NOT EXISTS idx_sales_contacts_prochaine_action
  ON public.sales_contacts (prochaine_action_le)
  WHERE archive IS FALSE AND sequence_active IS TRUE AND ne_plus_contacter IS FALSE;
CREATE INDEX IF NOT EXISTS idx_sales_contacts_responsable
  ON public.sales_contacts (responsable_id)
  WHERE archive IS FALSE;

CREATE TABLE IF NOT EXISTS public.sales_taches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES public.sales_contacts(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN (
    'PREMIER_CONTACT', 'RELANCE', 'RELANCE_FINALE', 'RAPPEL', 'ONBOARDING'
  )),
  canal text NOT NULL DEFAULT 'TELEPHONE'
    CHECK (canal IN ('TELEPHONE', 'EMAIL', 'WHATSAPP', 'AUTRE')),
  statut text NOT NULL DEFAULT 'A_FAIRE'
    CHECK (statut IN ('A_FAIRE', 'EN_COURS', 'TERMINEE', 'ANNULEE')),
  priorite text NOT NULL DEFAULT 'NORMALE'
    CHECK (priorite IN ('BASSE', 'NORMALE', 'HAUTE', 'URGENTE')),
  titre text NOT NULL,
  echeance_le timestamptz NOT NULL,
  assignee_a uuid REFERENCES public.equipe_admin(user_id) ON DELETE SET NULL,
  sequence_etape smallint NOT NULL DEFAULT 0 CHECK (sequence_etape BETWEEN 0 AND 20),
  origine text NOT NULL DEFAULT 'AUTOMATISATION'
    CHECK (origine IN ('AUTOMATISATION', 'MANUEL', 'EMAIL_JOLENE')),
  notes text,
  idempotence_key text NOT NULL UNIQUE,
  terminee_le timestamptz,
  terminee_par uuid,
  cree_le timestamptz NOT NULL DEFAULT now(),
  maj_le timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sales_taches_file
  ON public.sales_taches (statut, echeance_le, priorite);
CREATE INDEX IF NOT EXISTS idx_sales_taches_contact
  ON public.sales_taches (contact_id, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_sales_taches_assignee
  ON public.sales_taches (assignee_a, statut, echeance_le);

CREATE TABLE IF NOT EXISTS public.sales_activites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES public.sales_contacts(id) ON DELETE CASCADE,
  tache_id uuid REFERENCES public.sales_taches(id) ON DELETE SET NULL,
  action_type text NOT NULL,
  canal text CHECK (canal IS NULL OR canal IN ('TELEPHONE', 'EMAIL', 'WHATSAPP', 'AUTRE')),
  resultat text,
  details text,
  acteur_id uuid,
  automatisee boolean NOT NULL DEFAULT false,
  cree_le timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sales_activites_contact
  ON public.sales_activites (contact_id, cree_le DESC);
CREATE INDEX IF NOT EXISTS idx_sales_activites_recentes
  ON public.sales_activites (cree_le DESC);

ALTER TABLE public.sales_taches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_activites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_all_sales_taches ON public.sales_taches;
CREATE POLICY admin_all_sales_taches
  ON public.sales_taches
  TO authenticated
  USING (public.est_admin())
  WITH CHECK (public.est_admin());

DROP POLICY IF EXISTS admin_all_sales_activites ON public.sales_activites;
CREATE POLICY admin_all_sales_activites
  ON public.sales_activites
  TO authenticated
  USING (public.est_admin())
  WITH CHECK (public.est_admin());

REVOKE ALL ON TABLE public.sales_taches FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.sales_activites FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.sales_taches TO authenticated;
GRANT SELECT, INSERT ON TABLE public.sales_activites TO authenticated;
GRANT ALL ON TABLE public.sales_taches TO service_role;
GRANT ALL ON TABLE public.sales_activites TO service_role;

-- Initialisation automatique des contacts ajoutes depuis FINESS, l'Annuaire
-- Sante, un CSV ou le formulaire manuel.
CREATE OR REPLACE FUNCTION public.fn_crm_initialiser_contact()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public, auth
AS $fn$
BEGIN
  IF NEW.statut IN ('INSCRIT', 'PERDU') OR NEW.archive IS TRUE THEN
    NEW.sequence_active := false;
    NEW.prochaine_action_le := NULL;
  ELSE
    NEW.sequence_active := COALESCE(NEW.sequence_active, true);
    NEW.prochaine_action_le := COALESCE(NEW.prochaine_action_le, now());
  END IF;

  IF NEW.responsable_id IS NULL THEN
    SELECT ea.user_id
      INTO NEW.responsable_id
      FROM public.equipe_admin ea
     WHERE ea.actif IS TRUE
       AND ea.user_id IS NOT NULL
     ORDER BY
       CASE WHEN lower(ea.email) IN ('gabrielle.pcd@outlook.com', 'admin@jolene.app') THEN 0 ELSE 1 END,
       ea.cree_le
     LIMIT 1;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_crm_initialiser_contact ON public.sales_contacts;
CREATE TRIGGER trg_crm_initialiser_contact
BEFORE INSERT ON public.sales_contacts
FOR EACH ROW EXECUTE FUNCTION public.fn_crm_initialiser_contact();

-- Backfill non destructif : les contacts de demo et historiques restent en
-- place et obtiennent uniquement une prochaine action et un responsable.
UPDATE public.sales_contacts c
   SET responsable_id = COALESCE(
         c.responsable_id,
         (SELECT ea.user_id
            FROM public.equipe_admin ea
           WHERE ea.actif IS TRUE AND ea.user_id IS NOT NULL
           ORDER BY
             CASE WHEN lower(ea.email) IN ('gabrielle.pcd@outlook.com', 'admin@jolene.app') THEN 0 ELSE 1 END,
             ea.cree_le
           LIMIT 1)
       ),
       prochaine_action_le = CASE
         WHEN c.archive OR c.statut IN ('INSCRIT', 'PERDU') THEN NULL
         ELSE COALESCE(c.prochaine_action_le, c.dernier_contact_le, now())
       END,
       sequence_active = NOT (c.archive OR c.statut IN ('INSCRIT', 'PERDU'))
 WHERE c.responsable_id IS NULL
    OR (c.prochaine_action_le IS NULL AND NOT c.archive AND c.statut NOT IN ('INSCRIT', 'PERDU'));

-- Genere la file sans doublon. Cette fonction est appelee par le cron et par
-- le bouton "Actualiser l'automatisation" de l'admin.
CREATE OR REPLACE FUNCTION public.fn_crm_generer_taches()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_creees integer := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.sales_taches (
    contact_id, type, canal, priorite, titre, echeance_le, assignee_a,
    sequence_etape, origine, idempotence_key
  )
  SELECT
    c.id,
    CASE
      WHEN c.statut = 'PROSPECT' AND c.sequence_etape = 0 THEN 'PREMIER_CONTACT'
      WHEN c.a_rappeler THEN 'RAPPEL'
      WHEN c.sequence_etape >= 3 THEN 'RELANCE_FINALE'
      ELSE 'RELANCE'
    END,
    CASE WHEN c.telephone IS NOT NULL AND btrim(c.telephone) <> '' THEN 'TELEPHONE' ELSE 'EMAIL' END,
    CASE
      WHEN c.prochaine_action_le < now() - interval '2 days' THEN 'URGENTE'
      WHEN c.prochaine_action_le < now() THEN 'HAUTE'
      ELSE 'NORMALE'
    END,
    CASE
      WHEN c.statut = 'PROSPECT' AND c.sequence_etape = 0 THEN 'Premier contact — ' || c.nom
      WHEN c.a_rappeler THEN 'Rappeler — ' || c.nom
      WHEN c.sequence_etape >= 3 THEN 'Derniere relance — ' || c.nom
      ELSE 'Relance ' || c.sequence_etape::text || ' — ' || c.nom
    END,
    COALESCE(c.prochaine_action_le, now()),
    c.responsable_id,
    c.sequence_etape,
    'AUTOMATISATION',
    c.id::text || ':SEQUENCE:' || c.sequence_etape::text
  FROM public.sales_contacts c
  WHERE c.archive IS FALSE
    AND c.sequence_active IS TRUE
    AND c.ne_plus_contacter IS FALSE
    AND c.statut NOT IN ('INSCRIT', 'PERDU')
    AND COALESCE(c.prochaine_action_le, now()) <= now() + interval '7 days'
  ON CONFLICT (idempotence_key) DO NOTHING;

  GET DIAGNOSTICS v_creees = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'taches_creees', v_creees, 'genere_le', now());
END;
$fn$;

-- Enregistre un email envoye via Resend/Gmail, ferme la tache email courante et
-- programme la prochaine relance. Utilisable par les edge functions avec la
-- service_role et par l'admin depuis le cockpit CRM.
CREATE OR REPLACE FUNCTION public.fn_crm_enregistrer_email_envoye(
  p_contact_id uuid,
  p_automatisee boolean DEFAULT false,
  p_details text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_contact public.sales_contacts%ROWTYPE;
  v_etape smallint;
  v_echeance timestamptz;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_contact
  FROM public.sales_contacts
  WHERE id = p_contact_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contact CRM introuvable';
  END IF;
  IF v_contact.ne_plus_contacter OR v_contact.statut = 'PERDU' THEN
    RAISE EXCEPTION 'Ce contact ne doit plus etre contacte';
  END IF;

  v_etape := LEAST(v_contact.sequence_etape + 1, 20);
  v_echeance := now() + CASE
    WHEN v_etape <= 1 THEN interval '3 days'
    WHEN v_etape = 2 THEN interval '7 days'
    ELSE interval '14 days'
  END;

  UPDATE public.sales_contacts
     SET statut = CASE WHEN statut = 'PROSPECT' THEN 'CONTACTE' ELSE 'RELANCE' END,
         reponse = COALESCE(reponse, 'EN_ATTENTE'),
         dernier_contact_le = now(),
         derniere_action_type = 'EMAIL_ENVOYE',
         sequence_etape = v_etape,
         sequence_active = true,
         a_rappeler = true,
         prochaine_action_le = v_echeance,
         maj_le = now()
   WHERE id = p_contact_id;

  UPDATE public.sales_taches
     SET statut = 'TERMINEE', terminee_le = now(), terminee_par = auth.uid(), maj_le = now()
   WHERE contact_id = p_contact_id
     AND statut IN ('A_FAIRE', 'EN_COURS')
     AND canal = 'EMAIL';

  INSERT INTO public.sales_activites (
    contact_id, action_type, canal, resultat, details, acteur_id, automatisee
  ) VALUES (
    p_contact_id, 'EMAIL_ENVOYE', 'EMAIL', 'EN_ATTENTE', p_details,
    auth.uid(), COALESCE(p_automatisee, false)
  );

  PERFORM public.fn_crm_generer_taches();
  RETURN jsonb_build_object('success', true, 'prochaine_action_le', v_echeance, 'sequence_etape', v_etape);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_crm_effectuer_action(
  p_tache_id uuid,
  p_resultat text,
  p_notes text DEFAULT NULL,
  p_prochaine_action_le timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_tache public.sales_taches%ROWTYPE;
  v_contact public.sales_contacts%ROWTYPE;
  v_etape smallint;
  v_echeance timestamptz;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;
  IF p_resultat NOT IN (
    'EMAIL_ENVOYE', 'APPEL_REPONDU', 'SANS_REPONSE', 'INTERESSE',
    'INSCRIT', 'A_RAPPELER', 'PAS_INTERESSE', 'STOP'
  ) THEN
    RAISE EXCEPTION 'Resultat CRM invalide';
  END IF;

  SELECT * INTO v_tache
  FROM public.sales_taches
  WHERE id = p_tache_id
  FOR UPDATE;
  IF NOT FOUND OR v_tache.statut NOT IN ('A_FAIRE', 'EN_COURS') THEN
    RAISE EXCEPTION 'Tache CRM absente ou deja traitee';
  END IF;

  SELECT * INTO v_contact
  FROM public.sales_contacts
  WHERE id = v_tache.contact_id
  FOR UPDATE;

  IF p_resultat = 'EMAIL_ENVOYE' THEN
    PERFORM public.fn_crm_enregistrer_email_envoye(v_contact.id, false, p_notes);
  ELSE
    UPDATE public.sales_taches
       SET statut = 'TERMINEE', terminee_le = now(), terminee_par = auth.uid(),
           notes = COALESCE(p_notes, notes), maj_le = now()
     WHERE id = p_tache_id;

    v_etape := CASE
      WHEN p_resultat IN ('APPEL_REPONDU', 'SANS_REPONSE', 'INTERESSE') THEN LEAST(v_contact.sequence_etape + 1, 20)
      ELSE v_contact.sequence_etape
    END;
    v_echeance := CASE
      WHEN p_resultat = 'A_RAPPELER' THEN COALESCE(p_prochaine_action_le, now() + interval '1 day')
      WHEN p_resultat = 'INTERESSE' THEN COALESCE(p_prochaine_action_le, now() + interval '1 day')
      WHEN p_resultat = 'SANS_REPONSE' THEN COALESCE(p_prochaine_action_le, now() + interval '2 days')
      WHEN p_resultat = 'APPEL_REPONDU' THEN COALESCE(p_prochaine_action_le, now() + interval '3 days')
      ELSE NULL
    END;

    UPDATE public.sales_contacts
       SET statut = CASE
             WHEN p_resultat = 'INSCRIT' THEN 'INSCRIT'
             WHEN p_resultat = 'INTERESSE' AND statut = 'PROSPECT' THEN 'CONTACTE'
             WHEN p_resultat IN ('PAS_INTERESSE', 'STOP') THEN 'PERDU'
             WHEN p_resultat = 'SANS_REPONSE' THEN 'RELANCE'
             WHEN p_resultat = 'APPEL_REPONDU' AND statut = 'PROSPECT' THEN 'CONTACTE'
             ELSE statut
           END,
           reponse = CASE
             WHEN p_resultat IN ('INTERESSE', 'INSCRIT') THEN 'POSITIVE'
             WHEN p_resultat IN ('PAS_INTERESSE', 'STOP') THEN 'NEGATIVE'
             WHEN p_resultat = 'APPEL_REPONDU' THEN 'EN_ATTENTE'
             ELSE reponse
           END,
           a_rappeler = p_resultat IN ('A_RAPPELER', 'SANS_REPONSE', 'APPEL_REPONDU', 'INTERESSE'),
           ne_plus_contacter = p_resultat IN ('PAS_INTERESSE', 'STOP'),
           sequence_active = p_resultat NOT IN ('INSCRIT', 'PAS_INTERESSE', 'STOP'),
           sequence_etape = v_etape,
           prochaine_action_le = v_echeance,
           dernier_contact_le = CASE
             WHEN p_resultat IN ('APPEL_REPONDU', 'SANS_REPONSE', 'INTERESSE') THEN now()
             ELSE dernier_contact_le
           END,
           derniere_action_type = p_resultat,
           maj_le = now()
     WHERE id = v_contact.id;

    INSERT INTO public.sales_activites (
      contact_id, tache_id, action_type, canal, resultat, details, acteur_id, automatisee
    ) VALUES (
      v_contact.id, v_tache.id, 'TACHE_TRAITEE', v_tache.canal,
      p_resultat, p_notes, auth.uid(), false
    );

    IF v_echeance IS NOT NULL THEN
      PERFORM public.fn_crm_generer_taches();
    END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'contact_id', v_contact.id, 'resultat', p_resultat);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_crm_reporter_tache(
  p_tache_id uuid,
  p_echeance_le timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_contact_id uuid;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;
  IF p_echeance_le <= now() - interval '5 minutes' OR p_echeance_le > now() + interval '1 year' THEN
    RAISE EXCEPTION 'Nouvelle echeance invalide';
  END IF;

  UPDATE public.sales_taches
     SET echeance_le = p_echeance_le, priorite = 'NORMALE', maj_le = now()
   WHERE id = p_tache_id AND statut IN ('A_FAIRE', 'EN_COURS')
   RETURNING contact_id INTO v_contact_id;
  IF v_contact_id IS NULL THEN RAISE EXCEPTION 'Tache CRM introuvable'; END IF;

  UPDATE public.sales_contacts
     SET prochaine_action_le = p_echeance_le, a_rappeler = true, maj_le = now()
   WHERE id = v_contact_id;
  INSERT INTO public.sales_activites (contact_id, tache_id, action_type, resultat, acteur_id)
  VALUES (v_contact_id, p_tache_id, 'TACHE_REPORTEE', p_echeance_le::text, auth.uid());

  RETURN jsonb_build_object('success', true, 'echeance_le', p_echeance_le);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_crm_assigner_contact(
  p_contact_id uuid,
  p_responsable_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;
  IF p_responsable_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.equipe_admin WHERE user_id = p_responsable_id AND actif IS TRUE
  ) THEN
    RAISE EXCEPTION 'Responsable CRM invalide';
  END IF;

  UPDATE public.sales_contacts
     SET responsable_id = p_responsable_id, maj_le = now()
   WHERE id = p_contact_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Contact CRM introuvable'; END IF;
  UPDATE public.sales_taches
     SET assignee_a = p_responsable_id, maj_le = now()
   WHERE contact_id = p_contact_id AND statut IN ('A_FAIRE', 'EN_COURS');
  INSERT INTO public.sales_activites (contact_id, action_type, resultat, acteur_id)
  VALUES (p_contact_id, 'ATTRIBUTION', COALESCE(p_responsable_id::text, 'NON_ASSIGNE'), auth.uid());

  RETURN jsonb_build_object('success', true);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.fn_admin_crm_tableau(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'stats', jsonb_build_object(
      'a_traiter', (SELECT count(*) FROM public.sales_taches WHERE statut IN ('A_FAIRE', 'EN_COURS') AND echeance_le <= now()),
      'en_retard', (SELECT count(*) FROM public.sales_taches WHERE statut IN ('A_FAIRE', 'EN_COURS') AND echeance_le < date_trunc('day', now())),
      'sept_jours', (SELECT count(*) FROM public.sales_taches WHERE statut IN ('A_FAIRE', 'EN_COURS') AND echeance_le <= now() + interval '7 days'),
      'sans_responsable', (SELECT count(*) FROM public.sales_contacts WHERE archive IS FALSE AND sequence_active IS TRUE AND responsable_id IS NULL),
      'contacts_actifs', (SELECT count(*) FROM public.sales_contacts WHERE archive IS FALSE AND statut NOT IN ('INSCRIT', 'PERDU')),
      'taux_conversion', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE statut = 'INSCRIT') / count(*), 1) END FROM public.sales_contacts WHERE archive IS FALSE),
      'emails_7j', (SELECT count(*) FROM public.sales_activites WHERE action_type = 'EMAIL_ENVOYE' AND cree_le >= now() - interval '7 days'),
      'actions_7j', (SELECT count(*) FROM public.sales_activites WHERE cree_le >= now() - interval '7 days')
    ),
    'taches', COALESCE((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.echeance_le, t.priorite DESC)
      FROM (
        SELECT st.id, st.contact_id, st.type, st.canal, st.statut, st.priorite,
               st.titre, st.echeance_le, st.assignee_a, st.sequence_etape,
               st.origine, st.notes,
               sc.type AS contact_type, sc.nom, sc.profession, sc.telephone,
               sc.email, sc.ville, sc.departement, sc.statut AS contact_statut,
               sc.reponse, sc.ne_plus_contacter
        FROM public.sales_taches st
        JOIN public.sales_contacts sc ON sc.id = st.contact_id
        WHERE st.statut IN ('A_FAIRE', 'EN_COURS')
        ORDER BY st.echeance_le,
                 CASE st.priorite WHEN 'URGENTE' THEN 0 WHEN 'HAUTE' THEN 1 WHEN 'NORMALE' THEN 2 ELSE 3 END
        LIMIT LEAST(GREATEST(p_limit, 1), 300)
      ) t
    ), '[]'::jsonb),
    'activites', COALESCE((
      SELECT jsonb_agg(to_jsonb(a) ORDER BY a.cree_le DESC)
      FROM (
        SELECT sa.id, sa.contact_id, sa.action_type, sa.canal, sa.resultat,
               sa.details, sa.acteur_id, sa.automatisee, sa.cree_le, sc.nom
        FROM public.sales_activites sa
        JOIN public.sales_contacts sc ON sc.id = sa.contact_id
        ORDER BY sa.cree_le DESC
        LIMIT 30
      ) a
    ), '[]'::jsonb),
    'responsables', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', ea.user_id, 'nom', ea.nom, 'prenom', ea.prenom, 'email', ea.email
      ) ORDER BY ea.prenom, ea.nom)
      FROM public.equipe_admin ea
      WHERE ea.actif IS TRUE AND ea.user_id IS NOT NULL
    ), '[]'::jsonb),
    'genere_le', now()
  ) INTO v_result;

  RETURN v_result;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_crm_generer_taches() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_crm_enregistrer_email_envoye(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_crm_effectuer_action(uuid, text, text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_crm_reporter_tache(uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_crm_assigner_contact(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_admin_crm_tableau(integer) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.fn_crm_generer_taches() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_crm_enregistrer_email_envoye(uuid, boolean, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_crm_effectuer_action(uuid, text, text, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_crm_reporter_tache(uuid, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_crm_assigner_contact(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_crm_tableau(integer) TO authenticated, service_role;

-- File initiale et regeneration horaire. Le job execute uniquement du SQL en
-- base : aucun secret et aucun appel HTTP.
SELECT public.fn_crm_generer_taches();

DO $cron$
DECLARE
  v_job record;
BEGIN
  FOR v_job IN SELECT jobid FROM cron.job WHERE jobname = 'jolene_crm_generer_taches' LOOP
    PERFORM cron.unschedule(v_job.jobid);
  END LOOP;
  PERFORM cron.schedule(
    'jolene_crm_generer_taches',
    '5 * * * *',
    $job$SELECT public.fn_crm_generer_taches();$job$
  );
EXCEPTION
  WHEN undefined_table OR invalid_schema_name THEN
    RAISE NOTICE 'pg_cron indisponible : job CRM non planifie';
END;
$cron$;

-- ---------------------------------------------------------------------------
-- 2. Cockpit de lancement segmente REEL / TEST / TOUS
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_lancement(
  p_scope text DEFAULT 'REEL',
  p_jours integer DEFAULT 30,
  p_departement text DEFAULT NULL,
  p_profession text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $fn$
DECLARE
  v_scope text := upper(COALESCE(NULLIF(btrim(p_scope), ''), 'REEL'));
  v_jours integer := LEAST(GREATEST(COALESCE(p_jours, 30), 7), 365);
  v_departement text := NULLIF(upper(btrim(p_departement)), '');
  v_profession text := NULLIF(upper(btrim(p_profession)), '');
  v_result jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Acces admin refuse' USING ERRCODE = '42501';
  END IF;
  IF v_scope NOT IN ('REEL', 'TEST', 'TOUS') THEN
    RAISE EXCEPTION 'Scope invalide : REEL, TEST ou TOUS attendu';
  END IF;

  WITH
  soignants_filtres AS (
    SELECT s.*,
           COALESCE(NULLIF(s.adresse_code_postal, ''), '') AS cp,
           left(COALESCE(NULLIF(s.adresse_code_postal, ''), ''), 2) AS departement_calcule
    FROM public.soignants s
    WHERE s.supprime_le IS NULL
      AND (v_scope = 'TOUS'
        OR (v_scope = 'TEST' AND s.est_compte_test)
        OR (v_scope = 'REEL' AND NOT s.est_compte_test))
      AND (v_profession IS NULL OR s.profession::text = v_profession)
      AND (v_departement IS NULL OR left(COALESCE(s.adresse_code_postal, ''), 2) = v_departement)
  ),
  etablissements_filtres AS (
    SELECT e.*
    FROM public.etablissements e
    WHERE e.supprime_le IS NULL
      AND (v_scope = 'TOUS'
        OR (v_scope = 'TEST' AND e.est_compte_test)
        OR (v_scope = 'REEL' AND NOT e.est_compte_test))
      AND (v_departement IS NULL OR COALESCE(e.adresse_departement, left(e.adresse_code_postal, 2)) = v_departement)
  ),
  missions_filtres AS (
    SELECT m.*,
           COALESCE(e.adresse_departement, left(e.adresse_code_postal, 2)) AS departement,
           COALESCE(e.est_compte_test, false)
             OR COALESCE(sa.est_compte_test, false) AS est_test_calcule
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id AND e.supprime_le IS NULL
    LEFT JOIN public.soignants sa ON sa.id = m.soignant_assigne_id
    WHERE m.cree_le >= now() - make_interval(days => v_jours)
      AND (v_profession IS NULL OR m.profession_requise::text = v_profession)
      AND (v_departement IS NULL OR COALESCE(e.adresse_departement, left(e.adresse_code_postal, 2)) = v_departement)
      AND (v_scope = 'TOUS'
        OR (v_scope = 'TEST' AND (COALESCE(e.est_compte_test, false) OR COALESCE(sa.est_compte_test, false)))
        OR (v_scope = 'REEL' AND NOT (COALESCE(e.est_compte_test, false) OR COALESCE(sa.est_compte_test, false))))
  ),
  candidatures_valides AS (
    SELECT c.*
    FROM public.candidatures c
    JOIN missions_filtres m ON m.id = c.mission_id
    JOIN public.soignants s ON s.id = c.soignant_id
    WHERE v_scope = 'TOUS'
       OR (v_scope = 'TEST' AND (m.est_test_calcule OR s.est_compte_test))
       OR (v_scope = 'REEL' AND NOT m.est_test_calcule AND NOT s.est_compte_test)
  ),
  stats_mission AS (
    SELECT m.id, m.etablissement_id, m.profession_requise::text AS profession,
           m.departement, m.statut::text AS statut, m.cree_le, m.debut_le, m.fin_le,
           m.soignant_assigne_id, m.absence_sans_prevenir,
           min(c.cree_le) AS premiere_candidature_le,
           min(COALESCE(c.acceptee_a, c.traite_le)) FILTER (WHERE c.statut = 'ACCEPTEE') AS pourvue_le,
           count(c.id) AS nb_candidatures
    FROM missions_filtres m
    LEFT JOIN candidatures_valides c ON c.mission_id = m.id
    GROUP BY m.id, m.etablissement_id, m.profession_requise, m.departement,
             m.statut, m.cree_le, m.debut_le, m.fin_le, m.soignant_assigne_id,
             m.absence_sans_prevenir
  ),
  pointages AS (
    SELECT sp.mission_id,
           count(*) FILTER (WHERE sp.type_scan = 'OUVERTURE') AS ouvertures,
           count(*) FILTER (WHERE sp.type_scan = 'FERMETURE') AS fermetures
    FROM public.scans_pointage sp
    JOIN missions_filtres m ON m.id = sp.mission_id
    GROUP BY sp.mission_id
  ),
  paiements AS (
    SELECT m.id AS mission_id,
      (
        EXISTS (SELECT 1 FROM public.paiements_escrow pe WHERE pe.mission_id = m.id AND (pe.paye_le IS NOT NULL OR pe.statut = 'PAYE'))
        OR EXISTS (SELECT 1 FROM public.paiements_mission pm WHERE pm.mission_id = m.id AND (pm.capture_le IS NOT NULL OR pm.statut = 'CAPTURE'))
        OR EXISTS (SELECT 1 FROM public.paiements_soignant ps WHERE ps.mission_id = m.id AND ps.statut IN ('CONFIRME', 'RESOLU'))
        OR EXISTS (SELECT 1 FROM public.factures_honoraires fh WHERE fh.mission_id = m.id AND fh.statut IN ('PAYEE', 'FACTORISEE'))
      ) AS soignant_paye,
      (
        EXISTS (SELECT 1 FROM public.factures f WHERE f.mission_id = m.id AND f.statut = 'PAYEE')
        OR EXISTS (SELECT 1 FROM public.paiements_escrow pe WHERE pe.mission_id = m.id AND pe.debite_le IS NOT NULL)
      ) AS commission_encaissee
    FROM missions_filtres m
  ),
  segments_cles AS (
    SELECT DISTINCT sm.departement, sm.profession FROM stats_mission sm
    UNION
    SELECT DISTINCT sf.departement_calcule, sf.profession::text FROM soignants_filtres sf
    WHERE sf.profession IS NOT NULL
  ),
  segments AS (
    SELECT sk.departement, sk.profession,
      (SELECT count(*) FROM soignants_filtres sf
        WHERE sf.departement_calcule = sk.departement AND sf.profession::text = sk.profession
          AND sf.tous_documents_valides) AS soignants_verifies,
      (SELECT count(DISTINCT ds.soignant_id)
         FROM public.disponibilites_soignant ds
         JOIN soignants_filtres sf ON sf.id = ds.soignant_id
        WHERE sf.departement_calcule = sk.departement AND sf.profession::text = sk.profession
          AND ds.jour BETWEEN current_date AND current_date + 7) AS disponibles_7j,
      (SELECT count(*) FROM stats_mission sm
        WHERE sm.departement = sk.departement AND sm.profession = sk.profession) AS missions_publiees,
      (SELECT count(*) FROM stats_mission sm
        WHERE sm.departement = sk.departement AND sm.profession = sk.profession
          AND sm.statut = 'OUVERTE') AS missions_ouvertes,
      (SELECT count(*) FROM stats_mission sm
        WHERE sm.departement = sk.departement AND sm.profession = sk.profession
          AND sm.soignant_assigne_id IS NOT NULL) AS missions_pourvues
    FROM segments_cles sk
    WHERE sk.departement IS NOT NULL AND sk.profession IS NOT NULL
  ),
  terminees AS (
    SELECT sm.* FROM stats_mission sm WHERE sm.statut = 'TERMINEE'
  )
  SELECT jsonb_build_object(
    'scope', v_scope,
    'jours', v_jours,
    'departement', v_departement,
    'profession', v_profession,
    'genere_le', now(),
    'offre', jsonb_build_object(
      'inscrits', (SELECT count(*) FROM soignants_filtres),
      'verifies', (SELECT count(*) FROM soignants_filtres WHERE tous_documents_valides),
      'actifs_30j', (SELECT count(*) FROM soignants_filtres WHERE derniere_activite_le >= now() - interval '30 days'),
      'disponibles_7j', (SELECT count(DISTINCT ds.soignant_id) FROM public.disponibilites_soignant ds JOIN soignants_filtres sf ON sf.id = ds.soignant_id WHERE ds.jour BETWEEN current_date AND current_date + 7)
    ),
    'demande', jsonb_build_object(
      'etablissements', (SELECT count(*) FROM etablissements_filtres),
      'etablissements_verifies', (SELECT count(*) FROM etablissements_filtres WHERE rattachement_verifie AND statut_verification = 'VERIFIE'),
      'missions_publiees', (SELECT count(*) FROM stats_mission),
      'missions_ouvertes', (SELECT count(*) FROM stats_mission WHERE statut = 'OUVERTE'),
      'missions_pourvues', (SELECT count(*) FROM stats_mission WHERE soignant_assigne_id IS NOT NULL),
      'missions_terminees', (SELECT count(*) FROM terminees)
    ),
    'conversion', jsonb_build_object(
      'taux_reponse_pct', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE nb_candidatures > 0) / count(*), 1) END FROM stats_mission),
      'taux_pourvoi_pct', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE soignant_assigne_id IS NOT NULL) / count(*), 1) END FROM stats_mission WHERE statut NOT IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT')),
      'delai_premiere_candidature_h', (SELECT COALESCE(round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (premiere_candidature_le - cree_le))) / 3600.0)::numeric, 1), 0) FROM stats_mission WHERE premiere_candidature_le IS NOT NULL),
      'delai_pourvoi_h', (SELECT COALESCE(round((percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (pourvue_le - cree_le))) / 3600.0)::numeric, 1), 0) FROM stats_mission WHERE pourvue_le IS NOT NULL)
    ),
    'qualite', jsonb_build_object(
      'pointages_complets', (SELECT count(*) FROM terminees t JOIN pointages p ON p.mission_id = t.id WHERE p.ouvertures > 0 AND p.ouvertures = p.fermetures),
      'taux_pointage_complet_pct', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE p.ouvertures > 0 AND p.ouvertures = p.fermetures) / count(*), 1) END FROM terminees t LEFT JOIN pointages p ON p.mission_id = t.id),
      'soignants_payes', (SELECT count(*) FROM terminees t JOIN paiements p ON p.mission_id = t.id WHERE p.soignant_paye),
      'taux_paiement_pct', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE p.soignant_paye) / count(*), 1) END FROM terminees t LEFT JOIN paiements p ON p.mission_id = t.id),
      'commissions_encaissees', (SELECT count(*) FROM terminees t JOIN paiements p ON p.mission_id = t.id WHERE p.commission_encaissee),
      'taux_commission_encaissee_pct', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE p.commission_encaissee) / count(*), 1) END FROM terminees t LEFT JOIN paiements p ON p.mission_id = t.id),
      'no_show', (SELECT count(*) FROM stats_mission WHERE absence_sans_prevenir OR statut = 'ABSENCE'),
      'taux_no_show_pct', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * count(*) FILTER (WHERE absence_sans_prevenir OR statut = 'ABSENCE') / count(*), 1) END FROM stats_mission WHERE soignant_assigne_id IS NOT NULL),
      'litiges_ouverts', (SELECT count(*) FROM public.litiges l JOIN missions_filtres m ON m.id = l.mission_id WHERE l.statut IN ('OUVERT', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'REVUE_ADMIN')),
      'taux_litige_pct', (SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(100.0 * (SELECT count(DISTINCT l.mission_id) FROM public.litiges l JOIN missions_filtres m ON m.id = l.mission_id) / count(*), 1) END FROM stats_mission)
    ),
    'alertes', jsonb_build_object(
      'missions_sans_candidat_24h', (SELECT count(*) FROM stats_mission WHERE statut = 'OUVERTE' AND nb_candidatures = 0 AND cree_le < now() - interval '24 hours'),
      'pointages_incomplets', (SELECT count(*) FROM terminees t LEFT JOIN pointages p ON p.mission_id = t.id WHERE COALESCE(p.ouvertures, 0) = 0 OR p.ouvertures <> p.fermetures),
      'paiements_manquants', (SELECT count(*) FROM terminees t LEFT JOIN paiements p ON p.mission_id = t.id WHERE NOT COALESCE(p.soignant_paye, false)),
      'commissions_non_encaissees', (SELECT count(*) FROM terminees t LEFT JOIN paiements p ON p.mission_id = t.id WHERE NOT COALESCE(p.commission_encaissee, false))
    ),
    'entonnoirs', jsonb_build_object(
      'soignants', jsonb_build_array(
        jsonb_build_object('etape', 'Inscrits', 'valeur', (SELECT count(*) FROM soignants_filtres)),
        jsonb_build_object('etape', 'Verifies', 'valeur', (SELECT count(*) FROM soignants_filtres WHERE tous_documents_valides)),
        jsonb_build_object('etape', 'Candidats', 'valeur', (SELECT count(DISTINCT c.soignant_id) FROM candidatures_valides c)),
        jsonb_build_object('etape', 'Mission pourvue', 'valeur', (SELECT count(DISTINCT soignant_assigne_id) FROM stats_mission WHERE soignant_assigne_id IS NOT NULL)),
        jsonb_build_object('etape', 'Mission terminee', 'valeur', (SELECT count(DISTINCT soignant_assigne_id) FROM terminees WHERE soignant_assigne_id IS NOT NULL))
      ),
      'etablissements', jsonb_build_array(
        jsonb_build_object('etape', 'Inscrits', 'valeur', (SELECT count(*) FROM etablissements_filtres)),
        jsonb_build_object('etape', 'Verifies', 'valeur', (SELECT count(*) FROM etablissements_filtres WHERE rattachement_verifie AND statut_verification = 'VERIFIE')),
        jsonb_build_object('etape', 'Mission publiee', 'valeur', (SELECT count(DISTINCT etablissement_id) FROM stats_mission)),
        jsonb_build_object('etape', 'Mission pourvue', 'valeur', (SELECT count(DISTINCT etablissement_id) FROM stats_mission WHERE soignant_assigne_id IS NOT NULL)),
        jsonb_build_object('etape', 'Deuxieme mission', 'valeur', (SELECT count(*) FROM (SELECT etablissement_id FROM stats_mission GROUP BY etablissement_id HAVING count(*) >= 2) r))
      )
    ),
    'segments', COALESCE((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.missions_ouvertes DESC, s.disponibles_7j DESC) FROM segments s), '[]'::jsonb),
    'filtres_disponibles', jsonb_build_object(
      'departements', COALESCE((SELECT jsonb_agg(DISTINCT departement ORDER BY departement) FROM stats_mission WHERE departement IS NOT NULL), '[]'::jsonb),
      'professions', COALESCE((SELECT jsonb_agg(DISTINCT profession ORDER BY profession) FROM stats_mission WHERE profession IS NOT NULL), '[]'::jsonb)
    )
  ) INTO v_result;

  RETURN v_result;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_admin_cockpit_lancement(text, integer, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_cockpit_lancement(text, integer, text, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_admin_cockpit_lancement(text, integer, text, text) IS
  'Cockpit de lancement : liquidite, conversion et qualite, segmente REEL/TEST/TOUS sans masquer les donnees de demo.';
