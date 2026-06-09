-- Sales / Sourcing — 4e vague : Île-de-France + groupes globaux multi-professions
-- + renfort infirmières & dentistes. Dédup par URL normalisée.

INSERT INTO public.sales_groupes (nom, plateforme, profession, region, url, audience, statut, notes)
SELECT v.nom, v.plateforme, v.profession, v.region, v.url, v.audience, v.statut, v.notes
FROM (VALUES
  -- ── Île-de-France ──
  ('Chirurgiens-Dentistes en Île-de-France', 'FACEBOOK', 'DENTISTE', 'Île-de-France', 'https://www.facebook.com/groups/228576230981158/', 'MIXTE', 'A_VERIFIER', 'Groupe dentaire IDF.'),
  ('Répertoire des orthophonistes de Paris et IDF', 'FACEBOOK', 'ORTHOPHONISTE', 'Île-de-France', 'https://www.facebook.com/groups/repertoireorthoparisidf/', 'MIXTE', 'A_VERIFIER', 'Annuaire + annonces ortho Paris/IDF.'),
  -- ── Groupes GLOBAUX multi-professions ──
  ('Offres d''emploi en santé', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/groups/192186888229426/', 'MIXTE', 'A_VERIFIER', 'Généraliste santé toutes professions.'),
  ('Entraide Entre Soignants', 'FACEBOOK', 'TOUTES', 'National', 'https://www.facebook.com/groups/br.nurses/', 'SOIGNANTS', 'A_VERIFIER', 'Communauté multi-profession soignants (entraide + annonces).'),
  -- ── Infirmières (renfort national) ──
  ('Offres d''emploi Infirmier-e - France', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/275143669598036/', 'MIXTE', 'A_VERIFIER', 'Offres établissements + candidats.'),
  ('Infirmières en Mouvement', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/127401101407980/', 'SOIGNANTS', 'A_VERIFIER', 'Grande communauté IDE.'),
  ('Syndicat autonome des infirmières et infirmiers libéraux', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/1126684581084497/', 'SOIGNANTS', 'A_VERIFIER', 'Groupe syndical IDEL.'),
  ('Collectif Infirmiers Libéraux En Colère', 'FACEBOOK', 'IDE', 'National', 'https://www.facebook.com/groups/1282416832314648/', 'SOIGNANTS', 'A_VERIFIER', 'Grande audience IDEL.'),
  -- ── Dentistes (renfort national + équipe dentaire) ──
  ('Annonces Dentistes France', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/annonces.dentistes.france/', 'MIXTE', 'A_VERIFIER', 'Remplacement/emploi/collaboration/succession/gardes.'),
  ('[FRANCE] Dentistes', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/francedentistes/', 'MIXTE', 'A_VERIFIER', 'Communauté CD France.'),
  ('Super futur "chirurgien-dentiste"', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/200253880039520/', 'SOIGNANTS', 'A_VERIFIER', 'Étudiants/jeunes CD, opportunités.'),
  ('Assistant(e)/Secrétaire dentaire en alternance (Évolu''Santé)', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/evolusante.alternance/', 'MIXTE', 'A_VERIFIER', 'Alternance assistante/secrétaire dentaire.'),
  ('Assistante dentaire', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/232016038828003/', 'MIXTE', 'A_VERIFIER', 'Communauté + offres assistantes dentaires.'),
  ('Offres d''emploi assistantes et secrétaires dentaires', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/504398569762207/', 'ETABLISSEMENTS', 'A_VERIFIER', 'Côté cabinets.'),
  ('Emploi Secrétaire / Adjoint(e) médicale & dentaire', 'FACEBOOK', 'DENTISTE', 'National', 'https://www.facebook.com/groups/SecretaireAdjointeMedicalDentaire/', 'MIXTE', 'A_VERIFIER', 'Secrétaires/adjointes médicales & dentaires.')
) AS v(nom, plateforme, profession, region, url, audience, statut, notes)
WHERE NOT EXISTS (
  SELECT 1 FROM public.sales_groupes sg
  WHERE rtrim(coalesce(sg.url, ''), '/') = rtrim(v.url, '/')
);
