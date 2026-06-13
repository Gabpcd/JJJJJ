-- Refonte BFA : modèle "contrat signé + taux par bénéficiaire" (groupes ET
-- étabs isolés), au lieu des paliers par nombre de missions. Le BFA = taux ×
-- commissions Jolene HT encaissées sur les missions terminées de l'année.
-- Les paliers_bfa (mission-tiers) ne sont plus utilisés dans le calcul.

ALTER TABLE etablissements ADD COLUMN IF NOT EXISTS bfa_eligible boolean NOT NULL DEFAULT false;
ALTER TABLE etablissements ADD COLUMN IF NOT EXISTS bfa_taux numeric;
ALTER TABLE etablissements ADD COLUMN IF NOT EXISTS bfa_contrat_signe_le date;
ALTER TABLE groupes_sante ADD COLUMN IF NOT EXISTS bfa_taux numeric;

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_lister(p_annee integer DEFAULT (EXTRACT(year FROM now()))::integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_res jsonb;
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  WITH groupes AS (
    SELECT g.id, g.nom, COALESCE(g.bfa_taux,0) AS taux, g.bfa_contrat_signe_le,
           (SELECT count(*) FROM etablissements e WHERE e.groupe_sante_id = g.id) AS nb_etabs,
           COALESCE((SELECT count(*) FROM missions m JOIN etablissements e ON e.id=m.etablissement_id
                     WHERE e.groupe_sante_id=g.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS nb_missions,
           COALESCE((SELECT sum(m.montant_commission_ht) FROM missions m JOIN etablissements e ON e.id=m.etablissement_id
                     WHERE e.groupe_sante_id=g.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS commissions
    FROM groupes_sante g WHERE g.bfa_eligible = true
  ),
  etabs AS (
    SELECT e.id, e.nom, COALESCE(e.bfa_taux,0) AS taux, e.bfa_contrat_signe_le, 1 AS nb_etabs,
           COALESCE((SELECT count(*) FROM missions m WHERE m.etablissement_id=e.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS nb_missions,
           COALESCE((SELECT sum(m.montant_commission_ht) FROM missions m WHERE m.etablissement_id=e.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS commissions
    FROM etablissements e WHERE e.bfa_eligible = true AND e.groupe_sante_id IS NULL
  )
  SELECT jsonb_build_object(
    'annee', p_annee,
    'groupes', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type','GROUPE','id',id,'nom',nom,'taux',taux,'contrat_signe_le',bfa_contrat_signe_le,
        'nb_etabs',nb_etabs,'nb_missions',nb_missions,'commissions',round(commissions,2),
        'montant_bfa',round(commissions*taux/100,2),
        'verse',(SELECT bfa_verse FROM bfa_suivi s WHERE s.groupe_id=groupes.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1),
        'suivi_id',(SELECT id FROM bfa_suivi s WHERE s.groupe_id=groupes.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1)
      ) ORDER BY nom) FROM groupes), '[]'::jsonb),
    'etablissements', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type','ETABLISSEMENT','id',id,'nom',nom,'taux',taux,'contrat_signe_le',bfa_contrat_signe_le,
        'nb_missions',nb_missions,'commissions',round(commissions,2),
        'montant_bfa',round(commissions*taux/100,2),
        'verse',(SELECT bfa_verse FROM bfa_suivi s WHERE s.etablissement_id=etabs.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1),
        'suivi_id',(SELECT id FROM bfa_suivi s WHERE s.etablissement_id=etabs.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1)
      ) ORDER BY nom) FROM etabs), '[]'::jsonb)
  ) INTO v_res;
  RETURN v_res;
END; $function$;

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_definir_beneficiaire(
  p_type text, p_id uuid, p_eligible boolean, p_taux numeric DEFAULT NULL, p_contrat_signe_le date DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  IF p_eligible AND (p_taux IS NULL OR p_taux <= 0 OR p_taux > 100) THEN
    RETURN jsonb_build_object('success',false,'error','Taux BFA invalide (0 < taux ≤ 100)');
  END IF;
  IF p_type = 'GROUPE' THEN
    UPDATE groupes_sante SET bfa_eligible=p_eligible, bfa_taux=CASE WHEN p_eligible THEN p_taux ELSE bfa_taux END,
      bfa_contrat_signe_le=COALESCE(p_contrat_signe_le,bfa_contrat_signe_le) WHERE id=p_id;
  ELSIF p_type = 'ETABLISSEMENT' THEN
    UPDATE etablissements SET bfa_eligible=p_eligible, bfa_taux=CASE WHEN p_eligible THEN p_taux ELSE bfa_taux END,
      bfa_contrat_signe_le=COALESCE(p_contrat_signe_le,bfa_contrat_signe_le) WHERE id=p_id;
  ELSE
    RETURN jsonb_build_object('success',false,'error','Type invalide (GROUPE|ETABLISSEMENT)');
  END IF;
  RETURN jsonb_build_object('success',true);
END; $function$;

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_detail_groupe(p_groupe_id uuid, p_annee integer DEFAULT (EXTRACT(year FROM now()))::integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_res jsonb;
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'etablissement_id', e.id, 'nom', e.nom, 'ville', e.ville,
      'nb_missions', COALESCE(x.nb,0), 'ca_ht', round(COALESCE(x.ca,0),2),
      'commissions_ht', round(COALESCE(x.com,0),2)
    ) ORDER BY e.nom), '[]'::jsonb) INTO v_res
  FROM etablissements e
  LEFT JOIN LATERAL (
    SELECT count(*) AS nb, sum(m.total_brut) AS ca, sum(m.montant_commission_ht) AS com
    FROM missions m WHERE m.etablissement_id=e.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee
  ) x ON true
  WHERE e.groupe_sante_id = p_groupe_id;
  RETURN jsonb_build_object('groupe_id',p_groupe_id,'annee',p_annee,'etablissements',v_res);
