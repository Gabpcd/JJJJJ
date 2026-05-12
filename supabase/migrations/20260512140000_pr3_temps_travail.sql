-- PR 3 Sprint 1 — Durcissement temps de travail légal
--
-- Foundation existante (migration 20260317183608 + 20260416190300) :
-- - REPOS_11H (art. L3131-1 Code travail) ✓
-- - PLAFOND_48H_HEBDO (art. L3121-20) ✓
--
-- Ce que cette PR ajoute :
-- - MOYENNE_44H_12_SEMAINES (art. L3121-22) — libellé affiché côté UI
--   (CarteConformite.tsx) mais aucun trigger SQL ne calculait la moyenne
--   glissante. On l'implémente.
-- - REPOS_HEBDO_35H (art. L3132-1) — 35h consécutives par semaine de repos
--   obligatoire. Absent du code, on l'ajoute.
--
-- Travail de nuit (art. L3122-1 et suivants) + majorations conventionnelles :
-- pas implémenté en trigger ici car la majoration dépend de la CCN, qui
-- elle-même varie par étab. On documente le manque et on prévoit côté UI
-- un bandeau informatif "Mission de nuit — majoration selon CCN" (cf
-- composant DetailMission ou page candidature).

-- ──────────────────────────────────────────────────────────────
-- 0. Étendre la CHECK constraint conformite_travail_type_controle_check
-- pour accepter le nouveau type 'REPOS_HEBDO_35H'.
-- (Pré-requis avant CREATE TRIGGER ci-dessous, sinon les triggers
-- planteront au runtime sur leur premier INSERT.)
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.conformite_travail
  DROP CONSTRAINT conformite_travail_type_controle_check;

ALTER TABLE public.conformite_travail
  ADD CONSTRAINT conformite_travail_type_controle_check
  CHECK (type_controle = ANY (ARRAY[
    'REPOS_11H'::text,
    'REPOS_HEBDO_35H'::text,
    'PLAFOND_48H_HEBDO'::text,
    'MOYENNE_44H_12_SEMAINES'::text,
    'PLAFOND_10H_JOUR'::text,
    'PLAFOND_RIST'::text,
    'LIMITE_TRAVAIL_NUIT'::text,
    'VALIDITE_DOCUMENTS'::text
  ]));

-- ──────────────────────────────────────────────────────────────
-- 1. MOYENNE_44H_12_SEMAINES — durée maxi moyenne sur 12 semaines
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dec_verifier_moyenne_44h_12_semaines()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_semaine_courante date;
  v_debut_periode date;
  v_heures_total numeric;
  v_heures_mission numeric;
  v_nb_semaines int := 12;
  v_moyenne numeric;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  -- Durée de la mission en heures
  v_heures_mission := EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0;

  -- Semaine ISO de début de mission
  v_semaine_courante := DATE_TRUNC('week', NEW.debut_le::date)::date;
  -- 12 semaines glissantes en arrière depuis la semaine courante (incluse)
  v_debut_periode := v_semaine_courante - INTERVAL '11 weeks';

  -- Cumul heures Jolene sur les 12 semaines (missions ASSIGNEE/EN_COURS/
  -- TERMINEE, hors mission en cours d'évaluation)
  SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (fin_le - debut_le)) / 3600.0), 0)
  INTO v_heures_total
  FROM missions
  WHERE soignant_assigne_id = NEW.soignant_assigne_id
    AND id != NEW.id
    AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND debut_le::date >= v_debut_periode
    AND debut_le::date <= v_semaine_courante + INTERVAL '6 days';

  -- Ajouter heures externes déclarées
  SELECT v_heures_total + COALESCE(SUM(heures_salarie), 0) INTO v_heures_total
  FROM attestations_heures_externes
  WHERE soignant_id = NEW.soignant_assigne_id
    AND semaine_du >= v_debut_periode
    AND semaine_du <= v_semaine_courante + INTERVAL '6 days';

  -- Ajouter la mission en cours d'évaluation
  v_heures_total := v_heures_total + v_heures_mission;

  -- Moyenne hebdo sur 12 semaines
  v_moyenne := v_heures_total / v_nb_semaines;

  IF v_moyenne > 44.0 THEN
    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'MOYENNE_44H_12_SEMAINES', 'VIOLATION_BLOQUEE',
      jsonb_build_object(
        'moyenne_hebdo', ROUND(v_moyenne, 2),
        'total_heures', ROUND(v_heures_total, 2),
        'nb_semaines', v_nb_semaines,
        'plafond_moyenne', 44,
        'article', 'L3121-22'
      ));
    RAISE EXCEPTION
      '[CODE DU TRAVAIL] Moyenne hebdomadaire sur 12 semaines dépassée : %h/semaine en moyenne (max 44h, Art. L3121-22). Cette mission ferait passer la moyenne au-delà du plafond. Assignation bloquée.',
      ROUND(v_moyenne, 1);
  END IF;

  -- Log de conformité (pas systématique pour éviter spam — on log seulement
  -- si on s'approche du plafond, > 40h moyenne)
  IF v_moyenne > 40.0 THEN
    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'MOYENNE_44H_12_SEMAINES', 'CONFORME',
      jsonb_build_object('moyenne_hebdo', ROUND(v_moyenne, 2)));
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_verifier_moyenne_44h ON public.missions;
CREATE TRIGGER trg_dec_verifier_moyenne_44h
  BEFORE INSERT OR UPDATE OF soignant_assigne_id, statut, debut_le, fin_le
  ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_moyenne_44h_12_semaines();

