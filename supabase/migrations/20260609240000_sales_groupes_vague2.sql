-- Sales / Sourcing — 2e vague de groupes Facebook (régionaux manquants + métiers
-- supplémentaires : ostéo, pédicure-podologue, assistantes dentaires régionales,
-- crèches, médecins par région). Tous A_VERIFIER. Dédup par URL normalisée.
-- WhatsApp/Telegram : 0 lien public trouvé sur 8 recherches au total (structurel).

INSERT INTO public.sales_groupes (nom, plateforme, profession, region, url, audience, statut, notes)
SELECT v.nom, v.plateforme, v.profession, v.region, v.url, v.audience, v.statut, v.notes
FROM (VALUES
  -- ── INFIRMIERS (départements manquants) ──
  ('Remplacements IDEL 68 (Haut-Rhin)', 'FACEBOOK', 'IDE', 'Grand Est', 'https://www.facebook.com/groups/216608042461622/', 'SOIGNANTS', 'A_VERIFIER', 'Départemental Haut-Rhin/Alsace.'),
  ('Remplacement IDEL Nord-Isère (38)', 'FACEBOOK', 'IDE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/2541115656170305/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Remplacements Infirmier(e) Libéral(e) Région PACA', 'FACEBOOK', 'IDE', 'PACA', 'https://www.facebook.com/groups/378340982666242/', 'SOIGNANTS', 'A_VERIFIER', 'Couvre 04/05/13.'),
  ('Remplacement IDEL Loire-Atlantique (44)', 'FACEBOOK', 'IDE', 'Pays de la Loire', 'https://www.facebook.com/groups/386156084181921/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  -- ── MÉDECINS (régions manquantes) ──
  ('Médecins remplaçants de France (MRF)', 'FACEBOOK', 'MEDECIN', 'National', 'https://www.facebook.com/groups/assomrf/', 'MIXTE', 'A_VERIFIER', 'Grand groupe national association MRF.'),
  ('Rempla Médecine Générale Alsace', 'FACEBOOK', 'MEDECIN', 'Grand Est', 'https://www.facebook.com/groups/285645638709205/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement Médecine Générale Lyon / Rhône', 'FACEBOOK', 'MEDECIN', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/359118897547575/', 'MIXTE', 'A_VERIFIER', NULL),
  ('JMG - Rempla Marseille & 13', 'FACEBOOK', 'MEDECIN', 'PACA', 'https://www.facebook.com/groups/jmgremplamarseille/', 'MIXTE', 'A_VERIFIER', 'Couvre Var/06.'),
  ('Remplacement Médecine Générale Haute-Normandie (76)', 'FACEBOOK', 'MEDECIN', 'Normandie', 'https://www.facebook.com/groups/1612409019304671/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacements Médecine Générale Manche (50)', 'FACEBOOK', 'MEDECIN', 'Normandie', 'https://www.facebook.com/groups/280459322475984/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacements Médecine Générale Calvados (14)', 'FACEBOOK', 'MEDECIN', 'Normandie', 'https://www.facebook.com/groups/413478242416445/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacements Médecine Générale Ille-et-Vilaine (35)', 'FACEBOOK', 'MEDECIN', 'Bretagne', 'https://www.facebook.com/groups/416519935363813/', 'MIXTE', 'A_VERIFIER', 'Bassin Rennes.'),
  -- ── KINÉ (régions manquantes) ──
  ('Les Annonces des Kinés - Picardie / Hauts-de-France', 'FACEBOOK', 'KINE', 'Hauts-de-France', 'https://www.facebook.com/groups/1590919054492185/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Le réseau des kinés de Basse-Normandie', 'FACEBOOK', 'KINE', 'Normandie', 'https://www.facebook.com/groups/1247461118605183/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Kinés de Nouvelle-Aquitaine', 'FACEBOOK', 'KINE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/kinesnouvelleaquitaine/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Le réseau des Kinés Bordelais', 'FACEBOOK', 'KINE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/1697699100450341/', 'SOIGNANTS', 'A_VERIFIER', 'Bordeaux/Gironde.'),
  ('KFC - Kinés de Franche-Comté', 'FACEBOOK', 'KINE', 'Bourgogne-Franche-Comté', 'https://www.facebook.com/groups/129599061070859/', 'SOIGNANTS', 'A_VERIFIER', 'Besançon.'),
  ('Offres de remplacement Kiné à Grenoble', 'FACEBOOK', 'KINE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/1107598392637547/', 'SOIGNANTS', 'A_VERIFIER', 'Grenoble/Isère.'),
  ('Kiné Rhône-Alpes', 'FACEBOOK', 'KINE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/150146067059288/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Le réseau des Kinés (national)', 'FACEBOOK', 'KINE', 'National', 'https://www.facebook.com/groups/60186204192/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Le réseau des Kinés Parisiens', 'FACEBOOK', 'KINE', 'Île-de-France', 'https://www.facebook.com/groups/1745137112378763/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Kinés de France', 'FACEBOOK', 'KINE', 'National', 'https://www.facebook.com/groups/kinesfrance/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Remplacement kiné Pays de la Loire', 'FACEBOOK', 'KINE', 'Pays de la Loire', 'https://www.facebook.com/groups/834498706719233/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Kiné Annonces - Perpignan (2)', 'FACEBOOK', 'KINE', 'Occitanie', 'https://www.facebook.com/groups/450700271798512/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  -- ── ORTHO / OSTÉO / PÉDICURE-PODOLOGUE ──
  ('Orthophonistes à Paris et en Île-de-France', 'FACEBOOK', 'ORTHOPHONISTE', 'Île-de-France', 'https://www.facebook.com/groups/Ortho.Paris/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Orthophonie - Annonces', 'FACEBOOK', 'ORTHOPHONISTE', 'National', 'https://www.facebook.com/groups/598055253731871/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Orthophonistes (annonces)', 'FACEBOOK', 'ORTHOPHONISTE', 'National', 'https://www.facebook.com/groups/132474033450596/', 'SOIGNANTS', 'A_VERIFIER', 'Intitulé exact à confirmer.'),
  ('Pédi-Podo Annonces (pédicure-podologue)', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/groups/1453044374969002/', 'MIXTE', 'A_VERIFIER', 'Remplacement/collaboration podologie.'),
  ('OP - Petites Annonces des Ostéopathes', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/groups/petitesannocesosteopartageurs/', 'MIXTE', 'A_VERIFIER', 'Ostéopathes : rempla/assistanat/collab.'),
  ('Réseau des Ostéopathes - Annonces et informations', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/groups/174368209403909/', 'MIXTE', 'A_VERIFIER', NULL),
  -- ── SAGES-FEMMES / DENTAIRE / PHARMA / CRÈCHE / AS ──
  ('Groupe sages-femmes (remplacements/échanges)', 'FACEBOOK', 'SAGE_FEMME', 'National', 'https://www.facebook.com/groups/1936211703330994/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Dentistes d''Occitanie / Sud-Ouest', 'FACEBOOK', 'DENTISTE', 'Occitanie', 'https://www.facebook.com/groups/dentistes.sudouest/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Recrutement dentiste - Île-de-France', 'FACEBOOK', 'DENTISTE', 'Île-de-France', 'https://www.facebook.com/groups/504967861349279/', 'ETABLISSEMENTS', 'A_VERIFIER', 'Recrutement cabinets IDF.'),
  ('Opportunité collaboration - cabinet dentaire', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/351579358665804/', 'MIXTE', 'A_VERIFIER', 'Intitulé exact à confirmer.'),
  ('Remplacements Pharmacie Pays de la Loire', 'FACEBOOK', 'PHARMACIEN', 'Pays de la Loire', 'https://www.facebook.com/groups/2721903697820201/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Emploi officine (1)', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/groups/16411685282/', 'MIXTE', 'A_VERIFIER', 'Intitulé exact à confirmer.'),
  ('Emploi officine (2)', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/groups/57081950477/', 'MIXTE', 'A_VERIFIER', 'Intitulé exact à confirmer.'),
  ('Emploi pharmacie (3)', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/groups/1058579861163963/', 'MIXTE', 'A_VERIFIER', 'Intitulé exact à confirmer.'),
  ('Annonces emploi Préparateurs en Pharmacie Hauts-de-France', 'FACEBOOK', 'PREPARATEUR_PHARMA', 'Hauts-de-France', 'https://www.facebook.com/groups/926008471317771/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Recrutement en crèche Auvergne-Rhône-Alpes', 'FACEBOOK', 'AUXILIAIRE_PUERICULTURE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/1099705530451320/', 'MIXTE', 'A_VERIFIER', NULL),
  ('À la recherche d''un travail en crèche', 'FACEBOOK', 'AUXILIAIRE_PUERICULTURE', 'National', 'https://www.facebook.com/groups/823210134681541/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Offre d''emploi en crèche, micro-crèche', 'FACEBOOK', 'AUXILIAIRE_PUERICULTURE', 'National', 'https://www.facebook.com/groups/1698858800493638/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Association Nationale des Aides-Soignant(e)s de France', 'FACEBOOK', 'AS', 'National', 'https://www.facebook.com/groups/1842352139379742/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Syndicat National des Aides-Soignants', 'FACEBOOK', 'AS', 'National', 'https://www.facebook.com/groups/480506376145239/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Groupe d''entraide Toulon (soignants)', 'FACEBOOK', 'TOUTES', 'PACA', 'https://www.facebook.com/groups/1963804863772838/', 'MIXTE', 'A_VERIFIER', 'Entraide locale soignants Var.')
) AS v(nom, plateforme, profession, region, url, audience, statut, notes)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sales_groupes sg
  WHERE rtrim(coalesce(sg.url, ''), '/') = rtrim(v.url, '/')
);