END; $function$;

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_calculer(p_annee integer DEFAULT (EXTRACT(year FROM now()))::integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE r RECORD; v_com numeric; v_nb int; v_count int := 0;
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  FOR r IN SELECT id, COALESCE(bfa_taux,0) AS taux FROM groupes_sante WHERE bfa_eligible LOOP
    SELECT count(*), COALESCE(sum(m.montant_commission_ht),0) INTO v_nb, v_com
    FROM missions m JOIN etablissements e ON e.id=m.etablissement_id
    WHERE e.groupe_sante_id=r.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee;
    DELETE FROM bfa_suivi WHERE groupe_id=r.id AND annee=p_annee AND COALESCE(bfa_verse,false)=false;
    INSERT INTO bfa_suivi (groupe_id, annee, missions_cumulees, commissions_cumulees, taux_bfa, montant_bfa, bfa_verse, calcule_le)
    VALUES (r.id, p_annee, v_nb, v_com, r.taux, round(v_com*r.taux/100,2), false, now());
    v_count := v_count + 1;
  END LOOP;
  FOR r IN SELECT id, COALESCE(bfa_taux,0) AS taux FROM etablissements WHERE bfa_eligible AND groupe_sante_id IS NULL LOOP
    SELECT count(*), COALESCE(sum(m.montant_commission_ht),0) INTO v_nb, v_com
    FROM missions m WHERE m.etablissement_id=r.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee;
    DELETE FROM bfa_suivi WHERE etablissement_id=r.id AND annee=p_annee AND COALESCE(bfa_verse,false)=false;
    INSERT INTO bfa_suivi (etablissement_id, annee, missions_cumulees, commissions_cumulees, taux_bfa, montant_bfa, bfa_verse, calcule_le)
    VALUES (r.id, p_annee, v_nb, v_com, r.taux, round(v_com*r.taux/100,2), false, now());
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('success',true,'annee',p_annee,'beneficiaires_calcules',v_count);
END; $function$;

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_marquer_verse(p_suivi_id uuid, p_date date DEFAULT current_date)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  UPDATE bfa_suivi SET bfa_verse=true, date_versement=p_date WHERE id=p_suivi_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','Suivi BFA introuvable'); END IF;
  RETURN jsonb_build_object('success',true);
END; $function$;

GRANT EXECUTE ON FUNCTION public.fn_admin_bfa_lister(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_bfa_definir_beneficiaire(text,uuid,boolean,numeric,date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_bfa_detail_groupe(uuid,integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_bfa_calculer(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_bfa_marquer_verse(uuid,date) TO authenticated, service_role;
