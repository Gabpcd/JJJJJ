-- Sales / Sourcing — nouveaux canaux Instagram / TikTok / Snapchat + seed des
-- comptes réels de recrutement santé (agences d'intérim + communautés soignantes).
-- Snapchat : aucun compte pro de sourcing soignant FR (recherche infructueuse) —
-- la plateforme est ajoutée au cas où, mais non seedée.

ALTER TABLE public.sales_groupes DROP CONSTRAINT IF EXISTS sales_groupes_plateforme_check;
ALTER TABLE public.sales_groupes ADD CONSTRAINT sales_groupes_plateforme_check
  CHECK (plateforme IN ('WHATSAPP','FACEBOOK','LINKEDIN','TELEGRAM','JOBBOARD','AUTRE','INSTAGRAM','TIKTOK','SNAPCHAT'));

INSERT INTO public.sales_groupes (nom, plateforme, profession, region, url, audience, statut, notes)
SELECT v.nom, v.plateforme, v.profession, v.region, v.url, v.audience, v.statut, v.notes
FROM (VALUES
  -- Instagram — agences / plateformes
  ('Hublo', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/hublo_fr', 'MIXTE', 'ACTIF', 'Plateforme remplacements/recrutement santé.'),
  ('Mediflash', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/mediflash.fr', 'SOIGNANTS', 'ACTIF', 'Renfort soignant indépendant.'),
  ('Adecco Medical', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/adeccomedicalfr', 'MIXTE', 'ACTIF', 'Intérim/vacation/CDI santé.'),
  ('Appel Médical', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/appelmedical', 'SOIGNANTS', 'ACTIF', 'N°1 intérim médical/paramédical FR.'),
  ('Appel Médical Région Ouest', 'INSTAGRAM', 'TOUTES', 'Pays de la Loire', 'https://instagram.com/appelmedical_regionouest', 'MIXTE', 'ACTIF', 'Antenne Ouest.'),
  ('Appel Médical IDF', 'INSTAGRAM', 'TOUTES', 'Île-de-France', 'https://instagram.com/appelmedical_idf', 'MIXTE', 'ACTIF', 'Antenne Île-de-France.'),
  ('Appel Médical Europe', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/appel_medical_europe', 'MIXTE', 'ACTIF', 'Branche Europe/expatriation.'),
  ('Staffmatch', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/staffmatch', 'SOIGNANTS', 'ACTIF', 'Agence intérim digitale (santé incluse).'),
  ('StaffSanté & StaffSocial', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/staffsante.staffsocial', 'MIXTE', 'ACTIF', '1er site emploi santé FR.'),
  ('Emploi soignant', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/emploisoignant', 'MIXTE', 'ACTIF', 'Job board santé multi-professions.'),
  ('Medelse', 'INSTAGRAM', 'TOUTES', 'National', 'https://instagram.com/medelse_fr', 'SOIGNANTS', 'ACTIF', 'Plateforme renfort soignant.'),
  ('Vitalis Médical Angers', 'INSTAGRAM', 'TOUTES', 'Pays de la Loire', 'https://instagram.com/vitalismedicalangers', 'MIXTE', 'ACTIF', 'Agence intérim paramédical/médical/social.'),
  ('Vitalis Médical Aix', 'INSTAGRAM', 'TOUTES', 'PACA', 'https://instagram.com/vitalismedical_aix', 'MIXTE', 'ACTIF', 'Agence intérim (réseau 45+ agences).'),
  ('Les Infirmières (MACSF)', 'INSTAGRAM', 'IDE', 'National', 'https://instagram.com/les_infirmieres_macsf', 'SOIGNANTS', 'ACTIF', 'Plus gros compte communauté infirmière FR (~89K).'),
  ('C''est l''infirmière !', 'INSTAGRAM', 'IDE', 'National', 'https://instagram.com/cestlinfirmiere', 'SOIGNANTS', 'ACTIF', 'Communauté infirmière (~32K).'),
  ('Entre infirmières libérales', 'INSTAGRAM', 'IDE', 'National', 'https://instagram.com/entre_infirmieres_liberales', 'SOIGNANTS', 'ACTIF', 'Communauté IDEL.'),
  -- TikTok
  ('Mediflash', 'TIKTOK', 'TOUTES', 'National', 'https://www.tiktok.com/@mediflash.fr', 'SOIGNANTS', 'ACTIF', 'Compte TikTok de la plateforme de renfort soignant.'),
  ('Axelle Infirmière', 'TIKTOK', 'IDE', 'National', 'https://www.tiktok.com/@axelleinfirmiere', 'SOIGNANTS', 'ACTIF', 'Créatrice infirmière (~50K), forte communauté IDE/ESI.'),
  ('Juliette (infirmière réa)', 'TIKTOK', 'IDE', 'Occitanie', 'https://www.tiktok.com/@juliettedtrx', 'SOIGNANTS', 'ACTIF', 'Infirmière réa Toulouse (~112K), grande communauté.')
) AS v(nom, plateforme, profession, region, url, audience, statut, notes)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sales_groupes sg
  WHERE rtrim(coalesce(sg.url, ''), '/') = rtrim(v.url, '/')
);
