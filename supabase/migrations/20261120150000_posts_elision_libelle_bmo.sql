-- Posts de l'agent de croissance : élision dans la phrase BMO.
--
-- Le brouillon écrivait « projets de recrutement de aides-soignants ». La préposition suit
-- maintenant le libellé : « d'aides-soignants », « de médecins ».
--
-- Redéfinition partie de la définition LIVE (garde-fou 9.0) : au 20/11/2026, md5(prosrc) en
-- production = c98f830980520adae5b85910b09fc277, identique au corps de 20261109140000.
-- Seuls changent la variable v_de_libelle et la phrase BMO. CREATE OR REPLACE conserve les
-- droits (EXECUTE réservé à postgres) : aucun GRANT ni REVOKE ici.
--
-- Inchangé : la phrase n'est produite que pour une ligne bmo_precision = 'EXACT' dont la part
-- est publiée. Les infirmiers (catégorie BMO commune avec les sages-femmes, 'AGREGAT') ne sont
-- donc jamais cités.

CREATE OR REPLACE FUNCTION private.fn_growth_agent_posts()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $body$
DECLARE
  v_depts text[] := private.fn_growth_config_liste('agents_departements_cibles', '75,92,56');
  v_semaine text := to_char(now() AT TIME ZONE 'Europe/Paris', 'IYYY-"S"IW');
  v_angle integer := (extract(week FROM now() AT TIME ZONE 'Europe/Paris')::integer % 3);
  v_dept text;
  v_prof text;
  v_n integer;
  v_crees integer := 0;
  v_nb integer;
  v_taux numeric;
  v_bmo record;
  v_lien text;
  v_corps text;
  v_groupes jsonb;
  v_de_libelle text;
