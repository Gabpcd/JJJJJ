-- Sales / Sourcing — 3e vague ciblée infirmières / aides-soignantes / pharmaciens
-- (départements restants + Corse/DOM + salariées-hôpital + groupes emploi régionaux
-- portant les offres EHPAD/AS + officine régional). Dédup par URL normalisée.
-- WhatsApp : 0 lien public sur 11 recherches au total (structurel).

INSERT INTO public.sales_groupes (nom, plateforme, profession, region, url, audience, statut, notes)
SELECT v.nom, v.plateforme, v.profession, v.region, v.url, v.audience, v.statut, v.notes
FROM (VALUES
  -- ── INFIRMIÈRES (Pau, Corse, DOM, salariées/hôpital) ──
  ('Infirmiers libéraux Pau et alentours (64)', 'FACEBOOK', 'IDE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/184324308803480/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('JOB 64 - Emploi Pyrénées-Atlantiques', 'FACEBOOK', 'IDE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/222487604947754/', 'MIXTE', 'A_VERIFIER', 'Emploi généraliste 64 (postes soignants).'),
  ('Infirmier/e en Corse', 'FACEBOOK', 'IDE', 'Corse', 'https://www.facebook.com/groups/98519131051/', 'SOIGNANTS', 'A_VERIFIER', 'Libéral + salarié.'),
  ('Infirmiers libéraux de Guadeloupe (Onsil)', 'FACEBOOK', 'IDE', 'Guadeloupe (DOM)', 'https://www.facebook.com/groups/734527442073705/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('IDEL 972 - Martinique - Fort-de-France', 'FACEBOOK', 'IDE', 'Martinique (DOM)', 'https://www.facebook.com/groups/1201684013916576/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Remplacement médecine générale Antilles-Guyane', 'FACEBOOK', 'MEDECIN', 'Antilles-Guyane (DOM)', 'https://www.facebook.com/groups/1059174337589422/', 'MIXTE', 'A_VERIFIER', 'Surtout médecins.'),
  ('Offres emploi PMS, IDE, TMS, SF, AS, médecin (salarié)', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/578192460470015/', 'MIXTE', 'A_VERIFIER', 'Emploi paramédical salarié.'),
  -- ── AIDES-SOIGNANTES (santé + emploi régional EHPAD/AS) ──
  ('Recrutement Infirmier(e)s & Aide-Soignant(e)s', 'FACEBOOK', 'AS', 'National', 'https://www.facebook.com/groups/1648146865494570/', 'MIXTE', 'A_VERIFIER', 'Offres établissements IDE+AS.'),
  ('Aide-Soignant, Infirmière etc. intérimaires', 'FACEBOOK', 'AS', 'National', 'https://www.facebook.com/groups/527663747425407/', 'SOIGNANTS', 'A_VERIFIER', 'Intérim AS/IDE.'),
  ('Infirmiers et Aides-soignants de Nouvelle-Aquitaine', 'FACEBOOK', 'AS', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/393336634356655/', 'MIXTE', 'A_VERIFIER', 'Régional AS+IDE.'),
  ('Parlons des Agents de Service Hospitalier (ASH)', 'FACEBOOK', 'AES', 'National', 'https://www.facebook.com/groups/331346603641383/', 'SOIGNANTS', 'A_VERIFIER', 'Communauté ASH, partages d''offres.'),
  ('Emploi aide à domicile Pays de la Loire (44/49/72/85/53)', 'FACEBOOK', 'AS', 'Pays de la Loire', 'https://www.facebook.com/groups/4580054265406142/', 'MIXTE', 'A_VERIFIER', 'Médico-social, profils AS.'),
  ('Offres d''emploi (59) Nord', 'FACEBOOK', 'AS', 'Hauts-de-France', 'https://www.facebook.com/groups/offres.d.emploi.nord/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional — offres EHPAD/AS fréquentes.'),
  ('Offres d''emploi (54) Meurthe-et-Moselle', 'FACEBOOK', 'AS', 'Grand Est', 'https://www.facebook.com/groups/offres.d.emploi.meurthe.et.moselle/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional — offres EHPAD/AS.'),
  ('Offres d''emploi (57) Moselle', 'FACEBOOK', 'AS', 'Grand Est', 'https://www.facebook.com/groups/offres.d.emploi.moselle/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional — offres EHPAD/AS.'),
  ('Job Emploi - Lorraine', 'FACEBOOK', 'AS', 'Grand Est', 'https://www.facebook.com/groups/jobemploilorraine/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional — offres médico-social.'),
  ('Emploi Auvergne-Rhône-Alpes', 'FACEBOOK', 'AS', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/emploi.recrutement.auvergne.rhone.alpes/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional — offres santé/EHPAD.'),
  ('Urgence Emploi Lyon et alentours', 'FACEBOOK', 'AS', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/1247977478595918/', 'MIXTE', 'A_VERIFIER', 'Généraliste — offres AS/ASH.'),
  ('Emploi 69 Rhône', 'FACEBOOK', 'AS', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/390913820970881/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional.'),
  ('Recherche emploi Lyon (CDD/CDI/stage/alternance)', 'FACEBOOK', 'AS', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/emploi.stage.cdd.cdi.alternance.lyon/', 'MIXTE', 'A_VERIFIER', 'Généraliste — offres santé.'),
  ('Offres d''emploi - Paris IDF', 'FACEBOOK', 'AS', 'Île-de-France', 'https://www.facebook.com/groups/401123027674669/', 'MIXTE', 'A_VERIFIER', 'Généraliste — offres AS/ASH.'),
  ('Emploi à Paris et en Île-de-France', 'FACEBOOK', 'AS', 'Île-de-France', 'https://www.facebook.com/groups/JobsParisFRANCE/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional.'),
  ('Emploi Bordeaux / Gironde', 'FACEBOOK', 'AS', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/1511917715722769/', 'MIXTE', 'A_VERIFIER', 'Généraliste local.'),
  ('Jobs et Emplois Bourgogne-Franche-Comté', 'FACEBOOK', 'AS', 'Bourgogne-Franche-Comté', 'https://www.facebook.com/groups/jobsbfc/', 'MIXTE', 'A_VERIFIER', 'Généraliste régional.'),
  ('Offres d''EMPLOI et STAGE en BRETAGNE', 'FACEBOOK', 'AS', 'Bretagne', 'https://www.facebook.com/groups/339462753212612/', 'MIXTE', 'A_VERIFIER', 'Généraliste — offres AS/ASH.'),
  ('Offre d''emploi & recherche d''emploi (santé)', 'FACEBOOK', 'AS', 'National', 'https://www.facebook.com/groups/776268819206742/', 'MIXTE', 'A_VERIFIER', 'Généraliste — offres santé/ASH.'),
  -- ── PHARMACIENS / PRÉPARATEURS ──
  ('PHARMA JOB CDD/CDI/INTÉRIM', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/groups/861463257667078/', 'MIXTE', 'A_VERIFIER', 'Pharmaciens + préparateurs.'),
  ('PHARM''UB - réseau emploi pharmacie', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/groups/635803555243071/', 'MIXTE', 'A_VERIFIER', 'Tous profils officine.'),
  ('EMPLOI PHARMACIEN', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/groups/157531854591770/', 'MIXTE', 'A_VERIFIER', NULL),
  ('PharmaNancy', 'FACEBOOK', 'PHARMACIEN', 'Grand Est', 'https://www.facebook.com/groups/PharmaNancy/', 'MIXTE', 'A_VERIFIER', 'Local Nancy — à vérifier.'),
  ('URPS Pharmaciens Auvergne-Rhône-Alpes', 'FACEBOOK', 'PHARMACIEN', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/2085525828406779/', 'MIXTE', 'A_VERIFIER', 'Pro/info, emploi possible.')
) AS v(nom, plateforme, profession, region, url, audience, statut, notes)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sales_groupes sg
  WHERE rtrim(coalesce(sg.url, ''), '/') = rtrim(v.url, '/')
);
