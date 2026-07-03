CREATE OR REPLACE FUNCTION public.dec_verifier_plafond_48h()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_heures_mission numeric; v_heures_jolene numeric; v_heures_externes numeric;
  v_heures_total numeric; v_soignant RECORD; v_semaine_debut date; v_use_effectif boolean;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  SELECT * INTO v_soignant FROM soignants WHERE id = NEW.soignant_assigne_id;
  IF v_soignant.type_exercice = 'LIBERAL' THEN RETURN NEW; END IF;

  v_semaine_debut := date_trunc('week', NEW.debut_le)::date;

  v_use_effectif := EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL);
  IF v_use_effectif THEN
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0) INTO v_heures_mission
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause;
  ELSE
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (fin - debut)) / 3600.0), 0) INTO v_heures_mission
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND NOT est_pause;
  END IF;

  IF v_heures_mission = 0 AND NOT EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id) THEN
    v_heures_mission := COALESCE(NEW.duree_heures, EXTRACT(EPOCH FROM (NEW.fin_le - NEW.debut_le)) / 3600.0, 0);
  END IF;

  SELECT COALESCE(SUM(
    CASE WHEN EXISTS (SELECT 1 FROM mission_creneaux mc2 WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL)
      THEN (SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (mc3.fin - mc3.debut)) / 3600.0), 0)
            FROM mission_creneaux mc3 WHERE mc3.mission_id = m.id AND mc3.type_creneau = 'EFFECTIF' AND mc3.fin IS NOT NULL AND NOT mc3.est_pause)
      ELSE (SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (mc4.fin - mc4.debut)) / 3600.0), 0)
            FROM mission_creneaux mc4 WHERE mc4.mission_id = m.id AND mc4.type_creneau = 'PREVISIONNEL' AND NOT mc4.est_pause)
    END
  ), 0) INTO v_heures_jolene
  FROM missions m
  WHERE m.soignant_assigne_id = NEW.soignant_assigne_id AND m.id != NEW.id
    AND m.statut IN ('ASSIGNEE', 'EN_COURS', 'TERMINEE')
    AND m.debut_le >= v_semaine_debut::timestamptz
    AND m.debut_le < (v_semaine_debut + 7)::timestamptz;

  SELECT COALESCE(heures_salarie, 0) INTO v_heures_externes
  FROM attestations_heures_externes
  WHERE soignant_id = NEW.soignant_assigne_id AND semaine_du = v_semaine_debut;
  IF NOT FOUND THEN v_heures_externes := 0; END IF;

  v_heures_total := v_heures_jolene + v_heures_externes + v_heures_mission;

  IF v_heures_total > 48 THEN
    INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
    VALUES (NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'VIOLATION_BLOQUEE',
      jsonb_build_object('heures_jolene', ROUND(v_heures_jolene + v_heures_mission, 2),
        'heures_externes', ROUND(v_heures_externes, 2), 'total', ROUND(v_heures_total, 2),
        'plafond', 48, 'article', 'L3121-20'));
    RAISE EXCEPTION '[CODE DU TRAVAIL] Plafond hebdomadaire dépassé : %h Jolene + %h ailleurs = %h total (max 48h, Art. L3121-20)',
      ROUND(v_heures_jolene + v_heures_mission, 1), ROUND(v_heures_externes, 1), ROUND(v_heures_total, 1);
  END IF;

  INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
  VALUES (NEW.soignant_assigne_id, NEW.id, 'PLAFOND_48H_HEBDO', 'CONFORME',
    jsonb_build_object('total_heures', ROUND(v_heures_total, 2)));
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_expiration_documents()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM fn_calculer_tous_documents_valides(NEW.soignant_id);
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_docs_jusqua_fin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_doc_expire RECORD;
BEGIN
    -- Uniquement quand le soignant accepte (OUVERTE → ASSIGNEE)
    IF NEW.statut = 'ASSIGNEE' AND OLD.statut = 'OUVERTE' AND NEW.soignant_assigne_id IS NOT NULL THEN
        -- Vérifier que les docs critiques sont valides jusqu'à fin_le
        SELECT type_document, valide_jusqua INTO v_doc_expire
        FROM documents_soignants
        WHERE soignant_id = NEW.soignant_assigne_id
          AND est_critique = TRUE
          AND supprime_le IS NULL
          AND valide_jusqua IS NOT NULL
          AND valide_jusqua < NEW.fin_le::DATE
        LIMIT 1;

        IF v_doc_expire.type_document IS NOT NULL THEN
            RAISE EXCEPTION 'Votre document \"%\" expire le % — avant la fin de cette mission (%). Veuillez le renouveler.',
                v_doc_expire.type_document,
                TO_CHAR(v_doc_expire.valide_jusqua, 'DD/MM/YYYY'),
                TO_CHAR(NEW.fin_le, 'DD/MM/YYYY');
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_profession_etablissement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_type type_etablissement;
BEGIN
    SELECT type INTO v_type FROM etablissements WHERE id = NEW.etablissement_id;

    IF v_type = 'PHARMACIE_OFFICINE' THEN
        IF NEW.profession_requise NOT IN ('PHARMACIEN', 'PREPARATEUR_PHARMA') THEN
            RAISE EXCEPTION 'Une pharmacie d''officine ne peut publier que des missions pour pharmacien ou préparateur.';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_numerotation_facture()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_dernier_numero TEXT;
    v_dernier_seq INTEGER;
    v_nouveau_seq INTEGER;
BEGIN
    -- Extraire le séquentiel du dernier numéro
    SELECT numero_facture INTO v_dernier_numero
    FROM factures
    WHERE numero_facture LIKE 'SD-' || TO_CHAR(NOW(), 'YYYYMM') || '-%'
    ORDER BY cree_le DESC LIMIT 1;

    IF v_dernier_numero IS NOT NULL THEN
        v_dernier_seq := SPLIT_PART(v_dernier_numero, '-', 3)::INTEGER;
        v_nouveau_seq := SPLIT_PART(NEW.numero_facture, '-', 3)::INTEGER;
        IF v_nouveau_seq != v_dernier_seq + 1 THEN
            RAISE WARNING 'Saut de numérotation facture détecté : % → %', v_dernier_numero, NEW.numero_facture;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_evaluation_counterparty()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD;
    v_expected_evalue UUID;
    v_etab_id UUID;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = NEW.mission_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mission introuvable';
    END IF;

    v_etab_id := mon_etablissement_id();

    IF v_mission.soignant_assigne_id = NEW.evaluateur_id THEN
        -- Soignant évalue → doit évaluer l'établissement
        v_expected_evalue := v_mission.etablissement_id;
    ELSIF v_mission.etablissement_id = v_etab_id THEN
        -- Établissement évalue → doit évaluer le soignant
        v_expected_evalue := v_mission.soignant_assigne_id;
    ELSIF est_admin() THEN
        -- Admin peut évaluer
        NEW.visible := FALSE;
        RETURN NEW;
    ELSE
        RAISE EXCEPTION 'Vous n''avez pas participé à cette mission.';
    END IF;

    IF NEW.evalue_id != v_expected_evalue THEN
        RAISE EXCEPTION 'L''évaluation doit concerner l''autre partie de la mission.';
    END IF;

    -- Forcer visible = FALSE (modération admin)
    NEW.visible := FALSE;

    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_eligibilite_liberal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant RECORD;
    v_type_paiement TEXT;
BEGIN
    IF NEW.soignant_assigne_id IS NOT NULL AND NEW.statut = 'ASSIGNEE' AND OLD.statut = 'OUVERTE' THEN
        SELECT * INTO v_soignant FROM soignants WHERE id = NEW.soignant_assigne_id;

        -- Si le soignant est libéral, vérifier 3200h
        IF v_soignant.type_contrat = 'LIBERAL' THEN
            IF v_soignant.heures_cumulees < 3200 THEN
                RAISE EXCEPTION 'Vous devez cumuler 3 200 heures d''exercice pour accepter des missions en libéral. Vous avez actuellement % heures.', ROUND(v_soignant.heures_cumulees);
            END IF;
        END IF;

        -- Un libéral ne peut pas accepter une mission à bulletin de paie.
        -- On lit la valeur EN COURS d'application (NEW), pas la valeur périmée en table.
        v_type_paiement := NEW.type_paiement_soignant;
        IF v_soignant.type_contrat = 'LIBERAL' AND v_type_paiement = 'BULLETIN_PAIE' THEN
            RAISE EXCEPTION 'En tant que libéral, vous ne pouvez accepter que des missions de type vacation libérale.';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

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
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_repos_11h()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_fin_prev_work timestamptz; v_debut_this_work timestamptz; v_fin_this_work timestamptz;
  v_debut_next_work timestamptz; v_ecart numeric; v_use_effectif boolean;
BEGIN
  IF NEW.soignant_assigne_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.statut NOT IN ('ASSIGNEE', 'EN_COURS') THEN RETURN NEW; END IF;

  v_use_effectif := EXISTS (SELECT 1 FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL);
  IF v_use_effectif THEN
    SELECT MIN(debut), MAX(fin) INTO v_debut_this_work, v_fin_this_work
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'EFFECTIF' AND fin IS NOT NULL AND NOT est_pause;
  ELSE
    SELECT MIN(debut), MAX(fin) INTO v_debut_this_work, v_fin_this_work
    FROM mission_creneaux WHERE mission_id = NEW.id AND type_creneau = 'PREVISIONNEL' AND NOT est_pause;
  END IF;
  IF v_debut_this_work IS NULL THEN v_debut_this_work := NEW.debut_le; v_fin_this_work := NEW.fin_le; END IF;

  SELECT MAX(
    CASE WHEN EXISTS (SELECT 1 FROM mission_creneaux mc2 WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL)
      THEN (SELECT MAX(mc3.fin) FROM mission_creneaux mc3 WHERE mc3.mission_id = m.id AND mc3.type_creneau = 'EFFECTIF' AND mc3.fin IS NOT NULL AND NOT mc3.est_pause)
      ELSE (SELECT MAX(mc4.fin) FROM mission_creneaux mc4 WHERE mc4.mission_id = m.id AND mc4.type_creneau = 'PREVISIONNEL' AND NOT mc4.est_pause)
    END
  ) INTO v_fin_prev_work
  FROM missions m WHERE m.soignant_assigne_id = NEW.soignant_assigne_id AND m.id != NEW.id
    AND m.fin_le <= NEW.debut_le AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE');

  IF v_fin_prev_work IS NOT NULL THEN
    v_ecart := EXTRACT(EPOCH FROM (v_debut_this_work - v_fin_prev_work)) / 3600.0;
    IF v_ecart < 11.0 THEN
      INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
      VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'VIOLATION_BLOQUEE',
        jsonb_build_object('ecart_heures', ROUND(v_ecart, 2), 'minimum_requis', 11, 'sens', 'avant', 'article', 'L3131-1'));
      RAISE EXCEPTION '[CODE DU TRAVAIL] Repos insuffisant avant mission : % heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.', ROUND(v_ecart, 1);
    END IF;
  END IF;

  SELECT MIN(
    CASE WHEN EXISTS (SELECT 1 FROM mission_creneaux mc2 WHERE mc2.mission_id = m.id AND mc2.type_creneau = 'EFFECTIF' AND mc2.fin IS NOT NULL)
      THEN (SELECT MIN(mc3.debut) FROM mission_creneaux mc3 WHERE mc3.mission_id = m.id AND mc3.type_creneau = 'EFFECTIF' AND mc3.fin IS NOT NULL AND NOT mc3.est_pause)
      ELSE (SELECT MIN(mc4.debut) FROM mission_creneaux mc4 WHERE mc4.mission_id = m.id AND mc4.type_creneau = 'PREVISIONNEL' AND NOT mc4.est_pause)
    END
  ) INTO v_debut_next_work
  FROM missions m WHERE m.soignant_assigne_id = NEW.soignant_assigne_id AND m.id != NEW.id
    AND m.debut_le >= NEW.fin_le AND m.statut IN ('ASSIGNEE','EN_COURS','TERMINEE');

  IF v_debut_next_work IS NOT NULL THEN
    v_ecart := EXTRACT(EPOCH FROM (v_debut_next_work - v_fin_this_work)) / 3600.0;
    IF v_ecart < 11.0 THEN
      INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat, details_violation)
      VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'VIOLATION_BLOQUEE',
        jsonb_build_object('ecart_heures', ROUND(v_ecart, 2), 'minimum_requis', 11, 'sens', 'apres', 'article', 'L3131-1'));
      RAISE EXCEPTION '[CODE DU TRAVAIL] Repos insuffisant après mission : % heures au lieu de 11h minimum (Art. L3131-1). Assignation bloquée.', ROUND(v_ecart, 1);
    END IF;
  END IF;

  INSERT INTO conformite_travail (soignant_id, mission_id, type_controle, resultat)
  VALUES (NEW.soignant_assigne_id, NEW.id, 'REPOS_11H', 'CONFORME');
  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.est_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT COALESCE(
        (SELECT raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME' FROM auth.users WHERE id = auth.uid()),
        false
    );
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.est_admin_etablissement()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT (raw_app_meta_data ->> 'role') IN ('ADMIN_ETABLISSEMENT', 'ETABLISSEMENT')
     FROM auth.users
     WHERE id = auth.uid()),
    false
  );
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_type_contrat_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_type_contrat TEXT;
    v_type_paiement TEXT;
BEGIN
    IF NEW.soignant_assigne_id IS NOT NULL AND NEW.statut = 'ASSIGNEE' AND OLD.statut = 'OUVERTE' THEN
        SELECT type_contrat INTO v_type_contrat
        FROM soignants WHERE id = NEW.soignant_assigne_id;

        -- Valeur en cours d'application (NEW), pas la valeur périmée en table.
        v_type_paiement := NEW.type_paiement_soignant;

        IF v_type_contrat = 'LIBERAL' AND v_type_paiement = 'BULLETIN_PAIE' THEN
            RAISE EXCEPTION 'En tant que libéral, vous ne pouvez accepter que des missions de type vacation libérale.';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_type_exercice_profession()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_autorises TEXT[];
BEGIN
    -- Ne vérifier que si type_exercice ou profession change
    IF TG_OP = 'UPDATE' AND OLD.type_exercice = NEW.type_exercice AND OLD.profession = NEW.profession THEN
        RETURN NEW;
    END IF;
    
    -- Skip si system update
    IF current_setting('jolene.system_update', true) = 'true' THEN RETURN NEW; END IF;
    
    SELECT types_exercice_autorises INTO v_autorises
    FROM regles_exercice_profession WHERE profession = NEW.profession;
    
    -- Si pas de règle, autoriser tout
    IF v_autorises IS NULL THEN RETURN NEW; END IF;
    
    IF NOT (COALESCE(NEW.type_exercice, 'SALARIE') = ANY(v_autorises)) THEN
        RAISE EXCEPTION 'Le type d''exercice \"%\" n''est pas autorisé pour la profession \"%\". Types autorisés : %',
            NEW.type_exercice, NEW.profession, array_to_string(v_autorises, ', ');
    END IF;
    
    RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.est_admin_valide()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT COALESCE((SELECT raw_app_meta_data ->> 'role' = 'ADMIN_PLATEFORME' AND COALESCE(banned_until, '1970-01-01'::timestamptz) < now() AND email_confirmed_at IS NOT NULL FROM auth.users WHERE id = auth.uid()), false); $function$


---FIN-FONCTION---

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
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.dec_verifier_profession_etudiant()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_soignant RECORD;
  v_mission_prof TEXT;
