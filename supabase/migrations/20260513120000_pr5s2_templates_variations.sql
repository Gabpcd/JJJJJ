-- PR 5 Sprint 2 — Variations templates contrats par profession × type_etab
--
-- Sprint 1 a livré 7 templates :
--   CDD (master), REMPLACEMENT_LIBERAL (master),
--   LIBERAL_MEDECIN_CABINET, LIBERAL_DENTISTE_CABINET,
--   LIBERAL_IDE_CABINET, LIBERAL_SAGE_FEMME_CABINET, LIBERAL_KINE_CABINET.
--
-- Cette PR ajoute les variations légales borderline restantes pour les
-- cas mixtes (clinique / EHPAD / HAD) et les professions non couvertes
-- (orthophoniste, ergothérapeute, psychomotricien).
--
-- Décision Q5 Sprint 1 : pas besoin de templates CDD par profession —
-- le template CDD master utilise {{profession}}, {{convention_collective}}
-- et {{caisse_retraite}} comme variables et couvre les 18 professions
-- via substitution. Le PDF rendu indique bien la profession précise.
--
-- Templates ajoutés (7) :
--   LIBERAL_MEDECIN_CLINIQUE  — art. R.4127-65 médecin
--   LIBERAL_MEDECIN_EHPAD     — idem + spécificité EHPAD
--   LIBERAL_SAGE_FEMME_CLINIQUE — art. R.4127-359
--   LIBERAL_KINE_CLINIQUE     — art. R.4321-129
--   LIBERAL_ORTHOPHONISTE_CABINET — art. R.4341-7
--   LIBERAL_ERGOTHERAPEUTE_CABINET — art. R.4331-13
--   LIBERAL_PSYCHOMOTRICIEN_CABINET — art. R.4332-13
--
-- Helper RPC fn_resolve_template_contrat ajouté pour permettre au
-- frontend / edge function de résoudre le template approprié à partir
-- de (type_contrat, profession, type_etab) avec fallback automatique
-- sur le master.

-- 1. Helper : génération HTML libéral standard (DRY).
--    Note : on garde des templates physiquement en DB pour faciliter
--    l'édition / audit, mais on factorise via un wrapper.

-- Suppression idempotente des templates avant re-insertion (rerun safe)
DELETE FROM public.templates_contrat
WHERE type_contrat IN (
  'LIBERAL_MEDECIN_CLINIQUE', 'LIBERAL_MEDECIN_EHPAD',
  'LIBERAL_SAGE_FEMME_CLINIQUE', 'LIBERAL_KINE_CLINIQUE',
  'LIBERAL_ORTHOPHONISTE_CABINET', 'LIBERAL_ERGOTHERAPEUTE_CABINET',
  'LIBERAL_PSYCHOMOTRICIEN_CABINET'
);

DO $$
DECLARE
  v_template_html text;
BEGIN

-- Variables communes :
--   {{profession_label}}        : "médecin", "sage-femme", "kiné", etc.
--   {{art_ordinal_ref}}         : "art. R.4127-65 Code de la santé publique"
--   {{type_etab_label}}         : "clinique", "EHPAD", "cabinet"
--   {{caisse_liberal}}          : "CARPIMKO", "CNAVPL", "CIPAV"

