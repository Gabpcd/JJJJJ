-- Production definitions audited 2026-09-25. Application only via deploy-supabase.
-- No production data backfill; existing alerts and ACL remain preserved.

-- Source commune : mêmes critères pour l'annuaire, le compteur et l'aperçu email.
-- Fonction privée invoker : aucun nouvel accès aux profils n'est accordé.
CREATE OR REPLACE FUNCTION private.fn_resultats_recherche_soignants_etab(
  p_etab_id uuid,
  p_profession text DEFAULT NULL,
  p_specialites text[] DEFAULT NULL,
  p_ville text DEFAULT NULL,
  p_distance_max_km integer DEFAULT NULL,
  p_type_exercice text DEFAULT NULL,
  p_note_min numeric DEFAULT NULL,
  p_score_min integer DEFAULT NULL,
  p_experience_min integer DEFAULT NULL,
  p_disponible_urgence boolean DEFAULT NULL,
  p_documents_valides boolean DEFAULT NULL,
  p_recherche_texte text DEFAULT NULL
) RETURNS TABLE (soignant_id uuid, distance_km numeric)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $matching$
  SELECT s.id, d.distance_km
  FROM public.soignants s
  LEFT JOIN public.etablissements e ON e.id = p_etab_id
    AND p_distance_max_km IS NOT NULL
  CROSS JOIN LATERAL (SELECT CASE
        WHEN e.adresse_lat IS NOT NULL
             AND s.adresse_lat IS NOT NULL THEN
          round((
            6371 * 2 * asin(sqrt(
              power(sin(radians(s.adresse_lat - e.adresse_lat) / 2), 2)
              + cos(radians(e.adresse_lat))
                * cos(radians(s.adresse_lat))
                * power(
                  sin(radians(s.adresse_lng - e.adresse_lng) / 2),
                  2
                )
            ))
          )::numeric, 1)
        ELSE NULL
      END AS distance_km) d
  WHERE s.supprime_le IS NULL
      AND coalesce(s.statut_compte::text,'ACTIF') NOT IN ('SUPPRIME','SUSPENDU')
      AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=s.id AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now()))
      AND (
        (
          p_etab_id IS NULL
          AND s.est_compte_test IS FALSE
        )
        OR (
          p_etab_id IS NOT NULL
          AND private.fn_comptes_meme_cohorte_test(s.id, p_etab_id)
        )
      )
      AND (
        p_profession IS NULL
        OR p_profession = ''
        OR s.profession::text = p_profession
      )
      AND (
        p_specialites IS NULL
        OR array_length(p_specialites, 1) IS NULL
        OR s.specialites && p_specialites
      )
      AND (
        p_ville IS NULL
        OR p_ville = ''
        OR s.adresse_ville ILIKE '%' || p_ville || '%'
      )
      AND (
        p_type_exercice IS NULL
        OR p_type_exercice = ''
        OR COALESCE(s.type_exercice, 'SALARIE') = p_type_exercice
      )
      AND (
        p_note_min IS NULL
        OR (
          COALESCE(s.nb_evaluations, 0) >= 3
          AND COALESCE(s.note_moyenne, 0) >= p_note_min
        )
      )
      AND (
        p_score_min IS NULL
        OR (
          COALESCE(s.total_missions_terminees, 0) >= 3
          AND COALESCE(s.score_fiabilite, 0) >= p_score_min
        )
      )
      AND (
        p_experience_min IS NULL
        OR COALESCE(s.annees_experience, 0) >= p_experience_min
      )
      AND (
        p_disponible_urgence IS NULL
        OR COALESCE(s.disponible_urgence, false) =
          p_disponible_urgence
      )
      AND (
        p_documents_valides IS NULL
        OR COALESCE(s.tous_documents_valides, false) =
          p_documents_valides
      )
      AND (
        p_recherche_texte IS NULL
        OR p_recherche_texte = ''
        OR s.prenom ILIKE '%' || p_recherche_texte || '%'
        OR COALESCE(s.bio, '') ILIKE
          '%' || p_recherche_texte || '%'
      )
    AND (p_distance_max_km IS NULL OR d.distance_km IS NULL OR d.distance_km <= p_distance_max_km);
$matching$;
REVOKE ALL ON FUNCTION private.fn_resultats_recherche_soignants_etab(uuid,text,text[],text,integer,text,numeric,integer,integer,boolean,boolean,text) FROM PUBLIC, anon, authenticated;

