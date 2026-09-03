-- PR 5 Sprint 1 — Seed templates contrats (CDD + libéral)
--
-- Remplace les 2 templates existants (CDD générique, REMPLACEMENT_LIBERAL)
-- par des versions renforcées juridiquement, et ajoute 5 templates
-- spécifiques pour les cas borderline (médecin libéral, dentiste, IDEL,
-- sage-femme, kiné).
--
-- Approche MVP : 2 master + 5 spécifiques au lieu des ~30 idéaux. Les
-- variations supplémentaires (par profession salariée notamment) peuvent
-- être ajoutées incrémentalement dans Sprint 2+ sans bloquer le launch.
--
-- Mentions obligatoires intégrées :
-- - Jolene = plateforme technique uniquement, pas employeur ni intérim
-- - CDD : art. L1242-12 (mentions obligatoires) + L1242-2 1°/2°
-- - Libéral : art. 289 I-2 CGI (mandat facturation) + 261 4-1° (exo TVA)
-- - Libéral remplacement : références ordinales (R.4127-65 médecin,
--   R.4127-274 dentiste, R.4312-12 IDEL)
-- - Footer "Modèle Jolene v1 — pour conseil juridique, consultez votre
--   conseil" (Gabrielle décision Q5)

-- Common template HTML wrapper utility (en plain HTML, pas markdown
-- pour rester compatible avec contenu_html existant)

-- Seed CDD générique (master) — remplace l'existant
DELETE FROM public.templates_contrat WHERE type_contrat = 'CDD';
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables) VALUES (
  'CDD',
  'Contrat à Durée Déterminée (CDD) — Master',
  2,
  true,
  $html$<h1>CONTRAT À DURÉE DÉTERMINÉE (CDD)</h1>
<p><strong>Mention obligatoire Jolene :</strong> Jolene SASU (jolene.app) intervient en qualité de fournisseur de plateforme technique uniquement. Jolene n'est ni employeur, ni intermédiaire de travail temporaire, ni intérim, ni portage salarial. Le présent contrat est conclu directement et exclusivement entre l'établissement et le soignant.</p>
<p><strong>Entre :</strong></p>
<p>L'établissement <strong>{{etablissement_nom}}</strong>, SIRET <strong>{{etablissement_siret}}</strong>, FINESS {{etablissement_finess}}, dont le siège est situé {{etablissement_adresse}}, représenté par son directeur/directrice, ci-après dénommé <strong>« l'Employeur »</strong>,</p>
<p><strong>Et :</strong></p>
<p>{{soignant_prenom}} {{soignant_nom}}, né(e) le {{soignant_date_naissance}}, demeurant {{soignant_adresse}}, ci-après dénommé(e) <strong>« le Salarié »</strong>.</p>
<h2>Article 1 — Objet et motif du contrat</h2>
<p>Le présent contrat est conclu pour un motif de <strong>{{motif_cdd}}</strong> (art. L1242-2 du Code du travail). Le poste consiste en : <strong>{{intitule_mission}}</strong> ({{profession}}).</p>
<h2>Article 2 — Durée et terme</h2>
<p>Date de début : <strong>{{debut_le}}</strong>. Date de fin : <strong>{{fin_le}}</strong>. Durée totale prévisionnelle : {{duree_heures}} heures.</p>
<h2>Article 3 — Convention collective applicable</h2>
<p>La convention collective applicable est celle de l'Employeur : <strong>{{convention_collective}}</strong>. Le Salarié reconnaît en avoir pris connaissance.</p>
<h2>Article 4 — Période d'essai</h2>
<p>Une période d'essai de <strong>{{periode_essai_libelle}}</strong> est prévue, conformément à l'art. L1242-10 du Code du travail.</p>
<h2>Article 5 — Rémunération</h2>
<p>Taux horaire brut : <strong>{{taux_horaire}} € brut/h</strong>, majorations légales incluses (nuit ≥ 25%, dimanche ≥ 25%, jour férié ≥ 50%) ou conventionnelles selon la CCN applicable. À la fin du contrat, le Salarié percevra une <strong>indemnité de fin de contrat (IFM) de 10%</strong> de la rémunération brute totale (art. L1243-8) et une <strong>indemnité compensatrice de congés payés (ICP) de 10%</strong> (art. L3141-22).</p>
<h2>Article 6 — Cotisations sociales</h2>
<p>L'Employeur s'engage à effectuer la <strong>DPAE</strong> auprès de l'URSSAF avant la prise de poste (art. R1221-2). Caisse de retraite complémentaire : <strong>{{caisse_retraite}}</strong>. Régime de prévoyance : <strong>{{regime_prevoyance}}</strong>.</p>
<h2>Article 7 — Temps de travail légal</h2>
<p>Le Salarié s'engage à respecter les durées maximales légales : 10h/jour (L3121-18), 48h/semaine absolu (L3121-20), 44h moyenne sur 12 semaines (L3121-22), et les repos minimums : 11h entre deux journées (L3131-1), 35h hebdomadaire (L3132-2).</p>
<h2>Article 8 — Pointage</h2>
<p>Le pointage de l'arrivée et du départ s'effectue obligatoirement via l'application Jolene (GPS ou code à 6 chiffres). Les heures réellement travaillées sont validées par l'Employeur dans les 48h suivant la fin de mission, ou validation automatique à J+72h en l'absence de contestation.</p>
<h2>Article 9 — Litiges</h2>
<p>Tout litige relatif à l'exécution du présent contrat est de la compétence du Conseil de prud'hommes du lieu d'exécution. Les parties peuvent saisir la médiation interne Jolene en amont.</p>
<h2>Article 10 — Données personnelles (RGPD)</h2>
<p>Les données du Salarié sont traitées par l'Employeur en sa qualité de responsable de traitement (art. 4-7 RGPD), avec Jolene comme sous-traitant technique (art. 28). Durée de conservation : 5 ans à compter de la fin de mission (obligation comptable + URSSAF).</p>
<p>Fait à {{etablissement_ville}}, le <strong>{{date_signature}}</strong>, en deux exemplaires signés électroniquement dans Jolene (art. 1366-1367 Code civil).</p>
<p><em>Modèle Jolene v1 — {{date_signature}}. Pour toute question juridique, consultez votre conseil.</em></p>
$html$::text,
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_date_naissance","soignant_adresse","motif_cdd","intitule_mission","profession","debut_le","fin_le","duree_heures","convention_collective","periode_essai_libelle","taux_horaire","caisse_retraite","regime_prevoyance","date_signature"]'::jsonb
);