v_template_html := $html$<h1>CONTRAT DE PRESTATION LIBÉRALE — {{profession_label_upper}} EN {{type_etab_label_upper}}</h1>
<p><strong>Mention obligatoire Jolene :</strong> Jolene SASU intervient en qualité de fournisseur de plateforme technique et de mandataire de facturation (art. 289 I-2 du Code général des impôts). Jolene n'est ni employeur, ni intérim. Le présent contrat de prestation est conclu directement entre l'établissement donneur d'ordre et le soignant libéral.</p>
<p><strong>Entre :</strong></p>
<p>L'établissement <strong>{{etablissement_nom}}</strong> ({{type_etab_label}}), SIRET {{etablissement_siret}}, FINESS {{etablissement_finess}}, dont le siège est situé {{etablissement_adresse}}, ci-après dénommé <strong>« le Donneur d'ordre »</strong>,</p>
<p><strong>Et :</strong></p>
<p>{{soignant_prenom}} {{soignant_nom}}, {{profession_label}} libéral·e inscrit·e à l'Ordre, SIRET <strong>{{soignant_siret}}</strong>, n° RPPS <strong>{{soignant_rpps}}</strong>, ci-après dénommé(e) <strong>« le Prestataire »</strong>.</p>
<h2>Article 1 — Objet et nature de la prestation</h2>
<p>Prestation libérale ponctuelle de {{profession_label}} dans le cadre de la mission « <strong>{{intitule_mission}}</strong> » au sein de {{etablissement_nom}} ({{type_etab_label}}). Le Prestataire exerce de manière strictement indépendante, sans lien de subordination avec le Donneur d'ordre (art. L8221-1 Code du travail).</p>
<h2>Article 2 — Cadre déontologique et ordinal</h2>
<p>Le Prestataire s'engage à respecter les règles déontologiques de sa profession, notamment <strong>{{art_ordinal_ref}}</strong> relatif au remplacement et à l'exercice en clientèle privée. Il est inscrit au tableau de l'Ordre/Conseil correspondant et assume la responsabilité civile professionnelle de ses actes.</p>
<h2>Article 3 — Indépendance professionnelle</h2>
<p>Le Prestataire fixe librement ses méthodes de soin, ses horaires (dans la fenêtre convenue), et n'est soumis à aucun pouvoir hiérarchique du Donneur d'ordre. L'absence de lien de subordination est une condition substantielle du présent contrat. {{specificite_type_etab}}</p>
<h2>Article 4 — Rémunération et facturation</h2>
<p>Honoraires : <strong>{{taux_horaire}} € HT/h</strong>, exonérés de TVA conformément à l'<strong>art. 261 4-1° CGI</strong> (prestations de soins à la personne). Facturation effectuée par <strong>Jolene SASU en qualité de mandataire</strong> du Prestataire, en application de l'art. 289 I-2 CGI et du mandat signé entre le Prestataire et Jolene.</p>
<h2>Article 5 — Statut social du Prestataire</h2>
<p>Le Prestataire assume seul ses obligations sociales et fiscales : URSSAF (cotisations indépendant), caisse de retraite professionnelle <strong>{{caisse_liberal}}</strong>, déclaration BNC ou IS. Le Donneur d'ordre n'a aucune obligation déclarative pour le Prestataire (DPAE non requise).</p>
<h2>Article 6 — Durée et conditions d'exécution</h2>
<p>Date de début : <strong>{{debut_le}}</strong>. Date de fin : <strong>{{fin_le}}</strong>. Durée totale : {{duree_heures}} heures.</p>
<h2>Article 7 — Pointage et validation</h2>
<p>Le pointage s'effectue via l'application Jolene (GPS ou code à 6 chiffres). La validation des heures par le Donneur d'ordre conditionne la facturation. Délai : 48h après fin de mission, validation auto à J+72h sinon.</p>
<h2>Article 8 — Litiges</h2>
<p>Tout litige relatif au présent contrat est de la compétence du <strong>tribunal de commerce</strong> du lieu d'exécution (relation B2B). Médiation interne Jolene possible en amont.</p>
<h2>Article 9 — Données personnelles (RGPD)</h2>
<p>Données du Prestataire traitées par Jolene en qualité de mandataire de facturation. Durée de conservation : 10 ans (obligation comptable art. L123-22 Code de commerce).</p>
<p>Fait à {{etablissement_ville}}, le <strong>{{date_signature}}</strong>, en deux exemplaires électroniques signés via OTP SMS Jolene (art. 1366-1367 Code civil).</p>
<p><em>Modèle Jolene v1 — {{date_signature}}. Pour toute question juridique, consultez votre conseil.</em></p>
$html$;

-- Insère les 7 templates libéraux additionnels via UPSERT
-- (idempotent : re-run safe).

-- 1. LIBERAL_MEDECIN_CLINIQUE
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_MEDECIN_CLINIQUE',
  'Prestation libérale — Médecin en clinique privée',
  1,
  true,
  replace(replace(replace(replace(replace(replace(replace(
    v_template_html,
    '{{profession_label_upper}}', 'MÉDECIN'),
    '{{profession_label}}', 'médecin'),
    '{{art_ordinal_ref}}', 'art. R.4127-65 du Code de la santé publique'),
    '{{type_etab_label_upper}}', 'CLINIQUE'),
    '{{type_etab_label}}', 'clinique privée'),
    '{{caisse_liberal}}', 'CARMF'),
    '{{specificite_type_etab}}', 'En clinique, le Prestataire dispose de l''accès aux plateaux techniques mais conserve son autonomie diagnostique et thérapeutique. La clinique met à disposition les moyens matériels nécessaires sans que cela ne constitue un lien de subordination.'
  ),
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
)
;