-- Équivalent du périmètre mon_etablissement_id pour le destinataire du cron.
-- Le cron ne doit jamais emprunter les claims d'un utilisateur.
CREATE OR REPLACE FUNCTION private.fn_etablissement_destinataire_alerte(p_user_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $scope$
  SELECT COALESCE(
    (SELECT m.etablissement_id
     FROM public.membres_etablissement m
     JOIN public.etablissements e ON e.id = m.etablissement_id
     WHERE m.user_id = u.id AND m.actif IS TRUE AND e.supprime_le IS NULL
     ORDER BY CASE m.role WHEN 'PROPRIETAIRE' THEN 1 WHEN 'ADMIN_GROUPE' THEN 2 ELSE 3 END
     LIMIT 1),
    (SELECT e.id FROM public.etablissements e
     WHERE e.id = u.id AND e.supprime_le IS NULL
       AND u.raw_app_meta_data->>'role' IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT'))
  )
  FROM auth.users u
  WHERE u.id = p_user_id AND u.deleted_at IS NULL
    AND (u.banned_until IS NULL OR u.banned_until <= now())
    AND NOT EXISTS (SELECT 1 FROM public.soignants s WHERE s.id=u.id AND (s.supprime_le IS NOT NULL OR s.statut_compte::text IN ('SUPPRIME','SUSPENDU')));
$scope$;
REVOKE ALL ON FUNCTION private.fn_etablissement_destinataire_alerte(uuid) FROM PUBLIC, anon, authenticated;

-- Fail closed pour les anciennes sauvegardes malformées ou critères inconnus :
-- aucun cast invalide ne doit arrêter toutes les autres recherches du cron.
CREATE OR REPLACE FUNCTION private.fn_filtres_recherche_soignants_valides(p_filtres jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = ''
AS $validation$
DECLARE k text; v text; maximum numeric; entier boolean;
BEGIN
  IF p_filtres IS NULL OR jsonb_typeof(p_filtres) <> 'object' THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_filtres) AS x(cle) WHERE cle <> ALL(ARRAY[
    'profession','type_exercice','ville','distance_max_km','note_min','score_min',
    'experience_min','disponible_urgence','documents_valides','recherche_texte'])) THEN RETURN false; END IF;
  FOREACH k IN ARRAY ARRAY['profession','type_exercice','ville','recherche_texte'] LOOP
    IF p_filtres ? k AND jsonb_typeof(p_filtres->k) NOT IN ('string','null') THEN RETURN false; END IF;
  END LOOP;
  IF COALESCE(p_filtres->>'profession','') <> '' AND NOT EXISTS (
    SELECT 1 FROM unnest(enum_range(NULL::public.type_profession)) AS p(profession) WHERE p.profession::text=p_filtres->>'profession'
  ) THEN RETURN false; END IF;
  IF COALESCE(p_filtres->>'type_exercice','') <> '' AND p_filtres->>'type_exercice' NOT IN ('LIBERAL','SALARIE','MIXTE') THEN RETURN false; END IF;
  FOREACH k IN ARRAY ARRAY['disponible_urgence','documents_valides'] LOOP
    IF p_filtres ? k AND jsonb_typeof(p_filtres->k) NOT IN ('boolean','null') THEN RETURN false; END IF;
  END LOOP;
  FOREACH k IN ARRAY ARRAY['distance_max_km','note_min','score_min','experience_min'] LOOP
    v := p_filtres->>k;
    IF v IS NULL OR v = '' THEN CONTINUE; END IF;
    IF jsonb_typeof(p_filtres->k) NOT IN ('string','number') OR length(v)>20 OR v !~ '^[0-9]+([.][0-9]+)?$' THEN RETURN false; END IF;
    maximum := CASE k WHEN 'distance_max_km' THEN 500 WHEN 'note_min' THEN 5 WHEN 'score_min' THEN 100 ELSE 50 END;
    entier := k <> 'note_min';
    IF v::numeric > maximum OR (entier AND trunc(v::numeric) <> v::numeric) THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
END;
$validation$;
REVOKE ALL ON FUNCTION private.fn_filtres_recherche_soignants_valides(jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.fn_resultats_filtre_soignants(p_filtre_id uuid, p_since timestamptz)
RETURNS TABLE (soignant_id uuid, distance_km numeric)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path = ''
AS $saved$
DECLARE f public.filtres_sauvegardes; e uuid;
BEGIN
  SELECT * INTO f FROM public.filtres_sauvegardes WHERE id=p_filtre_id AND audience='ETAB_RECHERCHE_SOIGNANTS';
  IF NOT FOUND OR NOT private.fn_filtres_recherche_soignants_valides(f.filtres) THEN RETURN; END IF;
  e := private.fn_etablissement_destinataire_alerte(f.utilisateur_id);
  IF e IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT r.soignant_id,r.distance_km
  FROM private.fn_resultats_recherche_soignants_etab(
    e, NULLIF(f.filtres->>'profession',''), NULL::text[], NULLIF(f.filtres->>'ville',''),
    NULLIF(f.filtres->>'distance_max_km','')::numeric::integer, NULLIF(f.filtres->>'type_exercice',''),
    NULLIF(f.filtres->>'note_min','')::numeric, NULLIF(f.filtres->>'score_min','')::numeric::integer,
    NULLIF(f.filtres->>'experience_min','')::numeric::integer,
    CASE WHEN f.filtres->>'disponible_urgence' = 'true' THEN true ELSE NULL END,
    CASE WHEN f.filtres->>'documents_valides' = 'true' THEN true ELSE NULL END,
    NULLIF(f.filtres->>'recherche_texte','')
  ) r
  JOIN public.soignants s ON s.id=r.soignant_id
  WHERE s.cree_le > p_since AND s.cree_le <= now();
END;
$saved$;
REVOKE ALL ON FUNCTION private.fn_resultats_filtre_soignants(uuid,timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_rechercher_soignants_etab(p_profession text DEFAULT NULL::text, p_specialites text[] DEFAULT NULL::text[], p_ville text DEFAULT NULL::text, p_distance_max_km integer DEFAULT NULL::integer, p_type_exercice text DEFAULT NULL::text, p_note_min numeric DEFAULT NULL::numeric, p_score_min integer DEFAULT NULL::integer, p_experience_min integer DEFAULT NULL::integer, p_disponible_urgence boolean DEFAULT NULL::boolean, p_documents_valides boolean DEFAULT NULL::boolean, p_recherche_texte text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_etab_id uuid;
  v_limit integer;
  v_offset integer;
  v_result jsonb;
BEGIN
  IF NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object('error','Accès refusé : compte inactif');
  END IF;
  IF NOT est_admin() THEN
    v_etab_id := mon_etablissement_id();
    IF v_etab_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.etablissements e WHERE e.id=v_etab_id AND e.supprime_le IS NULL) THEN
      RETURN jsonb_build_object(
        'error',
        'Accès refusé : étab requis'
      );
    END IF;
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  v_offset := GREATEST(COALESCE(p_offset, 0), 0);

  WITH with_distance AS (
    SELECT s.*, r.distance_km
    FROM private.fn_resultats_recherche_soignants_etab(
      v_etab_id, p_profession, p_specialites, p_ville, p_distance_max_km,
      p_type_exercice, p_note_min, p_score_min, p_experience_min,
      p_disponible_urgence, p_documents_valides, p_recherche_texte
    ) r
    JOIN public.soignants s ON s.id=r.soignant_id
  ),
  ranked AS (
    SELECT
      *,
      row_number() OVER (
        ORDER BY
          CASE
            WHEN COALESCE(total_missions_terminees, 0) >= 3
              THEN score_fiabilite
            ELSE -1
          END DESC NULLS LAST,
          CASE
            WHEN COALESCE(nb_evaluations, 0) >= 3
              THEN note_moyenne
            ELSE -1
          END DESC NULLS LAST,
          COALESCE(total_missions_terminees, 0) DESC,
          id
      ) AS rn,
      count(*) OVER () AS total_count
    FROM with_distance
  ),
  paged AS (
    SELECT *
    FROM ranked
    WHERE rn > v_offset
      AND rn <= v_offset + v_limit
  )
  SELECT jsonb_build_object(
    'soignants',
    COALESCE(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'prenom', p.prenom,
      'nom_initiale', left(p.nom, 1) || '.',
      'profession', p.profession::text,
      'specialite_medicale', p.specialite_medicale,
      'type_exercice', COALESCE(p.type_exercice, 'SALARIE'),
      'score_fiabilite', CASE
        WHEN COALESCE(p.total_missions_terminees, 0) >= 3
          THEN p.score_fiabilite
        ELSE NULL
      END,
      'note_moyenne', CASE
        WHEN COALESCE(p.nb_evaluations, 0) >= 3
          THEN p.note_moyenne
        ELSE NULL
      END,
      'nb_evaluations', COALESCE(p.nb_evaluations, 0),
      'total_missions_terminees',
        COALESCE(p.total_missions_terminees, 0),
      'annees_experience', p.annees_experience,
      'specialites', COALESCE(p.specialites, ARRAY[]::text[]),
      'bio_extrait', left(COALESCE(p.bio, ''), 200),
      'avatar_url', p.avatar_url,
      'rpps_verifie', COALESCE(p.rpps_verifie, false),
      'tous_documents_valides',
        COALESCE(p.tous_documents_valides, false),
      'disponible_urgence', COALESCE(p.disponible_urgence, false),
      'ville', p.adresse_ville,
      'distance_km', p.distance_km,
      'priorite_missions_urgentes',
        COALESCE(p.priorite_missions_urgentes, false),
      'badge_ambassadeur',
        COALESCE(p.badge_ambassadeur, false)
    ) ORDER BY p.rn), '[]'::jsonb),
    'count_total', COALESCE(max(p.total_count), 0),
    'limit', v_limit,
    'offset', v_offset
  )
  INTO v_result
  FROM paged p;

  RETURN COALESCE(
    v_result,
    jsonb_build_object(
      'soignants', '[]'::jsonb,
      'count_total', 0,
      'limit', v_limit,
      'offset', v_offset
    )
  );
END;
$function$;

-- Les préférences réellement proposées dans Explorer. Une ancienne clé inconnue
-- ferme la recherche au lieu de créer une alerte plus large que la sauvegarde.
CREATE OR REPLACE FUNCTION private.fn_filtres_recherche_missions_valides(p jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE k text; v text;
BEGIN
 IF p IS NULL OR jsonb_typeof(p)<>'object' THEN RETURN false; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p) AS keys(cle) WHERE keys.cle<>ALL(ARRAY['profession','rayonKm','tauxMin','typeContrat','urgentesOnly','horaire','villeRecherche'])) THEN RETURN false; END IF;
 FOREACH k IN ARRAY ARRAY['profession','typeContrat','horaire','villeRecherche'] LOOP
  IF p?k AND jsonb_typeof(p->k) NOT IN ('string','null') THEN RETURN false; END IF;
 END LOOP;
 IF coalesce(p->>'profession','')<>'' AND NOT EXISTS(SELECT 1 FROM unnest(enum_range(NULL::public.type_profession)) AS professions(valeur) WHERE professions.valeur::text=p->>'profession') THEN RETURN false; END IF;
 IF coalesce(p->>'typeContrat','TOUS') NOT IN ('TOUS','CDD','LIBERAL') OR coalesce(p->>'horaire','TOUS') NOT IN ('TOUS','JOUR','NUIT','WEEKEND') THEN RETURN false; END IF;
 IF p?'urgentesOnly' AND jsonb_typeof(p->'urgentesOnly') NOT IN ('boolean','null') THEN RETURN false; END IF;
 FOREACH k IN ARRAY ARRAY['rayonKm','tauxMin'] LOOP
  v:=p->>k;
  IF v IS NULL THEN CONTINUE; END IF;
  IF jsonb_typeof(p->k) NOT IN ('number','string') OR length(v)>20 OR v!~'^[0-9]+([.][0-9]+)?$' OR v::numeric>10000 THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END $fn$;
