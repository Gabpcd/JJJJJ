-- Le compte réel de la fondatrice avait bien son rôle Auth et son registre
-- equipe_admin, mais pas la famille de compte canonique introduite après sa
-- création. Complète cet invariant sans créer d'identité ni toucher au mot de
-- passe.

INSERT INTO public.types_comptes_auth (
  user_id,
  type_compte,
  finalise_le,
  claim_token,
  claim_expire_le
)
SELECT
  u.id,
  'ADMIN',
  now(),
  NULL,
  NULL
FROM auth.users u
WHERE lower(COALESCE(u.email, '')) = 'gabrielle.pcd@outlook.com'
  AND u.deleted_at IS NULL
  AND u.raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME'
ON CONFLICT (user_id) DO UPDATE
SET type_compte = 'ADMIN',
    finalise_le = COALESCE(types_comptes_auth.finalise_le, EXCLUDED.finalise_le),
    claim_token = NULL,
    claim_expire_le = NULL;
