-- Fix Gabrielle Picard test account: set rpps_verifie = true and update mission count
UPDATE soignants
SET rpps_verifie = true,
    total_missions_terminees = (
      SELECT count(*) FROM missions
      WHERE soignant_assigne_id = soignants.id AND statut = 'TERMINEE'
    )
WHERE id = '1b3bfd46-b4d5-4805-9c44-afd6dcf38b67';

-- Also fix the duplicate if it's also a real test account
UPDATE soignants
SET rpps_verifie = true,
    total_missions_terminees = (
      SELECT count(*) FROM missions
      WHERE soignant_assigne_id = soignants.id AND statut = 'TERMINEE'
    )
WHERE id = 'afac77e8-7572-4ca3-a237-df265d2a3366';