REVOKE ALL ON FUNCTION private.fn_filtres_recherche_missions_valides(jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.fn_destinataire_alerte_actif(p_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
 SELECT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=p_uid AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now()))
 AND NOT EXISTS(SELECT 1 FROM public.soignants s WHERE s.id=p_uid AND (s.supprime_le IS NOT NULL OR s.statut_compte::text IN ('SUPPRIME','SUSPENDU')))
 AND NOT EXISTS(SELECT 1 FROM public.etablissements e WHERE e.id=p_uid AND e.supprime_le IS NOT NULL)
$fn$;
REVOKE ALL ON FUNCTION private.fn_destinataire_alerte_actif(uuid) FROM PUBLIC,anon,authenticated;

-- Reproduit planningCorrespondAuFiltre : vrais créneaux, pauses exclues,
-- repli uniquement mission ponctuelle, nuit 20h–7h et week-end en Europe/Paris.
CREATE OR REPLACE FUNCTION private.fn_mission_correspond_horaire(p_id uuid,p_horaire text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
 WITH m AS (SELECT * FROM public.missions WHERE id=p_id),
 c AS (SELECT c.debut,c.fin FROM public.mission_creneaux c WHERE c.mission_id=p_id AND c.type_creneau='PREVISIONNEL' AND NOT coalesce(c.est_pause,false)),
 planning AS (
  SELECT * FROM c UNION ALL SELECT m.debut_le,m.fin_le FROM m
  WHERE coalesce(m.nb_creneaux,0)<=1 AND NOT EXISTS(SELECT 1 FROM c) AND m.debut_le IS NOT NULL AND m.fin_le IS NOT NULL
 ), valide AS (
  SELECT count(*)>0 AND bool_and(fin IS NOT NULL AND fin>debut)
   AND (coalesce((SELECT nb_creneaux FROM m),0)=0 OR count(*)=(SELECT nb_creneaux FROM m)) AS exact FROM planning
 ), nature AS (
  SELECT p.*, EXISTS(
   SELECT 1 FROM generate_series((p.debut AT TIME ZONE 'Europe/Paris')::date::timestamp,(p.fin AT TIME ZONE 'Europe/Paris')::date::timestamp,interval '1 day') j
   WHERE (p.debut < ((j+interval '7 hours') AT TIME ZONE 'Europe/Paris') AND p.fin > (j AT TIME ZONE 'Europe/Paris'))
      OR (p.debut < ((j+interval '1 day') AT TIME ZONE 'Europe/Paris') AND p.fin > ((j+interval '20 hours') AT TIME ZONE 'Europe/Paris'))
  ) AS nuit, EXISTS(
   SELECT 1 FROM generate_series((p.debut AT TIME ZONE 'Europe/Paris')::date::timestamp,(p.fin AT TIME ZONE 'Europe/Paris')::date::timestamp,interval '1 day') j
   WHERE extract(isodow FROM j) IN (6,7) AND p.debut<((j+interval '1 day') AT TIME ZONE 'Europe/Paris') AND p.fin>(j AT TIME ZONE 'Europe/Paris')
  ) AS weekend FROM planning p
 )
 SELECT p_horaire='TOUS' OR (coalesce((SELECT exact FROM valide),false) AND EXISTS(
  SELECT 1 FROM nature WHERE CASE p_horaire WHEN 'NUIT' THEN nuit WHEN 'JOUR' THEN NOT nuit WHEN 'WEEKEND' THEN weekend ELSE false END
 ))
$fn$;
REVOKE ALL ON FUNCTION private.fn_mission_correspond_horaire(uuid,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION private.fn_resultats_filtre_missions(p_filtre_id uuid,p_since timestamptz)
RETURNS TABLE(mission_id uuid) LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=''
AS $fn$
DECLARE f public.filtres_sauvegardes; s public.soignants; profession text; accepted text[]; raw text; rayon numeric; ville text;
BEGIN
 SELECT * INTO f FROM public.filtres_sauvegardes WHERE id=p_filtre_id AND audience='SOIGNANT_RECHERCHE_MISSIONS';
 IF NOT FOUND OR NOT private.fn_filtres_recherche_missions_valides(f.filtres) OR NOT private.fn_destinataire_alerte_actif(f.utilisateur_id) THEN RETURN; END IF;
 SELECT * INTO s FROM public.soignants WHERE id=f.utilisateur_id AND supprime_le IS NULL;
 IF NOT FOUND AND NOT EXISTS(SELECT 1 FROM public.parcours_inscription WHERE user_id=f.utilisateur_id AND type_compte='SOIGNANT') THEN RETURN; END IF;
 profession:=coalesce(s.profession::text,(SELECT donnees->>'profession' FROM public.parcours_inscription WHERE user_id=f.utilisateur_id AND type_compte='SOIGNANT'));
 raw:=trim(coalesce(s.types_contrat_acceptes,''));
 IF raw<>'' THEN
  BEGIN
   IF jsonb_typeof(raw::jsonb)='array' THEN
    IF jsonb_array_length(raw::jsonb)>0 THEN SELECT array_agg(value) INTO accepted FROM jsonb_array_elements_text(raw::jsonb); END IF;
   END IF;
  EXCEPTION WHEN invalid_text_representation THEN NULL; END;
  IF accepted IS NULL THEN SELECT array_agg(trim(x)) INTO accepted FROM unnest(string_to_array(raw,',')) x WHERE trim(x)<>''; END IF;
 END IF;
 IF accepted IS NULL THEN accepted:=CASE s.type_exercice WHEN 'MIXTE' THEN ARRAY['CDD','LIBERAL'] WHEN 'LIBERAL' THEN ARRAY['LIBERAL'] ELSE CASE WHEN s.type_contrat IS NOT NULL THEN ARRAY[s.type_contrat::text] ELSE ARRAY['CDD','VACATION','LIBERAL','SALARIE'] END END; END IF;
 rayon:=coalesce((f.filtres->>'rayonKm')::numeric,s.rayon_deplacement_km,50);
 ville:=lower(trim(coalesce(f.filtres->>'villeRecherche','')));
 RETURN QUERY SELECT m.id FROM public.missions m
 JOIN public.etablissements e ON e.id=m.etablissement_id AND e.supprime_le IS NULL
 CROSS JOIN LATERAL(SELECT coalesce(nullif(m.type_contrat_recherche,''),substring(m.description FROM '\[CONTRAT:(TOUS|SALARIE|LIBERAL)\]'),'TOUS') AS type) contrat
 WHERE m.statut='OUVERTE' AND m.debut_le>=now() AND m.cree_le>p_since AND m.cree_le<=now()
 AND private.fn_destinataire_alerte_actif(e.id)
 AND CASE WHEN s.id IS NULL THEN
   m.soignant_assigne_id IS NULL AND public.fn_mission_publique(m.id) IS NOT NULL
   AND NOT private.fn_mission_lie_compte_test(m.id)
  ELSE private.fn_comptes_meme_cohorte_test(f.utilisateur_id,e.id) END
 AND NOT public.fn_est_exclu(f.utilisateur_id,e.id)
 AND CASE WHEN coalesce(f.filtres->>'profession','')<>'' THEN m.profession_requise::text=f.filtres->>'profession'
  ELSE profession IS NULL OR profession='' OR m.profession_requise::text=profession OR (profession IN ('IADE','IBODE') AND m.profession_requise::text='IDE') END
 AND coalesce(m.taux_horaire_base,0)>=coalesce((f.filtres->>'tauxMin')::numeric,0)
 AND (coalesce((f.filtres->>'urgentesOnly')::boolean,false)=false OR m.est_urgente IS TRUE)
 AND (ville='' OR position(ville IN lower(coalesce(e.adresse_ville,'')))>0 OR starts_with(lower(coalesce(e.adresse_code_postal,'')),ville))
 AND (s.adresse_lat IS NULL OR s.adresse_lng IS NULL OR e.adresse_lat IS NULL OR e.adresse_lng IS NULL OR
  round((6371*2*asin(least(1,sqrt(power(sin(radians(e.adresse_lat-s.adresse_lat)/2),2)+cos(radians(s.adresse_lat))*cos(radians(e.adresse_lat))*power(sin(radians(e.adresse_lng-s.adresse_lng)/2),2)))))::numeric,1)<=rayon)
 AND (contrat.type<>'LIBERAL' OR 'LIBERAL'=ANY(accepted))
 AND (coalesce(f.filtres->>'typeContrat','TOUS')<>'CDD' OR contrat.type<>'LIBERAL')
 AND (coalesce(f.filtres->>'typeContrat','TOUS')<>'LIBERAL' OR contrat.type<>'SALARIE')
 AND private.fn_mission_correspond_horaire(m.id,coalesce(f.filtres->>'horaire','TOUS'));
END $fn$;
REVOKE ALL ON FUNCTION private.fn_resultats_filtre_missions(uuid,timestamptz) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.fn_compter_nouveaux_pour_filtre(p_filtre_id uuid, p_since timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filtre RECORD;
  v_count integer := 0;
  v_profession text;
  v_taux_min numeric;
  v_urgentes_only boolean;
BEGIN
  SELECT * INTO v_filtre FROM filtres_sauvegardes WHERE id = p_filtre_id;
  IF NOT FOUND THEN RETURN 0; END IF;

  IF v_filtre.audience = 'SOIGNANT_RECHERCHE_MISSIONS' THEN
    SELECT count(*) INTO v_count FROM private.fn_resultats_filtre_missions(p_filtre_id,p_since);
  ELSIF v_filtre.audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    SELECT count(*) INTO v_count
    FROM private.fn_resultats_filtre_soignants(p_filtre_id, p_since);
  END IF;

  RETURN COALESCE(v_count, 0);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_obtenir_apercu_filtre(p_filtre_id uuid, p_since timestamp with time zone, p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_filtre RECORD;
  v_result jsonb;
  v_profession text;
  v_taux_min numeric;
  v_urgentes_only boolean;
BEGIN
  SELECT * INTO v_filtre FROM filtres_sauvegardes WHERE id = p_filtre_id;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  IF v_filtre.audience = 'SOIGNANT_RECHERCHE_MISSIONS' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', m.id, 'intitule', m.intitule, 'profession', m.profession_requise::text,
      'etablissement', e.nom, 'ville', e.adresse_ville,
      'taux_horaire', m.taux_horaire_base,
      'debut_le', m.debut_le, 'fin_le', m.fin_le,
      'urgente', COALESCE(m.est_urgente, false)
    ) ORDER BY m.cree_le DESC), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT m2.* FROM missions m2
      JOIN private.fn_resultats_filtre_missions(p_filtre_id,p_since) r ON r.mission_id=m2.id
      ORDER BY m2.cree_le DESC,m2.id LIMIT least(100,greatest(1,coalesce(p_limit,5)))
    ) m
    LEFT JOIN etablissements e ON e.id = m.etablissement_id;
  ELSIF v_filtre.audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', s.id, 'prenom', s.prenom, 'nom_initiale', LEFT(s.nom,1) || '.',
      'profession', s.profession::text,
      'note_moyenne', CASE WHEN COALESCE(s.nb_evaluations,0) >= 3 THEN s.note_moyenne ELSE NULL END
    ) ORDER BY s.cree_le DESC, s.id), '[]'::jsonb) INTO v_result
    FROM (
      SELECT s.* FROM private.fn_resultats_filtre_soignants(p_filtre_id,p_since) r
      JOIN public.soignants s ON s.id=r.soignant_id
      ORDER BY s.cree_le DESC, s.id
      LIMIT LEAST(GREATEST(COALESCE(p_limit,5),1),100)
    ) s;
  ELSE
    v_result := '[]'::jsonb;
  END IF;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$function$;

