-- Pré-lancement : le centre d'aide doit décrire le runtime réel. Les articles
-- dont les garanties ne sont pas démontrées sont dépubliés, pas supprimés :
-- leur contenu reste disponible à l'équipe pour réécriture.

UPDATE public.articles_aide
SET publie = false,
    mis_a_jour_le = now()
WHERE slug IN (
  'comment-jolene-assure-securite',
  'cgu-jolene',
  'parrainage-soignant'
);

UPDATE public.articles_aide
SET contenu = replace(
      replace(
        contenu,
        '4. L''app capture votre **position GPS** (consentement obligatoire à l''inscription)',
        '4. Si vous avez accepté la géolocalisation, l''app joint votre **position GPS**. En cas de refus, le pointage reste possible et l''établissement le valide manuellement.'
      ),
      'Vous pouvez retirer votre consentement à tout moment dans **Profil → Confidentialité**.',
      'Vous pouvez retirer votre consentement à tout moment dans **Profil → Préférences**. Le pointage sans GPS reste disponible.'
    ),
    mis_a_jour_le = now()
WHERE slug = 'comment-fonctionne-pointage';

UPDATE public.articles_aide
SET contenu = replace(
      contenu,
      '- **Tous vos documents valides** : diplôme, identité, RCP (responsabilité civile professionnelle) si applicable. Si un document expire pendant la mission, vous serez bloqué.',
      '- **Un profil permettant la candidature** : identité de base et profession vérifiée. Les documents requis doivent être valides avant l''affectation définitive et la réalisation de la mission.'
    ),
    mis_a_jour_le = now()
WHERE slug = 'comment-candidater-mission';

UPDATE public.articles_aide
SET contenu = replace(
      contenu,
      '⚠️ La page de recherche soignants côté établissement arrive prochainement. Vous pouvez gérer/supprimer vos filtres existants dans **Paramètres → Mes recherches sauvegardées**, mais la création de nouveaux filtres pour cette audience est limitée pour l''instant.',
      'La recherche soignants est disponible dans **Soignants → Annuaire**. Appliquez vos critères puis enregistrez la recherche pour la retrouver et activer ses alertes.'
    ),
    mis_a_jour_le = now()
WHERE slug = 'sauvegarder-recherches-alertes';

UPDATE public.articles_aide
SET contenu = replace(
      replace(
        contenu,
        '**Profil → Confidentialité → Télécharger mes données**',
        '**Profil → Confidentialité → Télécharger mes données**'
      ),
      '**Profil → Confidentialité → Supprimer mon compte**',
      '**Mon compte → Supprimer mon compte**'
    ),
    mis_a_jour_le = now()
WHERE slug IN ('mes-droits-rgpd', 'mes-droits-rgpd-soignant');

UPDATE public.articles_aide
SET contenu = replace(
      contenu,
      'Allez sur **Profil → Mandat de facturation**',
      'Allez sur **Mon compte → Mandat de facturation**'
    ),
    mis_a_jour_le = now()
WHERE slug = 'signer-mandat-facturation';

-- Les comptes de test restent visibles dans leurs espaces connectés pour les
-- captures stores, mais ne sont jamais exposés dans Google Jobs ou le sitemap.
CREATE OR REPLACE FUNCTION public.fn_mission_publique(p_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT to_jsonb(t) FROM (
    SELECT m.id, m.intitule, left(coalesce(m.description, ''), 1500) AS description,
           m.profession_requise::text, m.debut_le, m.fin_le, m.taux_horaire_base,
           m.est_urgente, m.service, m.cree_le, m.modifie_le,
           e.nom AS etablissement_nom, e.type::text AS etablissement_type,
           e.adresse_ville::text AS ville, e.adresse_code_postal::text AS code_postal
    FROM public.missions m
    JOIN public.etablissements e ON e.id = m.etablissement_id
    WHERE m.id = p_id
      AND m.statut = 'OUVERTE'
      AND m.debut_le > now()
      AND e.supprime_le IS NULL
      AND e.est_compte_test = false
      AND e.statut_verification = 'VERIFIE'
      AND e.peut_publier_missions = true
  ) t;
$$;

REVOKE ALL ON FUNCTION public.fn_mission_publique(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mission_publique(uuid) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_missions_ouvertes_sitemap()
RETURNS TABLE(id uuid, maj timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT m.id, greatest(m.cree_le, coalesce(m.modifie_le, m.cree_le)) AS maj
  FROM public.missions m
  JOIN public.etablissements e ON e.id = m.etablissement_id
  WHERE m.statut = 'OUVERTE'
    AND m.debut_le > now()
    AND e.supprime_le IS NULL
    AND e.est_compte_test = false
    AND e.statut_verification = 'VERIFIE'
    AND e.peut_publier_missions = true
  ORDER BY m.cree_le DESC
  LIMIT 2000;
$$;

REVOKE ALL ON FUNCTION public.fn_missions_ouvertes_sitemap() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_missions_ouvertes_sitemap() TO service_role;
