-- 7f-2 — fn_obtenir_mes_parrainages v2 : expose la progression GMV du filleul
-- (« plus que X € de missions avant vos primes ») + montants paramétrés
-- (prime 25 €, seuil 500 € — plus de 100/50 en dur).
CREATE OR REPLACE FUNCTION public.fn_obtenir_mes_parrainages()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_filleuls JSONB; v_parrain_info JSONB; v_total_gains NUMERIC; v_nb_primes_versees INT;
  v_prime integer := (public.fn_param_num('prime_parrainage_eur', 25))::integer;
  v_seuil_gmv numeric := public.fn_param_num('seuil_gmv_parrainage_eur', 500);
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('error','Non authentifié'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',p.id,'filleul_id',p.filleul_id,'prenom',s.prenom,'statut',p.statut,'cree_le',p.cree_le,
    'filleul_active_le',p.filleul_active_le,
    'commission_cumulee_filleul',COALESCE(p.commission_cumulee_filleul,0),
    'gmv_cumule_filleul',COALESCE(p.gmv_cumule_filleul,0),
    'reste_gmv_avant_prime',GREATEST(0, v_seuil_gmv - COALESCE(p.gmv_cumule_filleul,0)),
    'seuil_gmv',v_seuil_gmv,
    'seuil_atteint',(COALESCE(p.gmv_cumule_filleul,0) >= v_seuil_gmv
                     AND COALESCE(p.commission_cumulee_filleul,0) >= 4 * v_prime),
    'prime_versee_le',p.prime_versee_le,'premiere_mission_le',s.premiere_mission_le,
    'bonus_heures',COALESCE(p.bonus_heures_parrain,0)
  ) ORDER BY p.cree_le DESC), '[]'::jsonb)
  INTO v_filleuls
  FROM parrainages p JOIN soignants s ON s.id = p.filleul_id WHERE p.parrain_id = v_uid;
  SELECT COUNT(*), COALESCE(SUM(v_prime),0) INTO v_nb_primes_versees, v_total_gains
    FROM parrainages WHERE parrain_id = v_uid AND statut = 'PRIME_VERSEE';
  SELECT jsonb_build_object('parrain_prenom',sp.prenom,'statut',p.statut,'prime_versee_le',p.prime_versee_le)
    INTO v_parrain_info FROM parrainages p JOIN soignants sp ON sp.id = p.parrain_id WHERE p.filleul_id = v_uid LIMIT 1;
  RETURN jsonb_build_object('filleuls',v_filleuls,'total_gains_eur',v_total_gains,
    'nb_primes_versees',v_nb_primes_versees,'prime_eur',v_prime,'seuil_gmv_eur',v_seuil_gmv,
    'mon_parrain',COALESCE(v_parrain_info,'null'::jsonb));
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_obtenir_mes_parrainages() TO authenticated;
