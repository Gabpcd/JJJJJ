-- AUDIT INFRA J2.3.B.AUDIT — Fix doublon BIENVENUE/SERIE_J0
--
-- Cause : SERIE_SOIGNANT_J0 et BIENVENUE_SOIGNANT (resp ETAB) faisaient
-- doublon métier — chacune envoyait "Bienvenue sur Jolene". Couplé au double
-- envoi de BIENVENUE par AuthContext.tsx + register-* fns, un nouvel inscrit
-- recevait jusqu'à 3 emails de bienvenue (BIENVENUE x2 + SERIE_J0).
--
-- Fix : la série démarre désormais à J+1. BIENVENUE reste l'email immédiat
-- envoyé par register-soignant/register-etablissement. Le côté frontend
-- (AuthContext.tsx) n'envoie plus de BIENVENUE en parallèle (corrigé dans
-- le même commit).
--
-- Migration also marks all existing J0 PLANIFIE rows as SKIPPED with reason
-- BIENVENUE_DEJA_ENVOYE for cleanliness.

CREATE OR REPLACE FUNCTION public.fn_planifier_serie_onboarding(
  p_utilisateur_id uuid,
  p_serie public.serie_onboarding_type
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  -- J0 retiré : BIENVENUE_SOIGNANT/BIENVENUE_ETABLISSEMENT envoyé immédiatement
  -- par register-soignant/register-etablissement remplit ce rôle. La série
  -- de relances commence à J+1.
  INSERT INTO serie_email_envois (utilisateur_id, serie, etape, planifie_le, statut)
  VALUES
    (p_utilisateur_id, p_serie, 'J1', now() + INTERVAL '1 day', 'PLANIFIE'),
    (p_utilisateur_id, p_serie, 'J3', now() + INTERVAL '3 days', 'PLANIFIE'),
    (p_utilisateur_id, p_serie, 'J7', now() + INTERVAL '7 days', 'PLANIFIE')
  ON CONFLICT (utilisateur_id, serie, etape) DO NOTHING;
  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.fn_planifier_serie_onboarding(uuid, public.serie_onboarding_type) TO service_role;

UPDATE serie_email_envois SET statut='SKIPPED', skip_raison='BIENVENUE_DEJA_ENVOYE'
WHERE etape='J0' AND statut='PLANIFIE';
