UPDATE auth.users 
SET raw_app_meta_data = raw_app_meta_data || '{"role": "ADMIN_PLATEFORME"}'::jsonb 
WHERE id = 'df0ad65f-df4e-435e-900b-a792720dd985';