BEGIN
  FOREACH v_dept IN ARRAY v_depts LOOP
    FOREACH v_prof IN ARRAY ARRAY['AS', 'IDE'] LOOP
      -- « d'aides-soignants », « de médecins » : élision devant une voyelle.
      v_de_libelle := CASE
        WHEN lower(left(private.fn_growth_libelle_profession(v_prof, true), 1)) IN ('a', 'e', 'é', 'è', 'ê', 'i', 'o', 'u', 'y')
        THEN 'd''' ELSE 'de ' END || private.fn_growth_libelle_profession(v_prof, true);

      SELECT count(*), max(m.taux_horaire_base) INTO v_nb, v_taux
      FROM private.fn_growth_missions_reelles() m
      JOIN public.etablissements e ON e.id = m.etablissement_id
      WHERE m.statut = 'OUVERTE' AND m.debut_le > now()
        AND m.profession_requise::text = v_prof
        AND e.adresse_departement = v_dept
        AND public.fn_mission_publique(m.id) IS NOT NULL;

      SELECT t.bmo_projets_recrutement AS projets, round(t.bmo_difficulte_pct) AS pct, t.bmo_annee AS annee
        INTO v_bmo
      FROM public.acquisition_territoires t
      WHERE t.departement = v_dept AND t.profession = v_prof AND t.bmo_precision = 'EXACT'
        AND t.bmo_projets_recrutement > 0 AND t.bmo_difficulte_pct IS NOT NULL;

      SELECT COALESCE(jsonb_agg(jsonb_build_object('nom', g.nom, 'url', g.url, 'membres', g.membres)
               ORDER BY g.favori DESC, g.membres DESC NULLS LAST), '[]'::jsonb)
        INTO v_groupes
      FROM (
        SELECT sg.nom, sg.url, sg.membres, sg.favori
        FROM public.sales_groupes sg
        WHERE sg.plateforme = 'FACEBOOK'
          AND sg.profession IN (v_prof, 'TOUTES')
          AND COALESCE(sg.audience, 'MIXTE') IN ('SOIGNANTS', 'MIXTE')
          AND COALESCE(sg.statut, '') <> 'INACTIF'
        ORDER BY sg.favori DESC, sg.membres DESC NULLS LAST
        LIMIT 5
      ) g;

      v_lien := private.fn_growth_lien('/devenir-soignant', 'facebook', 'social',
        'agent-posts', v_dept || '-' || lower(v_prof) || '-' || v_semaine);

      IF v_nb > 0 THEN
        v_corps := concat_ws(E'\n\n',
          format('%s du %s : %s mission%s à pourvoir en ce moment sur Jolene%s.',
            private.fn_growth_majuscule(private.fn_growth_libelle_profession(v_prof, true)), v_dept, v_nb,
            CASE WHEN v_nb > 1 THEN 's' ELSE '' END,
            CASE WHEN v_taux IS NOT NULL THEN format(', jusqu''à %s €/h', trim(to_char(v_taux, 'FM999990.00'))) ELSE '' END),
          'Vacations, CDD courts et remplacements auprès d''établissements de santé. Inscription gratuite, contrats générés automatiquement.',
          'Voir les missions et s''inscrire : ' || v_lien);
      ELSE
        v_corps := concat_ws(E'\n\n',
          format('%s du %s : inscrivez-vous gratuitement sur Jolene et soyez prévenu dès qu''un établissement proche de chez vous publie une mission (vacation, CDD court, remplacement).',
            private.fn_growth_majuscule(private.fn_growth_libelle_profession(v_prof, true)), v_dept),
          CASE WHEN v_bmo.projets IS NOT NULL THEN format(
            'Pour information, France Travail recense %s projets de recrutement %s dans le %s en %s, dont %s %% jugés difficiles par les employeurs (enquête BMO).',
            v_bmo.projets, v_de_libelle, v_dept, v_bmo.annee, v_bmo.pct) END,
          'Créer son profil en 2 minutes : ' || v_lien);
      END IF;

      INSERT INTO public.growth_brouillons (
        agent, canal, cible_type, departement, profession, corps, lien, contexte,
        idempotence_key, expire_le
      ) VALUES (
        'POST_SOCIAL', 'FACEBOOK_GROUPE', 'PUBLIC', v_dept, v_prof, v_corps, v_lien,
        jsonb_build_object('semaine', v_semaine, 'missions_ouvertes_reelles', v_nb,
          'groupes_suggeres', v_groupes,
          'regle', 'Publication manuelle uniquement : pas d''auto-post, pas de scraping des membres.'),
        'posts:' || v_semaine || ':fb:' || v_dept || ':' || v_prof,
        now() + interval '7 days'
      )
      ON CONFLICT (idempotence_key) DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_crees := v_crees + v_n;
    END LOOP;
  END LOOP;

  -- Un post LinkedIn fondatrice par semaine, cible établissements.
  v_lien := private.fn_growth_lien('/recruter-soignants', 'linkedin', 'social',
    'agent-posts', 'etablissements-' || v_semaine);
  v_corps := CASE v_angle
    WHEN 0 THEN concat_ws(E'\n\n',
      'Un arrêt maladie à 6 h du matin, un week-end à couvrir, des congés qui se chevauchent : dans beaucoup d''EHPAD et de structures médico-sociales, le remplacement se joue au téléphone, au dernier moment.',
      'Avec Jolene, vous publiez la mission en quelques minutes et les soignants candidatent directement. Contrats et facturation sont générés automatiquement.',
      'Nous démarrons en Île-de-France et dans le Morbihan. Si vous dirigez un établissement et voulez tester sur votre prochaine absence, écrivez-moi : je publie la première mission avec vous.',
      v_lien)
    WHEN 1 THEN concat_ws(E'\n\n',
      'Une question que me posent les directeurs d''établissement : « combien ça coûte ? »',
      'Sur Jolene : 15 % HT de commission sur le montant de la mission, sans abonnement ni frais d''entrée. Vous ne payez que si vous recrutez. Pas de marge d''agence.',
      'Nous ouvrons la plateforme établissement par établissement en Île-de-France et dans le Morbihan, avec un accompagnement personnel pour la première mission.',
      v_lien)
    ELSE concat_ws(E'\n\n',
      'Recruter un renfort, c''est aussi vérifier : identité, diplôme, numéro RPPS lorsqu''il existe.',
      'Sur Jolene, l''identité et les qualifications professionnelles des soignants sont contrôlées, notamment via le RPPS lorsqu''il existe, et vous gardez la décision finale sur chaque candidature.',
      'Vous dirigez un EHPAD, un centre de santé ou une structure médico-sociale en Île-de-France ou dans le Morbihan ? Parlons de votre prochaine absence à couvrir.',
      v_lien)
  END;
  INSERT INTO public.growth_brouillons (
    agent, canal, cible_type, corps, lien, contexte, idempotence_key, expire_le
  ) VALUES (
    'POST_SOCIAL', 'LINKEDIN', 'PUBLIC', v_corps, v_lien,
    jsonb_build_object('semaine', v_semaine, 'angle', v_angle,
      'cible', 'Directions d''établissements (profil LinkedIn de la fondatrice)'),
    'posts:' || v_semaine || ':linkedin', now() + interval '7 days'
  )
  ON CONFLICT (idempotence_key) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_crees := v_crees + v_n;

  RETURN jsonb_build_object('brouillons_crees', v_crees, 'semaine', v_semaine);
END;
$body$;