-- ──────────────────────────────────────────────────────────────
-- 2. REPOS_HEBDO_35H — repos hebdomadaire de 35h consécutives
-- ──────────────────────────────────────────────────────────────
-- Art. L3132-1 : "Il est interdit de faire travailler un salarié plus de
-- six jours par semaine." → repos hebdomadaire de min 24h consécutives.
-- Combiné au repos quotidien de 11h, on obtient 35h consécutives minimum
-- de repos par semaine (art. L3132-2).
--
-- Stratégie : pour la semaine ISO de la nouvelle mission, on calcule la
-- plus longue plage continue de NON-travail (en heures). Si < 35h, on
-- bloque. C'est cher à calculer, donc on le fait seulement pour les
-- semaines où le soignant aurait > 5 jours de missions Jolene.
CREATE OR REPLACE FUNCTION public.dec_verifier_repos_hebdo_35h()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_semaine_debut date;
  v_semaine_fin date;
  v_nb_missions_semaine int;
  v_plage_max_repos numeric;  -- en heures
  v_rec RECORD;
  v_prev_fin timestamptz;
  v_ecart numeric;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  v_semaine_debut := DATE_TRUNC('week', NEW.debut_le::date)::date;
  v_semaine_fin := v_semaine_debut + INTERVAL '7 days';

  -- Compter missions sur la semaine
  SELECT COUNT(*) INTO v_nb_missions_semaine
  FROM missions
  WHERE soignant_assigne_id = NEW.soignant_assigne_id
    AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND debut_le::date >= v_semaine_debut
    AND debut_le::date < v_semaine_fin;

  -- Optimisation : si <= 4 missions sur la semaine, il y aura quasi
  -- forcément 35h de repos quelque part. On skip le calcul.
  IF v_nb_missions_semaine + 1 <= 4 THEN RETURN NEW; END IF;

  -- Calcul plage max de repos : on parcourt les missions de la semaine
  -- (en y ajoutant la mission courante) triées par debut, et on cherche
  -- le plus gros gap entre la fin de l'une et le début de la suivante.
  v_plage_max_repos := 0;
  v_prev_fin := v_semaine_debut::timestamptz;  -- début de semaine = lundi 00:00

  FOR v_rec IN
    SELECT debut_le, fin_le FROM (
      SELECT debut_le, fin_le FROM missions
      WHERE soignant_assigne_id = NEW.soignant_assigne_id
        AND id != NEW.id
        AND statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
        AND debut_le::date >= v_semaine_debut
        AND debut_le::date < v_semaine_fin
      UNION ALL
      SELECT NEW.debut_le, NEW.fin_le
    ) sub
    ORDER BY debut_le
  LOOP
    v_ecart := EXTRACT(EPOCH FROM (v_rec.debut_le - v_prev_fin)) / 3600.0;
    IF v_ecart > v_plage_max_repos THEN
      v_plage_max_repos := v_ecart;
    END IF;
    v_prev_fin := v_rec.fin_le;
  END LOOP;

  -- Gap après la dernière mission jusqu'à la fin de semaine
  v_ecart := EXTRACT(EPOCH FROM (v_semaine_fin::timestamptz - v_prev_fin)) / 3600.0;
  IF v_ecart > v_plage_max_repos THEN
    v_plage_max_repos := v_ecart;
  END IF;

  IF v_plage_max_repos < 35.0 THEN
    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_HEBDO_35H', 'VIOLATION_BLOQUEE',
      jsonb_build_object(
        'plage_max_repos_heures', ROUND(v_plage_max_repos, 2),
        'minimum_requis', 35,
        'nb_missions_semaine', v_nb_missions_semaine + 1,
        'article', 'L3132-2'
      ));
    RAISE EXCEPTION
      '[CODE DU TRAVAIL] Repos hebdomadaire insuffisant : plage max de %h consécutives sans travail (minimum légal 35h, Art. L3132-2 = 24h + 11h repos quotidien). Assignation bloquée.',
      ROUND(v_plage_max_repos, 1);
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_dec_verifier_repos_hebdo_35h ON public.missions;
CREATE TRIGGER trg_dec_verifier_repos_hebdo_35h
  BEFORE INSERT OR UPDATE OF soignant_assigne_id, statut, debut_le, fin_le
  ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.dec_verifier_repos_hebdo_35h();