-- Seed Libéral générique (master) — remplace REMPLACEMENT_LIBERAL existant
DELETE FROM public.templates_contrat WHERE type_contrat = 'REMPLACEMENT_LIBERAL';
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables) VALUES (
  'REMPLACEMENT_LIBERAL',
  'Contrat de prestation libérale — Master',
  2,
  true,
  $html$<h1>CONTRAT DE PRESTATION LIBÉRALE</h1>
<p><strong>Mention obligatoire Jolene :</strong> Jolene SASU intervient en qualité de fournisseur de plateforme technique et de mandataire de facturation (art. 289 I-2 du Code général des impôts). Jolene n'est ni employeur, ni intérim. Le présent contrat de prestation est conclu directement entre l'établissement donneur d'ordre et le soignant libéral.</p>
<p><strong>Entre :</strong></p>
<p>L'établissement <strong>{{etablissement_nom}}</strong>, SIRET {{etablissement_siret}}, ci-après dénommé <strong>« le Donneur d'ordre »</strong>,</p>
<p><strong>Et :</strong></p>
<p>{{soignant_prenom}} {{soignant_nom}}, professionnel de santé libéral inscrit à l'Ordre/au Conseil, SIRET <strong>{{soignant_siret}}</strong>, n° RPPS <strong>{{soignant_rpps}}</strong>, ci-après dénommé(e) <strong>« le Prestataire »</strong>.</p>
<h2>Article 1 — Objet</h2>
<p>Prestation libérale ponctuelle de {{profession}} dans le cadre de la mission « <strong>{{intitule_mission}}</strong> ». Le Prestataire exerce de manière strictement indépendante, sans lien de subordination avec le Donneur d'ordre (art. L8221-1 Code du travail).</p>
<h2>Article 2 — Indépendance professionnelle</h2>
<p>Le Prestataire fixe librement ses horaires (dans la fenêtre convenue), choisit ses méthodes de soin, et n'est soumis à aucun pouvoir hiérarchique du Donneur d'ordre. L'absence de lien de subordination est une condition substantielle du présent contrat.</p>
<h2>Article 3 — Rémunération et facturation</h2>
<p>Honoraires : <strong>{{taux_horaire}} € HT/h</strong>, exonérés de TVA conformément à l'<strong>art. 261 4-1° CGI</strong> (prestations de soins à la personne). Facturation effectuée par <strong>Jolene SASU en qualité de mandataire</strong> du Prestataire, en application de l'art. 289 I-2 CGI et du mandat signé entre le Prestataire et Jolene.</p>
<h2>Article 4 — Statut social du Prestataire</h2>
<p>Le Prestataire assume seul ses obligations sociales et fiscales : URSSAF (cotisations indépendant), CARPIMKO/CNAVPL/CIPAV selon la profession, déclaration BNC ou IS. Le Donneur d'ordre n'a aucune obligation déclarative pour le Prestataire.</p>
<h2>Article 5 — Durée et conditions d'exécution</h2>
<p>Date de début : <strong>{{debut_le}}</strong>. Date de fin : <strong>{{fin_le}}</strong>. Durée totale : {{duree_heures}} heures.</p>
<h2>Article 6 — Pointage et validation</h2>
<p>Le pointage s'effectue via l'application Jolene. La validation des heures par le Donneur d'ordre conditionne la facturation. Délai : 48h après fin de mission, validation auto à J+72h sinon.</p>
<h2>Article 7 — Litiges</h2>
<p>Litige relatif au présent contrat : <strong>tribunal de commerce</strong> du lieu d'exécution (relation B2B). Médiation interne Jolene possible en amont.</p>
<h2>Article 8 — RGPD</h2>
<p>Données du Prestataire traitées par Jolene en sa qualité de mandataire de facturation. Durée de conservation : 10 ans (obligation comptable Art. L123-22).</p>
<p>Fait à {{etablissement_ville}}, le <strong>{{date_signature}}</strong>, en deux exemplaires signés électroniquement dans Jolene (art. 1366-1367 Code civil).</p>
<p><em>Modèle Jolene v1 — {{date_signature}}. Pour toute question juridique, consultez votre conseil.</em></p>
$html$::text,
  '["etablissement_nom","etablissement_siret","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","profession","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
);

