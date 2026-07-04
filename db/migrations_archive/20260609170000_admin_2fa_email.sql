-- 2FA admin par email (alternative gratuite au SMS) — table des codes à usage unique.
--
-- L'edge function admin-2fa (service_role) génère un code à 6 chiffres, en stocke le
-- hash + une expiration courte, l'envoie par email (Resend), puis le vérifie. La
-- table n'est jamais lue côté client (RLS active, aucune policy).

CREATE TABLE IF NOT EXISTS public.admin_2fa_codes (
  admin_id uuid PRIMARY KEY,
  code_hash text,
  expire_le timestamptz,
  tentatives int NOT NULL DEFAULT 0,
  verifie_le timestamptz,
  cree_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_2fa_codes ENABLE ROW LEVEL SECURITY;
-- Aucune policy : accès réservé au service_role (edge function admin-2fa).
