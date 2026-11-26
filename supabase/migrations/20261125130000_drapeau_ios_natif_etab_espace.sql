-- Lot 5, T14 de l'app iOS native (M1 de la revue fraîche de #1190) — coupe-circuit
-- de l'espace établissement ENTIER : drapeau ios_natif_etab_espace_actif.
--
-- Même gabarit que B0 (20261102150000_drapeaux_ios_natif.sql) et D-FLAGS
-- (20261102204450_drapeaux_ios_natif_lots_2_4_5.sql) : une ligne
-- parametres_systeme, valeur 1, bornes 0/1, catégorie OPERATIONS (visible dans
-- AdminConfig, modifiable par fn_admin_maj_parametre), cablee true. L'app la lit
-- via la RPC existante fn_param_bool(p_cle, p_defaut) (grants existants :
-- authenticated + service_role, aucun GRANT anon ; aucune fonction créée ici).
--
-- Différence avec les sept drapeaux ios_natif_etab_<ecran>_actif : ceux-ci coupent
-- un écran (renvoi web à sa place) ; celui-ci ferme l'espace établissement entier.
-- À 0, un compte établissement reçoit l'écran « Espace non disponible » et le
-- renvoi vers jolene.app, exactement comme avant l'ouverture de T14, sans aucun
-- appel établissement (fn_mes_permissions_etab n'est pas appelée). Lu à chaque
-- résolution de session : connexion, lancement et retour au premier plan.
-- Absent ou illisible : l'app garde l'espace ouvert (fail-open, comme les sept
-- autres ; docs/mobile-swift/DECISIONS_LOT5.md, section T14).
--
-- ON CONFLICT (cle) DO NOTHING, jamais DO UPDATE : un rejeu ne doit pas réarmer
-- un espace coupé en urgence par l'administrateur.
-- Garde : src/lib/__tests__/drapeauxIosNatifMigration.test.ts (29 clés au total).

INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('ios_natif_etab_espace_actif',1,'App iOS — espace établissement actif',
 'Autorise l''espace établissement entier de l''application iOS. À 0, un compte établissement voit « Espace non disponible » et un renvoi vers la version web, sans aucun écran natif établissement.',
 'booléen',0,1,'OPERATIONS','Coupe-circuit : passez à 0 uniquement si l''espace établissement natif est cassé. Lu par l''app à l''ouverture de session et au retour au premier plan.',true)
ON CONFLICT(cle) DO NOTHING;