BEGIN
  SELECT est_etudiant, scolarite_profession_autorisee
    INTO v_soignant
    FROM soignants WHERE id = NEW.soignant_id;

  IF v_soignant.est_etudiant
     AND v_soignant.scolarite_profession_autorisee IS NOT NULL THEN
    SELECT profession_requise INTO v_mission_prof
      FROM missions WHERE id = NEW.mission_id;
    IF v_mission_prof IS NOT NULL
       AND UPPER(v_mission_prof) != UPPER(v_soignant.scolarite_profession_autorisee) THEN
      RAISE EXCEPTION
        'En tant qu''étudiant(e), vous ne pouvez postuler qu''aux missions % (profession autorisée par votre scolarité vérifiée).',
        v_soignant.scolarite_profession_autorisee
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.est_soignant()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT COALESCE(
        (SELECT raw_app_meta_data ->> 'role' = 'SOIGNANT' FROM auth.users WHERE id = auth.uid()),
        false
    );
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_activer_liberal()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_soignant RECORD;
    v_taux JSONB;
BEGIN
    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant.siret_liberal IS NULL THEN
        RETURN '{\"error\":\"SIRET non renseigné\"}'::JSONB;
    END IF;
    IF v_soignant.profession NOT IN (SELECT profession FROM professions_liberal_eligible) THEN
        RETURN '{\"error\":\"Votre profession n''est pas éligible au libéral\"}'::JSONB;
    END IF;

    -- Calculer le taux Free Transition
    v_taux := fn_calculer_taux_free_transition(auth.uid());

    UPDATE soignants SET
        type_contrat = 'LIBERAL',
        statut_liberal = 'ACTIF',
        date_passage_liberal = CURRENT_DATE,
        code_ape = (SELECT code_ape FROM professions_liberal_eligible WHERE profession = v_soignant.profession),
        modifie_le = NOW()
    WHERE id = auth.uid();

    -- Créer la conversion
    INSERT INTO conversions_liberal (
        soignant_id, heures_plateforme_au_demarrage, heures_externes_validees,
        heures_totales, statut, free_transition_eligible,
        taux_prise_en_charge, montant_pris_en_charge, complete_le
    ) VALUES (
        auth.uid(), v_soignant.heures_plateforme,
        COALESCE((SELECT SUM(heures_declarees) FROM heures_externes WHERE soignant_id = auth.uid() AND statut = 'VALIDEE'), 0),
        v_soignant.heures_cumulees, 'COMPLET',
        (v_taux ->> 'eligible')::BOOLEAN,
        (v_taux ->> 'taux_prise_en_charge')::INTEGER,
        (v_taux ->> 'montant_pris_en_charge')::NUMERIC,
        NOW()
    ) ON CONFLICT DO NOTHING;

    RETURN jsonb_build_object('success', true, 'taux', v_taux);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_accepter_mission(p_mission_id uuid, p_choix_contrat text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_mission RECORD; v_soignant RECORD; v_type_paiement TEXT; v_mode_paiement TEXT;
    v_type_contrat_gen TEXT; v_numero_contrat TEXT; v_contrat_id UUID; v_choix_effectif TEXT; v_rows INT;
BEGIN
    SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
    IF v_mission.statut != 'OUVERTE' THEN RETURN jsonb_build_object('error', 'Cette mission n''est plus disponible'); END IF;
    IF v_mission.mode_attribution != 'PREMIER_ARRIVE' THEN RETURN jsonb_build_object('error', 'Cette mission nécessite une candidature'); END IF;
    SELECT * INTO v_soignant FROM soignants WHERE id = auth.uid();
    IF v_soignant IS NULL THEN RETURN jsonb_build_object('error', 'Profil soignant introuvable'); END IF;
    IF NOT fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
           v_mission.profession_requise, v_mission.specialite_medicale_requise, v_mission.accepte_non_specialises) THEN
        RETURN jsonb_build_object('error', 'Profession incompatible.');
    END IF;
    IF v_mission.type_contrat_recherche = 'SALARIE' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('SALARIE', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux salariés.');
    END IF;
    IF v_mission.type_contrat_recherche = 'LIBERAL' AND COALESCE(v_soignant.type_exercice, 'SALARIE') NOT IN ('LIBERAL', 'MIXTE') THEN
        RETURN jsonb_build_object('error', 'Mission réservée aux libéraux.');
    END IF;
    IF v_soignant.type_exercice = 'MIXTE' AND v_mission.type_contrat_recherche = 'TOUS' THEN
        v_choix_effectif := COALESCE(p_choix_contrat, v_soignant.preference_contrat_mixte);
        IF v_choix_effectif IS NULL OR v_choix_effectif NOT IN ('SALARIE', 'LIBERAL') THEN
            RETURN jsonb_build_object('error', 'Choisissez votre mode de contrat.', 'choix_requis', TRUE,
                'options', jsonb_build_array(
                    jsonb_build_object('value', 'SALARIE', 'label', 'Salarié (CDD / bulletin de paie)'),
                    jsonb_build_object('value', 'LIBERAL', 'label', 'Libéral (note d''honoraires)')));
        END IF;
    ELSE
        v_choix_effectif := p_choix_contrat;
    END IF;
    IF fn_est_exclu(auth.uid(), v_mission.etablissement_id) THEN RETURN jsonb_build_object('error', 'Accès refusé.'); END IF;
    IF NOT fn_documents_ok_pour_mission(auth.uid(), COALESCE(v_choix_effectif, v_mission.type_contrat_recherche::text)) THEN
        RETURN jsonb_build_object('error', 'Vos documents doivent être validés pour ce type de mission. Téléversez-les dans Mes documents — la vérification automatique prend quelques minutes.');
    END IF;
    IF v_soignant.type_exercice = 'LIBERAL' OR (v_soignant.type_exercice = 'MIXTE' AND (v_choix_effectif = 'LIBERAL' OR v_mission.type_contrat_recherche = 'LIBERAL')) THEN
        v_type_paiement := 'NOTE_HONORAIRES'; v_mode_paiement := 'STRIPE_CONNECT'; v_type_contrat_gen := 'LIBERAL';
    ELSE
        v_type_paiement := 'BULLETIN_PAIE'; v_mode_paiement := 'DIRECT'; v_type_contrat_gen := 'CDD';
    END IF;
    UPDATE missions SET soignant_assigne_id = auth.uid(), statut = 'ASSIGNEE',
        choix_contrat_soignant = v_choix_effectif, type_paiement_soignant = v_type_paiement,
        mode_paiement_soignant = v_mode_paiement, modifie_le = NOW()
    WHERE id = p_mission_id AND statut = 'OUVERTE';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN RETURN jsonb_build_object('error', 'Cette mission vient d''être prise par un autre soignant (déjà prise).'); END IF;
    v_numero_contrat := fn_generer_numero_contrat_safe(v_type_contrat_gen);
    INSERT INTO contrats_mission (mission_id, etablissement_id, soignant_id, type_contrat, numero_contrat, statut)
    VALUES (p_mission_id, v_mission.etablissement_id, auth.uid(), v_type_contrat_gen, v_numero_contrat, 'EN_ATTENTE_SIGNATURES')
    ON CONFLICT DO NOTHING RETURNING id INTO v_contrat_id;
    IF v_contrat_id IS NULL THEN
        SELECT id INTO v_contrat_id FROM contrats_mission
        WHERE mission_id = p_mission_id AND soignant_id = auth.uid() AND statut <> 'ANNULE'
        ORDER BY cree_le DESC LIMIT 1;
    END IF;
    RETURN jsonb_build_object('success', TRUE, 'contrat_id', v_contrat_id, 'contrat_numero', v_numero_contrat,
        'type_paiement', v_type_paiement, 'mode_paiement', v_mode_paiement);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_accepter_mission_urgence(p_mission_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_soignant RECORD; v_mission RECORD; v_existing UUID; v_candidature_id UUID;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Non authentifié'); END IF;
  SELECT * INTO v_soignant FROM soignants WHERE id = v_uid AND supprime_le IS NULL;
  IF v_soignant IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Profil soignant introuvable'); END IF;
  SELECT * INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'OUVERTE' OR COALESCE(v_mission.est_urgente, false) = false THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission non disponible (non-urgente ou non-ouverte)');
  END IF;
  IF NOT public.fn_soignant_compatible_mission(v_soignant.profession, v_soignant.specialite_medicale,
    v_mission.profession_requise, v_mission.specialite_medicale_requise, COALESCE(v_mission.accepte_non_specialises, true)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Profession ou spécialité incompatible');
  END IF;
  IF NOT fn_documents_ok_pour_mission(v_uid, v_mission.type_contrat_recherche::text) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Vos documents ne sont pas validés pour ce type de mission');
  END IF;
  IF v_mission.type_contrat_recherche = 'LIBERAL' THEN
    IF NOT EXISTS (SELECT 1 FROM documents_soignants WHERE soignant_id = v_uid AND type_document = 'RCP_ASSURANCE'
      AND statut_verification = 'VERIFIE' AND supprime_le IS NULL AND (valide_jusqua IS NULL OR valide_jusqua > CURRENT_DATE)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'Assurance RCP obligatoire pour une mission urgente en libéral.');
    END IF;
  END IF;
  SELECT id INTO v_existing FROM candidatures WHERE mission_id = p_mission_id AND soignant_id = v_uid LIMIT 1;
  IF v_existing IS NOT NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Vous avez déjà candidaté à cette mission'); END IF;
  INSERT INTO candidatures (mission_id, soignant_id, statut, message, cree_le)
  VALUES (p_mission_id, v_uid, 'EN_ATTENTE_VALIDATION_ETAB', 'Acceptation rapide via pool urgence', NOW())
  RETURNING id INTO v_candidature_id;
  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien, type_ressource, id_ressource)
  VALUES (v_mission.etablissement_id, 'ETABLISSEMENT', 'POOL_URGENCE_ACCEPTATION', '🚨 Acceptation rapide pool urgence',
    v_soignant.prenom || ' ' || LEFT(v_soignant.nom, 1) || '. (' || v_soignant.profession::text || ') a accepté votre mission urgente. Validez ou refusez sous 1h.',
    '/etablissement/missions/' || p_mission_id::text, 'candidature', v_candidature_id);
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_uid, p_type_acteur := 'SOIGNANT',
    p_action := 'POOL_URGENCE_ACCEPTATION_RAPIDE', p_type_ressource := 'candidature', p_id_ressource := v_candidature_id,
    p_details := jsonb_build_object('mission_id', p_mission_id));
  RETURN jsonb_build_object('success', true, 'candidature_id', v_candidature_id,
    'message', 'Acceptation enregistrée. Attente validation établissement.');
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_accepter_invitation_membre(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_invitation RECORD;
  v_membre_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTHENTIFIE');
  END IF;

  SELECT * INTO v_invitation
  FROM public.invitations_etablissement
  WHERE token = p_token
  LIMIT 1;

  IF v_invitation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TOKEN_INVALIDE');
  END IF;

  IF v_invitation.statut != 'EN_ATTENTE' THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_TRAITEE');
  END IF;

  IF v_invitation.expire_le < now() THEN
    UPDATE public.invitations_etablissement SET statut = 'EXPIREE' WHERE id = v_invitation.id;
    RETURN jsonb_build_object('success', false, 'error_code', 'INVITATION_EXPIREE');
  END IF;

  -- Optionnel : vérifier que l'email du user correspond à l'invitation
  IF lower(COALESCE((SELECT email FROM auth.users WHERE id = v_uid), '')) != lower(v_invitation.email_invite) THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'EMAIL_INCORRECT',
                                'error', 'Cette invitation est pour une autre adresse e-mail');
  END IF;

  -- Créer le membre (upsert au cas où réactivation)
  INSERT INTO public.membres_etablissement (
    etablissement_id, user_id, role, invite_par, invite_le, accepte_le, actif
  ) VALUES (
    v_invitation.etablissement_id, v_uid, v_invitation.role_propose,
    v_invitation.invite_par, v_invitation.invite_le, now(), true
  )
  ON CONFLICT (etablissement_id, user_id) DO UPDATE SET
    role = EXCLUDED.role,
    actif = true,
    accepte_le = now(),
    maj_le = now()
  RETURNING id INTO v_membre_id;

  -- Marquer invitation comme acceptée
  UPDATE public.invitations_etablissement SET
    statut = 'ACCEPTEE',
    acceptee_le = now(),
    acceptee_par_user_id = v_uid
  WHERE id = v_invitation.id;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'MODIFICATION_PROFIL', 'membre_etablissement', v_membre_id,
    jsonb_build_object(
      'evenement', 'INVITATION_MEMBRE_ACCEPTEE',
      'invitation_id', v_invitation.id,
      'etablissement_id', v_invitation.etablissement_id,
      'role', v_invitation.role_propose
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'membre_id', v_membre_id,
    'etablissement_id', v_invitation.etablissement_id,
    'role', v_invitation.role_propose
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_acquisition_canaux(p_jours integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_depuis timestamptz := now() - (p_jours || ' days')::interval;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid() AND raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ) THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  WITH soignants_p AS (
    SELECT coalesce(source_acquisition, 'DIRECT') AS canal, id
    FROM soignants WHERE cree_le >= v_depuis
  ),
  etabs_p AS (
    SELECT coalesce(source_acquisition, 'DIRECT') AS canal, id
    FROM etablissements WHERE cree_le >= v_depuis AND supprime_le IS NULL
  ),
  soignants_actifs AS (
    SELECT DISTINCT soignant_id FROM candidatures
  ),
  par_canal AS (
    SELECT
      canal,
      count(*) FILTER (WHERE src = 'S') AS soignants,
      count(*) FILTER (WHERE src = 'E') AS etablissements,
      count(*) FILTER (WHERE src = 'S' AND actif) AS soignants_actifs
    FROM (
      SELECT canal, 'S' AS src, (id IN (SELECT soignant_id FROM soignants_actifs)) AS actif FROM soignants_p
      UNION ALL
      SELECT canal, 'E' AS src, false AS actif FROM etabs_p
    ) u
    GROUP BY canal
  ),
  par_campagne AS (
    SELECT campagne, sum(n) AS inscriptions FROM (
      SELECT coalesce(nullif(utm_campaign, ''), '(aucune)') AS campagne, count(*) AS n
      FROM soignants WHERE cree_le >= v_depuis AND utm_campaign IS NOT NULL GROUP BY 1
      UNION ALL
      SELECT coalesce(nullif(utm_campaign, ''), '(aucune)'), count(*)
      FROM etablissements WHERE cree_le >= v_depuis AND supprime_le IS NULL AND utm_campaign IS NOT NULL GROUP BY 1
    ) c GROUP BY campagne
  )
  SELECT jsonb_build_object(
    'periode_jours', p_jours,
    'par_canal', coalesce((
      SELECT jsonb_agg(row_to_json(t)::jsonb ORDER BY (t.soignants + t.etablissements) DESC)
      FROM par_canal t
    ), '[]'::jsonb),
    'par_campagne', coalesce((
      SELECT jsonb_agg(row_to_json(t)::jsonb ORDER BY t.inscriptions DESC)
      FROM par_campagne t
    ), '[]'::jsonb),
    'total_soignants', (SELECT count(*) FROM soignants_p),
    'total_etabs', (SELECT count(*) FROM etabs_p)
  ) INTO v_result;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_activer_garantie_mission(p_mission_id uuid, p_actif boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m RECORD;
BEGIN
  SELECT * INTO v_m FROM missions WHERE id = p_mission_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Mission introuvable'); END IF;
  IF v_m.etablissement_id != mon_etablissement_id() AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF v_m.statut NOT IN ('OUVERTE', 'ASSIGNEE') THEN
    RETURN jsonb_build_object('error', 'La garantie ne peut être modifiée que sur une mission ouverte ou assignée.');
  END IF;
  UPDATE missions SET garantie_remplacement = p_actif, modifie_le = NOW() WHERE id = p_mission_id;
  RETURN jsonb_build_object('success', TRUE, 'garantie', p_actif);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_ajouter_document_soignant(p_soignant_id uuid, p_type_document text, p_cle text, p_nom_fichier text, p_type_mime text DEFAULT NULL::text, p_taille_octets bigint DEFAULT NULL::bigint, p_valider boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_doc_id uuid;
  v_resultat jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM soignants WHERE id = p_soignant_id) THEN
    RETURN jsonb_build_object('error', 'Soignant introuvable');
  END IF;

  INSERT INTO documents_soignants (
    soignant_id, type_document, libelle, s3_bucket, s3_cle,
    nom_fichier, type_mime, taille_octets, statut_verification
  ) VALUES (
    p_soignant_id,
    p_type_document::type_document,
    'Ajouté par l''équipe Jolene (' || p_type_document || ')',
    'jolene-documents', p_cle,
    p_nom_fichier, p_type_mime, p_taille_octets, 'EN_ATTENTE'
  ) RETURNING id INTO v_doc_id;

  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (auth.uid(), 'ADMIN', 'MODERATION_DOCUMENT', 'document', v_doc_id,
    jsonb_build_object('action', 'AJOUT_ADMIN', 'type_document', p_type_document, 'soignant_id', p_soignant_id));

  IF p_valider THEN
    v_resultat := fn_admin_moderer_document(v_doc_id, 'VALIDER');
    IF v_resultat ? 'error' THEN RETURN v_resultat; END IF;
  END IF;

  RETURN jsonb_build_object('success', true, 'document_id', v_doc_id, 'valide', p_valider);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_chorus_config_toggle(p_etablissement_id uuid, p_actif boolean, p_numero_structure text DEFAULT NULL::text, p_code_service text DEFAULT NULL::text, p_identifiant_cpro text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  INSERT INTO public.chorus_pro_config (etablissement_id, numero_structure, code_service, identifiant_cpro, actif)
  VALUES (p_etablissement_id, p_numero_structure, p_code_service, p_identifiant_cpro, p_actif)
  ON CONFLICT (etablissement_id) DO UPDATE
    SET actif = EXCLUDED.actif,
        numero_structure = COALESCE(EXCLUDED.numero_structure, chorus_pro_config.numero_structure),
        code_service = COALESCE(EXCLUDED.code_service, chorus_pro_config.code_service),
        identifiant_cpro = COALESCE(EXCLUDED.identifiant_cpro, chorus_pro_config.identifiant_cpro);

  PERFORM fn_ecrire_audit_safe(
    v_actor, 'ADMIN_PLATEFORME',
    CASE WHEN p_actif THEN 'CHORUS_CONFIG_ACTIVEE' ELSE 'CHORUS_CONFIG_DESACTIVEE' END,
    'chorus_pro_config', p_etablissement_id,
    NULL, jsonb_build_object('actif', p_actif), NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_lister(p_annee integer DEFAULT (EXTRACT(year FROM now()))::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_res jsonb;
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;

  WITH groupes AS (
    SELECT g.id, g.nom, COALESCE(g.bfa_taux,0) AS taux, g.bfa_contrat_signe_le,
           (SELECT count(*) FROM etablissements e WHERE e.groupe_sante_id = g.id) AS nb_etabs,
           COALESCE((SELECT count(*) FROM missions m JOIN etablissements e ON e.id=m.etablissement_id
                     WHERE e.groupe_sante_id=g.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS nb_missions,
           COALESCE((SELECT sum(m.montant_commission_ht) FROM missions m JOIN etablissements e ON e.id=m.etablissement_id
                     WHERE e.groupe_sante_id=g.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS commissions
    FROM groupes_sante g WHERE g.bfa_eligible = true
  ),
  etabs AS (
    SELECT e.id, e.nom, COALESCE(e.bfa_taux,0) AS taux, e.bfa_contrat_signe_le, 1 AS nb_etabs,
           COALESCE((SELECT count(*) FROM missions m WHERE m.etablissement_id=e.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS nb_missions,
           COALESCE((SELECT sum(m.montant_commission_ht) FROM missions m WHERE m.etablissement_id=e.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee),0) AS commissions
    FROM etablissements e WHERE e.bfa_eligible = true AND e.groupe_sante_id IS NULL
  )
  SELECT jsonb_build_object(
    'annee', p_annee,
    'groupes', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type','GROUPE','id',id,'nom',nom,'taux',taux,'contrat_signe_le',bfa_contrat_signe_le,
        'nb_etabs',nb_etabs,'nb_missions',nb_missions,'commissions',round(commissions,2),
        'montant_bfa',round(commissions*taux/100,2),
        'verse',(SELECT bfa_verse FROM bfa_suivi s WHERE s.groupe_id=groupes.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1),
        'suivi_id',(SELECT id FROM bfa_suivi s WHERE s.groupe_id=groupes.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1)
      ) ORDER BY nom) FROM groupes), '[]'::jsonb),
    'etablissements', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'type','ETABLISSEMENT','id',id,'nom',nom,'taux',taux,'contrat_signe_le',bfa_contrat_signe_le,
        'nb_missions',nb_missions,'commissions',round(commissions,2),
        'montant_bfa',round(commissions*taux/100,2),
        'verse',(SELECT bfa_verse FROM bfa_suivi s WHERE s.etablissement_id=etabs.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1),
        'suivi_id',(SELECT id FROM bfa_suivi s WHERE s.etablissement_id=etabs.id AND s.annee=p_annee ORDER BY calcule_le DESC LIMIT 1)
      ) ORDER BY nom) FROM etabs), '[]'::jsonb)
  ) INTO v_res;
  RETURN v_res;
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_definir_beneficiaire(p_type text, p_id uuid, p_eligible boolean, p_taux numeric DEFAULT NULL::numeric, p_contrat_signe_le date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  IF p_eligible AND (p_taux IS NULL OR p_taux <= 0 OR p_taux > 100) THEN
    RETURN jsonb_build_object('success',false,'error','Taux BFA invalide (0 < taux ≤ 100)');
  END IF;
  IF p_type = 'GROUPE' THEN
    UPDATE groupes_sante SET bfa_eligible=p_eligible, bfa_taux=CASE WHEN p_eligible THEN p_taux ELSE bfa_taux END,
      bfa_contrat_signe_le=COALESCE(p_contrat_signe_le,bfa_contrat_signe_le) WHERE id=p_id;
  ELSIF p_type = 'ETABLISSEMENT' THEN
    UPDATE etablissements SET bfa_eligible=p_eligible, bfa_taux=CASE WHEN p_eligible THEN p_taux ELSE bfa_taux END,
      bfa_contrat_signe_le=COALESCE(p_contrat_signe_le,bfa_contrat_signe_le) WHERE id=p_id;
  ELSE
    RETURN jsonb_build_object('success',false,'error','Type invalide (GROUPE|ETABLISSEMENT)');
  END IF;
  RETURN jsonb_build_object('success',true);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_detail_groupe(p_groupe_id uuid, p_annee integer DEFAULT (EXTRACT(year FROM now()))::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_res jsonb;
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'etablissement_id', e.id, 'nom', e.nom, 'ville', e.ville,
      'nb_missions', COALESCE(x.nb,0), 'ca_ht', round(COALESCE(x.ca,0),2),
      'commissions_ht', round(COALESCE(x.com,0),2)
    ) ORDER BY e.nom), '[]'::jsonb) INTO v_res
  FROM etablissements e
  LEFT JOIN LATERAL (
    SELECT count(*) AS nb, sum(m.total_brut) AS ca, sum(m.montant_commission_ht) AS com
    FROM missions m WHERE m.etablissement_id=e.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee
  ) x ON true
  WHERE e.groupe_sante_id = p_groupe_id;
  RETURN jsonb_build_object('groupe_id',p_groupe_id,'annee',p_annee,'etablissements',v_res);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_calculer(p_annee integer DEFAULT (EXTRACT(year FROM now()))::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r RECORD; v_com numeric; v_nb int; v_count int := 0;
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  -- Groupes éligibles
  FOR r IN SELECT id, COALESCE(bfa_taux,0) AS taux FROM groupes_sante WHERE bfa_eligible LOOP
    SELECT count(*), COALESCE(sum(m.montant_commission_ht),0) INTO v_nb, v_com
    FROM missions m JOIN etablissements e ON e.id=m.etablissement_id
    WHERE e.groupe_sante_id=r.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee;
    DELETE FROM bfa_suivi WHERE groupe_id=r.id AND annee=p_annee AND COALESCE(bfa_verse,false)=false;
    INSERT INTO bfa_suivi (groupe_id, annee, missions_cumulees, commissions_cumulees, taux_bfa, montant_bfa, bfa_verse, calcule_le)
    VALUES (r.id, p_annee, v_nb, v_com, r.taux, round(v_com*r.taux/100,2), false, now());
    v_count := v_count + 1;
  END LOOP;
  -- Étabs isolés éligibles
  FOR r IN SELECT id, COALESCE(bfa_taux,0) AS taux FROM etablissements WHERE bfa_eligible AND groupe_sante_id IS NULL LOOP
    SELECT count(*), COALESCE(sum(m.montant_commission_ht),0) INTO v_nb, v_com
    FROM missions m WHERE m.etablissement_id=r.id AND m.statut='TERMINEE' AND EXTRACT(YEAR FROM m.fin_le)=p_annee;
    DELETE FROM bfa_suivi WHERE etablissement_id=r.id AND annee=p_annee AND COALESCE(bfa_verse,false)=false;
    INSERT INTO bfa_suivi (etablissement_id, annee, missions_cumulees, commissions_cumulees, taux_bfa, montant_bfa, bfa_verse, calcule_le)
    VALUES (r.id, p_annee, v_nb, v_com, r.taux, round(v_com*r.taux/100,2), false, now());
    v_count := v_count + 1;
  END LOOP;
  RETURN jsonb_build_object('success',true,'annee',p_annee,'beneficiaires_calcules',v_count);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_bfa_marquer_verse(p_suivi_id uuid, p_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  UPDATE bfa_suivi SET bfa_verse=true, date_versement=p_date WHERE id=p_suivi_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','Suivi BFA introuvable'); END IF;
  RETURN jsonb_build_object('success',true);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects(p_type text DEFAULT NULL::text, p_departement text DEFAULT NULL::text, p_q text DEFAULT NULL::text, p_favoris boolean DEFAULT false, p_page integer DEFAULT 1, p_avec_email boolean DEFAULT false, p_avec_tel boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_total bigint;
  v_resultats jsonb;
  v_par_page int := 30;
  v_offset int := (greatest(p_page,1)-1) * 30;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;

  SELECT count(*) INTO v_total
  FROM prospects_etablissements p
  WHERE (p_type IS NULL OR p_type = '' OR p.type_jolene = p_type)
    AND (p_departement IS NULL OR p_departement = '' OR p.departement = upper(p_departement))
    AND (NOT p_favoris OR p.favori)
    AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
    AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
    AND (p_q IS NULL OR p_q = '' OR p.nom ILIKE '%'||p_q||'%' OR p.ville ILIKE '%'||p_q||'%');

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_resultats
  FROM (
    SELECT p.finess, p.siret, p.nom, p.type_jolene, p.categorie_lib, p.telephone,
           p.email, p.adresse, p.code_postal, p.ville, p.departement, p.favori
    FROM prospects_etablissements p
    WHERE (p_type IS NULL OR p_type = '' OR p.type_jolene = p_type)
      AND (p_departement IS NULL OR p_departement = '' OR p.departement = upper(p_departement))
      AND (NOT p_favoris OR p.favori)
      AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
      AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
      AND (p_q IS NULL OR p_q = '' OR p.nom ILIKE '%'||p_q||'%' OR p.ville ILIKE '%'||p_q||'%')
    ORDER BY p.favori DESC, p.nom
    LIMIT v_par_page OFFSET v_offset
  ) t;

  RETURN jsonb_build_object(
    'total', v_total,
    'page', greatest(p_page,1),
    'total_pages', ceil(v_total::numeric / v_par_page),
    'resultats', v_resultats
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_chercher_prospects_soignants(p_profession text DEFAULT NULL::text, p_departement text DEFAULT NULL::text, p_q text DEFAULT NULL::text, p_favoris boolean DEFAULT false, p_page integer DEFAULT 1, p_avec_email boolean DEFAULT false, p_avec_tel boolean DEFAULT false, p_etudiants boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_total bigint; v_res jsonb; v_page int := GREATEST(p_page, 1);
BEGIN
  IF NOT public.est_admin() THEN RETURN jsonb_build_object('error', 'Accès refusé'); END IF;
  SELECT count(*) INTO v_total FROM prospects_soignants p
   WHERE (p_profession IS NULL OR p.profession = p_profession)
     AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
     AND (NOT p_favoris OR p.favori)
     AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
     AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
     AND (NOT p_etudiants OR p.est_etudiant)
     AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%');
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb), '[]'::jsonb) INTO v_res FROM (
    SELECT p.* FROM prospects_soignants p
     WHERE (p_profession IS NULL OR p.profession = p_profession)
       AND (p_departement IS NULL OR p.departement = lpad(p_departement, 2, '0'))
       AND (NOT p_favoris OR p.favori)
       AND (NOT p_avec_email OR (p.email IS NOT NULL AND p.email <> ''))
       AND (NOT p_avec_tel OR (p.telephone IS NOT NULL AND p.telephone <> ''))
       AND (NOT p_etudiants OR p.est_etudiant)
       AND (p_q IS NULL OR p.nom ILIKE '%' || p_q || '%' OR p.ville ILIKE '%' || p_q || '%' OR p.enseigne ILIKE '%' || p_q || '%')
     ORDER BY p.favori DESC, p.departement, p.ville, p.nom
     LIMIT 30 OFFSET (v_page - 1) * 30
  ) t;
  RETURN jsonb_build_object('total', v_total, 'page', v_page, 'total_pages', CEIL(v_total / 30.0), 'resultats', v_res);
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_conformite()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN '{\"error\":\"Accès refusé\"}'::JSONB; END IF;

    RETURN jsonb_build_object(
        'violations_repos_11h', (SELECT COUNT(*) FROM conformite_travail WHERE resultat != 'CONFORME' AND controle_le > NOW() - INTERVAL '30 days'),
        'alertes_48h', (SELECT COUNT(*) FROM soignants s WHERE (SELECT COALESCE(SUM(duree_heures),0) FROM missions m WHERE m.soignant_assigne_id = s.id AND m.statut IN ('ASSIGNEE', 'EN_COURS') AND m.debut_le > DATE_TRUNC('week', NOW())) > 44),
        'docs_expires', (SELECT COUNT(*) FROM documents_soignants WHERE statut_verification = 'EXPIRE' AND supprime_le IS NULL),
        'docs_en_attente', (SELECT COUNT(*) FROM documents_soignants WHERE statut_verification = 'EN_ATTENTE' AND supprime_le IS NULL),
        'cddu_repetitifs', COALESCE((SELECT COUNT(*) FROM (SELECT 1 FROM missions WHERE statut = 'TERMINEE' GROUP BY soignant_assigne_id, etablissement_id HAVING COUNT(DISTINCT debut_le::DATE) > 150) sub), 0),
        'soignants_sans_docs', (SELECT COUNT(*) FROM soignants WHERE tous_documents_valides = FALSE AND supprime_le IS NULL),
        'missions_sans_contrat', (SELECT COUNT(*) FROM missions m WHERE m.statut IN ('ASSIGNEE', 'EN_COURS') AND NOT EXISTS (SELECT 1 FROM contrats_mission c WHERE c.mission_id = m.id AND c.statut = 'SIGNE_COMPLET'))
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_conformite_detail(p_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN '[]'::jsonb;
  END IF;

  CASE p_type
    WHEN 'violations_repos_11h' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.controle_le DESC)
        FROM (
          SELECT
            ct.id,
            ct.type_controle,
            ct.resultat,
            ct.controle_le,
            ct.details_violation,
            ct.soignant_id,
            ct.mission_id,
            m.etablissement_id,
            s.prenom || ' ' || s.nom AS soignant_nom,
            m.intitule AS mission_intitule,
            e.nom AS etablissement_nom
          FROM public.conformite_travail ct
          JOIN public.soignants s ON s.id = ct.soignant_id
          JOIN public.missions m ON m.id = ct.mission_id
          JOIN public.etablissements e ON e.id = m.etablissement_id
          WHERE ct.resultat <> 'CONFORME'
            AND ct.controle_le > NOW() - INTERVAL '30 days'
          ORDER BY ct.controle_le DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'alertes_48h' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.heures_semaine DESC)
        FROM (
          SELECT
            s.id AS soignant_id,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            hs.heures_semaine,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM (
            SELECT
              m.soignant_assigne_id,
              COALESCE(SUM(m.duree_heures), 0) AS heures_semaine
            FROM public.missions m
            WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
              AND m.debut_le > DATE_TRUNC('week', NOW())
            GROUP BY m.soignant_assigne_id
            HAVING SUM(m.duree_heures) > 44
          ) hs
          JOIN public.soignants s ON s.id = hs.soignant_assigne_id
          LEFT JOIN LATERAL (
            SELECT
              m2.id AS mission_id,
              m2.intitule AS mission_intitule,
              m2.etablissement_id,
              e2.nom AS etablissement_nom
            FROM public.missions m2
            LEFT JOIN public.etablissements e2 ON e2.id = m2.etablissement_id
            WHERE m2.soignant_assigne_id = s.id
              AND m2.statut IN ('ASSIGNEE', 'EN_COURS')
              AND m2.debut_le > DATE_TRUNC('week', NOW())
            ORDER BY m2.debut_le ASC
            LIMIT 1
          ) rm ON TRUE
          ORDER BY hs.heures_semaine DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'docs_expires' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.valide_jusqua ASC)
        FROM (
          SELECT
            d.id,
            d.soignant_id,
            d.type_document,
            d.nom_fichier,
            d.valide_jusqua,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM public.documents_soignants d
          JOIN public.soignants s ON s.id = d.soignant_id
          LEFT JOIN LATERAL (
            SELECT
              m.id AS mission_id,
              m.intitule AS mission_intitule,
              m.etablissement_id,
              e.nom AS etablissement_nom
            FROM public.missions m
            LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.soignant_assigne_id = d.soignant_id
            ORDER BY
              CASE
                WHEN m.statut IN ('EN_COURS', 'ASSIGNEE') THEN 0
                WHEN m.statut = 'TERMINEE' THEN 1
                ELSE 2
              END,
              m.debut_le DESC
            LIMIT 1
          ) rm ON TRUE
          WHERE d.statut_verification = 'EXPIRE'
            AND d.supprime_le IS NULL
          ORDER BY d.valide_jusqua ASC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'docs_en_attente' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.televerse_le DESC)
        FROM (
          SELECT
            d.id,
            d.soignant_id,
            d.type_document,
            d.nom_fichier,
            d.televerse_le,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM public.documents_soignants d
          JOIN public.soignants s ON s.id = d.soignant_id
          LEFT JOIN LATERAL (
            SELECT
              m.id AS mission_id,
              m.intitule AS mission_intitule,
              m.etablissement_id,
              e.nom AS etablissement_nom
            FROM public.missions m
            LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.soignant_assigne_id = d.soignant_id
            ORDER BY
              CASE
                WHEN m.statut IN ('EN_COURS', 'ASSIGNEE') THEN 0
                WHEN m.statut = 'TERMINEE' THEN 1
                ELSE 2
              END,
              m.debut_le DESC
            LIMIT 1
          ) rm ON TRUE
          WHERE d.statut_verification = 'EN_ATTENTE'
            AND d.supprime_le IS NULL
          ORDER BY d.televerse_le DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'cddu_repetitifs' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.nb_missions DESC)
        FROM (
          SELECT
            base.soignant_id,
            base.etablissement_id,
            base.soignant_nom,
            base.etablissement_nom,
            base.nb_missions,
            base.premiere_mission,
            base.derniere_mission,
            rm.mission_id,
            rm.mission_intitule
          FROM (
            SELECT
              m.soignant_assigne_id AS soignant_id,
              m.etablissement_id,
              s.prenom || ' ' || s.nom AS soignant_nom,
              e.nom AS etablissement_nom,
              COUNT(*) AS nb_missions,
              MIN(m.debut_le)::date AS premiere_mission,
              MAX(m.fin_le)::date AS derniere_mission
            FROM public.missions m
            JOIN public.soignants s ON s.id = m.soignant_assigne_id
            JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.statut = 'TERMINEE'
            GROUP BY m.soignant_assigne_id, m.etablissement_id, s.prenom, s.nom, e.nom
            HAVING COUNT(DISTINCT m.debut_le::date) > 150
          ) base
          LEFT JOIN LATERAL (
            SELECT
              m2.id AS mission_id,
              m2.intitule AS mission_intitule
            FROM public.missions m2
            WHERE m2.soignant_assigne_id = base.soignant_id
              AND m2.etablissement_id = base.etablissement_id
            ORDER BY m2.fin_le DESC
            LIMIT 1
          ) rm ON TRUE
          ORDER BY base.nb_missions DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'soignants_sans_docs' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.cree_le DESC)
        FROM (
          SELECT
            s.id AS soignant_id,
            s.prenom || ' ' || s.nom AS soignant_nom,
            s.profession,
            s.cree_le,
            s.email,
            rm.mission_id,
            rm.mission_intitule,
            rm.etablissement_id,
            rm.etablissement_nom
          FROM public.soignants s
          LEFT JOIN LATERAL (
            SELECT
              m.id AS mission_id,
              m.intitule AS mission_intitule,
              m.etablissement_id,
              e.nom AS etablissement_nom
            FROM public.missions m
            LEFT JOIN public.etablissements e ON e.id = m.etablissement_id
            WHERE m.soignant_assigne_id = s.id
            ORDER BY
              CASE
                WHEN m.statut IN ('EN_COURS', 'ASSIGNEE') THEN 0
                WHEN m.statut = 'TERMINEE' THEN 1
                ELSE 2
              END,
              m.debut_le DESC
            LIMIT 1
          ) rm ON TRUE
          WHERE s.tous_documents_valides = FALSE
            AND s.supprime_le IS NULL
          ORDER BY s.cree_le DESC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    WHEN 'missions_sans_contrat' THEN
      RETURN COALESCE((
        SELECT jsonb_agg(row_to_json(t) ORDER BY t.debut_le ASC)
        FROM (
          SELECT
            m.id AS mission_id,
            m.id,
            m.intitule,
            m.debut_le,
            m.fin_le,
            m.statut,
            m.etablissement_id,
            s.id AS soignant_id,
            e.nom AS etablissement_nom,
            s.prenom || ' ' || s.nom AS soignant_nom
          FROM public.missions m
          JOIN public.etablissements e ON e.id = m.etablissement_id
          LEFT JOIN public.soignants s ON s.id = m.soignant_assigne_id
          WHERE m.statut IN ('ASSIGNEE', 'EN_COURS')
            AND NOT EXISTS (
              SELECT 1
              FROM public.contrats_mission c
              WHERE c.mission_id = m.id
                AND c.statut = 'SIGNE_COMPLET'
            )
          ORDER BY m.debut_le ASC
          LIMIT 50
        ) t
      ), '[]'::jsonb);

    ELSE
      RETURN '[]'::jsonb;
  END CASE;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_cohort_economics(p_mois integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_debut DATE := (CURRENT_DATE - (p_mois || ' months')::INTERVAL)::DATE;
  v_result JSONB;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès admin uniquement');
  END IF;

  WITH monthly_signups AS (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS cohorte,
      COUNT(*) FILTER(WHERE TRUE) AS nouveaux_soignants
    FROM soignants WHERE cree_le >= v_debut AND supprime_le IS NULL
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ),
  monthly_etab AS (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS cohorte,
      COUNT(*) AS nouveaux_etabs
    FROM etablissements WHERE cree_le >= v_debut AND supprime_le IS NULL
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ),
  monthly_missions AS (
    SELECT TO_CHAR(cree_le, 'YYYY-MM') AS mois,
      COUNT(*) AS total_missions,
      COUNT(*) FILTER(WHERE statut = 'TERMINEE') AS missions_terminees,
      COUNT(*) FILTER(WHERE statut IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT')) AS missions_annulees,
      ROUND(COALESCE(SUM(total_brut) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS gmv,
      ROUND(COALESCE(SUM(montant_commission_ht) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS commission_ht,
      ROUND(COALESCE(SUM(montant_commission_ttc) FILTER(WHERE statut = 'TERMINEE'), 0), 2) AS commission_ttc,
      COUNT(DISTINCT soignant_assigne_id) FILTER(WHERE statut = 'TERMINEE') AS soignants_actifs,
      COUNT(DISTINCT etablissement_id) FILTER(WHERE statut = 'TERMINEE') AS etabs_actifs,
      ROUND(COALESCE(AVG(duree_heures) FILTER(WHERE statut = 'TERMINEE'), 0), 1) AS duree_moyenne_h
    FROM missions WHERE cree_le >= v_debut
    GROUP BY TO_CHAR(cree_le, 'YYYY-MM')
  ),
  retention AS (
    SELECT m1.mois,
      COUNT(DISTINCT m1.sid) AS actifs,
      COUNT(DISTINCT m2.sid) AS retenus_mois_suivant
    FROM (
      SELECT DISTINCT TO_CHAR(debut_le, 'YYYY-MM') AS mois, soignant_assigne_id AS sid
      FROM missions WHERE statut = 'TERMINEE' AND debut_le >= v_debut
    ) m1
    LEFT JOIN (
      SELECT DISTINCT TO_CHAR(debut_le, 'YYYY-MM') AS mois, soignant_assigne_id AS sid
      FROM missions WHERE statut = 'TERMINEE' AND debut_le >= v_debut
    ) m2 ON m2.sid = m1.sid AND m2.mois = TO_CHAR((TO_DATE(m1.mois, 'YYYY-MM') + INTERVAL '1 month'), 'YYYY-MM')
    GROUP BY m1.mois
  ),
  unit_eco AS (
    SELECT
      ROUND(COALESCE(SUM(montant_commission_ttc) / NULLIF(COUNT(DISTINCT etablissement_id), 0), 0), 2) AS arpu_etab,
      ROUND(COALESCE(SUM(total_brut) / NULLIF(COUNT(DISTINCT soignant_assigne_id), 0), 0), 2) AS rev_per_soignant,
      ROUND(COALESCE(SUM(montant_commission_ht) / NULLIF(COUNT(*), 0), 0), 2) AS commission_par_mission,
      ROUND(COALESCE(AVG(CASE WHEN duree_heures > 0 THEN montant_commission_ht / duree_heures END), 0), 2) AS commission_par_heure,
      ROUND(COALESCE(AVG(CASE WHEN duree_heures > 0 THEN total_brut / duree_heures END), 0), 2) AS gmv_par_heure,
      ROUND(COUNT(*) FILTER(WHERE statut = 'TERMINEE') * 100.0 / NULLIF(COUNT(*), 1), 1) AS taux_completion,
      ROUND(COUNT(*) FILTER(WHERE statut IN ('ANNULEE_PAR_ETABLISSEMENT', 'ANNULEE_PAR_SOIGNANT')) * 100.0 / NULLIF(COUNT(*), 1), 1) AS taux_annulation
    FROM missions WHERE cree_le >= v_debut AND statut = 'TERMINEE'
  ),
  totals AS (
    SELECT
      (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL) AS total_soignants,
      (SELECT COUNT(*) FROM etablissements WHERE supprime_le IS NULL) AS total_etabs,
      (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE') AS total_missions_terminees,
      (SELECT ROUND(COALESCE(SUM(total_brut), 0), 2) FROM missions WHERE statut = 'TERMINEE') AS gmv_total,
      (SELECT ROUND(COALESCE(SUM(montant_commission_ttc), 0), 2) FROM missions WHERE statut = 'TERMINEE') AS revenue_total
  )
  SELECT jsonb_build_object(
    'cohortes_mensuelles', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'mois', mm.mois, 'nouveaux_soignants', COALESCE(ms.nouveaux_soignants, 0),
        'nouveaux_etabs', COALESCE(me.nouveaux_etabs, 0),
        'missions', COALESCE(mm.total_missions, 0),
        'missions_terminees', COALESCE(mm.missions_terminees, 0),
        'gmv', COALESCE(mm.gmv, 0),
        'commission_ht', COALESCE(mm.commission_ht, 0),
        'commission_ttc', COALESCE(mm.commission_ttc, 0),
        'soignants_actifs', COALESCE(mm.soignants_actifs, 0),
        'etabs_actifs', COALESCE(mm.etabs_actifs, 0),
        'duree_moyenne_h', COALESCE(mm.duree_moyenne_h, 0)
      ) ORDER BY mm.mois), '[]'::jsonb)
      FROM monthly_missions mm
      LEFT JOIN monthly_signups ms ON ms.cohorte = mm.mois
      LEFT JOIN monthly_etab me ON me.cohorte = mm.mois
    ),
    'retention_mensuelle', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'mois', r.mois, 'actifs', r.actifs, 'retenus', r.retenus_mois_suivant,
        'taux_retention', CASE WHEN r.actifs > 0 THEN ROUND(r.retenus_mois_suivant * 100.0 / r.actifs, 1) ELSE 0 END
      ) ORDER BY r.mois), '[]'::jsonb)
      FROM retention r
    ),
    'unit_economics', (SELECT row_to_json(ue)::jsonb FROM unit_eco ue),
    'totals', (SELECT row_to_json(t)::jsonb FROM totals t)
  ) INTO v_result;

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_chorus_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_par_statut JSONB;
BEGIN
  IF NOT est_admin() THEN RETURN '{\"error\":\"Acces refuse\"}'::JSONB; END IF;

  SELECT jsonb_object_agg(status, nb)
  INTO v_par_statut
  FROM (
    SELECT status, COUNT(*) AS nb FROM public.chorus_submissions GROUP BY status
  ) t;

  RETURN jsonb_build_object(
    'total_submissions', (SELECT COUNT(*) FROM public.chorus_submissions),
    'par_statut', COALESCE(v_par_statut, '{}'::JSONB),
    'erreurs_7j', (SELECT COUNT(*) FROM public.chorus_submissions WHERE status='error' AND created_at > NOW() - INTERVAL '7 days'),
    'derniere_sync', (SELECT MAX(last_checked_at) FROM public.chorus_submissions),
    'etabs_configures_actifs', (SELECT COUNT(*) FROM public.chorus_pro_config WHERE actif=TRUE),
    'etabs_secteur_public_total', (SELECT COUNT(*) FROM public.etablissements WHERE est_secteur_public=TRUE AND supprime_le IS NULL)
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_chorus_submission_reset(p_facture_honoraire_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_existing_sub_id UUID;
BEGIN
  IF NOT est_admin() THEN RETURN '{\"error\":\"Acces refuse\"}'::JSONB; END IF;

  SELECT chorus_submission_id INTO v_existing_sub_id
  FROM public.factures_honoraires WHERE id = p_facture_honoraire_id;

  IF v_existing_sub_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Facture sans chorus_submission_id rien a reset');
  END IF;

  UPDATE public.chorus_submissions
  SET status = 'error',
      error_message = COALESCE(error_message || ' | ', '') || 'Resubmit admin initie le ' || NOW()::TEXT
  WHERE id = v_existing_sub_id
  AND status NOT IN ('error', 'rejected');

  UPDATE public.factures_honoraires
  SET chorus_submission_id = NULL,
      chorus_submission_status = NULL
  WHERE id = p_facture_honoraire_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'ancienne_submission_id', v_existing_sub_id,
    'message', 'Facture reset admin peut maintenant invoquer submit-to-chorus'
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_cleanup_test_accounts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_deleted_count integer := 0;
  v_user record;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  FOR v_user IN
    SELECT id, email FROM auth.users
    WHERE email LIKE 'playwright-test-%@%'
  LOOP
    DELETE FROM auth.users WHERE id = v_user.id;
    v_deleted_count := v_deleted_count + 1;
  END LOOP;

  RETURN jsonb_build_object('deleted', v_deleted_count);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_cockpit_fondateur()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result jsonb;
  v_total_soignants int;
  v_total_etabs int;
  v_soignants_7j int;
  v_etabs_7j int;
  v_soignants_30j int;
  v_etabs_30j int;
  v_missions_terminees int;
  v_missions_mois int;
  v_gmv_total numeric;
  v_revenue_total numeric;
  v_revenue_mois numeric;
  v_taux_activation_soignant numeric;
  v_taux_activation_etab numeric;
  v_acquisition_mensuelle jsonb;
  v_revenue_mensuel jsonb;
  v_charges_equipe numeric;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid()
    AND raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'
  ) THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  SELECT count(*) INTO v_total_soignants FROM soignants;
  SELECT count(*) INTO v_total_etabs FROM etablissements WHERE supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_7j FROM soignants WHERE cree_le >= now() - interval '7 days';
  SELECT count(*) INTO v_etabs_7j FROM etablissements WHERE cree_le >= now() - interval '7 days' AND supprime_le IS NULL;
  SELECT count(*) INTO v_soignants_30j FROM soignants WHERE cree_le >= now() - interval '30 days';
  SELECT count(*) INTO v_etabs_30j FROM etablissements WHERE cree_le >= now() - interval '30 days' AND supprime_le IS NULL;

  SELECT count(*) INTO v_missions_terminees FROM missions WHERE statut = 'TERMINEE';
  SELECT count(*) INTO v_missions_mois FROM missions
    WHERE statut = 'TERMINEE' AND debut_le >= date_trunc('month', now());

  SELECT coalesce(sum(total_brut), 0) INTO v_gmv_total FROM missions WHERE statut = 'TERMINEE';
  SELECT coalesce(sum(montant_commission_ht), 0) INTO v_revenue_total
    FROM missions WHERE statut = 'TERMINEE' AND montant_commission_ht IS NOT NULL;
  SELECT coalesce(sum(montant_commission_ht), 0) INTO v_revenue_mois
    FROM missions
    WHERE statut = 'TERMINEE' AND montant_commission_ht IS NOT NULL
    AND debut_le >= date_trunc('month', now());

  SELECT CASE WHEN v_total_soignants = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT soignant_id) FROM candidatures) / v_total_soignants, 1)
  END INTO v_taux_activation_soignant;

  SELECT CASE WHEN v_total_etabs = 0 THEN 0 ELSE
    round(100.0 * (SELECT count(DISTINCT etablissement_id) FROM missions) / v_total_etabs, 1)
  END INTO v_taux_activation_etab;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.mois), '[]'::jsonb)
  INTO v_acquisition_mensuelle
  FROM (
    SELECT
      to_char(m.mois, 'YYYY-MM') AS mois,
      (SELECT count(*) FROM soignants s WHERE date_trunc('month', s.cree_le) = m.mois) AS soignants,
      (SELECT count(*) FROM etablissements e WHERE date_trunc('month', e.cree_le) = m.mois AND e.supprime_le IS NULL) AS etablissements
    FROM generate_series(
      date_trunc('month', now()) - interval '11 months',
      date_trunc('month', now()),
      interval '1 month'
    ) AS m(mois)
  ) t;

  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.mois), '[]'::jsonb)
  INTO v_revenue_mensuel
  FROM (
    SELECT
      to_char(m.mois, 'YYYY-MM') AS mois,
      coalesce((
        SELECT sum(mi.montant_commission_ht)
        FROM missions mi
        WHERE mi.statut = 'TERMINEE'
        AND mi.montant_commission_ht IS NOT NULL
        AND date_trunc('month', mi.debut_le) = m.mois
      ), 0) AS revenue_ht,
      coalesce((
        SELECT sum(mi.total_brut)
        FROM missions mi
        WHERE mi.statut = 'TERMINEE'
        AND date_trunc('month', mi.debut_le) = m.mois
      ), 0) AS gmv
    FROM generate_series(
      date_trunc('month', now()) - interval '11 months',
      date_trunc('month', now()),
      interval '1 month'
    ) AS m(mois)
  ) t;

  SELECT coalesce(sum(salaire_brut_mensuel * 1.45), 0)
  INTO v_charges_equipe
  FROM equipe_admin WHERE actif = true AND salaire_brut_mensuel > 0;

  v_result := jsonb_build_object(
    'total_soignants', v_total_soignants,
    'total_etabs', v_total_etabs,
    'soignants_7j', v_soignants_7j,
    'etabs_7j', v_etabs_7j,
    'soignants_30j', v_soignants_30j,
    'etabs_30j', v_etabs_30j,
    'missions_terminees', v_missions_terminees,
    'missions_mois', v_missions_mois,
    'gmv_total', v_gmv_total,
    'revenue_total', v_revenue_total,
    'revenue_mois', v_revenue_mois,
    'taux_activation_soignant', v_taux_activation_soignant,
    'taux_activation_etab', v_taux_activation_etab,
    'acquisition_mensuelle', v_acquisition_mensuelle,
    'revenue_mensuel', v_revenue_mensuel,
    'charges_equipe_mensuel', v_charges_equipe
  );

  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_creer_compte_employe(p_email text, p_password text, p_prenom text, p_nom text, p_poste text DEFAULT 'Opérations'::text, p_salaire_brut numeric DEFAULT 0, p_acces_groupes text[] DEFAULT ARRAY['Dashboard'::text])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_role text;
  v_new_user_id uuid;
BEGIN
  SELECT raw_app_meta_data->>'role' INTO v_caller_role
  FROM auth.users WHERE id = auth.uid();

  IF v_caller_role <> 'ADMIN_PLATEFORME' THEN
    RAISE EXCEPTION 'Seul un ADMIN_PLATEFORME peut créer des comptes employés';
  END IF;

  IF p_email IS NULL OR p_email = '' THEN
    RAISE EXCEPTION 'Email requis';
  END IF;
  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'Mot de passe requis (8 caractères minimum)';
  END IF;

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    p_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', ARRAY['email'], 'role', 'ADMIN_PLATEFORME'),
    jsonb_build_object('prenom', p_prenom, 'nom', p_nom),
    now(), now(), '', '', '', ''
  )
  RETURNING id INTO v_new_user_id;

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  VALUES (
    gen_random_uuid(), v_new_user_id,
    jsonb_build_object('sub', v_new_user_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
    'email', v_new_user_id::text, now(), now(), now()
  );

  INSERT INTO equipe_admin (user_id, nom, prenom, email, poste, salaire_brut_mensuel, acces_groupes, date_embauche)
  VALUES (v_new_user_id, p_nom, p_prenom, p_email, p_poste, p_salaire_brut, p_acces_groupes, current_date);

  INSERT INTO admin_securite (admin_id, email_2fa)
  VALUES (v_new_user_id, p_email)
  ON CONFLICT (admin_id) DO UPDATE SET email_2fa = EXCLUDED.email_2fa;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_new_user_id,
    'email', p_email,
    'acces_groupes', to_jsonb(p_acces_groupes)
  );
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_factor_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN '{\"error\":\"Accès refusé\"}'::JSONB; END IF;
    RETURN jsonb_build_object(
        'total_demandes', (SELECT COUNT(*) FROM factor_advances),
        'demandes_en_cours', (SELECT COUNT(*) FROM factor_advances WHERE statut IN ('DEMANDEE','EN_ANALYSE','APPROUVEE')),
        'demandes_financees', (SELECT COUNT(*) FROM factor_advances WHERE statut IN ('FINANCEE','RECOUVREE')),
        'demandes_rejetees', (SELECT COUNT(*) FROM factor_advances WHERE statut = 'REJETEE'),
        'volume_finance_total', (SELECT COALESCE(SUM(montant_net_soignant), 0) FROM factor_advances WHERE statut IN ('FINANCEE','RECOUVREE')),
        'commission_jolene_total', (SELECT COALESCE(SUM(frais_jolene), 0) FROM factor_advances WHERE statut IN ('FINANCEE','RECOUVREE'))
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_creer_litige_force(p_mission_id uuid, p_type_litige type_litige, p_motif text, p_raison_bypass text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_mission RECORD;
  v_litige_id UUID;
  v_est_informatif BOOLEAN;
  v_facture_id UUID;
BEGIN
  IF v_user_id IS NULL OR NOT public.est_admin() THEN
    RETURN jsonb_build_object('error', 'Admin requis pour cette opération.');
  END IF;
  IF length(trim(p_motif)) < 10 THEN
    RETURN jsonb_build_object('error', 'Le motif doit contenir au moins 10 caractères.');
  END IF;
  IF length(trim(COALESCE(p_raison_bypass, ''))) < 10 THEN
    RETURN jsonb_build_object('error', 'La raison du bypass doit contenir au moins 10 caractères (traçabilité).');
  END IF;

  SELECT id, etablissement_id, soignant_assigne_id
    INTO v_mission
    FROM public.missions WHERE id = p_mission_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Mission introuvable');
  END IF;

  IF p_type_litige IN ('DESACCORD_MONTANT_FACTURE', 'NON_PAIEMENT', 'FRAIS_COMPLEMENTAIRES') THEN
    SELECT id INTO v_facture_id
      FROM public.factures_honoraires
     WHERE mission_id = p_mission_id AND statut <> 'BROUILLON'
     ORDER BY date_emission DESC NULLS LAST
     LIMIT 1;
  END IF;

  v_est_informatif := NOT public.fn_fenetre_contestation_ouverte(
    p_type_litige, p_mission_id, v_facture_id
  );

  INSERT INTO public.litiges (
    mission_id, soignant_id, etablissement_id, initie_par,
    motif, statut, type_litige, est_informatif, facture_id
  )
  VALUES (
    p_mission_id, v_mission.soignant_assigne_id, v_mission.etablissement_id, 'ADMIN',
    trim(p_motif), 'OUVERT', p_type_litige, v_est_informatif, v_facture_id
  )
  RETURNING id INTO v_litige_id;

  PERFORM public.fn_ecrire_audit(
    v_user_id, 'ADMIN', 'LITIGE_FORCE_CREATION',
    'litige', v_litige_id, NULL,
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type_litige', p_type_litige,
      'est_informatif', v_est_informatif,
      'raison_bypass', trim(p_raison_bypass),
      'facture_id', v_facture_id
    ),
    NULL, NULL
  );

  RETURN jsonb_build_object(
    'success', TRUE,
    'litige_id', v_litige_id,
    'est_informatif', v_est_informatif,
    'facture_id', v_facture_id
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_forcer_reupload_rib(p_etablissement_id uuid, p_raison text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_etab RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Accès admin uniquement');
  END IF;

  IF p_raison IS NULL OR LENGTH(TRIM(p_raison)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Raison requise (min 10 caractères)');
  END IF;

  SELECT id, nom, rib_s3_key INTO v_etab FROM etablissements WHERE id = p_etablissement_id;
  IF v_etab IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
  END IF;

  UPDATE etablissements SET rib_s3_key = NULL, modifie_le = NOW()
  WHERE id = p_etablissement_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    p_etablissement_id, 'ETABLISSEMENT', 'SYSTEM',
    '⚠️ RIB à re-uploader',
    'Pour des raisons de conformité, vous devez re-uploader votre RIB. Raison : ' || p_raison,
    '/etablissement/finaliser-inscription'
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'ADMIN_ACTION', p_type_ressource := 'etablissement', p_id_ressource := p_etablissement_id,
    p_details := jsonb_build_object(
      'sous_action', 'FORCER_REUPLOAD_RIB',
      'rib_avant', v_etab.rib_s3_key,
      'raison', p_raison
    )
  );

  RETURN jsonb_build_object('success', true, 'etablissement_id', p_etablissement_id);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_externalisation_retry(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Admin requis'); END IF;
  UPDATE public.externalisation_actions SET
    statut = 'PENDING', tentatives = 0, next_retry_at = NOW(),
    cron_lock_at = NULL, cron_lock_par = NULL
  WHERE id = p_id AND statut IN ('ERROR', 'PENDING_AIFE');
  RETURN jsonb_build_object('success', true);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_externalisation_cancel(p_id uuid, p_motif text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Admin requis'); END IF;
  UPDATE public.externalisation_actions SET
    statut = 'CANCELLED', traite_le = NOW(),
    derniere_erreur = 'Annulée par admin : ' || COALESCE(p_motif, '')
  WHERE id = p_id AND statut IN ('PENDING', 'PENDING_AIFE', 'ERROR');
  RETURN jsonb_build_object('success', true);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_detail_contrat(p_contrat_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_contrat jsonb;
  v_audit jsonb;
  v_signatures jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT jsonb_build_object(
    'id', cm.id,
    'numero_contrat', cm.numero_contrat,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'mission_debut_le', m.debut_le,
    'mission_fin_le', m.fin_le,
    'soignant_id', cm.soignant_id,
    'soignant_nom', s.prenom || ' ' || s.nom,
    'soignant_email', su.email,
    'soignant_rpps', s.numero_rpps,
    'etablissement_id', cm.etablissement_id,
    'etablissement_nom', e.nom,
    'etablissement_siret', e.siret,
    'type_contrat', cm.type_contrat,
    'statut', cm.statut,
    'mode_signature', cm.mode_signature,
    'hash_document', cm.hash_document,
    'signature_soignant', cm.signature_soignant,
    'signature_soignant_le', cm.signature_soignant_le,
    'signature_ip_soignant', cm.signature_ip_soignant::text,
    'signature_navigateur_soignant', cm.signature_navigateur_soignant,
    'signature_etablissement', cm.signature_etablissement,
    'signature_etablissement_le', cm.signature_etablissement_le,
    'signature_ip_etablissement', cm.signature_ip_etablissement::text,
    'signature_navigateur_etablissement', cm.signature_navigateur_etablissement,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_effectuee_le', cm.dpae_effectuee_le,
    'dpae_numero', cm.dpae_numero,
    'storage_path', cm.storage_path,
    'pdf_cle_s3', cm.pdf_cle_s3,
    'cree_le', cm.cree_le,
    'modifie_le', cm.modifie_le
  )
  INTO v_contrat
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  LEFT JOIN public.soignants s ON s.id = cm.soignant_id
  LEFT JOIN auth.users su ON su.id = cm.soignant_id
  LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id
  WHERE cm.id = p_contrat_id;

  IF v_contrat IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'CONTRAT_INTROUVABLE');
  END IF;

  -- Signatures détaillées si existantes (Sprint 2)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', sc.id,
    'signataire_role', sc.signataire_role,
    'signe_a', sc.signe_a,
    'ip_signature', sc.ip_signature::text,
    'user_agent', sc.user_agent,
    'hash_document', sc.hash_document,
    'otp_valide_a', sc.otp_valide_a,
    'statut_signature', sc.statut_signature
  ) ORDER BY sc.signe_a DESC), '[]'::jsonb)
  INTO v_signatures
  FROM public.signatures_contrats sc
  WHERE sc.contrat_id = p_contrat_id;

  -- Audit trail
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', ja.id,
    'acteur_id', ja.acteur_id,
    'type_acteur', ja.type_acteur,
    'action', ja.action,
    'details', ja.details,
    'cree_le', ja.cree_le
  ) ORDER BY ja.cree_le DESC), '[]'::jsonb)
  INTO v_audit
  FROM public.journaux_audit ja
  WHERE (ja.type_ressource = 'contrat_mission' OR ja.type_ressource = 'contrats_mission')
    AND ja.id_ressource = p_contrat_id
  LIMIT 100;

  RETURN jsonb_build_object(
    'success', true,
    'contrat', v_contrat,
    'signatures', v_signatures,
    'audit_trail', v_audit
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_detail_template_contrat(p_template_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_template jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT jsonb_build_object(
    'id', t.id,
    'nom', t.nom,
    'type_contrat', t.type_contrat,
    'version', t.version,
    'est_actif', t.est_actif,
    'variables', t.variables,
    'contenu_html', t.contenu_html,
    'cree_le', t.cree_le,
    'modifie_le', t.modifie_le
  )
  INTO v_template
  FROM public.templates_contrat t
  WHERE t.id = p_template_id;

  IF v_template IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'TEMPLATE_INTROUVABLE');
  END IF;

  RETURN jsonb_build_object('success', true, 'template', v_template);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_generer_posts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  SELECT coalesce(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.nb DESC), '[]'::jsonb) INTO v
  FROM (
    SELECT m.profession_requise::text AS profession,
           count(*) AS nb,
           max(m.taux_horaire_base) AS taux_max,
           (SELECT string_agg(DISTINCT e2.adresse_ville, ', ')
            FROM (SELECT e3.adresse_ville FROM missions m3
                  JOIN etablissements e3 ON e3.id = m3.etablissement_id
                  WHERE m3.statut='OUVERTE' AND m3.profession_requise = m.profession_requise
                  LIMIT 3) e2(adresse_ville)) AS villes
    FROM missions m
    WHERE m.statut = 'OUVERTE'
    GROUP BY m.profession_requise
  ) t;
  RETURN v;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_kpi()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    result jsonb;
    debut_semaine timestamptz := date_trunc('week', now());
    debut_mois timestamptz := date_trunc('month', now());
    fin_mois timestamptz := date_trunc('month', now()) + INTERVAL '1 month';