-- Templates LIBERAL spécifiques par profession × type_etab (cas borderline)
-- Convention : type_contrat = 'LIBERAL_<PROFESSION>_<TYPE_ETAB>'

INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables) VALUES
('LIBERAL_MEDECIN_CABINET',
 'Remplacement médecin libéral (cabinet) — CNOM R.4127-65',
 1, true,
 $html$<h1>CONTRAT DE REMPLACEMENT — MÉDECIN LIBÉRAL EN CABINET</h1>
<p><strong>Mention Jolene :</strong> Jolene plateforme technique uniquement, pas employeur. Mandat de facturation art. 289 I-2 CGI.</p>
<p><strong>Référence ordinale :</strong> contrat conforme à l'art. R.4127-65 du Code de la santé publique (Code de déontologie médicale, CNOM). Durée maximale de remplacement : 3 mois consécutifs renouvelables avec accord du Conseil départemental de l'Ordre.</p>
<p>Entre <strong>{{etablissement_nom}}</strong> (cabinet médical, n° {{etablissement_finess}}) représenté par le Dr {{etablissement_contact}}, et <strong>Dr {{soignant_prenom}} {{soignant_nom}}</strong> (RPPS {{soignant_rpps}}, SIRET {{soignant_siret}}, inscrit au Tableau de l'Ordre n° {{soignant_numero_ordre}}).</p>
<h2>Article 1 — Objet</h2>
<p>Remplacement temporaire du médecin titulaire pendant son absence. Le remplaçant exerce sous sa propre responsabilité professionnelle et assurance RCP.</p>
<h2>Article 2 — Rétrocession d'honoraires</h2>
<p>Le remplaçant perçoit l'intégralité des honoraires des actes pratiqués, déduction faite d'une rétrocession au cabinet de <strong>{{taux_retrocession}} %</strong> (usage : 70% au remplaçant / 30% au cabinet). Versement via Jolene mandataire.</p>
<h2>Article 3 — Conformité ordinale</h2>
<p>Notification du Conseil départemental de l'Ordre : <strong>obligation à la charge du médecin titulaire</strong>. Le remplaçant fournit copie de son inscription à l'Ordre et de sa RCP en cours de validité.</p>
<p>Reste du contrat : durée, pointage, RGPD, litiges (tribunal de commerce) — comme le modèle libéral master.</p>
<p>Fait à {{etablissement_ville}}, le {{date_signature}}.</p>
<p><em>Modèle Jolene v1. Pour toute question juridique, consultez votre conseil.</em></p>
$html$::text,
 '["etablissement_nom","etablissement_finess","etablissement_contact","etablissement_ville","soignant_prenom","soignant_nom","soignant_rpps","soignant_siret","soignant_numero_ordre","taux_retrocession","date_signature"]'::jsonb),

('LIBERAL_DENTISTE_CABINET',
 'Remplacement chirurgien-dentiste libéral (cabinet) — CNOC R.4127-274',
 1, true,
 $html$<h1>CONTRAT DE REMPLACEMENT — CHIRURGIEN-DENTISTE LIBÉRAL</h1>
<p><strong>Mention Jolene :</strong> plateforme technique + mandataire facturation art. 289 I-2 CGI.</p>
<p><strong>Référence ordinale :</strong> contrat conforme à l'art. R.4127-274 du CSP (Code de déontologie des chirurgiens-dentistes, CNOC). Contrat-type CNOC + déclaration auprès du Conseil départemental.</p>
<p>Entre le cabinet dentaire <strong>{{etablissement_nom}}</strong> et le Dr {{soignant_prenom}} {{soignant_nom}} (RPPS {{soignant_rpps}}, n° Ordre {{soignant_numero_ordre}}).</p>
<h2>Article 1 — Objet</h2>
<p>Remplacement du dentiste titulaire pour la période {{debut_le}} → {{fin_le}}. Actes facturés à la nomenclature CCAM/SNRD.</p>
<h2>Article 2 — Rétrocession</h2>
<p>Le remplaçant perçoit {{taux_retrocession}}% des honoraires perçus (usage : 60-70%). Reversement via Jolene mandataire.</p>
<h2>Article 3 — Responsabilité</h2>
<p>Chaque praticien exerce sous sa propre RCP. Le remplaçant fournit copie de son inscription à l'Ordre et de sa RCP avant prise de poste.</p>
<p>Fait à {{etablissement_ville}}, le {{date_signature}}.</p>
<p><em>Modèle Jolene v1. Pour toute question juridique, consultez votre conseil.</em></p>
$html$::text,
 '["etablissement_nom","etablissement_ville","soignant_prenom","soignant_nom","soignant_rpps","soignant_numero_ordre","debut_le","fin_le","taux_retrocession","date_signature"]'::jsonb),

('LIBERAL_IDE_CABINET',
 'Remplacement IDEL en cabinet — R.4312-12 CSP',
 1, true,
 $html$<h1>CONTRAT DE REMPLACEMENT — INFIRMIER(ÈRE) LIBÉRAL(E) (IDEL)</h1>
<p><strong>Mention Jolene :</strong> plateforme technique + mandataire facturation art. 289 I-2 CGI.</p>
<p><strong>⚠️ Rappel juridique :</strong> le remplacement IDEL n'est autorisé qu'<strong>IDEL → IDEL en cabinet IDEL</strong> (art. R.4312-12 CSP). Toute autre configuration (EHPAD, clinique, hôpital) constituerait un cas de salariat déguisé requalifiable en travail dissimulé (art. L8221-1 Code travail, Conseil d'État 11/02/2025 arrêt Mediflash).</p>
<p>Entre le cabinet IDEL <strong>{{etablissement_nom}}</strong> (titulaire IDE libéral, RPPS {{etablissement_rpps_titulaire}}) et <strong>{{soignant_prenom}} {{soignant_nom}}</strong> (IDE libéral, RPPS {{soignant_rpps}}, SIRET {{soignant_siret}}).</p>
<h2>Article 1 — Objet</h2>
<p>Remplacement de l'IDEL titulaire pour la période {{debut_le}} → {{fin_le}}. Tournée de soins infirmiers à domicile et/ou au cabinet.</p>
<h2>Article 2 — Rétrocession d'honoraires</h2>
<p>Conformément à l'art. R.4312-12, le remplaçant perçoit l'intégralité des honoraires des soins qu'il effectue, déduction faite d'une <strong>rétrocession au cabinet titulaire de {{taux_retrocession}}%</strong> (usage : 10-30%). Reversement via Jolene mandataire facturation.</p>
<h2>Article 3 — Conformité ordinale</h2>
<p>Déclaration de remplacement à l'Ordre National des Infirmiers : à la charge du titulaire. Durée max : 24 mois cumulés sans reprise libérale (R.4312-13).</p>
<h2>Article 4 — Continuité des soins</h2>
<p>Le remplaçant s'engage à assurer la continuité des soins à la patientèle du titulaire, dans le respect du secret professionnel et de la confraternité.</p>
<p>Fait à {{etablissement_ville}}, le {{date_signature}}.</p>
<p><em>Modèle Jolene v1. Pour toute question juridique, consultez votre conseil.</em></p>
$html$::text,
 '["etablissement_nom","etablissement_rpps_titulaire","etablissement_ville","soignant_prenom","soignant_nom","soignant_rpps","soignant_siret","debut_le","fin_le","taux_retrocession","date_signature"]'::jsonb),

('LIBERAL_SAGE_FEMME_CABINET',
 'Remplacement sage-femme libérale (cabinet)',
 1, true,
 $html$<h1>CONTRAT DE REMPLACEMENT — SAGE-FEMME LIBÉRALE</h1>
<p><strong>Mention Jolene :</strong> plateforme technique + mandataire facturation 289 I-2 CGI.</p>
<p><strong>Référence ordinale :</strong> contrat-type Conseil National de l'Ordre des Sages-Femmes (CNOSF). Déclaration au Conseil départemental.</p>
<p>Entre le cabinet <strong>{{etablissement_nom}}</strong> et <strong>{{soignant_prenom}} {{soignant_nom}}</strong> (RPPS {{soignant_rpps}}, n° Ordre {{soignant_numero_ordre}}).</p>
<h2>Article 1 — Objet</h2>
<p>Remplacement temporaire de la sage-femme titulaire. Période : {{debut_le}} → {{fin_le}}.</p>
<h2>Article 2 — Rétrocession</h2>
<p>Rétrocession de {{taux_retrocession}}% des honoraires au cabinet titulaire. Versement via Jolene mandataire.</p>
<p>Fait à {{etablissement_ville}}, le {{date_signature}}.</p>
<p><em>Modèle Jolene v1. Pour toute question juridique, consultez votre conseil.</em></p>
$html$::text,
 '["etablissement_nom","etablissement_ville","soignant_prenom","soignant_nom","soignant_rpps","soignant_numero_ordre","debut_le","fin_le","taux_retrocession","date_signature"]'::jsonb),

('LIBERAL_KINE_CABINET',
 'Remplacement kinésithérapeute libéral (cabinet)',
 1, true,
 $html$<h1>CONTRAT DE REMPLACEMENT — MASSEUR-KINÉSITHÉRAPEUTE LIBÉRAL</h1>
<p><strong>Mention Jolene :</strong> plateforme technique + mandataire facturation 289 I-2 CGI.</p>
<p><strong>Référence ordinale :</strong> contrat conforme au Code de déontologie des masseurs-kinésithérapeutes (CSP art. R.4321-127 et suiv.). Déclaration au Conseil départemental de l'Ordre.</p>
<p>Entre le cabinet <strong>{{etablissement_nom}}</strong> et <strong>{{soignant_prenom}} {{soignant_nom}}</strong> (RPPS {{soignant_rpps}}, SIRET {{soignant_siret}}, n° Ordre {{soignant_numero_ordre}}).</p>
<h2>Article 1 — Objet</h2>
<p>Remplacement temporaire pour la période {{debut_le}} → {{fin_le}}. Continuité des soins de la patientèle.</p>
<h2>Article 2 — Rétrocession</h2>
<p>Honoraires perçus par le remplaçant moins rétrocession de {{taux_retrocession}}% au cabinet titulaire. Reversement Jolene mandataire.</p>
<p>Fait à {{etablissement_ville}}, le {{date_signature}}.</p>
<p><em>Modèle Jolene v1. Pour toute question juridique, consultez votre conseil.</em></p>
$html$::text,
 '["etablissement_nom","etablissement_ville","soignant_prenom","soignant_nom","soignant_rpps","soignant_siret","soignant_numero_ordre","debut_le","fin_le","taux_retrocession","date_signature"]'::jsonb);

-- Audit (action='SYSTEM' autorisée)
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'table', NULL,
  jsonb_build_object(
    'evenement', 'TEMPLATES_CONTRATS_SEED',
    'pr', 'PR 5 Sprint 1',
    'templates_inserts_ou_majs', ARRAY[
      'CDD (master)', 'REMPLACEMENT_LIBERAL (master)',
      'LIBERAL_MEDECIN_CABINET', 'LIBERAL_DENTISTE_CABINET',
      'LIBERAL_IDE_CABINET', 'LIBERAL_SAGE_FEMME_CABINET',
      'LIBERAL_KINE_CABINET'
    ],
    'mentions_legales_inclues', ARRAY[
      'Jolene plateforme technique uniquement',
      'CDD art. L1242-12 mentions obligatoires',
      'Libéral art. 289 I-2 CGI mandat facturation',
      'Libéral art. 261 4-1° CGI exonération TVA',
      'Référence Conseil d''Etat 11/02/2025 (Mediflash) pour IDEL'
    ],
    'note_validation_juridique', 'v1 sans avocat (décision Gabrielle Q5). Audit prévu 6-12 mois post-launch.'
  )
);
