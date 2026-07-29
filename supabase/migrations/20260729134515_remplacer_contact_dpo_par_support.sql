-- Le contact protection des données utilise la boîte support unique.
-- Cette mise à jour corrige également les articles d'aide créés par les
-- anciennes migrations archivées, sans modifier leurs autres contenus.
UPDATE public.articles_aide
SET contenu = replace(contenu, 'dpo@' || 'jolene.app', 'support@jolene.app')
WHERE strpos(contenu, 'dpo@' || 'jolene.app') > 0;