-- 2. LIBERAL_MEDECIN_EHPAD
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_MEDECIN_EHPAD',
  'Prestation libérale — Médecin coordonnateur en EHPAD',
  1,
  true,
  replace(replace(replace(replace(replace(replace(replace(
    v_template_html,
    '{{profession_label_upper}}', 'MÉDECIN'),
    '{{profession_label}}', 'médecin'),
    '{{art_ordinal_ref}}', 'art. R.4127-65 du Code de la santé publique'),
    '{{type_etab_label_upper}}', 'EHPAD'),
    '{{type_etab_label}}', 'EHPAD'),
    '{{caisse_liberal}}', 'CARMF'),
    '{{specificite_type_etab}}', 'En EHPAD, le Prestataire intervient sur consultation des résidents avec respect du secret médical et du dossier médical partagé. Le médecin coordonnateur (s''il existe) garde son rôle distinct sans hiérarchie sur le Prestataire.'
  ),
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
)
;

-- 3. LIBERAL_SAGE_FEMME_CLINIQUE
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_SAGE_FEMME_CLINIQUE',
  'Prestation libérale — Sage-femme en clinique',
  1,
  true,
  replace(replace(replace(replace(replace(replace(replace(
    v_template_html,
    '{{profession_label_upper}}', 'SAGE-FEMME'),
    '{{profession_label}}', 'sage-femme'),
    '{{art_ordinal_ref}}', 'art. R.4127-359 du Code de la santé publique'),
    '{{type_etab_label_upper}}', 'CLINIQUE'),
    '{{type_etab_label}}', 'clinique privée'),
    '{{caisse_liberal}}', 'CARCDSF'),
    '{{specificite_type_etab}}', 'La sage-femme libérale en clinique exerce dans le cadre de sa compétence propre (suivi de grossesse, accouchements eutociques, post-partum) et conserve son indépendance professionnelle.'
  ),
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
)
;

-- 4. LIBERAL_KINE_CLINIQUE
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_KINE_CLINIQUE',
  'Prestation libérale — Masseur-Kinésithérapeute en clinique',
  1,
  true,
  replace(replace(replace(replace(replace(replace(replace(
    v_template_html,
    '{{profession_label_upper}}', 'MASSEUR-KINÉSITHÉRAPEUTE'),
    '{{profession_label}}', 'masseur-kinésithérapeute'),
    '{{art_ordinal_ref}}', 'art. R.4321-129 du Code de la santé publique'),
    '{{type_etab_label_upper}}', 'CLINIQUE'),
    '{{type_etab_label}}', 'clinique de soins de suite et réadaptation'),
    '{{caisse_liberal}}', 'CARPIMKO'),
    '{{specificite_type_etab}}', 'Le kinésithérapeute libéral en clinique SSR exerce sur prescription médicale et conserve la responsabilité de ses choix techniques de rééducation.'
  ),
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
)
;

-- 5. LIBERAL_ORTHOPHONISTE_CABINET
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_ORTHOPHONISTE_CABINET',
  'Prestation libérale — Orthophoniste en cabinet',
  1,
  true,
  replace(replace(replace(replace(replace(replace(replace(
    v_template_html,
    '{{profession_label_upper}}', 'ORTHOPHONISTE'),
    '{{profession_label}}', 'orthophoniste'),
    '{{art_ordinal_ref}}', 'art. R.4341-7 du Code de la santé publique'),
    '{{type_etab_label_upper}}', 'CABINET'),
    '{{type_etab_label}}', 'cabinet d''orthophonie'),
    '{{caisse_liberal}}', 'CARPIMKO'),
    '{{specificite_type_etab}}', 'Le Prestataire orthophoniste assure le remplacement du titulaire du cabinet selon les modalités de l''art. R.4341-7. Le matériel de bilan et de rééducation reste la propriété du titulaire mais est mis à disposition du remplaçant pendant la durée du contrat.'
  ),
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
)
;

-- 6. LIBERAL_ERGOTHERAPEUTE_CABINET
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_ERGOTHERAPEUTE_CABINET',
  'Prestation libérale — Ergothérapeute en cabinet',
  1,
  true,
  replace(replace(replace(replace(replace(replace(replace(
    v_template_html,
    '{{profession_label_upper}}', 'ERGOTHÉRAPEUTE'),
    '{{profession_label}}', 'ergothérapeute'),
    '{{art_ordinal_ref}}', 'art. R.4331-13 du Code de la santé publique'),
    '{{type_etab_label_upper}}', 'CABINET'),
    '{{type_etab_label}}', 'cabinet d''ergothérapie'),
    '{{caisse_liberal}}', 'CIPAV'),
    '{{specificite_type_etab}}', 'L''ergothérapeute libéral exerce sur prescription médicale, généralement dans un cadre HAD (hospitalisation à domicile) ou cabinet privé. Le Prestataire conserve son autonomie de jugement clinique et de choix des techniques de réadaptation.'
  ),
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
)
;

