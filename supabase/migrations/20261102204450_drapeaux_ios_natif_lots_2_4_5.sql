-- Lots 2, 4 et 5 app iOS native (D-FLAGS) — drapeaux ios_natif_<ecran>_actif.
--
-- Même mécanisme et même gabarit que B0 (20261102150000_drapeaux_ios_natif.sql,
-- décision 9 du lot 0, docs/mobile-swift/DECISIONS_LOT0.md) : un écran natif
-- cassé doit pouvoir être désactivé à chaud, l'app affichant alors un renvoi vers
-- le web. L'app lit ces clés via la RPC existante fn_param_bool(p_cle, p_defaut)
-- après ouverture de session (aucun GRANT anon ; grants existants : authenticated
-- + service_role). Sans ligne en base, fn_param_bool renvoie p_defaut et
-- fn_admin_maj_parametre répond « Paramètre inconnu » : l'administrateur ne peut
-- pas créer la clé depuis l'interface, d'où ces vingt-trois lignes.
--
-- ON CONFLICT (cle) DO NOTHING, jamais DO UPDATE : un rejeu ne doit pas réarmer
-- un écran coupé en urgence par l'administrateur. Catégorie OPERATIONS : seule
-- façon d'apparaître dans AdminConfig (src/pages/admin/AdminConfig.tsx,
-- CATEGORIES). Bornes 0/1 : fn_admin_maj_parametre refuse toute valeur hors
-- [0, 1] ; fn_param_bool lit « valeur <> 0 ». valeur 1 = écran actif (défaut
-- fail-open côté app).
--
-- Écrans (blueprints v2) :
-- - lot 2 (soignant : pointage, justificatifs, contrats OTP) : presences,
--   documents, contrats — coupe-circuit du pointage et de la signature ;
-- - lot 4 (soignant, parcours secondaires, B0-bis et D18, 13 clés) : swipe,
--   recherches, disponibilites, parrainage, litiges, reclamations, messagerie,
--   bulletins, evaluations, score, pool_urgence, exclusions, serie ;
-- - lot 5 (espace établissement, B5a et D14, 7 clés) : etab_accueil,
--   etab_missions, etab_publier, etab_presences, etab_pointage (coupe-circuit
--   du polling 5 s du code rotatif), etab_messages, etab_compte.
-- Garde : src/lib/__tests__/drapeauxIosNatifMigration.test.ts (28 clés au total
-- avec B0).

-- Lot 2 — soignant

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_presences_actif',1,'App iOS — écran Présences actif',
 'Autorise l''écran natif Présences (pointage des missions) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_documents_actif',1,'App iOS — écran Mes documents actif',
 'Autorise l''écran natif Mes documents (justificatifs) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_contrats_actif',1,'App iOS — écran Contrats actif',
 'Autorise l''écran natif Contrats (lecture et signature par code SMS) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

-- Lot 4 — soignant, parcours secondaires

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_swipe_actif',1,'App iOS — écran Swipe actif',
 'Autorise l''écran natif Swipe (missions proposées en cartes) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_recherches_actif',1,'App iOS — écran Recherches sauvegardées actif',
 'Autorise l''écran natif Recherches sauvegardées (alertes de missions) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_disponibilites_actif',1,'App iOS — écran Mes disponibilités actif',
 'Autorise l''écran natif Mes disponibilités de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_parrainage_actif',1,'App iOS — écran Parrainage actif',
 'Autorise l''écran natif Parrainage de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_litiges_actif',1,'App iOS — écran Litiges actif',
 'Autorise l''écran natif Litiges de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_reclamations_actif',1,'App iOS — écran Réclamations actif',
 'Autorise l''écran natif Réclamations de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_messagerie_actif',1,'App iOS — écran Messagerie actif',
 'Autorise l''écran natif Messagerie de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_bulletins_actif',1,'App iOS — écran Bulletins de paie actif',
 'Autorise l''écran natif Bulletins de paie (copies déposées par l''employeur, en lecture) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_evaluations_actif',1,'App iOS — écran Évaluations actif',
 'Autorise l''écran natif Évaluations (évaluations reçues) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_score_actif',1,'App iOS — écran Mon score actif',
 'Autorise l''écran natif Mon score (score de fiabilité et contestation d''un événement) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_pool_urgence_actif',1,'App iOS — écran Pool urgence actif',
 'Autorise l''écran natif Pool urgence (missions urgentes) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_exclusions_actif',1,'App iOS — écran Établissements exclus actif',
 'Autorise l''écran natif Établissements exclus (exclusions envoyées et reçues) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_serie_actif',1,'App iOS — écran Détail de série actif',
 'Autorise l''écran natif Détail de série (acceptation des missions d''une série) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

-- Lot 5 — espace établissement

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_accueil_actif',1,'App iOS — écran établissement Accueil actif',
 'Autorise l''écran natif Accueil de l''espace établissement (actions prioritaires) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_missions_actif',1,'App iOS — écran établissement Missions actif',
 'Autorise l''écran natif Missions de l''espace établissement (liste, détail et candidatures) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_publier_actif',1,'App iOS — écran établissement Publier une mission actif',
 'Autorise l''écran natif Publier une mission (simple ou urgente) de l''espace établissement de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_presences_actif',1,'App iOS — écran établissement Présences actif',
 'Autorise l''écran natif Présences de l''espace établissement (validation et contestation) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_pointage_actif',1,'App iOS — écran établissement Pointage actif',
 'Autorise l''écran natif Pointage de l''espace établissement (code de pointage rotatif et QR plein écran) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_messages_actif',1,'App iOS — écran établissement Messages actif',
 'Autorise l''écran natif Messages (messagerie) de l''espace établissement de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_compte_actif',1,'App iOS — écran établissement Compte actif',
 'Autorise l''écran natif Compte de l''espace établissement de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;