BEGIN
    IF NOT est_admin() THEN RETURN '{\"error\":\"Accès réservé aux administrateurs\"}'::JSONB; END IF;

    SELECT jsonb_build_object(
        -- Totaux
        'soignants_total', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL),
        'etablissements_total', (SELECT COUNT(*) FROM etablissements WHERE supprime_le IS NULL),
        'missions_terminees_total', (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE'),
        'missions_terminees_mois', (SELECT COUNT(*) FROM missions WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois),
        'missions_ouvertes', (SELECT COUNT(*) FROM missions WHERE statut IN ('OUVERTE','ASSIGNEE','EN_COURS')),

        -- Nouveaux
        'soignants_semaine', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL AND cree_le >= debut_semaine),
        'etablissements_semaine', (SELECT COUNT(*) FROM etablissements WHERE supprime_le IS NULL AND cree_le >= debut_semaine),

        -- Litiges
        'litiges_ouverts', (SELECT COUNT(*) FROM litiges WHERE statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','CONTESTEE')),

        -- COMMISSIONS JOLENE = ce que Jolene garde (pas le GMV)
        -- Réalisé ce mois : commissions des missions déjà TERMINEE ce mois
        'ca_commissions_ht_mois', (
            SELECT COALESCE(SUM(montant_commission_ht), 0)
            FROM missions
            WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
        ),
        -- Potentiel ce mois = réalisé + missions ASSIGNEE/EN_COURS dont fin_le est ce mois (projection)
        'ca_potentiel_mois', (
            SELECT COALESCE(SUM(montant_commission_ht), 0)
            FROM missions
            WHERE fin_le >= debut_mois AND fin_le < fin_mois
              AND statut IN ('TERMINEE','ASSIGNEE','EN_COURS')
        ),

        -- Encaissé total = factures payées (l'argent réellement sur le compte)
        'ca_encaisse_total', (
            SELECT COALESCE(SUM(montant_ht), 0)
            FROM factures
            WHERE statut = 'PAYEE'
        ),
        -- Potentiel total = toutes les commissions sur missions TERMINEE (facturables)
        'ca_potentiel_total', (
            SELECT COALESCE(SUM(montant_commission_ht), 0)
            FROM missions
            WHERE statut = 'TERMINEE'
        ),

        -- GMV (volume brut transité) = total brut des missions = ce que les établissements paient aux soignants via Jolene
        -- C'est PAS du CA Jolene, juste le volume d'affaires qui passe par la plateforme
        'gmv_mois', (
            SELECT COALESCE(SUM(total_brut), 0)
            FROM missions
            WHERE statut = 'TERMINEE' AND fin_le >= debut_mois AND fin_le < fin_mois
        ),
        'gmv_total', (
            SELECT COALESCE(SUM(total_brut), 0)
            FROM missions
            WHERE statut = 'TERMINEE'
        ),

        'taux_acceptation_mois', (
            SELECT CASE 
                WHEN COUNT(*) FILTER (WHERE cree_le >= debut_mois) = 0 THEN 0
                ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE statut IN ('ASSIGNEE','EN_COURS','TERMINEE') AND cree_le >= debut_mois)
                    / NULLIF(COUNT(*) FILTER (WHERE cree_le >= debut_mois), 0))
            END
            FROM missions
        ),

        'factures_impayees', (SELECT COUNT(*) FROM factures WHERE statut IN ('EMISE','EN_RETARD')),
        'docs_en_attente', (SELECT COUNT(*) FROM documents_soignants WHERE statut_verification = 'EN_ATTENTE'),
        'etab_en_attente', (SELECT COUNT(*) FROM etablissements WHERE statut_verification = 'EN_ATTENTE')
    ) INTO result;

    RETURN result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_graphiques()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE result jsonb;
