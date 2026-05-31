-- BUG (bloqueurs) : 6 fonctions appellent des fonctions pgcrypto (digest/crypt/
-- gen_salt) — situées dans le schéma `extensions` — avec search_path=public →
-- échec 42883 « function ... does not exist » dès qu'on atteint l'appel crypto.
-- Concerne : signature OTP (envoi + vérif), suppression de compte RGPD,
-- vérification de clé API, génération + validation des codes de secours pointage.
-- Fix : ajouter `extensions` au search_path (public prioritaire pour les tables).
ALTER FUNCTION public.fn_envoyer_otp_signature(p_contrat_id uuid) SET search_path = public, extensions;
ALTER FUNCTION public.fn_generer_code_secours_mission(p_mission_id uuid, p_type text) SET search_path = public, extensions;
ALTER FUNCTION public.fn_signer_contrat_otp(p_contrat_id uuid, p_otp_code text, p_hash_document text, p_signature_image text) SET search_path = public, extensions;
ALTER FUNCTION public.fn_supprimer_mon_compte() SET search_path = public, extensions;
ALTER FUNCTION public.fn_valider_code_secours(p_mission_id uuid, p_code text, p_lat numeric, p_lng numeric, p_precision numeric, p_terminal_id text) SET search_path = public, extensions;
ALTER FUNCTION public.fn_verifier_api_key(p_cle_api text, p_cle_secret text) SET search_path = public, extensions;
-- + fn_charger_demo_investisseur (uuid_generate_v4 de uuid-ossp dans extensions)
ALTER FUNCTION public.fn_charger_demo_investisseur() SET search_path = public, extensions;
