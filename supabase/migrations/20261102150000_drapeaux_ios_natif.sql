-- Lot 1 app iOS native (B0) — drapeaux ios_natif_<ecran>_actif.
--
-- Décision 9 du lot 0 (docs/mobile-swift/DECISIONS_LOT0.md) : un écran natif cassé
-- doit pouvoir être désactivé à chaud, l'app affichant alors un renvoi vers le web.
-- L'app lit ces clés via la RPC existante fn_param_bool(p_cle, p_defaut) après
-- ouverture de session (aucun GRANT anon ; grants existants : authenticated +
-- service_role). Sans ligne en base, fn_param_bool renvoie p_defaut et
-- fn_admin_maj_parametre répond « Paramètre inconnu » : l'administrateur ne peut
-- pas créer la clé depuis l'interface, d'où ces cinq lignes.
--
-- Modèle : 20260925121402_decouverte_api_alertes_recherches.sql (INSERT idempotent,
-- ON CONFLICT (cle) DO NOTHING). Jamais DO UPDATE : un rejeu ne doit pas réarmer
-- un écran coupé en urgence par l'administrateur.
--
-- Écrans = les cinq onglets du socle (ios-native/Jolene/Screens/MainTabView.swift) :
-- accueil, explorer, missions, revenus, profil. Catégorie OPERATIONS : seule façon
-- d'apparaître dans AdminConfig (src/pages/admin/AdminConfig.tsx, CATEGORIES).
-- Bornes 0/1 : fn_admin_maj_parametre refuse toute autre valeur ; fn_param_bool
-- lit « valeur <> 0 ». valeur 1 = écran actif (défaut fail-open côté app).

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_accueil_actif',1,'App iOS — écran Accueil actif',
 'Autorise l''écran natif Accueil de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_explorer_actif',1,'App iOS — écran Explorer actif',
 'Autorise l''écran natif Explorer (missions ouvertes) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_missions_actif',1,'App iOS — écran Mes missions actif',
 'Autorise l''écran natif Mes missions (candidatures, à venir, passées) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_revenus_actif',1,'App iOS — écran Revenus actif',
 'Autorise l''écran natif Revenus de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_profil_actif',1,'App iOS — écran Profil actif',
 'Autorise l''écran natif Profil (compte) de l''application iOS. À 0, l''app affiche un renvoi vers la version web à la place de cet écran.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''écran natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;