BEGIN
    IF NOT est_admin() THEN RETURN '{\"error\":\"Accès réservé aux administrateurs\"}'::JSONB; END IF;
    SELECT jsonb_build_object(
        'missions_par_semaine', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.semaine)
            FROM (SELECT date_trunc('week', cree_le)::DATE AS semaine, COUNT(*) AS total
                FROM missions WHERE cree_le >= NOW() - INTERVAL '12 weeks'
                GROUP BY date_trunc('week', cree_le)) t
        ), '[]'::jsonb),
        'ca_par_mois', COALESCE((
            SELECT jsonb_agg(row_to_json(t) ORDER BY t.mois)
            FROM (SELECT date_trunc('month', date_emission)::DATE AS mois, SUM(montant_ht) AS ca_ht
                FROM factures WHERE date_emission >= NOW() - INTERVAL '6 months' AND statut != 'ANNULEE'
                GROUP BY date_trunc('month', date_emission)) t
        ), '[]'::jsonb)
    ) INTO result;
    RETURN result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_incoherences_identite()
 RETURNS TABLE(soignant_id uuid, prenom text, nom text, prenom_profil text, nom_profil text, nom_rpps text, nom_cni text, coherence_identite text, coherence_details jsonb, rpps_verifie boolean, identite_verifiee boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN; END IF;
    RETURN QUERY
    SELECT
      s.id,
      s.prenom::TEXT,
      s.nom::TEXT,
      s.prenom::TEXT AS prenom_profil,
      s.nom::TEXT AS nom_profil,
      (s.coherence_details->>'nom_rpps')::TEXT,
      (s.coherence_details->>'nom_cni')::TEXT,
      s.coherence_identite,
      s.coherence_details,
      s.rpps_verifie,
      s.identite_verifiee
    FROM soignants s
    WHERE s.coherence_identite = 'INCOHERENT'
    AND s.supprime_le IS NULL
    ORDER BY s.modifie_le DESC;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_invocations_purge()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ DECLARE v_deleted INTEGER := 0; v_partial INTEGER; v_lock_acquired BOOLEAN; BEGIN v_lock_acquired := pg_try_advisory_xact_lock(hashtext('admin_invocations_purge')); IF NOT v_lock_acquired THEN RAISE EXCEPTION 'Purge déjà en cours'; END IF; DELETE FROM admin_invocations WHERE target_function IN ('generate-invoice','submit-to-chorus','factor-request-advance') AND invoked_at < now() - INTERVAL '10 years'; GET DIAGNOSTICS v_partial = ROW_COUNT; v_deleted := v_deleted + v_partial; DELETE FROM admin_invocations WHERE target_function NOT IN ('generate-invoice','submit-to-chorus','factor-request-advance') AND status_returned IS NOT NULL AND status_returned >= 400 AND invoked_at < now() - INTERVAL '2 years'; GET DIAGNOSTICS v_partial = ROW_COUNT; v_deleted := v_deleted + v_partial; DELETE FROM admin_invocations WHERE target_function NOT IN ('generate-invoice','submit-to-chorus','factor-request-advance') AND (status_returned IS NULL OR status_returned < 400) AND invoked_at < now() - INTERVAL '90 days'; GET DIAGNOSTICS v_partial = ROW_COUNT; v_deleted := v_deleted + v_partial; RETURN v_deleted; END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_invocations_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_result_cols_were_null BOOLEAN;
  v_result_cols_now_set BOOLEAN;
  v_result_cols_unchanged BOOLEAN;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF pg_try_advisory_xact_lock(hashtext('admin_invocations_purge')) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'DELETE interdit sur admin_invocations (audit ops)';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.admin_user_id IS DISTINCT FROM OLD.admin_user_id
       OR NEW.target_function IS DISTINCT FROM OLD.target_function
       OR NEW.target_payload IS DISTINCT FROM OLD.target_payload
       OR NEW.reason IS DISTINCT FROM OLD.reason
       OR NEW.dry_run IS DISTINCT FROM OLD.dry_run
       OR NEW.is_test IS DISTINCT FROM OLD.is_test
       OR NEW.invoked_at IS DISTINCT FROM OLD.invoked_at
       OR NEW.request_id IS DISTINCT FROM OLD.request_id
    THEN
      RAISE EXCEPTION 'admin_invocations: colonnes contexte immuables';
    END IF;

    IF NEW.internal_status IS DISTINCT FROM OLD.internal_status THEN
      IF OLD.internal_status = 'PENDING' AND NEW.internal_status NOT IN ('INVOKED', 'CRASHED') THEN
        RAISE EXCEPTION 'admin_invocations: transition invalide depuis PENDING';
      END IF;
      IF OLD.internal_status = 'INVOKED' AND NEW.internal_status NOT IN ('COMPLETED', 'CRASHED') THEN
        RAISE EXCEPTION 'admin_invocations: transition invalide depuis INVOKED';
      END IF;
      IF OLD.internal_status IN ('COMPLETED', 'CRASHED') THEN
        RAISE EXCEPTION 'admin_invocations: etat terminal, pas de transition';
      END IF;
    END IF;

    v_result_cols_were_null := OLD.status_returned IS NULL AND OLD.duration_ms IS NULL AND OLD.response_excerpt IS NULL AND OLD.completed_at IS NULL;
    v_result_cols_now_set := NEW.status_returned IS NOT NULL AND NEW.duration_ms IS NOT NULL AND NEW.response_excerpt IS NOT NULL AND NEW.completed_at IS NOT NULL;
    v_result_cols_unchanged := NEW.status_returned IS NOT DISTINCT FROM OLD.status_returned AND NEW.duration_ms IS NOT DISTINCT FROM OLD.duration_ms AND NEW.response_excerpt IS NOT DISTINCT FROM OLD.response_excerpt AND NEW.completed_at IS NOT DISTINCT FROM OLD.completed_at;

    IF v_result_cols_unchanged THEN RETURN NEW; END IF;
    IF v_result_cols_were_null AND v_result_cols_now_set THEN RETURN NEW; END IF;

    IF NOT v_result_cols_were_null THEN
      RAISE EXCEPTION 'admin_invocations: resultat deja rempli';
    ELSE
      RAISE EXCEPTION 'admin_invocations: 4 colonnes resultat doivent etre remplies ensemble';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lever_suspension(p_soignant_id uuid, p_raison text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_soignant RECORD; v_url TEXT; v_token TEXT;
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Accès admin uniquement'); END IF;
  IF p_raison IS NULL OR LENGTH(TRIM(p_raison)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Raison requise');
  END IF;

  SELECT id, prenom, statut_compte INTO v_soignant FROM soignants WHERE id = p_soignant_id;
  IF v_soignant IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Soignant introuvable'); END IF;
  IF v_soignant.statut_compte = 'ACTIF' THEN RETURN jsonb_build_object('success', false, 'error', 'Compte déjà actif'); END IF;

  UPDATE soignants SET
    statut_compte = 'ACTIF', suspension_raison = NULL, suspension_le = NULL,
    nb_absences_sans_prevenir_6_mois = 0, modifie_le = NOW()
  WHERE id = p_soignant_id;

  INSERT INTO notifications (destinataire_id, type_destinataire, type, titre, corps, lien)
  VALUES (
    p_soignant_id, 'SOIGNANT', 'SYSTEM',
    '✅ Compte réactivé',
    'Votre compte est réactivé. Vous pouvez à nouveau candidater aux missions. Raison : ' || p_raison,
    '/soignant/tableau-de-bord'
  );

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'COMPTE_LEVEE_SUSPENSION', p_type_ressource := 'soignant', p_id_ressource := p_soignant_id,
    p_details := jsonb_build_object('raison', p_raison)
  );

  BEGIN
    v_url := public.fn_lire_secret_cron('supabase_url');
    v_token := public.fn_lire_secret_cron('service_role_key');
    IF v_url IS NOT NULL AND v_token IS NOT NULL THEN
      PERFORM net.http_post(
        url := v_url || '/functions/v1/send-email',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_token),
        body := jsonb_build_object(
          'type', 'COMPTE_REACTIVE', 'destinataire_id', p_soignant_id,
          'data', jsonb_build_object('prenom', v_soignant.prenom, 'raison', p_raison)
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_health_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_result jsonb;
  v_crons_health jsonb;
  v_stripe_health jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès admin uniquement');
  END IF;

  SELECT public.fn_check_crons_health() INTO v_crons_health;
  SELECT public.fn_check_stripe_webhook_health() INTO v_stripe_health;

  v_result := jsonb_build_object(
    'timestamp', NOW(),
    'database', jsonb_build_object('connected', true, 'version', current_setting('server_version')),
    'crons', v_crons_health,
    'stripe_webhooks', v_stripe_health,
    'alertes_actives', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'type', type_alerte, 'severite', severite,
        'source', source, 'message', message, 'cree_le', cree_le
      ) ORDER BY cree_le DESC), '[]'::jsonb)
      FROM alertes_systeme WHERE resolu_le IS NULL
    ),
    'stats_temps_reel', jsonb_build_object(
      'soignants_actifs_7j', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL AND derniere_activite_le > NOW() - INTERVAL '7 days'),
      'missions_ouvertes', (SELECT COUNT(*) FROM missions WHERE statut = 'OUVERTE'),
      'missions_assignees', (SELECT COUNT(*) FROM missions WHERE statut = 'ASSIGNEE'),
      'missions_en_cours', (SELECT COUNT(*) FROM missions WHERE statut = 'EN_COURS'),
      'candidatures_pending', (SELECT COUNT(*) FROM candidatures WHERE statut = 'EN_ATTENTE'),
      'litiges_ouverts', (SELECT COUNT(*) FROM litiges WHERE statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','MEDIATION_EN_COURS','REVUE_ADMIN'))
    ),
    'logs_recents', jsonb_build_object(
      'audit_24h', (SELECT COUNT(*) FROM journaux_audit WHERE cree_le > NOW() - INTERVAL '24 hours'),
      'emails_24h', (SELECT COUNT(*) FROM emails_envoyes WHERE cree_le > NOW() - INTERVAL '24 hours'),
      'sms_24h', (SELECT COUNT(*) FROM sms_envoyes WHERE cree_le > NOW() - INTERVAL '24 hours'),
      'notifications_24h', (SELECT COUNT(*) FROM notifications WHERE cree_le > NOW() - INTERVAL '24 hours')
    )
  );
  RETURN v_result;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_get_user_id_by_email(p_email text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  IF NOT (
    auth.role() = 'service_role'
    OR (auth.uid() IS NOT NULL AND est_admin())
  ) THEN
    RAISE EXCEPTION 'Accès refusé: réservé service_role ou admin';
  END IF;

  SELECT id INTO v_id
  FROM auth.users
  WHERE email = lower(p_email)
  LIMIT 1;

  RETURN v_id;
END;
$function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_externalisations(p_statut text DEFAULT NULL::text, p_type_action text DEFAULT NULL::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Admin requis'); END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'type_action', type_action, 'statut', statut, 'source', source, 'source_id', source_id,
    'tentatives', tentatives, 'derniere_erreur', derniere_erreur, 'next_retry_at', next_retry_at,
    'cree_le', cree_le, 'traite_le', traite_le, 'payload', payload, 'resultat', resultat
  ) ORDER BY cree_le DESC), '[]'::jsonb) INTO v_result
  FROM (SELECT * FROM public.externalisation_actions
    WHERE (p_statut IS NULL OR statut = p_statut)
      AND (p_type_action IS NULL OR type_action = p_type_action)
    ORDER BY cree_le DESC LIMIT p_limit) t;
  RETURN jsonb_build_object('success', true, 'actions', v_result);
