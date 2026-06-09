-- Destination du code 2FA admin : une BOÎTE EMAIL RÉELLE, distincte de l'email de
-- connexion. L'email de connexion admin@jolene.app n'est pas une vraie boîte ; le
-- code de vérification doit donc partir vers une adresse réellement relevée.
--
-- Table de paramétrage par admin (future-proof pour des comptes admin nominatifs).
-- L'edge function admin-2fa (service_role) lit cette table pour choisir le
-- destinataire ; à défaut, elle retombe sur l'email de connexion.

CREATE TABLE IF NOT EXISTS public.admin_securite (
  admin_id uuid PRIMARY KEY,
  email_2fa text NOT NULL,
  maj_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_securite ENABLE ROW LEVEL SECURITY;
-- Aucune policy : accès réservé au service_role (edge function admin-2fa).

COMMENT ON TABLE public.admin_securite IS
  'Email de destination du code 2FA admin (boîte réelle), distinct de l''email de connexion.';

-- Seed : compte admin principal -> email personnel réel de la fondatrice.
INSERT INTO public.admin_securite (admin_id, email_2fa)
VALUES ('09e82688-e524-42bb-9268-1384c757f33d', 'gabrielle.pcd@outlook.com')
ON CONFLICT (admin_id) DO UPDATE
  SET email_2fa = EXCLUDED.email_2fa, maj_le = now();
