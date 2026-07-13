-- Les verdicts historiques antérieurs aux contrôles déterministes ne sont pas
-- promus par ancienneté. Seuls les comptes réels repassent en revue ; les
-- données et statuts des comptes explicitement marqués est_compte_test restent
-- intacts pour les démonstrations et captures stores.

-- Les deux comptes de démonstration officiels existaient avant l'introduction
-- de est_compte_test. On les classe explicitement avant le backfill : leurs
-- données ne sont ni supprimées ni dévalidées et ils continuent à se voir entre
-- eux, tout en restant isolés des utilisateurs réels.
UPDATE public.soignants s
SET est_compte_test = true,
    modifie_le = now()
FROM auth.users u
WHERE u.id = s.id
  AND lower(u.email) = 'marie.lefevre@jolene-demo.dev'
  AND s.est_compte_test IS FALSE;

-- Le trigger canonique rabaisse volontairement tout dossier incomplet lors de
-- n'importe quel UPDATE. On le suspend uniquement autour de ce marquage
-- administratif borné, sinon le compte de capture perdrait son état VERIFIE et
-- son droit de publication. Le DDL et l'UPDATE sont transactionnels : une
-- erreur restaure aussi automatiquement l'état du trigger.
ALTER TABLE public.etablissements
  DISABLE TRIGGER trg_invalider_verifications_etablissement;
ALTER TABLE public.etablissements
  DISABLE TRIGGER trg_auto_valider_etablissement;

UPDATE public.etablissements e
SET est_compte_test = true,
    modifie_le = now()
FROM auth.users u
WHERE u.id = e.id
  AND lower(u.email) = 'etab@jolene.app'
  AND e.est_compte_test IS FALSE;

ALTER TABLE public.etablissements
  ENABLE TRIGGER trg_auto_valider_etablissement;
ALTER TABLE public.etablissements
  ENABLE TRIGGER trg_invalider_verifications_etablissement;

UPDATE public.etablissements e
SET peut_publier_missions = false,
    statut_verification = CASE
      WHEN e.statut_verification = 'SUSPENDU' THEN 'SUSPENDU'
      ELSE 'EN_COURS'
    END,
    verifie_le = NULL,
    verifie_par = NULL,
    modifie_le = now()
WHERE e.supprime_le IS NULL
  AND COALESCE(e.est_compte_test, false) IS FALSE
  AND (e.statut_verification = 'VERIFIE' OR e.peut_publier_missions IS TRUE)
  AND NOT (
    COALESCE(e.siret_verifie, false)
    AND COALESCE(e.finess_verifie, false)
    AND COALESCE(e.representant_identite_verifiee, false)
    AND COALESCE(e.rattachement_verifie, false)
    AND COALESCE(e.contrat_service_signe, false)
  );

