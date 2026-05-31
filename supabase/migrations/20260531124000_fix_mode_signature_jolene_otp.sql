-- BUG : fn_signer_contrat_otp pose mode_signature='JOLENE_OTP', mais
-- contrats_mission_mode_signature_check n'autorisait que ('CANVAS','YOUSIGN')
-- → la signature par OTP échouait (23514). Jamais exercé (0 signature OTP).
-- On ajoute 'JOLENE_OTP' aux valeurs autorisées.
ALTER TABLE public.contrats_mission DROP CONSTRAINT contrats_mission_mode_signature_check;
ALTER TABLE public.contrats_mission ADD CONSTRAINT contrats_mission_mode_signature_check
  CHECK (mode_signature = ANY (ARRAY['CANVAS'::text, 'YOUSIGN'::text, 'JOLENE_OTP'::text]));