-- Une livraison durable est créée dans la même transaction que le watermark.
-- email_queue conserve son transport et son identité idempotente existants.
CREATE TABLE private.alertes_filtres_livraisons (
 email_id uuid PRIMARY KEY REFERENCES public.email_queue(id) ON DELETE CASCADE,
 filtre_id uuid NOT NULL REFERENCES public.filtres_sauvegardes(id) ON DELETE CASCADE,
 fenetre_debut timestamptz NOT NULL,
 fenetre_fin timestamptz NOT NULL,
 filtres jsonb NOT NULL,
 etablissement_id uuid,
 prochaine_tentative_le timestamptz NOT NULL DEFAULT now(),
 tentatives integer NOT NULL DEFAULT 0,
 UNIQUE(filtre_id,fenetre_debut,fenetre_fin),
 CHECK(fenetre_fin>=fenetre_debut)
);
ALTER TABLE private.alertes_filtres_livraisons ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.alertes_filtres_livraisons FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE private.alertes_filtres_worker (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 derniere_execution_le timestamptz NOT NULL
);
ALTER TABLE private.alertes_filtres_worker ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.alertes_filtres_worker FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.fn_capacite_alertes_recherches()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT auth.uid() IS NOT NULL
 AND private.fn_etablissement_destinataire_alerte(auth.uid()) IS NOT NULL
 AND EXISTS(SELECT 1 FROM private.alertes_filtres_worker WHERE derniere_execution_le>now()-interval '3 hours')
