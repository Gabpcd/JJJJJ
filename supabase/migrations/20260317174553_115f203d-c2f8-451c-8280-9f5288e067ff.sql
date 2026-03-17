-- Mettre à jour les emails des comptes tests vers @jolene.app
UPDATE public.soignants SET email = 'test@jolene.app' WHERE email = 'test@joleneapp.com';
UPDATE public.etablissements SET email_contact = 'etab@jolene.app' WHERE email_contact = 'etab@joleneapp.com';
