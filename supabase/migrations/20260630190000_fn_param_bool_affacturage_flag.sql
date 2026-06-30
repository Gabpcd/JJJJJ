-- Feature flag « affacturage_actif » (paiement rapide Defacto) — OFF par défaut,
-- flippable À CHAUD sans redeploy (incident → coupure immédiate).
--
-- L'affacturage n'est pas en production (Defacto pas branché) : l'onglet « Avances »
-- de Revenus, le toggle « Paiement rapide J+2 (Defacto) » du profil et la « cession
-- de créance » promettent un service indisponible. On les masque derrière ce flag.
--
-- fn_param_bool : miroir booléen de fn_param_num (parametres_systeme.valeur est
-- numérique → 0 = false, ≠ 0 = true). GRANT à authenticated car lu côté front
-- (contrairement à fn_param_num qui n'est appelé que server-side).

CREATE OR REPLACE FUNCTION public.fn_param_bool(p_cle text, p_defaut boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT valeur <> 0 FROM public.parametres_systeme WHERE cle = p_cle), p_defaut);
$function$;

GRANT EXECUTE ON FUNCTION public.fn_param_bool(text, boolean) TO authenticated, service_role;

INSERT INTO public.parametres_systeme (cle, valeur, label, description, categorie, cablee)
VALUES (
  'affacturage_actif', 0, 'Affacturage actif (Defacto)',
  'Active le paiement rapide / affacturage Defacto côté soignant (onglet Avances de Revenus, cession de créance, opt-in J+2). OFF tant que Defacto n''est pas branché — passer valeur à 1 pour activer, 0 pour couper.',
  'FINANCE', true
)
ON CONFLICT (cle) DO NOTHING;