-- 7. LIBERAL_PSYCHOMOTRICIEN_CABINET
INSERT INTO public.templates_contrat (type_contrat, nom, version, est_actif, contenu_html, variables)
VALUES (
  'LIBERAL_PSYCHOMOTRICIEN_CABINET',
  'Prestation libérale — Psychomotricien en cabinet',
  1,
  true,
  replace(replace(replace(replace(replace(replace(replace(
    v_template_html,
    '{{profession_label_upper}}', 'PSYCHOMOTRICIEN'),
    '{{profession_label}}', 'psychomotricien'),
    '{{art_ordinal_ref}}', 'art. R.4332-13 du Code de la santé publique'),
    '{{type_etab_label_upper}}', 'CABINET'),
    '{{type_etab_label}}', 'cabinet de psychomotricité'),
    '{{caisse_liberal}}', 'CIPAV'),
    '{{specificite_type_etab}}', 'Le psychomotricien libéral exerce sur prescription médicale. Le Prestataire est responsable des bilans psychomoteurs et des choix techniques de prise en charge.'
  ),
  '["etablissement_nom","etablissement_siret","etablissement_finess","etablissement_adresse","etablissement_ville","soignant_prenom","soignant_nom","soignant_siret","soignant_rpps","intitule_mission","taux_horaire","debut_le","fin_le","duree_heures","date_signature"]'::jsonb
)
;

END $$;

-- 2. RPC helper : résoudre le template à appliquer à partir de
--    (type_contrat, profession, type_etab). Permet à generate-contrat-mission-pdf
--    de choisir le slug exact ou de retomber sur le master.
CREATE OR REPLACE FUNCTION public.fn_resolve_template_contrat(
  p_type_contrat text,
  p_profession text,
  p_type_etab text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_slug text;
  v_template RECORD;
  v_profession_court text;
BEGIN
  -- Tentative de matching spécifique : LIBERAL_<PROFESSION>_<TYPE_ETAB>
  IF p_type_contrat IN ('REMPLACEMENT_LIBERAL', 'LIBERAL') AND p_profession IS NOT NULL AND p_type_etab IS NOT NULL THEN
    -- Normalisation profession : enlever "_LIBERAL" / "IDE_LIBERAL" → "IDE", garder MEDECIN, DENTISTE, etc.
    v_profession_court := regexp_replace(upper(p_profession), '_LIBERAL$', '');
    v_slug := 'LIBERAL_' || v_profession_court || '_' || upper(p_type_etab);
    SELECT type_contrat, nom, version INTO v_template
    FROM public.templates_contrat
    WHERE type_contrat = v_slug AND est_actif = true
    ORDER BY version DESC LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object(
        'success', true, 'slug', v_template.type_contrat,
        'nom', v_template.nom, 'version', v_template.version,
        'match', 'specifique'
      );
    END IF;
  END IF;

  -- Fallback : master
  IF p_type_contrat IN ('REMPLACEMENT_LIBERAL', 'LIBERAL') THEN
    v_slug := 'REMPLACEMENT_LIBERAL';
  ELSE
    v_slug := p_type_contrat; -- CDD, etc.
  END IF;

  SELECT type_contrat, nom, version INTO v_template
  FROM public.templates_contrat
  WHERE type_contrat = v_slug AND est_actif = true
  ORDER BY version DESC LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Aucun template actif pour ' || v_slug);
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'slug', v_template.type_contrat,
    'nom', v_template.nom, 'version', v_template.version,
    'match', 'master_fallback'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_resolve_template_contrat(text, text, text) TO authenticated;

-- 3. Audit
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'PR5_SPRINT2_TEMPLATES_VARIATIONS_INSTALLED',
    'pr', 'PR 5 Sprint 2',
    'templates_ajoutes', ARRAY[
      'LIBERAL_MEDECIN_CLINIQUE', 'LIBERAL_MEDECIN_EHPAD',
      'LIBERAL_SAGE_FEMME_CLINIQUE', 'LIBERAL_KINE_CLINIQUE',
      'LIBERAL_ORTHOPHONISTE_CABINET', 'LIBERAL_ERGOTHERAPEUTE_CABINET',
      'LIBERAL_PSYCHOMOTRICIEN_CABINET'
    ],
    'rpc', 'fn_resolve_template_contrat',
    'note', 'CDD master gère les 18 professions via {{profession}} variable'
  )
);