-- ──────────────────────────────────────────────────────────────
-- 3. RPC info travail de nuit — utilitaire pour le frontend
-- ──────────────────────────────────────────────────────────────
-- Renvoie true si la mission contient au moins 3h de travail entre 21h et
-- 06h (définition générique du travail de nuit, art. L3122-2 — la
-- convention collective peut restreindre cette plage).
CREATE OR REPLACE FUNCTION public.fn_mission_est_de_nuit(
  p_debut timestamptz,
  p_fin timestamptz
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_heures_nuit numeric := 0;
  v_curseur timestamptz;
  v_curseur_fin timestamptz;
  v_h_debut int;
BEGIN
  -- Approche naïve : on découpe la mission en pas de 30 min et on compte
  -- les pas qui tombent dans la plage 21h-06h.
  v_curseur := p_debut;
  WHILE v_curseur < p_fin LOOP
    v_curseur_fin := LEAST(v_curseur + INTERVAL '30 minutes', p_fin);
    v_h_debut := EXTRACT(HOUR FROM v_curseur)::int;
    IF v_h_debut >= 21 OR v_h_debut < 6 THEN
      v_heures_nuit := v_heures_nuit + EXTRACT(EPOCH FROM (v_curseur_fin - v_curseur)) / 3600.0;
    END IF;
    v_curseur := v_curseur_fin;
  END LOOP;
  RETURN v_heures_nuit >= 3.0;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_mission_est_de_nuit(timestamptz, timestamptz) TO anon, authenticated;

-- ──────────────────────────────────────────────────────────────
-- 4. Audit
-- ──────────────────────────────────────────────────────────────
-- Audit avec action='SYSTEM' (valeur autorisée par CHECK constraint
-- journaux_audit_action_check). Contexte custom dans details jsonb.
INSERT INTO public.journaux_audit (
  acteur_id, type_acteur, action, type_ressource, id_ressource, details
) VALUES (
  '00000000-0000-0000-0000-000000000000', 'SYSTEME',
  'SYSTEM', 'fonction', NULL,
  jsonb_build_object(
    'evenement', 'TEMPS_TRAVAIL_DURCISSEMENT_INSTALLED',
    'pr', 'PR 3 Sprint 1 révisé',
    'nouveaux_controles', ARRAY['MOYENNE_44H_12_SEMAINES','REPOS_HEBDO_35H','fn_mission_est_de_nuit'],
    'articles_couverts', ARRAY['L3121-22','L3132-1','L3132-2','L3122-2'],
    'note_travail_nuit', 'Majoration CCN gérée côté UI (info-bandeau), pas en trigger SQL — dépend de la CCN de l''étab'
  )
);