$fn$;
REVOKE ALL ON FUNCTION public.fn_capacite_alertes_recherches() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.fn_capacite_alertes_recherches() TO authenticated;

-- Appelé par le nouveau worker uniquement. Aucun envoi ici ; reprend les lots
-- en erreur dont le délai est échu, sans toucher aux autres types d'emails.
CREATE OR REPLACE FUNCTION public.fn_reprendre_alertes_filtres()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE n integer;
BEGIN
 INSERT INTO private.alertes_filtres_worker(id,derniere_execution_le) VALUES(true,now())
 ON CONFLICT(id) DO UPDATE SET derniere_execution_le=excluded.derniere_execution_le;
 UPDATE public.email_queue q SET statut='EN_ATTENTE'
 FROM private.alertes_filtres_livraisons l
 WHERE q.id=l.email_id AND q.statut='ERREUR' AND l.prochaine_tentative_le<=now();
 GET DIAGNOSTICS n=ROW_COUNT;
 RETURN n;
END $fn$;
REVOKE ALL ON FUNCTION public.fn_reprendre_alertes_filtres() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reprendre_alertes_filtres() TO service_role;

CREATE OR REPLACE FUNCTION public.fn_reporter_echec_alerte_filtre(p_email_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
 UPDATE private.alertes_filtres_livraisons SET tentatives=tentatives+1,
 prochaine_tentative_le=now()+make_interval(hours=>least(24,power(2,least(tentatives,5))::int))
 WHERE email_id=p_email_id;
END $fn$;
REVOKE ALL ON FUNCTION public.fn_reporter_echec_alerte_filtre(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporter_echec_alerte_filtre(uuid) TO service_role;

-- Une préférence désactivée ou modifiée, un destinataire détaché/banni, ou un
-- résultat devenu inaccessible annulent le lot. Aucun élargissement au réessai.
CREATE OR REPLACE FUNCTION public.fn_verifier_livraison_alerte_filtre(p_email_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE l private.alertes_filtres_livraisons; f public.filtres_sauvegardes; q public.email_queue; ids uuid[];
BEGIN
 SELECT * INTO l FROM private.alertes_filtres_livraisons WHERE email_id=p_email_id;
 IF NOT FOUND THEN RETURN false; END IF;
 SELECT * INTO f FROM public.filtres_sauvegardes WHERE id=l.filtre_id;
 SELECT * INTO q FROM public.email_queue WHERE id=p_email_id;
 IF f.id IS NULL OR NOT f.alerte_active OR f.filtres<>l.filtres OR q.destinataire_id<>f.utilisateur_id
 OR NOT private.fn_destinataire_alerte_actif(f.utilisateur_id) THEN RETURN false; END IF;
 IF f.audience='ETAB_RECHERCHE_SOIGNANTS' THEN
  IF private.fn_etablissement_destinataire_alerte(f.utilisateur_id) IS DISTINCT FROM l.etablissement_id THEN RETURN false; END IF;
  SELECT array_agg(r.soignant_id) INTO ids FROM private.fn_resultats_filtre_soignants(f.id,l.fenetre_debut) r
   JOIN public.soignants s ON s.id=r.soignant_id WHERE s.cree_le<=l.fenetre_fin;
  RETURN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(q.data->'soignants') item WHERE NOT coalesce((item->>'id')::uuid=ANY(ids),false));
 ELSE
  SELECT array_agg(r.mission_id) INTO ids FROM private.fn_resultats_filtre_missions(f.id,l.fenetre_debut) r
   JOIN public.missions m ON m.id=r.mission_id WHERE m.cree_le<=l.fenetre_fin;
  RETURN NOT EXISTS(SELECT 1 FROM jsonb_array_elements(q.data->'missions') item WHERE NOT coalesce((item->>'id')::uuid=ANY(ids),false));
 END IF;
END $fn$;
REVOKE ALL ON FUNCTION public.fn_verifier_livraison_alerte_filtre(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fn_verifier_livraison_alerte_filtre(uuid) TO service_role;

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
 ORDER BY f.id FOR UPDATE OF f SKIP LOCKED
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

-- Valider les critères avant activation, y compris via RPC hors interface.
CREATE OR REPLACE FUNCTION public.fn_creer_filtre_sauvegarde(p_nom text, p_audience filtre_audience, p_filtres jsonb, p_alerte_active boolean DEFAULT false, p_frequence_alerte filtre_frequence_alerte DEFAULT 'QUOTIDIENNE'::filtre_frequence_alerte)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  IF length(p_nom) = 0 OR length(p_nom) > 100 THEN
    RETURN jsonb_build_object('error','Nom invalide (1-100 caractères)');
  END IF;

  IF p_audience = 'ETAB_RECHERCHE_SOIGNANTS' THEN
    IF private.fn_etablissement_destinataire_alerte(v_uid) IS NULL THEN
      RETURN jsonb_build_object('error','Votre compte doit être actif et rattaché à un établissement.');
    END IF;
    IF NOT private.fn_filtres_recherche_soignants_valides(COALESCE(p_filtres,'{}'::jsonb)) THEN
      RETURN jsonb_build_object('error','Critères de recherche invalides. Recréez la recherche depuis l’annuaire.');
    END IF;
  END IF;

  IF p_audience='SOIGNANT_RECHERCHE_MISSIONS' AND (NOT private.fn_destinataire_alerte_actif(v_uid) OR NOT private.fn_filtres_recherche_missions_valides(COALESCE(p_filtres,'{}'::jsonb))) THEN
    RETURN jsonb_build_object('error','Compte ou critères de recherche invalides.');
  END IF;
  IF p_audience='ETAB_RECHERCHE_SOIGNANTS' AND p_alerte_active AND NOT public.fn_capacite_alertes_recherches() THEN
    RETURN jsonb_build_object('error','Les alertes ne sont pas encore disponibles. Vous pouvez sauvegarder sans alerte.');
  END IF;

  -- Limite : 20 filtres max par utilisateur
  SELECT count(*) INTO v_count FROM filtres_sauvegardes WHERE utilisateur_id = v_uid;
  IF v_count >= 20 THEN
    RETURN jsonb_build_object('error', 'Limite de 20 recherches sauvegardées atteinte. Supprimez-en une avant d''en créer une nouvelle.');
  END IF;

  INSERT INTO filtres_sauvegardes (utilisateur_id, nom, audience, filtres, alerte_active, frequence_alerte)
  VALUES (v_uid, p_nom, p_audience, COALESCE(p_filtres, '{}'::jsonb), p_alerte_active, p_frequence_alerte)
  RETURNING id INTO v_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_CREE', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := v_id,
    p_details := jsonb_build_object('nom', p_nom, 'audience', p_audience::text, 'alerte_active', p_alerte_active, 'frequence', p_frequence_alerte::text)
  );

  IF p_alerte_active THEN
    PERFORM fn_ecrire_audit_safe(
      p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
      p_action := 'ALERTE_ACTIVEE', p_type_ressource := 'filtre_sauvegarde',
      p_id_ressource := v_id,
      p_details := jsonb_build_object('frequence', p_frequence_alerte::text)
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_id);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Un filtre avec ce nom existe déjà');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_modifier_filtre_sauvegarde(p_id uuid, p_nom text DEFAULT NULL::text, p_alerte_active boolean DEFAULT NULL::boolean, p_frequence_alerte filtre_frequence_alerte DEFAULT NULL::filtre_frequence_alerte)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_old RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;

  SELECT * INTO v_old FROM filtres_sauvegardes WHERE id = p_id AND utilisateur_id = v_uid;
  IF NOT FOUND THEN RETURN jsonb_build_object('error','Filtre introuvable'); END IF;

  IF p_nom IS NOT NULL AND (length(p_nom) = 0 OR length(p_nom) > 100) THEN
    RETURN jsonb_build_object('error','Nom invalide (1-100 caractères)');
  END IF;

  IF v_old.audience = 'ETAB_RECHERCHE_SOIGNANTS' AND p_alerte_active IS TRUE THEN
    IF private.fn_etablissement_destinataire_alerte(v_uid) IS NULL THEN
      RETURN jsonb_build_object('error','Votre compte doit être actif et rattaché à un établissement.');
    END IF;
    IF NOT private.fn_filtres_recherche_soignants_valides(v_old.filtres) THEN
      RETURN jsonb_build_object('error','Critères de recherche invalides. Recréez la recherche depuis l’annuaire.');
    END IF;
  END IF;

  IF p_alerte_active IS TRUE AND v_old.audience='SOIGNANT_RECHERCHE_MISSIONS'
    AND (NOT private.fn_destinataire_alerte_actif(v_uid) OR NOT private.fn_filtres_recherche_missions_valides(v_old.filtres)) THEN
    RETURN jsonb_build_object('error','Compte ou critères de recherche invalides.');
  END IF;
  IF p_alerte_active IS TRUE AND NOT v_old.alerte_active AND v_old.audience='ETAB_RECHERCHE_SOIGNANTS' AND NOT public.fn_capacite_alertes_recherches() THEN
    RETURN jsonb_build_object('error','Les alertes ne sont pas encore disponibles.');
  END IF;

  UPDATE filtres_sauvegardes SET
    nom = COALESCE(p_nom, nom),
    alerte_active = COALESCE(p_alerte_active, alerte_active),
    frequence_alerte = COALESCE(p_frequence_alerte, frequence_alerte)
  WHERE id = p_id;

  PERFORM fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'FILTRE_MODIFIE', p_type_ressource := 'filtre_sauvegarde',
    p_id_ressource := p_id,
    p_details := jsonb_build_object(
      'nom_avant', v_old.nom, 'nom_apres', COALESCE(p_nom, v_old.nom),
      'alerte_active_avant', v_old.alerte_active,
      'alerte_active_apres', COALESCE(p_alerte_active, v_old.alerte_active),
      'frequence_avant', v_old.frequence_alerte::text,
      'frequence_apres', COALESCE(p_frequence_alerte, v_old.frequence_alerte)::text
    )
  );

  -- Audit toggle alerte
  IF p_alerte_active IS NOT NULL AND p_alerte_active <> v_old.alerte_active THEN
    PERFORM fn_ecrire_audit_safe(
      p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
      p_action := CASE WHEN p_alerte_active THEN 'ALERTE_ACTIVEE' ELSE 'ALERTE_DESACTIVEE' END,
      p_type_ressource := 'filtre_sauvegarde', p_id_ressource := p_id,
      p_details := jsonb_build_object('frequence', COALESCE(p_frequence_alerte, v_old.frequence_alerte)::text)
    );
  END IF;

  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Un filtre avec ce nom existe déjà');
END;
$function$;