WITH preuves_a_revoir AS (
  SELECT ds.id, ds.soignant_id
  FROM public.documents_soignants ds
  JOIN public.soignants s ON s.id = ds.soignant_id
  WHERE ds.supprime_le IS NULL
    AND ds.statut_verification = 'VERIFIE'
    AND COALESCE(s.est_compte_test, false) IS FALSE
    AND (
      -- Les pièces rattachées à une personne physique doivent conserver une
      -- identité complète et concordante. À l'inverse, RIB, KBIS,
      -- ATTESTATION_URSSAF, RCP_ASSURANCE et NOTE_HONORAIRES peuvent être
      -- établis au nom d'une personne morale : l'absence de prénom ne permet
      -- donc pas, à elle seule, de déclasser ces preuves historiques.
      (
        ds.type_document::text IN (
          'CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR', 'DIPLOME',
          'RPPS_ADELI', 'VACCINATIONS', 'CASIER_JUDICIAIRE',
          'AUTORISATION_EXERCICE', 'MEDECINE_TRAVAIL',
          'FORMATION_OBLIGATOIRE', 'CARTE_ORDRE', 'ATTESTATION_CPAM',
          'ATTESTATION_3200H', 'ARRET_MALADIE', 'ATTESTATION_SCOLARITE',
          'LICENCE_REMPLACEMENT', 'BULLETIN_PAIE',
          'ATTESTATION_EMPLOYEUR', 'CERTIFICAT_TRAVAIL'
        )
        AND (
          NULLIF(btrim(ds.nom_extrait_ia), '') IS NULL
          OR NULLIF(btrim(ds.prenom_extrait_ia), '') IS NULL
          OR ds.coherence_nom IS NOT TRUE
        )
      )
      OR (
        ds.type_document::text IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
        AND (
          COALESCE(ds.resultat_ia->>'date_naissance_extraite', '') !~ '^\d{4}-\d{2}-\d{2}$'
          OR s.date_naissance IS NULL
          OR ds.resultat_ia->>'date_naissance_extraite' <> s.date_naissance::text
        )
      )
      OR (
        ds.type_document::text = 'DIPLOME'
        AND NOT (
          upper(COALESCE(NULLIF(btrim(ds.resultat_ia->>'profession_certifiee'), ''), ''))
            = upper(COALESCE(s.profession::text, ''))
          -- Une spécialisation IADE/IBODE atteste aussi le socle IDE. Le sens
          -- inverse reste volontairement refusé : un DEI seul ne prouve pas la
          -- spécialité déclarée IADE ou IBODE.
          OR (
            s.profession = 'IDE'
            AND upper(COALESCE(ds.resultat_ia->>'profession_certifiee', ''))
              IN ('IADE', 'IBODE')
          )
        )
      )
      OR (
        ds.type_document::text = 'RPPS_ADELI'
        AND (
          upper(COALESCE(NULLIF(btrim(ds.resultat_ia->>'type_identifiant_professionnel'), ''), ''))
            NOT IN ('RPPS', 'ADELI')
          OR COALESCE(
            regexp_replace(ds.resultat_ia->>'numero_professionnel_extrait', '[^0-9]', '', 'g'),
            ''
          ) <> regexp_replace(
            CASE upper(ds.resultat_ia->>'type_identifiant_professionnel')
              WHEN 'RPPS' THEN COALESCE(s.numero_rpps, '')
              WHEN 'ADELI' THEN COALESCE(s.numero_adeli, '')
              ELSE ''
            END,
            '[^0-9]', '', 'g'
          )
        )
      )
      OR (
        ds.type_document::text = 'RIB'
        AND (
          COALESCE(ds.resultat_ia->>'iban_valide', 'false') <> 'true'
          OR NULLIF(ds.resultat_ia->>'iban_last4', '') IS NULL
        )
      )
      OR (
        ds.type_document::text = 'ATTESTATION_SCOLARITE'
        AND NOT (
          COALESCE(ds.resultat_ia->>'verdict_serveur', '') = 'VERIFIE'
          AND COALESCE(ds.resultat_ia->>'type_correspond', 'false') = 'true'
          AND COALESCE(ds.resultat_ia->>'document_lisible', 'false') = 'true'
          AND COALESCE(ds.resultat_ia->>'document_complet', 'false') = 'true'
          AND ds.valide_depuis IS NOT NULL
          AND ds.valide_depuis BETWEEN current_date - 400 AND current_date
          AND (ds.valide_jusqua IS NULL OR ds.valide_jusqua > current_date)
          AND upper(COALESCE(ds.resultat_ia->>'scolarite_formation', '')) = ANY (ARRAY[
            'IFSI', 'IFAS', 'MEDECINE_DFGSM', 'MEDECINE_DFASM', 'PHARMACIE',
            'MAIEUTIQUE', 'ODONTOLOGIE', 'KINE', 'ERGOTHERAPIE',
            'PSYCHOMOTRICITE', 'MANIP_RADIO'
          ])
          AND COALESCE(ds.resultat_ia->>'scolarite_annee_validee', '') ~ '^\d{1,2}$'
          AND CASE
            WHEN COALESCE(ds.resultat_ia->>'scolarite_annee_validee', '') ~ '^\d{1,2}$'
              THEN (ds.resultat_ia->>'scolarite_annee_validee')::integer
            ELSE NULL
          END BETWEEN 0 AND CASE upper(COALESCE(ds.resultat_ia->>'scolarite_formation', ''))
            WHEN 'IFSI' THEN 3
            WHEN 'IFAS' THEN 1
            WHEN 'MEDECINE_DFGSM' THEN 3
            WHEN 'MEDECINE_DFASM' THEN 3
            WHEN 'PHARMACIE' THEN 9
            WHEN 'MAIEUTIQUE' THEN 6
            WHEN 'ODONTOLOGIE' THEN 9
            WHEN 'KINE' THEN 5
            WHEN 'ERGOTHERAPIE' THEN 3
            WHEN 'PSYCHOMOTRICITE' THEN 3
            WHEN 'MANIP_RADIO' THEN 3
            ELSE -1
          END
          AND EXISTS (
            SELECT 1
            FROM public.fn_professions_autorisees_scolarite(
              upper(ds.resultat_ia->>'scolarite_formation'),
              CASE
                WHEN COALESCE(ds.resultat_ia->>'scolarite_annee_validee', '') ~ '^\d{1,2}$'
                  THEN (ds.resultat_ia->>'scolarite_annee_validee')::integer
                ELSE NULL
              END
            ) AS autorisee(profession)
            WHERE autorisee.profession = s.profession
          )
        )
      )
      OR (
        ds.type_document::text = 'LICENCE_REMPLACEMENT'
        AND NOT (
          COALESCE(s.profession::text, '') = 'MEDECIN'
          AND COALESCE(ds.resultat_ia->>'verdict_serveur', '') = 'VERIFIE'
          AND COALESCE(ds.resultat_ia->>'type_correspond', 'false') = 'true'
          AND COALESCE(ds.resultat_ia->>'document_lisible', 'false') = 'true'
          AND COALESCE(ds.resultat_ia->>'document_complet', 'false') = 'true'
          AND NULLIF(btrim(ds.resultat_ia->>'licence_remplacement_specialite'), '') IS NOT NULL
          AND ds.valide_depuis IS NOT NULL
          AND ds.valide_depuis <= current_date
          AND ds.valide_jusqua IS NOT NULL
          AND ds.valide_jusqua > current_date
          AND ds.valide_jusqua <= (ds.valide_depuis + interval '13 months')::date
        )
      )
      OR EXISTS (
        SELECT 1
        FROM public.documents_requis_par_profession drp
        WHERE drp.profession = s.profession
          AND drp.type_document = ds.type_document
          AND drp.a_expiration IS TRUE
          AND (ds.valide_jusqua IS NULL OR ds.valide_jusqua <= current_date)
      )
    )
)
UPDATE public.documents_soignants ds
SET statut_verification = 'EN_ATTENTE',
    motif_rejet = 'Preuve historique à revalider avec les contrôles renforcés.',
    verifie_le = NULL,
    verifie_par = NULL,
    modifie_le = now()