END; $function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_contrats(p_filtre_statut text DEFAULT NULL::text, p_recherche text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_contrats jsonb;
  v_total int;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT count(*) INTO v_total
  FROM public.contrats_mission cm
  JOIN public.missions m ON m.id = cm.mission_id
  LEFT JOIN public.soignants s ON s.id = cm.soignant_id
  LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id
  WHERE (p_filtre_statut IS NULL OR cm.statut = p_filtre_statut)
    AND (p_recherche IS NULL OR
         m.intitule ILIKE '%' || p_recherche || '%' OR
         cm.numero_contrat ILIKE '%' || p_recherche || '%' OR
         s.nom ILIKE '%' || p_recherche || '%' OR
         s.prenom ILIKE '%' || p_recherche || '%' OR
         e.nom ILIKE '%' || p_recherche || '%');

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', cm.id,
    'numero_contrat', cm.numero_contrat,
    'mission_id', cm.mission_id,
    'mission_intitule', m.intitule,
    'soignant_id', cm.soignant_id,
    'soignant_nom', s.prenom || ' ' || s.nom,
    'etablissement_id', cm.etablissement_id,
    'etablissement_nom', e.nom,
    'type_contrat', cm.type_contrat,
    'statut', cm.statut,
    'hash_court', CASE WHEN cm.hash_document IS NOT NULL THEN substring(cm.hash_document, 1, 12) || '...' ELSE NULL END,
    'signature_soignant', cm.signature_soignant,
    'signature_etablissement', cm.signature_etablissement,
    'signature_soignant_le', cm.signature_soignant_le,
    'signature_etablissement_le', cm.signature_etablissement_le,
    'mode_signature', cm.mode_signature,
    'dpae_effectuee', cm.dpae_effectuee,
    'dpae_numero', cm.dpae_numero,
    'cree_le', cm.cree_le
  ) ORDER BY cm.cree_le DESC), '[]'::jsonb)
  INTO v_contrats
  FROM (
    SELECT cm.* FROM public.contrats_mission cm
    JOIN public.missions m ON m.id = cm.mission_id
    LEFT JOIN public.soignants s ON s.id = cm.soignant_id
    LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id
    WHERE (p_filtre_statut IS NULL OR cm.statut = p_filtre_statut)
      AND (p_recherche IS NULL OR
           m.intitule ILIKE '%' || p_recherche || '%' OR
           cm.numero_contrat ILIKE '%' || p_recherche || '%' OR
           s.nom ILIKE '%' || p_recherche || '%' OR
           s.prenom ILIKE '%' || p_recherche || '%' OR
           e.nom ILIKE '%' || p_recherche || '%')
    ORDER BY cm.cree_le DESC
    LIMIT p_limit OFFSET p_offset
  ) cm
  JOIN public.missions m ON m.id = cm.mission_id
  LEFT JOIN public.soignants s ON s.id = cm.soignant_id
  LEFT JOIN public.etablissements e ON e.id = cm.etablissement_id;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset,
    'contrats', v_contrats
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_alertes_pointage(p_type_filtre text DEFAULT NULL::text, p_statut_filtre text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_alertes jsonb;
  v_total int;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COUNT(*) INTO v_total
  FROM public.alertes_systeme a
  WHERE a.type_alerte IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT')
    AND (p_type_filtre IS NULL OR a.type_alerte = p_type_filtre)
    AND (p_statut_filtre IS NULL
         OR (p_statut_filtre = 'OUVERTE' AND a.resolu_le IS NULL)
         OR (p_statut_filtre = 'RESOLUE' AND a.resolu_le IS NOT NULL));

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'type_alerte', a.type_alerte,
    'severite', a.severite,
    'source', a.source,
    'message', a.message,
    'details', a.details,
    'resolu_le', a.resolu_le,
    'cree_le', a.cree_le
  ) ORDER BY a.cree_le DESC), '[]'::jsonb)
  INTO v_alertes
  FROM (
    SELECT * FROM public.alertes_systeme
    WHERE type_alerte IN ('TELEPORTATION_DETECTED', 'POINTAGE_INCOHERENT')
      AND (p_type_filtre IS NULL OR type_alerte = p_type_filtre)
      AND (p_statut_filtre IS NULL
           OR (p_statut_filtre = 'OUVERTE' AND resolu_le IS NULL)
           OR (p_statut_filtre = 'RESOLUE' AND resolu_le IS NOT NULL))
    ORDER BY cree_le DESC
    LIMIT p_limit OFFSET p_offset
  ) a;

  RETURN jsonb_build_object(
    'success', true,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset,
    'alertes', v_alertes
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_heures_externes(p_statut text DEFAULT 'EN_ATTENTE'::text, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_lignes JSONB;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  SELECT COALESCE(jsonb_agg(ligne ORDER BY (ligne->>'cree_le') DESC), '[]'::jsonb)
    INTO v_lignes
  FROM (
    SELECT jsonb_build_object(
      'id', h.id,
      'soignant_id', h.soignant_id,
      'soignant_nom', s.nom,
      'soignant_prenom', s.prenom,
      'profession', s.profession,
      'type_exercice', s.type_exercice,
      'etablissement_nom', h.etablissement_nom,
      'etablissement_type', h.etablissement_type,
      'date_debut', h.date_debut,
      'date_fin', h.date_fin,
      'heures_declarees', h.heures_declarees,
      'heures_extraites_ia', h.heures_extraites_ia,
      'coherence_ia', h.coherence_ia,
      'statut_validation', h.statut_validation,
      'commentaire_validation', h.commentaire_validation,
      'attestation_url', h.attestation_url,
      'attestation_nom_fichier', h.attestation_nom_fichier,
      'verifie_ia_le', h.verifie_ia_le,
      'cree_le', h.cree_le
    ) AS ligne
    FROM public.heures_externes_soignants h
    JOIN public.soignants s ON s.id = h.soignant_id
    WHERE (p_statut = 'TOUS' OR h.statut_validation = p_statut)
    ORDER BY h.cree_le DESC
    LIMIT GREATEST(1, LEAST(p_limit, 500))
  ) sub;

  RETURN jsonb_build_object('success', true, 'heures', v_lignes);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements_a_verifier(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_resultat jsonb;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_resultat
  FROM (
    SELECT id, nom,
           siret, siret_verifie, siret_raison_sociale, siret_categorie_juridique,
           siret_code_naf, siret_est_actif,
           finess, finess_verifie, finess_raison_sociale,
           finess_categorie, finess_secteur, finess_est_public,
           adresse_rue, adresse_code_postal, adresse_ville, adresse_departement,
           telephone_contact, telephone_verifie,
           representant_nom, representant_prenom, representant_identite_verifiee,
           representant_piece_s3_key, representant_piece_type_document,
           representant_identite_resultat_ia,
           dirigeants, email_contact, email_contact_verifie,
           rattachement_methode, rattachement_verifie, statut_verification,
           contrat_valide, peut_publier_missions, motif_rejet, cree_le
    FROM etablissements
    WHERE supprime_le IS NULL
      AND COALESCE(rattachement_verifie, false) = false
      AND COALESCE(statut_verification, '') <> 'REJETE'
    ORDER BY cree_le DESC NULLS LAST
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  ) e;

  RETURN jsonb_build_object('success', true, 'etablissements', v_resultat);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_etablissements(p_recherche text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, nom text, type text, ville text, code_postal text, telephone text, email text, statut_verification text, peut_publier boolean, cree_le timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.est_admin() THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  RETURN QUERY
  SELECT e.id, e.nom::text, e.type::text, e.adresse_ville::text, e.adresse_code_postal::text,
         e.telephone_contact::text, e.email_contact::text, e.statut_verification::text,
         e.peut_publier_missions, e.cree_le
  FROM public.etablissements e
  WHERE e.supprime_le IS NULL
    AND (p_recherche IS NULL OR p_recherche = ''
         OR e.nom ILIKE '%' || p_recherche || '%'
         OR e.adresse_ville ILIKE '%' || p_recherche || '%')
  ORDER BY e.cree_le DESC
  LIMIT 500;
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_paliers_bfa()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  RETURN jsonb_build_object(
    'paliers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id, 'nom', p.nom, 'missions_min', p.missions_min,
        'missions_max', p.missions_max, 'taux_bfa', p.taux_bfa,
        'ordre', p.ordre, 'est_actif', p.est_actif
      ) ORDER BY p.ordre)
      FROM paliers_bfa p
    ), '[]'::jsonb),
    'groupes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', g.id, 'nom', g.nom, 'bfa_eligible', g.bfa_eligible,
        'bfa_contrat_signe_le', g.bfa_contrat_signe_le,
        'nb_etablissements', (SELECT count(*) FROM etablissements e WHERE e.groupe_sante_id = g.id AND e.supprime_le IS NULL)
      ) ORDER BY g.nom)
      FROM groupes_sante g
    ), '[]'::jsonb)
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_parametres()
 RETURNS SETOF parametres_systeme
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  RETURN QUERY SELECT * FROM public.parametres_systeme ORDER BY categorie, label;
END; $function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_mandats_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT est_admin() THEN RETURN '{\"error\":\"Accès refusé\"}'::JSONB; END IF;
    RETURN jsonb_build_object(
        'total_soignants', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL),
        'mandat_signe', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL AND mandat_facturation_signe = TRUE),
        'mandat_non_signe', (SELECT COUNT(*) FROM soignants WHERE supprime_le IS NULL AND COALESCE(mandat_facturation_signe, FALSE) = FALSE),
        'total_factures_honoraires', (SELECT COUNT(*) FROM factures_honoraires),
        'montant_factures_honoraires_total', (SELECT COALESCE(SUM(montant_ttc), 0) FROM factures_honoraires),
        'montant_factures_honoraires_impayees', (SELECT COALESCE(SUM(montant_ttc), 0) FROM factures_honoraires WHERE statut IN ('EMISE','EN_RETARD'))
    );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_taux_commission()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'groupes', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id, 'nom', nom, 'siren', siren,
        'taux_commission_negocie', taux_commission_negocie,
        'contrat_debut', contrat_debut, 'contrat_fin', contrat_fin,
        'nb_etablissements', (SELECT count(*) FROM etablissements e WHERE e.groupe_sante_id = g.id)
      ) ORDER BY nom), '[]'::jsonb)
      FROM groupes_sante g WHERE supprime_le IS NULL
    ),
    'etablissements', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', e.id, 'nom', e.nom, 'siret', e.siret,
        'taux_commission_negocie', e.taux_commission_negocie,
        'groupe_id', e.groupe_sante_id, 'groupe_nom', g.nom,
        'taux_groupe', g.taux_commission_negocie,
        'taux_resolu', COALESCE(e.taux_commission_negocie, g.taux_commission_negocie, 15),
        'taux_resolu_source', CASE
          WHEN e.taux_commission_negocie IS NOT NULL THEN 'etablissement'
          WHEN g.taux_commission_negocie IS NOT NULL THEN 'groupe'
          ELSE 'defaut_15' END
      ) ORDER BY e.nom), '[]'::jsonb)
      FROM etablissements e
      LEFT JOIN groupes_sante g ON g.id = e.groupe_sante_id
    )
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_marquer_absence_sans_prevenir(p_mission_id uuid, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_mission RECORD;
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success', false, 'error', 'Accès admin uniquement'); END IF;

  SELECT id, statut, soignant_assigne_id INTO v_mission FROM missions WHERE id = p_mission_id;
  IF v_mission IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable'); END IF;
  IF v_mission.statut <> 'ABSENCE' THEN RETURN jsonb_build_object('success', false, 'error', 'Mission doit être en statut ABSENCE'); END IF;

  UPDATE missions SET absence_sans_prevenir = true, modifie_le = NOW() WHERE id = p_mission_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'ADMIN_ACTION', p_type_ressource := 'mission', p_id_ressource := p_mission_id,
    p_details := jsonb_build_object('action', 'absence_sans_prevenir_marquee', 'motif', p_motif, 'soignant_id', v_mission.soignant_assigne_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_marquer_facture_en_retard(p_facture_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_ancien_statut text;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Accès refusé');
  END IF;

  SELECT statut INTO v_ancien_statut FROM public.factures WHERE id = p_facture_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Facture introuvable');
  END IF;

  UPDATE public.factures SET statut = 'EN_RETARD' WHERE id = p_facture_id;

  PERFORM fn_ecrire_audit_safe(
    v_actor, 'ADMIN_PLATEFORME',
    'FACTURE_MARQUEE_EN_RETARD', 'facture', p_facture_id,
    NULL,
    jsonb_build_object('ancien_statut', v_ancien_statut, 'nouveau_statut', 'EN_RETARD'),
    NULL, NULL
  );

  RETURN jsonb_build_object('ok', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_reclamations(p_statut text DEFAULT 'PENDING'::text, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL OR NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'evenement_type', r.evenement_type,
    'evenement_id', COALESCE(r.evenement_soignant_id, r.evenement_etab_id),
    'event_type_evenement',
      COALESCE((SELECT type_evenement FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT type_evenement FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'event_points',
      COALESCE((SELECT points FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT points FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'event_motif',
      COALESCE((SELECT motif FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT motif FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'event_cree_le',
      COALESCE((SELECT cree_le FROM public.evenements_score_soignant WHERE id = r.evenement_soignant_id),
                (SELECT cree_le FROM public.evenements_score_etab WHERE id = r.evenement_etab_id)),
    'contesteur_id', r.contesteur_id,
    'motif_categorie', r.motif_categorie,
    'texte_libre', r.texte_libre,
    'justificatif_storage_path', r.justificatif_storage_path,
    'statut', r.statut,
    'decision_admin', r.decision_admin,
    'motif_admin', r.motif_admin,
    'cree_le', r.cree_le,
    'jours_attente', EXTRACT(EPOCH FROM (NOW() - r.cree_le)) / 86400
  ) ORDER BY r.cree_le ASC), '[]'::jsonb) INTO v_result
  FROM public.reclamations_score r
  WHERE (p_statut IS NULL OR p_statut = 'TOUS' OR r.statut = p_statut)
  LIMIT p_limit;

  RETURN jsonb_build_object('success', true, 'reclamations', v_result);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_templates_contrats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_templates jsonb;
BEGIN
  IF NOT public.est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error_code', 'NON_AUTORISE');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'nom', t.nom,
    'type_contrat', t.type_contrat,
    'version', t.version,
    'est_actif', t.est_actif,
    'variables', t.variables,
    'contenu_taille', length(t.contenu_html),
    'cree_le', t.cree_le,
    'modifie_le', t.modifie_le
  ) ORDER BY t.type_contrat, t.version DESC, t.nom), '[]'::jsonb)
  INTO v_templates
  FROM public.templates_contrat t;

  RETURN jsonb_build_object('success', true, 'templates', v_templates);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_lister_signalements(p_statut text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, signaleur_id uuid, signaleur_type text, signaleur_nom text, cible_id uuid, cible_type text, cible_nom text, categorie text, motif text, mission_id uuid, statut text, resolution text, traite_le timestamp with time zone, cree_le timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    s.id, s.signaleur_id, s.signaleur_type,
    CASE WHEN s.signaleur_type = 'SOIGNANT'
      THEN (SELECT trim(coalesce(so.prenom,'') || ' ' || coalesce(so.nom,'')) FROM soignants so WHERE so.id = s.signaleur_id)
      ELSE (SELECT et.nom FROM etablissements et WHERE et.id = s.signaleur_id)
    END AS signaleur_nom,
    s.cible_id, s.cible_type,
    CASE WHEN s.cible_type = 'SOIGNANT'
      THEN (SELECT trim(coalesce(so.prenom,'') || ' ' || coalesce(so.nom,'')) FROM soignants so WHERE so.id = s.cible_id)
      ELSE (SELECT et.nom FROM etablissements et WHERE et.id = s.cible_id)
    END AS cible_nom,
    s.categorie, s.motif, s.mission_id, s.statut, s.resolution, s.traite_le, s.cree_le
  FROM public.signalements s
  WHERE public.est_admin()
    AND (p_statut IS NULL OR s.statut = p_statut)
  ORDER BY CASE s.statut WHEN 'OUVERT' THEN 0 WHEN 'EN_COURS' THEN 1 ELSE 2 END, s.cree_le DESC;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_maj_parametre(p_cle text, p_valeur numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v public.parametres_systeme;
BEGIN
  IF NOT public.est_admin() THEN RAISE EXCEPTION 'Accès admin requis'; END IF;
  SELECT * INTO v FROM public.parametres_systeme WHERE cle = p_cle;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Paramètre inconnu'); END IF;
  IF v.val_min IS NOT NULL AND p_valeur < v.val_min THEN
    RETURN jsonb_build_object('success', false, 'error', 'Valeur sous le minimum (' || v.val_min || ')'); END IF;
  IF v.val_max IS NOT NULL AND p_valeur > v.val_max THEN
    RETURN jsonb_build_object('success', false, 'error', 'Valeur au-dessus du maximum (' || v.val_max || ')'); END IF;
  UPDATE public.parametres_systeme SET valeur = p_valeur, maj_le = now() WHERE cle = p_cle;
  RETURN jsonb_build_object('success', true);
END; $function$

---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_moderer_evaluation(p_evaluation_id uuid, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_action_norm TEXT;
BEGIN
    IF NOT est_admin() THEN
        RETURN jsonb_build_object('error', 'Accès refusé — admin uniquement');
    END IF;

    -- Normaliser l'action pour accepter MAJ/min et plusieurs synonymes
    v_action_norm := UPPER(COALESCE(p_action, ''));

    IF v_action_norm IN ('PUBLIER', 'AFFICHER', 'DEMASQUER') THEN
        UPDATE evaluations SET visible = TRUE WHERE id = p_evaluation_id;
    ELSIF v_action_norm IN ('MASQUER', 'CACHER') THEN
        UPDATE evaluations SET visible = FALSE WHERE id = p_evaluation_id;
    ELSIF v_action_norm IN ('SUPPRIMER', 'SUPPRESSION') THEN
        DELETE FROM evaluations WHERE id = p_evaluation_id;
    ELSE
        RETURN jsonb_build_object('error', 'Action invalide : PUBLIER, MASQUER ou SUPPRIMER');
    END IF;

    -- Audit (fix: id_ressource au lieu de ressource_id)
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'MODERATION_EVALUATION', 'evaluation', p_evaluation_id,
        jsonb_build_object('action', v_action_norm));

    RETURN jsonb_build_object('success', TRUE, 'action', v_action_norm);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_moderer_document(p_document_id uuid, p_action text, p_motif text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_doc RECORD;
BEGIN
    IF NOT est_admin() THEN
        RETURN '{\"error\":\"Non autorisé\"}'::JSONB;
    END IF;
    SELECT * INTO v_doc FROM documents_soignants WHERE id = p_document_id;
    IF NOT FOUND THEN
        RETURN '{\"error\":\"Document non trouvé\"}'::JSONB;
    END IF;
    IF p_action = 'VALIDER' THEN
        UPDATE documents_soignants SET statut_verification = 'VERIFIE', verifie_par = auth.uid(), verifie_le = NOW(), motif_rejet = NULL WHERE id = p_document_id;
    ELSIF p_action = 'REJETER' THEN
        UPDATE documents_soignants SET statut_verification = 'REJETE', verifie_par = auth.uid(), verifie_le = NOW(), motif_rejet = COALESCE(p_motif, 'Document non conforme') WHERE id = p_document_id;
    ELSE
        RETURN jsonb_build_object('error', 'Action invalide: ' || p_action);
    END IF;
    INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
    VALUES (auth.uid(), 'ADMIN', 'MODERATION_DOCUMENT', 'document', p_document_id,
        jsonb_build_object('action', p_action, 'type_document', v_doc.type_document, 'soignant_id', v_doc.soignant_id));
    PERFORM fn_calculer_tous_documents_valides(v_doc.soignant_id);
    RETURN jsonb_build_object('success', true, 'action', p_action);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_taux_commission(p_etablissement_id uuid DEFAULT NULL::uuid, p_groupe_id uuid DEFAULT NULL::uuid, p_nouveau_taux numeric DEFAULT NULL::numeric, p_raison text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_old_taux numeric;
  v_target text;
  v_target_id uuid;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Admin requis');
  END IF;

  IF (p_etablissement_id IS NULL AND p_groupe_id IS NULL)
     OR (p_etablissement_id IS NOT NULL AND p_groupe_id IS NOT NULL) THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Exactement un de p_etablissement_id ou p_groupe_id doit être fourni');
  END IF;

  IF p_nouveau_taux IS NOT NULL AND (p_nouveau_taux < 0 OR p_nouveau_taux > 100) THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Taux de commission hors bornes (attendu entre 0 et 100)');
  END IF;

  IF COALESCE(trim(p_raison), '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Raison obligatoire (audit)');
  END IF;

  IF p_etablissement_id IS NOT NULL THEN
    SELECT taux_commission_negocie INTO v_old_taux
    FROM etablissements WHERE id = p_etablissement_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Établissement introuvable');
    END IF;
    UPDATE etablissements SET taux_commission_negocie = p_nouveau_taux WHERE id = p_etablissement_id;
    v_target := 'etablissement';
    v_target_id := p_etablissement_id;
  ELSE
    SELECT taux_commission_negocie INTO v_old_taux
    FROM groupes_sante WHERE id = p_groupe_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Groupe introuvable');
    END IF;
    UPDATE groupes_sante SET taux_commission_negocie = p_nouveau_taux WHERE id = p_groupe_id;
    v_target := 'groupe';
    v_target_id := p_groupe_id;
  END IF;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'TAUX_COMMISSION_MODIFIE',
    p_type_ressource := v_target,
    p_id_ressource := v_target_id,
    p_details := jsonb_build_object(
      'old_taux', v_old_taux,
      'new_taux', p_nouveau_taux,
      'raison', p_raison,
      'note', 'Impacte uniquement les futures missions assignées (gel existant préservé)'
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'cible', v_target,
    'cible_id', v_target_id,
    'ancien_taux', v_old_taux,
    'nouveau_taux', p_nouveau_taux
  );
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_gel_scope_litige(p_litige_id uuid, p_nouveau_scope text, p_raison text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_old_scope text;
  v_litige RECORD;
BEGIN
  IF NOT est_admin() THEN RETURN jsonb_build_object('success',false,'error','Admin requis'); END IF;
  IF p_nouveau_scope NOT IN ('MISSION_ENTIERE','FACTURE_UNIQUE','AUCUN','PERIODE_LITIGIEUSE') THEN
    RETURN jsonb_build_object('success',false,'error','Scope invalide');
  END IF;
  IF COALESCE(trim(p_raison),'') = '' THEN RETURN jsonb_build_object('success',false,'error','Raison obligatoire'); END IF;
  SELECT * INTO v_litige FROM litiges WHERE id = p_litige_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'error','Litige introuvable'); END IF;
  v_old_scope := v_litige.gel_facture_scope;
  IF p_nouveau_scope = 'FACTURE_UNIQUE' AND v_litige.facture_id IS NULL THEN
    RETURN jsonb_build_object('success',false,'error','FACTURE_UNIQUE requiert facture_id');
  END IF;
  IF p_nouveau_scope = 'PERIODE_LITIGIEUSE' AND (v_litige.periode_debut IS NULL OR v_litige.periode_fin IS NULL) THEN
    RETURN jsonb_build_object('success',false,'error','PERIODE_LITIGIEUSE requiert periode_debut et periode_fin');
  END IF;
  UPDATE litiges SET gel_facture_scope = p_nouveau_scope WHERE id = p_litige_id;
  UPDATE factures_honoraires SET statut_litige='NORMAL', litige_id=NULL
   WHERE litige_id=p_litige_id AND statut_litige='EN_ATTENTE_LITIGE';
  IF v_litige.statut IN ('OUVERT','EN_DISCUSSION','EN_MEDIATION','CONTESTEE')
     AND NOT COALESCE(v_litige.est_informatif,false) AND p_nouveau_scope <> 'AUCUN' THEN
    IF v_litige.categorie_litige = 'FINANCIER' AND v_litige.facture_id IS NOT NULL THEN
      UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
       WHERE id=v_litige.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
    ELSIF v_litige.categorie_litige::text IN ('PRESENCE','CONDITIONS','COMPORTEMENT') THEN
      IF p_nouveau_scope = 'FACTURE_UNIQUE' AND v_litige.facture_id IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
         WHERE id=v_litige.facture_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      ELSIF p_nouveau_scope = 'PERIODE_LITIGIEUSE' AND v_litige.periode_debut IS NOT NULL AND v_litige.periode_fin IS NOT NULL THEN
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
         WHERE mission_id=v_litige.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE'
           AND periode_debut <= v_litige.periode_fin AND periode_fin >= v_litige.periode_debut;
      ELSE
        UPDATE factures_honoraires SET statut_litige='EN_ATTENTE_LITIGE', litige_id=p_litige_id
         WHERE mission_id=v_litige.mission_id AND statut_litige='NORMAL' AND statut<>'PAYEE';
      END IF;
    END IF;
  END IF;
  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid, p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'LITIGE_GEL_SCOPE_MODIFIE', p_type_ressource := 'litige',
    p_id_ressource := p_litige_id,
    p_details := jsonb_build_object('old_scope',v_old_scope,'new_scope',p_nouveau_scope,'raison',p_raison,'reapplique_immediatement',true)
  );
  RETURN jsonb_build_object('success',true,'litige_id',p_litige_id,'old_scope',v_old_scope,'new_scope',p_nouveau_scope);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_masquer_notation(p_notation_id uuid, p_raison text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_notation RECORD;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Seul l''administrateur peut masquer une notation');
  END IF;

  IF p_raison IS NULL OR LENGTH(TRIM(p_raison)) < 10 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Raison requise (min 10 caractères)');
  END IF;

  SELECT * INTO v_notation FROM notations_missions WHERE id = p_notation_id;
  IF v_notation IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Notation introuvable');
  END IF;

  UPDATE notations_missions SET
    masque = true, masque_par = v_uid, masque_le = NOW(), mis_a_jour_le = NOW()
  WHERE id = p_notation_id;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'ADMIN_PLATEFORME',
    p_action := 'NOTATION_MASQUEE',
    p_type_ressource := 'notation',
    p_id_ressource := p_notation_id,
    p_details := jsonb_build_object('raison', p_raison, 'mission_id', v_notation.mission_id)
  );

  -- Recalculer le score de la cible (notation masquée sort du calcul)
  IF v_notation.sens = 'ETAB_VERS_SOIGNANT' THEN
    PERFORM public.fn_calculer_score_fiabilite_v2(v_notation.note_id, 'notation_masquee');
  ELSIF v_notation.sens = 'SOIGNANT_VERS_ETAB' THEN
    PERFORM public.fn_calculer_score_etablissement(v_notation.note_id);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_mes_acces()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_role text;
  v_groupes text[];
  v_actif boolean;
  v_poste text;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non authentifié';
  END IF;

  SELECT raw_app_meta_data->>'role' INTO v_role
  FROM auth.users WHERE id = v_uid;

  IF v_role <> 'ADMIN_PLATEFORME' THEN
    RAISE EXCEPTION 'Accès admin requis';
  END IF;

  SELECT acces_groupes, actif, poste INTO v_groupes, v_actif, v_poste
  FROM equipe_admin WHERE user_id = v_uid;

  -- Fondatrice (ou admin hors registre équipe) → accès total
  IF v_groupes IS NULL OR v_poste ILIKE '%fondat%' THEN
    RETURN jsonb_build_object('acces_total', true, 'groupes', '[]'::jsonb, 'actif', true);
  END IF;

  IF NOT v_actif THEN
    RAISE EXCEPTION 'Compte désactivé';
  END IF;

  RETURN jsonb_build_object('acces_total', false, 'groupes', to_jsonb(v_groupes), 'actif', v_actif);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_remise_groupe(p_groupe_id uuid, p_remise numeric, p_raison text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ancienne numeric;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;
  IF p_remise IS NULL OR p_remise < 0 OR p_remise > 100 THEN
    RETURN jsonb_build_object('error', 'La remise doit être entre 0 et 100 %');
  END IF;

  SELECT remise_groupe_pourcent INTO v_ancienne FROM groupes_sante WHERE id = p_groupe_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Groupe introuvable');
  END IF;

  UPDATE groupes_sante SET remise_groupe_pourcent = p_remise WHERE id = p_groupe_id;

  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (auth.uid(), 'ADMIN', 'TAUX_COMMISSION_MODIFIE', 'groupe', p_groupe_id,
    jsonb_build_object('champ', 'remise_groupe_pourcent', 'ancienne', v_ancienne, 'nouvelle', p_remise, 'raison', p_raison));

  RETURN jsonb_build_object('success', true, 'remise', p_remise);
END;
$function$


---FIN-FONCTION---

CREATE OR REPLACE FUNCTION public.fn_admin_modifier_palier_bfa(p_palier_id uuid, p_nom text DEFAULT NULL::text, p_missions_min integer DEFAULT NULL::integer, p_missions_max integer DEFAULT NULL::integer, p_taux_bfa numeric DEFAULT NULL::numeric, p_est_actif boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_avant record;
  v_min integer;
  v_max integer;
BEGIN
  IF NOT est_admin() THEN
    RETURN jsonb_build_object('error', 'Non autorisé');
  END IF;

  SELECT * INTO v_avant FROM paliers_bfa WHERE id = p_palier_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Palier introuvable');
  END IF;

  v_min := COALESCE(p_missions_min, v_avant.missions_min);
  v_max := COALESCE(p_missions_max, v_avant.missions_max);

  IF p_taux_bfa IS NOT NULL AND (p_taux_bfa < 0 OR p_taux_bfa > 50) THEN
    RETURN jsonb_build_object('error', 'Le taux BFA doit être entre 0 et 50 %');
  END IF;
  IF v_min < 0 OR (v_max IS NOT NULL AND v_max < v_min) THEN
    RETURN jsonb_build_object('error', 'Bornes invalides (max < min)');
  END IF;
  -- Non-chevauchement avec les autres paliers actifs
  IF COALESCE(p_est_actif, v_avant.est_actif) AND EXISTS (
    SELECT 1 FROM paliers_bfa autre
    WHERE autre.id <> p_palier_id AND autre.est_actif
      AND v_min <= COALESCE(autre.missions_max, 2147483647)
      AND COALESCE(v_max, 2147483647) >= autre.missions_min
  ) THEN
    RETURN jsonb_build_object('error', 'Les bornes chevauchent un autre palier actif');
  END IF;

  UPDATE paliers_bfa SET
    nom = COALESCE(p_nom, nom),
    missions_min = v_min,
    missions_max = CASE WHEN p_missions_max IS NOT NULL THEN p_missions_max ELSE missions_max END,
    taux_bfa = COALESCE(p_taux_bfa, taux_bfa),
    est_actif = COALESCE(p_est_actif, est_actif)
  WHERE id = p_palier_id;

  INSERT INTO journaux_audit (acteur_id, type_acteur, action, type_ressource, id_ressource, details)
  VALUES (auth.uid(), 'ADMIN', 'TAUX_COMMISSION_MODIFIE', 'palier_bfa', p_palier_id,
    jsonb_build_object(
      'avant', jsonb_build_object('nom', v_avant.nom, 'min', v_avant.missions_min, 'max', v_avant.missions_max, 'taux', v_avant.taux_bfa, 'actif', v_avant.est_actif),
      'apres', jsonb_build_object('nom', COALESCE(p_nom, v_avant.nom), 'min', v_min, 'max', COALESCE(p_missions_max, v_avant.missions_max), 'taux', COALESCE(p_taux_bfa, v_avant.taux_bfa), 'actif', COALESCE(p_est_actif, v_avant.est_actif))
    ));

  RETURN jsonb_build_object('success', true);
END;
$function$
