-- Découverte via l'API existante fn_param_bool : l'ancien backend renvoie false
-- pour cette clé absente et le frontend n'appelle pas de RPC encore inexistante.
-- Cette annonce ne remplace pas la capacité par compte et le heartbeat du worker.
INSERT INTO public.parametres_systeme(cle,valeur,label,description,unite,val_min,val_max,categorie,avertissement,cablee)
VALUES('api_alertes_recherches_v1',1,'API des alertes de recherches disponible',
 'Annonce la présence du contrat v1. Le serveur vérifie encore le compte, son périmètre et un worker de moins de trois heures.',
 'booléen',0,1,'GENERAL','Indicateur de déploiement : ne rend pas une alerte disponible sans contrôle du worker.',true)
ON CONFLICT(cle) DO NOTHING;
