-- Refuse tout envoi commercial vers un contact ayant exprimé STOP, marqué
-- perdu ou placé en opposition dans une source officielle. La fonction reste
-- inaccessible au navigateur : seules les Edge Functions en service_role
-- peuvent l'appeler immédiatement avant l'envoi externe.
CREATE OR REPLACE FUNCTION public.fn_sales_outreach_est_interdit(
  p_contact_id uuid DEFAULT NULL,
  p_cible text DEFAULT NULL,
  p_prospect_id text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_telephone text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_cible text := upper(btrim(COALESCE(p_cible, '')));
  v_prospect_id text := NULLIF(btrim(COALESCE(p_prospect_id, '')), '');
  v_email text := NULLIF(lower(btrim(COALESCE(p_email, ''))), '');
  v_telephone text := NULLIF(regexp_replace(COALESCE(p_telephone, ''), '\D', '', 'g'), '');
BEGIN
  IF v_cible NOT IN ('ETABLISSEMENT', 'SOIGNANT') THEN
    RETURN true;
  END IF;

  IF p_contact_id IS NULL
     AND v_prospect_id IS NULL
     AND v_email IS NULL
     AND (v_telephone IS NULL OR length(v_telephone) < 9) THEN
    RETURN true;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.sales_contacts c
    WHERE (c.ne_plus_contacter IS TRUE OR c.statut = 'PERDU')
      AND (
        (p_contact_id IS NOT NULL AND c.id = p_contact_id)
        OR (
          v_cible = 'ETABLISSEMENT'
          AND v_prospect_id IS NOT NULL
          AND c.finess = v_prospect_id
        )
        OR (
          v_prospect_id IS NOT NULL
          AND c.source_prospect_type = v_cible
          AND c.source_prospect_id = v_prospect_id
        )
        OR (v_email IS NOT NULL AND lower(btrim(c.email)) = v_email)
        OR (
          v_telephone IS NOT NULL
          AND length(v_telephone) >= 9
          AND regexp_replace(COALESCE(c.telephone, ''), '\D', '', 'g') = v_telephone
        )
      )
  ) THEN
    RETURN true;
  END IF;

  IF v_prospect_id IS NOT NULL AND (
    (v_cible = 'ETABLISSEMENT' AND EXISTS (
      SELECT 1 FROM public.prospects_etablissements p
      WHERE p.finess = v_prospect_id AND p.statut_sourcing = 'OPPOSITION'
    ))
    OR
    (v_cible = 'SOIGNANT' AND EXISTS (
      SELECT 1 FROM public.prospects_soignants p
      WHERE p.cle = v_prospect_id AND p.statut_sourcing = 'OPPOSITION'
    ))
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$fn$;

-- Le tableau CRM filtre aussi les contacts bloques a la source. Le composant
-- applique le meme garde-fou, mais il ne doit jamais recevoir une tache STOP.
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
      'a_traiter', (
        SELECT count(*)
        FROM public.sales_taches st
        JOIN public.sales_contacts sc ON sc.id = st.contact_id
        WHERE st.statut IN ('A_FAIRE', 'EN_COURS')
          AND st.echeance_le <= now()
          AND sc.ne_plus_contacter IS FALSE
          AND sc.statut <> 'PERDU'
      ),
      'en_retard', (
        SELECT count(*)
        FROM public.sales_taches st
        JOIN public.sales_contacts sc ON sc.id = st.contact_id
        WHERE st.statut IN ('A_FAIRE', 'EN_COURS')
          AND st.echeance_le < date_trunc('day', now())
          AND sc.ne_plus_contacter IS FALSE
          AND sc.statut <> 'PERDU'
      ),
      'sept_jours', (
        SELECT count(*)
        FROM public.sales_taches st
        JOIN public.sales_contacts sc ON sc.id = st.contact_id
        WHERE st.statut IN ('A_FAIRE', 'EN_COURS')
          AND st.echeance_le <= now() + interval '7 days'
          AND sc.ne_plus_contacter IS FALSE
          AND sc.statut <> 'PERDU'
      ),
      'sans_responsable', (
        SELECT count(*)
        FROM public.sales_contacts
        WHERE archive IS FALSE
          AND sequence_active IS TRUE
          AND responsable_id IS NULL
          AND ne_plus_contacter IS FALSE
          AND statut <> 'PERDU'
      ),
      'contacts_actifs', (
        SELECT count(*)
        FROM public.sales_contacts
        WHERE archive IS FALSE
          AND statut NOT IN ('INSCRIT', 'PERDU')
          AND ne_plus_contacter IS FALSE
      ),
      'taux_conversion', (
        SELECT CASE
          WHEN count(*) = 0 THEN 0
          ELSE round(100.0 * count(*) FILTER (WHERE statut = 'INSCRIT') / count(*), 1)
        END
        FROM public.sales_contacts
        WHERE archive IS FALSE AND ne_plus_contacter IS FALSE
      ),
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
          AND sc.ne_plus_contacter IS FALSE
          AND sc.statut <> 'PERDU'
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

REVOKE ALL ON FUNCTION public.fn_sales_outreach_est_interdit(uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sales_outreach_est_interdit(uuid, text, text, text, text)
  TO service_role;

REVOKE ALL ON FUNCTION public.fn_admin_crm_tableau(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_crm_tableau(integer) TO authenticated, service_role;
