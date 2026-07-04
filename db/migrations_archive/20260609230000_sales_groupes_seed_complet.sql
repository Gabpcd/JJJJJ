-- Sales / Sourcing — seed complet des groupes Facebook par profession (recherche
-- web exhaustive, nationaux + régionaux). Tous statut A_VERIFIER (la fondatrice
-- valide l'adhésion/intitulé). Hors-France (Maroc/Belgique/Québec) et purs
-- "concours/formation" exclus. WhatsApp/Telegram : aucun lien public trouvé
-- (par nature non indexés) → à coller manuellement.
--
-- Dédup : on n'insère que les URL absentes (comparaison sans slash final).

-- Compléter 2 lignes existantes (seedées sans URL) avec l'URL trouvée
UPDATE public.sales_groupes
  SET url = 'https://www.facebook.com/groups/annonces.orthophonistes.france/', statut = 'A_VERIFIER'
  WHERE nom = 'Annonces Orthophonistes France' AND url IS NULL;
UPDATE public.sales_groupes
  SET url = 'https://www.facebook.com/groups/471958797079298/', statut = 'A_VERIFIER'
  WHERE nom LIKE 'Kiné Annonces%' AND url IS NULL;

INSERT INTO public.sales_groupes (nom, plateforme, profession, region, url, audience, statut, notes)
SELECT v.nom, v.plateforme, v.profession, v.region, v.url, v.audience, v.statut, v.notes
FROM (VALUES
  -- ── INFIRMIERS (IDE / IDEL / IBODE / IADE) ──
  ('IDEL : astuces, entraide et remplacements', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/entreinfirmieresliberales/', 'SOIGNANTS', 'A_VERIFIER', 'Gros groupe national entraide/remplacement.'),
  ('Remplacement Infirmière - remplasoignant.fr', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/774684249365082/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement infirmières libérales', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/484258513787995/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Infirmiers libéraux : conseils, entraide (FNI)', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/groupefni/', 'SOIGNANTS', 'A_VERIFIER', 'Lié syndicat FNI.'),
  ('Infirmier Indépendant et Infirmière Indépendante', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/73222692443/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Infirmière et infirmier à la recherche d''emploi', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/336266723393832/', 'MIXTE', 'A_VERIFIER', NULL),
  ('IDEL EN COLÈRE', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/752323558207313/', 'SOIGNANTS', 'A_VERIFIER', 'Communauté militante, annonces circulent.'),
  ('Recrutement Infirmier(e)s & Aide-Soignant(e)s', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/584215498380295/', 'MIXTE', 'A_VERIFIER', 'Intitulé exact à confirmer.'),
  ('Infirmières et infirmiers libéraux des Pays de la Loire', 'FACEBOOK', 'IDE', 'Pays de la Loire', 'https://www.facebook.com/groups/276037600202714/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Infirmières et infirmiers libéraux de Bretagne', 'FACEBOOK', 'IDE', 'Bretagne', 'https://www.facebook.com/groups/283101969085517/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Offres d''emploi Infirmier-e - Bretagne', 'FACEBOOK', 'IDE', 'Bretagne', 'https://www.facebook.com/groups/2247044262015361/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement IDEL Hauts-de-France (ex NPDC)', 'FACEBOOK', 'IDE', 'Hauts-de-France', 'https://www.facebook.com/groups/remplacements.IDEL.NPDC/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement IDEL Nord-Pas-de-Calais', 'FACEBOOK', 'IDE', 'Hauts-de-France', 'https://www.facebook.com/groups/619094594942253/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement IDEL Aisne (02)', 'FACEBOOK', 'IDE', 'Hauts-de-France', 'https://www.facebook.com/groups/403536585057650/', 'MIXTE', 'A_VERIFIER', NULL),
  ('IDEL Remplacement Gironde (33)', 'FACEBOOK', 'IDE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/3863018103756698/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Infirmier libéral des Landes (40)', 'FACEBOOK', 'IDE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/696085787418070/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Infirmière libérale Dordogne (24)', 'FACEBOOK', 'IDE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/240515951252065/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement IDEL Pau (64)', 'FACEBOOK', 'IDE', 'Nouvelle-Aquitaine', 'https://www.facebook.com/groups/418075534565645/', 'MIXTE', 'A_VERIFIER', 'Intitulé exact à confirmer.'),
  ('Remplacement IDEL Toulouse (31)', 'FACEBOOK', 'IDE', 'Occitanie', 'https://www.facebook.com/groups/1642089042958676/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Entraide et Remplacement IDEL du 31', 'FACEBOOK', 'IDE', 'Occitanie', 'https://www.facebook.com/groups/487116642347684/', 'MIXTE', 'A_VERIFIER', NULL),
  ('IDEL - rempla Hérault (34)', 'FACEBOOK', 'IDE', 'Occitanie', 'https://www.facebook.com/groups/133136874714418/', 'MIXTE', 'A_VERIFIER', 'Montpellier.'),
  ('Remplacements IDEL du Vaucluse (84)', 'FACEBOOK', 'IDE', 'PACA', 'https://www.facebook.com/groups/171523773556369/', 'MIXTE', 'A_VERIFIER', NULL),
  ('IDEL 06 - Alpes-Maritimes - Nice', 'FACEBOOK', 'IDE', 'PACA', 'https://www.facebook.com/groups/201845154408375/', 'MIXTE', 'A_VERIFIER', NULL),
  ('AILG - Infirmiers Libéraux à La Garde (83)', 'FACEBOOK', 'IDE', 'PACA', 'https://www.facebook.com/groups/841318152616672/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Infirmières / aides-soignantes 83 (Var)', 'FACEBOOK', 'IDE', 'PACA', 'https://www.facebook.com/groups/Infirmieres.aidesoignantes83/', 'MIXTE', 'A_VERIFIER', 'Mixte IDE/AS.'),
  ('Remplacement IDEL Loire (42)', 'FACEBOOK', 'IDE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/402735917903409/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Entraide et remplacements IDEL du Cantal (15)', 'FACEBOOK', 'IDE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/691267368425834/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement IDEL région de Rouen (76)', 'FACEBOOK', 'IDE', 'Normandie', 'https://www.facebook.com/groups/314604902406646/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement IDEL Moselle (57)', 'FACEBOOK', 'IDE', 'Grand Est', 'https://www.facebook.com/groups/665363981259913/', 'MIXTE', 'A_VERIFIER', NULL),
  ('IDEL remplaçant La Réunion (974)', 'FACEBOOK', 'IDE', 'La Réunion (DOM)', 'https://www.facebook.com/groups/991619734189501/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Pour regrouper tous les IBODE de France', 'FACEBOOK', 'IBODE', 'National', 'https://www.facebook.com/groups/136951566383740/', 'SOIGNANTS', 'A_VERIFIER', 'Principal groupe IBODE national.'),
  ('SNIA - Infirmiers Anesthésistes (IADE)', 'FACEBOOK', 'IADE', 'National', 'https://www.facebook.com/SNIAIADE/', 'SOIGNANTS', 'A_VERIFIER', 'Page syndicale IADE (relaie emploi).'),
  -- ── AIDE-SOIGNANT / AES / AUX PUER / MANIP RADIO / DIÉTÉTICIEN ──
  ('Aide-Soignant - Offres d''Emploi', 'FACEBOOK', 'AS', 'National', 'https://www.facebook.com/groups/423416858037005/', 'MIXTE', 'A_VERIFIER', 'Dédié offres emploi AS.'),
  ('EMPLOIS IDE, AS, AES, ASH - Var & environs', 'FACEBOOK', 'AES', 'PACA', 'https://www.facebook.com/2798237580480383', 'MIXTE', 'A_VERIFIER', 'Multi-métiers Var ; vérifier format groupe/page.'),
  ('Annonces emploi petite enfance', 'FACEBOOK', 'AUXILIAIRE_PUERICULTURE', 'National', 'https://www.facebook.com/groups/1843081155986690/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Auxiliaires de puériculture de Nantes et alentours', 'FACEBOOK', 'AUXILIAIRE_PUERICULTURE', 'Pays de la Loire', 'https://www.facebook.com/groups/194822887198604/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Offre emploi MER (manipulateur radio)', 'FACEBOOK', 'MANIPULATEUR_RADIO', 'National', 'https://www.facebook.com/groups/302138299931875/', 'MIXTE', 'A_VERIFIER', 'Dédié offres MER/MERM.'),
  ('Groupe offres d''emploi santé IDF (MERM)', 'FACEBOOK', 'MANIPULATEUR_RADIO', 'Île-de-France', 'https://www.facebook.com/groups/1163120673865425/', 'MIXTE', 'A_VERIFIER', 'Offres MERM postées.'),
  ('Diet'' Emploi', 'FACEBOOK', 'DIETETICIEN', 'National', 'https://www.facebook.com/groups/745773042171326/', 'MIXTE', 'A_VERIFIER', 'Dédié emploi diététicien.'),
  ('Offres d''emploi des nutritionnistes diététiciens', 'FACEBOOK', 'DIETETICIEN', 'National', 'https://www.facebook.com/groups/2038779039621583/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Assistante médicale - Emploi - CH', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/groups/193801294117278/', 'MIXTE', 'A_VERIFIER', 'Postes hospitaliers santé.'),
  -- ── MÉDECINS / SAGES-FEMMES / DENTISTES / PHARMACIE ──
  ('Médecin généraliste français : remplaçant / installé', 'FACEBOOK', 'MEDECIN', 'National', 'https://www.facebook.com/groups/85165505336/', 'MIXTE', 'A_VERIFIER', 'Ancien grand groupe national MG.'),
  ('Remplacement Médecine Générale - France entière', 'FACEBOOK', 'MEDECIN', 'National', 'https://www.facebook.com/groups/523706649879822/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement Médecine Générale Paris / IDF', 'FACEBOOK', 'MEDECIN', 'Île-de-France', 'https://www.facebook.com/groups/175922542577398/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacements médecine générale Finistère (29)', 'FACEBOOK', 'MEDECIN', 'Bretagne', 'https://www.facebook.com/groups/201164449958684/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacement Médecine Générale Morbihan (56)', 'FACEBOOK', 'MEDECIN', 'Bretagne', 'https://www.facebook.com/groups/649465518520043/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Remplacements médecine générale Pays de la Loire', 'FACEBOOK', 'MEDECIN', 'Pays de la Loire', 'https://www.facebook.com/groups/353640031473804/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Rempmed - annonces médicales', 'FACEBOOK', 'MEDECIN', 'National', 'https://www.facebook.com/rempmed.fr/', 'MIXTE', 'A_VERIFIER', 'Page annonces remplacement/installation.'),
  ('Annonces Sages-Femmes France', 'FACEBOOK', 'SAGE_FEMME', 'National', 'https://www.facebook.com/groups/annonces.sages.femmes.france/', 'MIXTE', 'A_VERIFIER', 'Remplacement/emploi/collaboration.'),
  ('Sages-Femmes de France', 'FACEBOOK', 'SAGE_FEMME', 'National', 'https://www.facebook.com/groups/131113277033659/', 'SOIGNANTS', 'A_VERIFIER', 'Annonces ponctuelles.'),
  ('Rempla'' Dentaire', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/RemplaDentaire/', 'MIXTE', 'A_VERIFIER', 'Page remplacements courts dentaires.'),
  ('Ventes/achats de cabinets dentaires, collaboration', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/380601845656657/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Dentistes de France', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/204843909693791/', 'SOIGNANTS', 'A_VERIFIER', 'Annonces collab/rempla ponctuelles.'),
  ('Chirurgiens-Dentistes de France', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/463849046983071/', 'SOIGNANTS', 'A_VERIFIER', NULL),
  ('Club Officine - emploi pharmacie', 'FACEBOOK', 'PHARMACIEN', 'National', 'https://www.facebook.com/clubofficine/', 'ETABLISSEMENTS', 'A_VERIFIER', 'Page emploi pharmacien/préparateur.'),
  ('ClubOfficine - emploi préparateur', 'FACEBOOK', 'PREPARATEUR_PHARMA', 'National', 'https://www.facebook.com/clubofficine.preparateur/', 'ETABLISSEMENTS', 'A_VERIFIER', 'Page dédiée préparateurs.'),
  -- ── KINÉ (national + régionaux + DOM) ──
  ('Remplacement/Assistanat kiné France', 'FACEBOOK', 'KINE', 'National', 'https://www.facebook.com/groups/241923446303176/', 'MIXTE', 'A_VERIFIER', 'National généraliste.'),
  ('Kiné Annonces (kineannonces.fr)', 'FACEBOOK', 'KINE', 'National', 'https://www.facebook.com/groups/kineannonces.fr/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Réseau Annonces Emplois - Remplacement/Assistanat Kiné', 'FACEBOOK', 'KINE', 'National', 'https://www.facebook.com/groups/annoncekine/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Annonces Kiné - Île-de-France / Paris', 'FACEBOOK', 'KINE', 'Île-de-France', 'https://www.facebook.com/groups/IleDeFranceAppines/', 'MIXTE', 'A_VERIFIER', 'Réseau Appines.'),
  ('Kiné Paris remplas/collaboration', 'FACEBOOK', 'KINE', 'Île-de-France', 'https://www.facebook.com/groups/688266505769453/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Annonces Kiné - Bretagne', 'FACEBOOK', 'KINE', 'Bretagne', 'https://www.facebook.com/groups/BretagneAppines/', 'MIXTE', 'A_VERIFIER', 'Réseau Appines.'),
  ('Annonces Kiné - Pays de la Loire', 'FACEBOOK', 'KINE', 'Pays de la Loire', 'https://www.facebook.com/groups/PaysDeLaLoireAppines/', 'MIXTE', 'A_VERIFIER', 'Réseau Appines.'),
  ('Annonces Kiné - La Réunion', 'FACEBOOK', 'KINE', 'La Réunion (DOM)', 'https://www.facebook.com/groups/LaReunionAppines/', 'MIXTE', 'A_VERIFIER', 'Réseau Appines.'),
  ('Annonces Kiné - Mayotte', 'FACEBOOK', 'KINE', 'Mayotte (DOM)', 'https://www.facebook.com/groups/MayotteAppines/', 'MIXTE', 'A_VERIFIER', 'Réseau Appines.'),
  ('Annonces Kiné - Martinique', 'FACEBOOK', 'KINE', 'Martinique (DOM)', 'https://www.facebook.com/groups/MartiniqueAppines/', 'MIXTE', 'A_VERIFIER', 'Réseau Appines.'),
  ('Annonces Kiné - Guadeloupe', 'FACEBOOK', 'KINE', 'Guadeloupe (DOM)', 'https://www.facebook.com/groups/GuadeloupeAppines/', 'MIXTE', 'A_VERIFIER', 'Réseau Appines.'),
  ('Annonces Kinés Occitanie', 'FACEBOOK', 'KINE', 'Occitanie', 'https://www.facebook.com/groups/134661184019320/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Annonce rempla Kiné Montpellier', 'FACEBOOK', 'KINE', 'Occitanie', 'https://www.facebook.com/groups/147174412370674/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Kiné Annonces Perpignan', 'FACEBOOK', 'KINE', 'Occitanie', 'https://www.facebook.com/groups/807857026038270/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Annonces Rempla/Assistanat Kiné Lyon', 'FACEBOOK', 'KINE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/179104348932272/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Kiné en Savoie - remplacement/assistanat (73)', 'FACEBOOK', 'KINE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/809489433362988/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Kiné rempla Drôme (26)', 'FACEBOOK', 'KINE', 'Auvergne-Rhône-Alpes', 'https://www.facebook.com/groups/1122470671227549/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Kiné rempla Vaucluse (84)', 'FACEBOOK', 'KINE', 'PACA', 'https://www.facebook.com/groups/858266990979572/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Kinés du 83 (Var)', 'FACEBOOK', 'KINE', 'PACA', 'https://www.facebook.com/groups/515348045313821/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Kiné Corse remplacement/assistanat', 'FACEBOOK', 'KINE', 'Corse', 'https://www.facebook.com/groups/kinecorseremplacement/', 'MIXTE', 'A_VERIFIER', NULL),
  -- ── ORTHOPHONISTES / PSYCHOMOTRICIENS ──
  ('Petites Annonces d''Orthophonie', 'FACEBOOK', 'ORTHOPHONISTE', 'National', 'https://www.facebook.com/groups/190748377704254/', 'MIXTE', 'A_VERIFIER', NULL),
  ('Emplois et stages psychomotricien(ne)s', 'FACEBOOK', 'PSYCHOMOTRICIEN', 'National', 'https://www.facebook.com/groups/463101760491917/', 'MIXTE', 'A_VERIFIER', 'Emploi/stages national.')
) AS v(nom, plateforme, profession, region, url, audience, statut, notes)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sales_groupes sg
  WHERE rtrim(coalesce(sg.url, ''), '/') = rtrim(v.url, '/')
);