FROM preuves_a_revoir p
WHERE ds.id = p.id;

UPDATE public.soignants s
SET identite_verifiee = CASE
      WHEN EXISTS (
        SELECT 1 FROM public.documents_soignants ds
        WHERE ds.soignant_id = s.id
          AND ds.supprime_le IS NULL
          AND ds.statut_verification = 'VERIFIE'
          AND ds.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
      ) THEN s.identite_verifiee
      ELSE false
    END,
    coherence_identite = CASE
      WHEN EXISTS (
        SELECT 1 FROM public.documents_soignants ds
        WHERE ds.soignant_id = s.id
          AND ds.supprime_le IS NULL
          AND ds.statut_verification = 'VERIFIE'
          AND ds.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
      ) THEN s.coherence_identite
      ELSE 'NON_VERIFIE'
    END,
    tous_documents_valides = public.fn_documents_ok_pour_mission(
      s.id,
      CASE WHEN upper(COALESCE(s.type_exercice, 'SALARIE')) IN ('LIBERAL', 'MIXTE')
        THEN 'LIBERAL' ELSE 'SALARIE' END
    ),
    modifie_le = now()
WHERE COALESCE(s.est_compte_test, false) IS FALSE
  AND EXISTS (
    SELECT 1 FROM public.documents_soignants ds
    WHERE ds.soignant_id = s.id AND ds.supprime_le IS NULL
  );

-- Recalcule les droits étudiants uniquement pour les profils réels. La fonction
-- canonique ne conserve que les preuves actuelles, cohérentes avec la profession
-- du profil et issues du nouveau verdict serveur. Les comptes démo restent
-- strictement intacts pour les captures stores.
DO $$
DECLARE
  v_soignant_id uuid;
BEGIN
  FOR v_soignant_id IN
    SELECT s.id
    FROM public.soignants s
    WHERE s.est_compte_test IS FALSE
      AND s.supprime_le IS NULL
  LOOP
    PERFORM public.fn_recalculer_preuves_etudiant(v_soignant_id);
  END LOOP;
END;
$$;
