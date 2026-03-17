-- Mettre à jour les emails dans auth.users (email + metadata)
UPDATE auth.users SET email = 'admin@jolene.app', raw_user_meta_data = raw_user_meta_data || '{"email":"admin@jolene.app"}'::jsonb WHERE email = 'admin@joleneapp.com';
UPDATE auth.users SET email = 'test@jolene.app', raw_user_meta_data = raw_user_meta_data || '{"email":"test@jolene.app"}'::jsonb WHERE email = 'test@joleneapp.com';
UPDATE auth.users SET email = 'etab@jolene.app', raw_user_meta_data = raw_user_meta_data || '{"email":"etab@jolene.app"}'::jsonb WHERE email = 'etab@joleneapp.com';

-- Mettre à jour identity_data dans auth.identities (email est généré automatiquement)
UPDATE auth.identities SET identity_data = identity_data || '{"email":"admin@jolene.app"}'::jsonb WHERE identity_data->>'email' = 'admin@joleneapp.com';
UPDATE auth.identities SET identity_data = identity_data || '{"email":"test@jolene.app"}'::jsonb WHERE identity_data->>'email' = 'test@joleneapp.com';
UPDATE auth.identities SET identity_data = identity_data || '{"email":"etab@jolene.app"}'::jsonb WHERE identity_data->>'email' = 'etab@joleneapp.com';
