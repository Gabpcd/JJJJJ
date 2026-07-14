-- File admin de revue manuelle durable.
--
-- Le fichier a ete initialise avec `supabase migration new`, puis positionne
-- apres les migrations de durcissement precedentes afin que les decisions
-- humaines reutilisent leurs invariants finaux. Aucune donnee existante (test
-- ou reelle) n'est modifiee par cette migration.

-- Une approbation SIRET manuelle repose sur une piece d'identite precise. Sa
-- provenance reste rattachee au SIRET exact sur le profil afin que l'activation
-- liberale puisse la recontroler apres la decision, y compris apres expiration
-- ou remplacement du fichier. Les verifications entierement automatiques du
-- registre officiel conservent une source distincte et ne dependent pas de ces
-- colonnes documentaires.
ALTER TABLE public.soignants
  ADD COLUMN IF NOT EXISTS siret_liberal_source_verification text,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_siret varchar(14),
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_document_id uuid,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_document_modifie_le timestamptz,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_s3_bucket text,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_s3_cle text,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_s3_version_id text,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_storage_object_id uuid,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_storage_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_valide_jusqua date,
  ADD COLUMN IF NOT EXISTS siret_liberal_preuve_identite_empreinte_sha256 text;

ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_siret_liberal_source_verification_check;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_siret_liberal_source_verification_check
  CHECK (
    siret_liberal_source_verification IS NULL
    OR siret_liberal_source_verification IN (
      'REGISTRE_OFFICIEL',
      'REVUE_MANUELLE_IDENTITE'
    )
  );

ALTER TABLE public.soignants
  DROP CONSTRAINT IF EXISTS soignants_siret_liberal_preuve_manuelle_complete_check;
ALTER TABLE public.soignants
  ADD CONSTRAINT soignants_siret_liberal_preuve_manuelle_complete_check
  CHECK (
    siret_liberal_source_verification IS DISTINCT FROM 'REVUE_MANUELLE_IDENTITE'
    OR (
      siret_liberal_preuve_siret IS NOT NULL
      AND siret_liberal_preuve_siret ~ '^[0-9]{14}$'
      AND siret_liberal_preuve_identite_document_id IS NOT NULL
      AND siret_liberal_preuve_identite_document_modifie_le IS NOT NULL
      AND siret_liberal_preuve_identite_s3_bucket IS NOT DISTINCT FROM 'jolene-documents'
      AND NULLIF(siret_liberal_preuve_identite_s3_cle, '') IS NOT NULL
      AND siret_liberal_preuve_identite_storage_object_id IS NOT NULL
      AND siret_liberal_preuve_identite_storage_updated_at IS NOT NULL
      AND siret_liberal_preuve_identite_valide_jusqua IS NOT NULL
      AND siret_liberal_preuve_identite_empreinte_sha256 IS NOT NULL
      AND siret_liberal_preuve_identite_empreinte_sha256 ~ '^[0-9a-f]{64}$'
    )
  );

CREATE INDEX IF NOT EXISTS idx_soignants_siret_preuve_identite_document
  ON public.soignants (siret_liberal_preuve_identite_document_id)
  WHERE siret_liberal_preuve_identite_document_id IS NOT NULL;

COMMENT ON COLUMN public.soignants.siret_liberal_source_verification IS
  'Source du verdict SIRET courant : registre officiel ou revue manuelle fondee sur une piece d identite.';
COMMENT ON COLUMN public.soignants.siret_liberal_preuve_identite_document_id IS
  'Document exact ayant fonde une approbation manuelle du titulaire du SIRET liberal.';

-- Empreinte uniquement des attributs qui fondent le verdict. Elle complete le
-- verrou de ligne pris lors de la decision et detecte une mutation ulterieure
-- meme si un producteur oubliait de faire evoluer modifie_le.
CREATE OR REPLACE FUNCTION private.fn_empreinte_preuve_identite_siret(
  p_document public.documents_soignants
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public, extensions
AS $function$
  SELECT encode(
    extensions.digest(
      convert_to(
        jsonb_build_array(
          (p_document).id,
          (p_document).soignant_id,
          (p_document).type_document,
          (p_document).s3_bucket,
          (p_document).s3_cle,
          (p_document).s3_version_id,
          (p_document).valide_jusqua,
          (p_document).statut_verification,
          (p_document).verifie_le,
          (p_document).supprime_le,
          (p_document).revoque_le,
          (p_document).resultat_ia,
          (p_document).nom_extrait_ia,
          (p_document).prenom_extrait_ia,
          (p_document).coherence_nom
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$function$;

REVOKE ALL ON FUNCTION private.fn_empreinte_preuve_identite_siret(
  public.documents_soignants
) FROM PUBLIC, anon, authenticated;

-- Controle dynamique : current_date est volontairement evalue au moment de
-- l'activation. Une piece valable seulement jusqu'a aujourd'hui est deja
-- consideree expiree, comme dans les autres gates documentaires Jolene.
CREATE OR REPLACE FUNCTION private.fn_preuve_identite_siret_manuelle_courante(
  p_soignant_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, private, storage, extensions
AS $function$
DECLARE
  v_courante boolean := false;
BEGIN
  SELECT true
    INTO v_courante
    FROM public.soignants s
    JOIN public.documents_soignants d
      ON d.id = s.siret_liberal_preuve_identite_document_id
     AND d.soignant_id = s.id
    JOIN storage.objects o
      ON o.id = s.siret_liberal_preuve_identite_storage_object_id
     AND o.bucket_id = d.s3_bucket
     AND o.name = d.s3_cle
    WHERE s.id = p_soignant_id
      AND s.supprime_le IS NULL
      AND s.siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE'
      AND s.siret_liberal_preuve_siret IS NOT DISTINCT FROM s.siret_liberal
      AND s.siret_liberal_verifie IS TRUE
      AND s.siret_liberal_verifie_le IS NOT NULL
      AND s.siret_liberal_coherence_identite IS TRUE
      AND s.identite_verifiee IS TRUE
      AND s.coherence_identite = 'COHERENT'
      AND s.coherence_details ->> 'document_id' = d.id::text
      AND d.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
      AND d.statut_verification = 'VERIFIE'
      AND d.supprime_le IS NULL
      AND d.revoque_le IS NULL
      AND d.verifie_le IS NOT NULL
      AND d.valide_jusqua IS NOT NULL
      AND d.valide_jusqua > current_date
      AND d.coherence_nom IS TRUE
      AND d.resultat_ia ->> 'verdict_serveur' = 'VERIFIE'
      AND d.resultat_ia ->> 'date_naissance_extraite' = s.date_naissance::text
      AND public.fn_noms_personne_correspondent(
        s.nom,
        s.prenom,
        d.nom_extrait_ia,
        d.prenom_extrait_ia
      )
      AND d.s3_bucket = 'jolene-documents'
      AND d.s3_cle LIKE s.id::text || '/%'
      AND d.s3_bucket IS NOT DISTINCT FROM s.siret_liberal_preuve_identite_s3_bucket
      AND d.s3_cle IS NOT DISTINCT FROM s.siret_liberal_preuve_identite_s3_cle
      AND d.s3_version_id IS NOT DISTINCT FROM s.siret_liberal_preuve_identite_s3_version_id
      AND d.modifie_le IS NOT DISTINCT FROM s.siret_liberal_preuve_identite_document_modifie_le
      AND d.valide_jusqua IS NOT DISTINCT FROM s.siret_liberal_preuve_identite_valide_jusqua
      AND private.fn_empreinte_preuve_identite_siret(d)
            IS NOT DISTINCT FROM s.siret_liberal_preuve_identite_empreinte_sha256
      AND o.updated_at IS NOT DISTINCT FROM s.siret_liberal_preuve_identite_storage_updated_at
    LIMIT 1
    FOR SHARE OF d, o;
  RETURN COALESCE(v_courante, false);
END;
$function$;

REVOKE ALL ON FUNCTION private.fn_preuve_identite_siret_manuelle_courante(uuid)
  FROM PUBLIC, anon, authenticated;

-- La decision est conservee hors du schema expose. La cle primaire sur la
-- revue rend le traitement idempotent et interdit deux verdicts concurrents.
CREATE TABLE IF NOT EXISTS private.revue_manuelle_decisions (
  revue_id uuid PRIMARY KEY
    REFERENCES public.file_revue_manuelle(id) ON DELETE RESTRICT,
  decision text NOT NULL CHECK (decision IN ('APPROUVER', 'REJETER')),
  motif text NOT NULL CHECK (char_length(motif) BETWEEN 10 AND 1000),
  acteur_id uuid NOT NULL,
  service text NOT NULL,
  type_entite text NOT NULL,
  id_entite uuid NOT NULL,
  jeton_cas text NOT NULL CHECK (jeton_cas ~ '^[0-9a-f]{64}$'),
  source_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  decide_le timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE private.revue_manuelle_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.revue_manuelle_decisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.revue_manuelle_decisions
  FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE private.revue_manuelle_decisions IS
  'Verdict idempotent et snapshot CAS des revues manuelles admin.';

-- Le jeton couvre tout ce qui peut changer pendant qu'un administrateur lit
-- la carte. Un retry du producteur qui reutilise la meme ligne modifie les
-- donnees_originales et invalide donc immediatement une ancienne decision UI.
CREATE OR REPLACE FUNCTION private.fn_jeton_cas_revue_manuelle(
  p_id uuid,
  p_type_entite text,
  p_id_entite uuid,
  p_service text,
  p_motif text,
  p_donnees jsonb,
  p_statut text,
  p_priorite integer,
  p_assigne_a uuid,
  p_revu_le timestamptz,
  p_resolu_le timestamptz,
  p_expire_le timestamptz
)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public, extensions
AS $function$
  SELECT encode(
    extensions.digest(
      convert_to(
        jsonb_build_array(
          p_id, p_type_entite, p_id_entite, p_service,
          COALESCE(p_motif, ''), COALESCE(p_donnees, '{}'::jsonb),
          p_statut, p_priorite, p_assigne_a, p_revu_le,
          p_resolu_le, p_expire_le
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$function$;

REVOKE ALL ON FUNCTION private.fn_jeton_cas_revue_manuelle(
  uuid, text, uuid, text, text, jsonb, text, integer, uuid,
  timestamptz, timestamptz, timestamptz
) FROM PUBLIC, anon, authenticated;

-- La table brute contenait des snapshots de preuve mais restait lisible par
-- un admin AAL1 via l'ancienne policy. Toute lecture navigateur passe desormais
-- par la projection minimale AAL2 ci-dessous.
REVOKE ALL ON TABLE public.file_revue_manuelle FROM anon, authenticated;
DROP POLICY IF EXISTS pol_file_revue_insert ON public.file_revue_manuelle;
DROP POLICY IF EXISTS pol_file_revue_select ON public.file_revue_manuelle;

CREATE OR REPLACE FUNCTION public.fn_admin_lister_revues_manuelles(
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $function$
DECLARE
  v_resultat jsonb;
BEGIN
  IF auth.uid() IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorise requis'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(file) ORDER BY file.priorite DESC,
                                                file.cree_le ASC), '[]'::jsonb)
    INTO v_resultat
  FROM (
    SELECT
      f.id,
      f.type_entite,
      f.id_entite,
      f.service_en_echec,
      f.motif_echec,
      f.statut,
      f.priorite,
      f.cree_le,
      f.expire_le,
      CASE
        WHEN f.type_entite = 'ETABLISSEMENT' THEN COALESCE(e.est_compte_test, false)
        WHEN f.type_entite = 'SOIGNANT' THEN COALESCE(s.est_compte_test, false)
        WHEN f.type_entite = 'TELEVERSEMENT_DOCUMENT' THEN COALESCE(sd.est_compte_test, false)
        ELSE false
      END AS est_compte_test,
      f.service_en_echec IN (
        'VERIFY_RIB_ETABLISSEMENT',
        'VERIFY_FINESS_RECOUPEMENT',
        'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE'
      ) AS decision_directe,
      CASE
        WHEN f.type_entite = 'ETABLISSEMENT' THEN COALESCE(e.nom, 'Etablissement')
        WHEN f.type_entite = 'SOIGNANT' THEN btrim(COALESCE(s.prenom, '') || ' ' || COALESCE(s.nom, ''))
        WHEN f.type_entite = 'TELEVERSEMENT_DOCUMENT' THEN
          btrim(COALESCE(sd.prenom, '') || ' ' || COALESCE(sd.nom, ''))
        ELSE f.type_entite || ' ' || f.id_entite::text
      END AS ressource_libelle,
      CASE
        WHEN f.service_en_echec ILIKE '%HEURES%'
          THEN '/admin/heures-externes'
        WHEN f.type_entite = 'ETABLISSEMENT'
          THEN '/admin/verification-etablissements'
        WHEN f.type_entite = 'SOIGNANT'
          THEN '/admin/utilisateurs/' || f.id_entite::text
        WHEN f.type_entite = 'TELEVERSEMENT_DOCUMENT'
          THEN '/admin/moderation?onglet=documents'
        ELSE '/admin/moderation'
      END AS route_ressource,
      CASE
        WHEN f.service_en_echec IN (
          'VERIFY_RIB_ETABLISSEMENT',
          'VERIFY_PIECE_IDENTITE_ETAB',
          'VERIFY_JUSTIFICATIF_FONCTION'
        ) THEN 'jolene-documents'
        WHEN f.type_entite = 'TELEVERSEMENT_DOCUMENT' THEN d.s3_bucket
        ELSE NULL
      END AS preuve_bucket,
      CASE
        WHEN f.service_en_echec = 'VERIFY_RIB_ETABLISSEMENT' THEN e.rib_s3_key
        WHEN f.service_en_echec = 'VERIFY_PIECE_IDENTITE_ETAB'
          THEN e.representant_piece_s3_key
        WHEN f.service_en_echec = 'VERIFY_JUSTIFICATIF_FONCTION'
          THEN e.justificatif_fonction_s3_key
        WHEN f.type_entite = 'TELEVERSEMENT_DOCUMENT' THEN d.s3_cle
        ELSE NULL
      END AS preuve_path,
      CASE
        WHEN f.service_en_echec = 'VERIFY_RIB_ETABLISSEMENT' THEN 'RIB'
        WHEN f.service_en_echec = 'VERIFY_PIECE_IDENTITE_ETAB' THEN 'Identite du representant'
        WHEN f.service_en_echec = 'VERIFY_JUSTIFICATIF_FONCTION' THEN 'Justificatif de fonction'
        WHEN f.type_entite = 'TELEVERSEMENT_DOCUMENT' THEN d.type_document::text
        ELSE NULL
      END AS preuve_type,
      jsonb_strip_nulls(jsonb_build_object(
        'etablissement_nom', e.nom,
        'etablissement_siret', e.siret,
        'etablissement_finess', e.finess,
        'etablissement_version', e.verification_source_version,
        'rib_iban_last4', e.iban_last4,
        'soignant_prenom', s.prenom,
        'soignant_nom', s.nom,
        'soignant_profession', s.profession::text,
        'document_type', d.type_document::text,
        'donnees_revue', CASE
          WHEN f.service_en_echec = 'VERIFY_RIB_ETABLISSEMENT' THEN
            jsonb_strip_nulls(jsonb_build_object(
              'cause', f.donnees_originales ->> 'cause',
              'verification_source_version',
                f.donnees_originales ->> 'verification_source_version',
              'rib_source_sha256_v1',
                f.donnees_originales ->> 'rib_source_sha256_v1',
              'iban_last4', f.donnees_originales ->> 'iban_last4'
            ))
          WHEN f.service_en_echec = 'VERIFY_FINESS_RECOUPEMENT' THEN
            jsonb_strip_nulls(jsonb_build_object(
              'code', f.donnees_originales ->> 'code',
              'finess_candidat', f.donnees_originales ->> 'finess_candidat',
              'siret_profil', f.donnees_originales ->> 'siret_profil',
              'donnees_officielles_candidat',
                f.donnees_originales -> 'donnees_officielles_candidat',
              'recoupement', f.donnees_originales -> 'recoupement'
            ))
          WHEN f.service_en_echec = 'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE' THEN
            jsonb_strip_nulls(jsonb_build_object(
              'siret_candidat', f.donnees_originales ->> 'siret_candidat',
              'raison_sociale_officielle',
                f.donnees_originales ->> 'raison_sociale_officielle',
              'code_naf_officiel', f.donnees_originales ->> 'code_naf_officiel',
              'source_officielle', f.donnees_originales ->> 'source_officielle'
            ))
          ELSE jsonb_strip_nulls(jsonb_build_object(
            'code', f.donnees_originales ->> 'code',
            'cause', f.donnees_originales ->> 'cause'
          ))
        END
      )) AS contexte,
      private.fn_jeton_cas_revue_manuelle(
        f.id, f.type_entite, f.id_entite, f.service_en_echec,
        f.motif_echec, f.donnees_originales, f.statut, f.priorite,
        f.assigne_a, f.revu_le, f.resolu_le, f.expire_le
      ) AS jeton_cas
    FROM public.file_revue_manuelle f
    LEFT JOIN public.etablissements e
      ON f.type_entite = 'ETABLISSEMENT' AND e.id = f.id_entite
    LEFT JOIN public.soignants s
      ON f.type_entite = 'SOIGNANT' AND s.id = f.id_entite
    LEFT JOIN public.documents_soignants d
      ON f.type_entite = 'TELEVERSEMENT_DOCUMENT' AND d.id = f.id_entite
    LEFT JOIN public.soignants sd ON sd.id = d.soignant_id
    WHERE f.statut IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE')
    ORDER BY f.priorite DESC, f.cree_le ASC
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
  ) AS file;

  RETURN jsonb_build_object('success', true, 'revues', v_resultat);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_lister_revues_manuelles(integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_lister_revues_manuelles(integer)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_admin_decider_revue_manuelle(
  p_revue_id uuid,
  p_decision text,
  p_motif text,
  p_jeton_cas text,
  p_confirmation jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text := upper(btrim(COALESCE(p_decision, '')));
  v_motif text := left(btrim(COALESCE(p_motif, '')), 1000);
  v_confirmation jsonb := COALESCE(p_confirmation, '{}'::jsonb);
  v_revue public.file_revue_manuelle%ROWTYPE;
  v_decision_existante private.revue_manuelle_decisions%ROWTYPE;
  v_jeton text;
  v_etab public.etablissements%ROWTYPE;
  v_soignant public.soignants%ROWTYPE;
  v_doc_identite public.documents_soignants%ROWTYPE;
  v_donnees jsonb;
  v_officiel jsonb;
  v_version_origine bigint;
  v_version_attendue bigint;
  v_rib_key text;
  v_rib_sha256 text;
  v_rib_object_id uuid;
  v_rib_object_updated_at timestamptz;
  v_identite_object_id uuid;
  v_identite_object_updated_at timestamptz;
  v_identite_empreinte text;
  v_iban_normalise text;
  v_iban_last4 text;
  v_finess_candidat text;
  v_siret_candidat text;
  v_snapshot jsonb := '{}'::jsonb;
  v_rows integer;
BEGIN
  IF v_uid IS NULL
     OR COALESCE(auth.jwt() ->> 'aal', '') IS DISTINCT FROM 'aal2'
     OR NOT public.est_admin_valide() THEN
    RAISE EXCEPTION 'Administrateur AAL2 autorise requis'
      USING ERRCODE = '42501';
  END IF;
  IF p_revue_id IS NULL
     OR v_decision NOT IN ('APPROUVER', 'REJETER')
     OR char_length(v_motif) < 10
     OR COALESCE(p_jeton_cas, '') !~ '^[0-9a-f]{64}$'
     OR jsonb_typeof(v_confirmation) <> 'object' THEN
    RAISE EXCEPTION 'Decision, motif et snapshot de revue invalides'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_revue
  FROM public.file_revue_manuelle
  WHERE id = p_revue_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Revue introuvable' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_decision_existante
  FROM private.revue_manuelle_decisions
  WHERE revue_id = p_revue_id;
  IF FOUND THEN
    IF v_decision_existante.decision = v_decision
       AND v_decision_existante.jeton_cas = p_jeton_cas THEN
      RETURN jsonb_build_object(
        'success', true,
        'idempotent', true,
        'decision', v_decision,
        'service', v_decision_existante.service
      );
    END IF;
    RAISE EXCEPTION 'Cette revue possede deja un verdict different'
      USING ERRCODE = '40001';
  END IF;

  IF v_revue.statut NOT IN ('EN_ATTENTE', 'EN_COURS_REVUE', 'ESCALADE') THEN
    RAISE EXCEPTION 'Cette revue n est plus active; rechargez la file'
      USING ERRCODE = '40001';
  END IF;
  IF v_revue.expire_le IS NULL OR v_revue.expire_le < now() THEN
    RAISE EXCEPTION 'Le snapshot de revue a expire; relancez la verification source'
      USING ERRCODE = '40001';
  END IF;
  IF v_revue.service_en_echec NOT IN (
    'VERIFY_RIB_ETABLISSEMENT',
    'VERIFY_FINESS_RECOUPEMENT',
    'VERIFY_SIRET_IDENTITE_NON_CONCLUANTE'
  ) THEN
    RAISE EXCEPTION 'Cette preuve doit etre decidee dans son workflow specialise'
      USING ERRCODE = '22023';
  END IF;

  v_jeton := private.fn_jeton_cas_revue_manuelle(
    v_revue.id, v_revue.type_entite, v_revue.id_entite,
    v_revue.service_en_echec, v_revue.motif_echec,
    v_revue.donnees_originales, v_revue.statut, v_revue.priorite,
    v_revue.assigne_a, v_revue.revu_le, v_revue.resolu_le,
    v_revue.expire_le
  );
  IF v_jeton IS DISTINCT FROM p_jeton_cas THEN
    RAISE EXCEPTION 'La revue a change; rechargez avant de decider'
      USING ERRCODE = '40001';
  END IF;

  v_donnees := COALESCE(v_revue.donnees_originales, '{}'::jsonb);

  IF v_revue.service_en_echec = 'VERIFY_RIB_ETABLISSEMENT' THEN
    IF v_revue.type_entite <> 'ETABLISSEMENT' THEN
      RAISE EXCEPTION 'Type de ressource RIB incoherent' USING ERRCODE = '22023';
    END IF;
    v_version_origine := NULLIF(
      v_donnees ->> 'verification_source_version', ''
    )::bigint;
    v_version_attendue := NULLIF(
      v_donnees ->> 'verification_source_version_apres_verdict', ''
    )::bigint;
    v_rib_key := NULLIF(v_donnees ->> 'rib_s3_key', '');
    v_rib_sha256 := lower(NULLIF(v_donnees ->> 'rib_source_sha256_v1', ''));
    IF v_version_origine IS NULL
       OR v_version_attendue IS DISTINCT FROM v_version_origine + 1
       OR v_rib_key IS NULL
       OR v_rib_key NOT LIKE v_revue.id_entite::text || '/rib-etablissement-%'
       OR COALESCE(v_rib_sha256, '') !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION 'Snapshot RIB incomplet; relancez la verification automatique'
        USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_etab
    FROM public.etablissements
    WHERE id = v_revue.id_entite AND supprime_le IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Etablissement introuvable' USING ERRCODE = 'P0002';
    END IF;
    IF v_etab.verification_source_version IS DISTINCT FROM v_version_attendue
       OR v_etab.rib_s3_key IS DISTINCT FROM v_rib_key
       OR v_etab.rib_ia_coherent IS NOT NULL THEN
      RAISE EXCEPTION 'Le RIB ou son verdict a change; rechargez la file'
        USING ERRCODE = '40001';
    END IF;

    -- L'objet exact doit encore exister pendant toute la transaction de
    -- decision. On verrouille d'abord l'etablissement (ordre commun aux flux
    -- de remplacement), puis l'objet Storage afin d'eviter un interblocage.
    SELECT o.id, o.updated_at
    INTO v_rib_object_id, v_rib_object_updated_at
    FROM storage.objects o
    WHERE o.bucket_id = 'jolene-documents'
      AND o.name = v_rib_key
    FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Le fichier RIB source n existe plus; relancez la verification automatique'
        USING ERRCODE = '22023';
    END IF;

    v_iban_normalise := upper(regexp_replace(
      COALESCE(v_confirmation ->> 'iban', ''),
      '[^A-Za-z0-9]',
      '',
      'g'
    ));
    v_iban_last4 := right(v_iban_normalise, 4);
    IF v_decision = 'APPROUVER'
       AND NOT public.fn_iban_est_valide(v_iban_normalise) THEN
      RAISE EXCEPTION 'L IBAN complet lu sur le RIB est requis avec un checksum ISO 13616 valide'
        USING ERRCODE = '22023';
    END IF;
    IF v_decision = 'APPROUVER'
       AND NULLIF(upper(v_donnees ->> 'iban_last4'), '') IS NOT NULL
       AND upper(v_donnees ->> 'iban_last4') IS DISTINCT FROM v_iban_last4 THEN
      RAISE EXCEPTION 'Le suffixe IBAN saisi contredit le snapshot de verification'
        USING ERRCODE = '22023';
    END IF;
    IF v_decision = 'APPROUVER'
       AND NULLIF(v_donnees ->> 'iban_fingerprint_sha256_v1', '') IS NOT NULL
       AND encode(
         extensions.digest(
           convert_to(
             v_revue.id_entite::text || '|'
               || v_version_origine::text || '|'
               || v_rib_key || '|' || v_iban_normalise,
             'UTF8'
           ),
           'sha256'
         ),
         'hex'
       ) IS DISTINCT FROM v_donnees ->> 'iban_fingerprint_sha256_v1' THEN
      RAISE EXCEPTION 'L IBAN saisi ne correspond pas a celui extrait dans le snapshot'
        USING ERRCODE = '22023';
    END IF;

    v_snapshot := jsonb_build_object(
      'verification_source_version', v_etab.verification_source_version,
      'verification_source_version_origine', v_version_origine,
      'rib_s3_key', v_rib_key,
      'rib_source_sha256_v1', v_rib_sha256,
      'storage_object_id', v_rib_object_id,
      'storage_object_updated_at', v_rib_object_updated_at,
      'iban_last4', CASE WHEN v_decision = 'APPROUVER' THEN v_iban_last4 ELSE NULL END,
      'ancien_verdict', v_etab.rib_ia_resultat ->> 'verdict_final'
    );
    UPDATE public.etablissements
    SET rib_ia_resultat = (
          COALESCE(rib_ia_resultat, '{}'::jsonb)
            - 'iban' - 'iban_extrait' - 'raw_text'
        ) || jsonb_build_object(
          'verdict_final', CASE WHEN v_decision = 'APPROUVER' THEN 'VERIFIE' ELSE 'REJETE' END,
          'motif_serveur', v_motif,
          'revue_manuelle_requise', false,
          'source_validation', 'ADMIN_REVUE_MANUELLE',
          'revue_admin_le', now()
        ),
        rib_ia_coherent = v_decision = 'APPROUVER',
        rib_ia_verifie_le = now(),
        iban_last4 = CASE WHEN v_decision = 'APPROUVER' THEN v_iban_last4 ELSE NULL END,
        rib_verifie_s3_key = CASE WHEN v_decision = 'APPROUVER' THEN v_rib_key ELSE NULL END,
        rib_verifie_source_version = CASE
          WHEN v_decision = 'APPROUVER' THEN v_version_attendue + 1
          ELSE NULL
        END,
        modifie_le = now()
    WHERE id = v_revue.id_entite
      AND verification_source_version = v_version_attendue
      AND rib_s3_key = v_rib_key
      AND rib_ia_coherent IS NULL;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Decision RIB concurrente detectee' USING ERRCODE = '40001';
    END IF;

  ELSIF v_revue.service_en_echec = 'VERIFY_FINESS_RECOUPEMENT' THEN
    IF v_revue.type_entite <> 'ETABLISSEMENT' THEN
      RAISE EXCEPTION 'Type de ressource FINESS incoherent' USING ERRCODE = '22023';
    END IF;
    v_version_attendue := NULLIF(v_donnees ->> 'verification_source_version', '')::bigint;
    v_finess_candidat := NULLIF(v_donnees ->> 'finess_candidat', '');
    v_officiel := COALESCE(v_donnees -> 'donnees_officielles_candidat', '{}'::jsonb);
    IF v_version_attendue IS NULL
       OR COALESCE(v_finess_candidat, '') !~ '^[0-9]{9}$'
       OR jsonb_typeof(v_officiel) <> 'object'
       OR COALESCE((v_officiel ->> 'actif')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Snapshot FINESS officiel incomplet ou inactif'
        USING ERRCODE = '22023';
    END IF;
    IF v_decision = 'APPROUVER'
       AND NULLIF(btrim(v_officiel ->> 'raison_sociale'), '') IS NULL THEN
      RAISE EXCEPTION 'La raison sociale FINESS officielle est requise pour approuver'
        USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_etab
    FROM public.etablissements
    WHERE id = v_revue.id_entite AND supprime_le IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Etablissement introuvable' USING ERRCODE = 'P0002';
    END IF;
    IF v_etab.verification_source_version IS DISTINCT FROM v_version_attendue
       OR v_etab.finess IS DISTINCT FROM NULLIF(v_donnees ->> 'finess_canonique_avant', '')
       OR v_etab.siret IS DISTINCT FROM NULLIF(v_donnees ->> 'siret_profil', '')
       OR v_etab.siret_verifie IS DISTINCT FROM (v_donnees ->> 'siret_profil_verifie')::boolean THEN
      RAISE EXCEPTION 'Le dossier FINESS a change; rechargez la file'
        USING ERRCODE = '40001';
    END IF;

    v_snapshot := jsonb_build_object(
      'verification_source_version', v_etab.verification_source_version,
      'finess_canonique_avant', v_etab.finess,
      'finess_candidat', v_finess_candidat,
      'donnees_officielles_candidat', v_officiel,
      'recoupement', v_donnees -> 'recoupement'
    );
    v_rows := 0;
    IF v_decision = 'APPROUVER' THEN
      IF v_etab.finess IS DISTINCT FROM v_finess_candidat THEN
        UPDATE public.etablissements
        SET finess = v_finess_candidat,
            modifie_le = now()
        WHERE id = v_revue.id_entite;
      END IF;
      UPDATE public.etablissements
      SET finess_verifie = true,
          finess_verifie_le = now(),
          finess_raison_sociale = NULLIF(v_officiel ->> 'raison_sociale', ''),
          finess_categorie = NULLIF(v_officiel ->> 'categorie_label', ''),
          finess_secteur = NULLIF(v_officiel ->> 'secteur_label', ''),
          finess_est_public = CASE
            WHEN v_officiel ? 'est_public' THEN (v_officiel ->> 'est_public')::boolean
            ELSE NULL
          END,
          modifie_le = now()
      WHERE id = v_revue.id_entite;
      PERFORM public.fn_evaluer_rattachement_etablissement(v_revue.id_entite);
    ELSIF v_etab.finess IS NOT DISTINCT FROM v_finess_candidat THEN
      -- Un rejet du FINESS actuellement canonique révoque réellement cette
      -- preuve. Le numéro déclaré reste visible pour correction, mais aucun
      -- statut vérifié ni droit de publication ne survit au verdict humain.
      UPDATE public.etablissements
      SET finess_verifie = false,
          finess_verifie_le = NULL,
          finess_raison_sociale = NULL,
          finess_categorie = NULL,
          finess_secteur = NULL,
          finess_est_public = NULL,
          statut_verification = 'EN_COURS',
          peut_publier_missions = false,
          verifie_le = NULL,
          verifie_par = NULL,
          motif_rejet = left('FINESS rejete en revue manuelle : ' || v_motif, 1000),
          modifie_le = now()
      WHERE id = v_revue.id_entite
        AND verification_source_version = v_version_attendue;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Decision FINESS concurrente detectee' USING ERRCODE = '40001';
      END IF;
    END IF;

  ELSE
    IF v_revue.type_entite <> 'SOIGNANT' THEN
      RAISE EXCEPTION 'Type de ressource SIRET incoherent' USING ERRCODE = '22023';
    END IF;
    v_siret_candidat := NULLIF(v_donnees ->> 'siret_candidat', '');
    IF COALESCE(v_siret_candidat, '') !~ '^[0-9]{14}$'
       OR v_siret_candidat ~ '^0+$'
       OR NULLIF(v_donnees ->> 'profil_modifie_le', '') IS NULL
       OR COALESCE((v_donnees ->> 'siret_officiel_actif')::boolean, false) IS NOT TRUE
       OR COALESCE((v_donnees ->> 'activite_officielle_sante')::boolean, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'Snapshot SIRET officiel incomplet ou inactif'
        USING ERRCODE = '22023';
    END IF;
    IF v_decision = 'APPROUVER'
       AND NULLIF(btrim(v_donnees ->> 'raison_sociale_officielle'), '') IS NULL THEN
      RAISE EXCEPTION 'La raison sociale SIRET officielle est requise pour approuver'
        USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_soignant
    FROM public.soignants
    WHERE id = v_revue.id_entite AND supprime_le IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Soignant introuvable' USING ERRCODE = 'P0002';
    END IF;
    IF v_soignant.modifie_le IS DISTINCT FROM (v_donnees ->> 'profil_modifie_le')::timestamptz
       OR v_soignant.prenom IS DISTINCT FROM v_donnees ->> 'prenom_declare'
       OR v_soignant.nom IS DISTINCT FROM v_donnees ->> 'nom_declare'
       OR v_soignant.date_naissance IS DISTINCT FROM (v_donnees ->> 'date_naissance_declaree')::date
       OR v_soignant.siret_liberal IS DISTINCT FROM NULLIF(v_donnees ->> 'siret_canonique_avant', '')
       OR v_soignant.statut_liberal IS DISTINCT FROM NULLIF(v_donnees ->> 'statut_liberal', '')
       OR v_soignant.type_contrat::text IS DISTINCT FROM NULLIF(v_donnees ->> 'type_contrat', '') THEN
      RAISE EXCEPTION 'Le profil liberal a change; rechargez la file'
        USING ERRCODE = '40001';
    END IF;

    IF v_decision = 'APPROUVER' THEN
      IF v_soignant.identite_verifiee IS NOT TRUE
         OR v_soignant.coherence_identite IS DISTINCT FROM 'COHERENT' THEN
        RAISE EXCEPTION 'Une identite courante coherente est requise avant approbation SIRET'
          USING ERRCODE = '22023';
      END IF;

      SELECT * INTO v_doc_identite
      FROM public.documents_soignants d
      WHERE d.soignant_id = v_soignant.id
        AND d.type_document IN ('CARTE_IDENTITE', 'PASSEPORT', 'TITRE_SEJOUR')
        AND d.statut_verification = 'VERIFIE'
        AND d.supprime_le IS NULL
        AND d.revoque_le IS NULL
        AND d.verifie_le IS NOT NULL
        AND d.valide_jusqua IS NOT NULL
        AND d.valide_jusqua > current_date
        AND d.coherence_nom IS TRUE
        AND d.resultat_ia ->> 'verdict_serveur' = 'VERIFIE'
        AND d.resultat_ia ->> 'date_naissance_extraite' = v_soignant.date_naissance::text
        AND d.s3_bucket = 'jolene-documents'
        AND d.s3_cle LIKE v_soignant.id::text || '/%'
        AND public.fn_noms_personne_correspondent(
          v_soignant.nom,
          v_soignant.prenom,
          d.nom_extrait_ia,
          d.prenom_extrait_ia
        )
      ORDER BY d.verifie_le DESC, d.modifie_le DESC, d.id
      LIMIT 1
      FOR SHARE;

      IF NOT FOUND
         OR v_soignant.coherence_details ->> 'document_id'
              IS DISTINCT FROM v_doc_identite.id::text THEN
        RAISE EXCEPTION 'Une piece d identite precise, concordante et non expiree est requise avant approbation SIRET'
          USING ERRCODE = '22023';
      END IF;

      -- Le document logique ne suffit pas : la ligne de metadonnees de l'objet
      -- exact doit toujours exister. Ce verrou partage ferme la course avec un
      -- remplacement/suppression Storage pendant le verdict humain.
      SELECT o.id, o.updated_at
      INTO v_identite_object_id, v_identite_object_updated_at
      FROM storage.objects o
      WHERE o.bucket_id = v_doc_identite.s3_bucket
        AND o.name = v_doc_identite.s3_cle
      FOR SHARE;
      IF NOT FOUND OR v_identite_object_updated_at IS NULL THEN
        RAISE EXCEPTION 'Le fichier d identite source n existe plus; televersez puis verifiez une nouvelle piece'
          USING ERRCODE = '22023';
      END IF;

      v_identite_empreinte := private.fn_empreinte_preuve_identite_siret(
        v_doc_identite
      );
    END IF;

    v_snapshot := jsonb_build_object(
      'profil_modifie_le', v_soignant.modifie_le,
      'siret_canonique_avant', v_soignant.siret_liberal,
      'siret_candidat', v_siret_candidat,
      'siret_last4', right(v_siret_candidat, 4),
      'raison_sociale_officielle', v_donnees ->> 'raison_sociale_officielle',
      'preuve_identite_document_id', v_doc_identite.id,
      'preuve_identite_s3_bucket', v_doc_identite.s3_bucket,
      'preuve_identite_s3_cle', v_doc_identite.s3_cle,
      'preuve_identite_s3_version_id', v_doc_identite.s3_version_id,
      'preuve_identite_modifie_le', v_doc_identite.modifie_le,
      'preuve_identite_verifie_le', v_doc_identite.verifie_le,
      'preuve_identite_valide_jusqua', v_doc_identite.valide_jusqua,
      'preuve_identite_storage_object_id', v_identite_object_id,
      'preuve_identite_storage_updated_at', v_identite_object_updated_at,
      'preuve_identite_source_sha256_v1', v_identite_empreinte
    );
    v_rows := 0;
    IF v_decision = 'APPROUVER' THEN
      IF (v_soignant.statut_liberal = 'ACTIF' OR v_soignant.type_contrat::text = 'LIBERAL')
         AND v_soignant.siret_liberal IS NOT NULL
         AND v_soignant.siret_liberal IS DISTINCT FROM v_siret_candidat THEN
        RAISE EXCEPTION 'Le SIRET d un exercice liberal actif ne peut pas etre remplace ici'
          USING ERRCODE = '22023';
      END IF;
      UPDATE public.soignants
      SET siret_liberal = v_siret_candidat,
          statut_liberal = CASE WHEN statut_liberal = 'ACTIF' THEN 'ACTIF' ELSE 'EN_COURS' END,
          siret_liberal_verifie = true,
          siret_liberal_verifie_le = now(),
          siret_liberal_raison_sociale = NULLIF(v_donnees ->> 'raison_sociale_officielle', ''),
          siret_liberal_coherence_identite = true,
          siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE',
          siret_liberal_preuve_siret = v_siret_candidat,
          siret_liberal_preuve_identite_document_id = v_doc_identite.id,
          siret_liberal_preuve_identite_document_modifie_le = v_doc_identite.modifie_le,
          siret_liberal_preuve_identite_s3_bucket = v_doc_identite.s3_bucket,
          siret_liberal_preuve_identite_s3_cle = v_doc_identite.s3_cle,
          siret_liberal_preuve_identite_s3_version_id = v_doc_identite.s3_version_id,
          siret_liberal_preuve_identite_storage_object_id = v_identite_object_id,
          siret_liberal_preuve_identite_storage_updated_at = v_identite_object_updated_at,
          siret_liberal_preuve_identite_valide_jusqua = v_doc_identite.valide_jusqua,
          siret_liberal_preuve_identite_empreinte_sha256 = v_identite_empreinte,
          modifie_le = now()
      WHERE id = v_revue.id_entite
        AND modifie_le = v_soignant.modifie_le;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
    ELSIF v_soignant.siret_liberal IS NOT DISTINCT FROM v_siret_candidat THEN
      UPDATE public.soignants
      SET siret_liberal_verifie = false,
          siret_liberal_verifie_le = NULL,
          siret_liberal_raison_sociale = NULL,
          siret_liberal_coherence_identite = false,
          siret_liberal_source_verification = NULL,
          siret_liberal_preuve_siret = NULL,
          siret_liberal_preuve_identite_document_id = NULL,
          siret_liberal_preuve_identite_document_modifie_le = NULL,
          siret_liberal_preuve_identite_s3_bucket = NULL,
          siret_liberal_preuve_identite_s3_cle = NULL,
          siret_liberal_preuve_identite_s3_version_id = NULL,
          siret_liberal_preuve_identite_storage_object_id = NULL,
          siret_liberal_preuve_identite_storage_updated_at = NULL,
          siret_liberal_preuve_identite_valide_jusqua = NULL,
          siret_liberal_preuve_identite_empreinte_sha256 = NULL,
          tous_documents_valides = false,
          modifie_le = now()
      WHERE id = v_revue.id_entite
        AND modifie_le = v_soignant.modifie_le;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
    END IF;
    IF v_rows <> 1 AND (
      v_decision = 'APPROUVER'
      OR v_soignant.siret_liberal IS NOT DISTINCT FROM v_siret_candidat
    ) THEN
      RAISE EXCEPTION 'Decision SIRET concurrente detectee' USING ERRCODE = '40001';
    END IF;
    PERFORM public.fn_calculer_tous_documents_valides(v_revue.id_entite);
  END IF;

  INSERT INTO private.revue_manuelle_decisions (
    revue_id, decision, motif, acteur_id, service, type_entite,
    id_entite, jeton_cas, source_snapshot
  ) VALUES (
    v_revue.id, v_decision, v_motif, v_uid, v_revue.service_en_echec,
    v_revue.type_entite, v_revue.id_entite, v_jeton, v_snapshot
  );

  UPDATE public.file_revue_manuelle
  SET statut = 'RESOLU_MANUELLEMENT',
      assigne_a = v_uid,
      notes_resolution = left(
        CASE WHEN v_decision = 'APPROUVER' THEN 'Approuve : ' ELSE 'Rejete : ' END
          || v_motif,
        1000
      ),
      revu_le = COALESCE(revu_le, now()),
      resolu_le = now()
  WHERE id = v_revue.id
    AND statut = v_revue.statut;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Transition de revue concurrente detectee' USING ERRCODE = '40001';
  END IF;

  -- ADMIN_ACTION appartient a l'allowlist journaux_audit. L'ecriture directe
  -- est volontairement bloquante : un verdict sans audit est annule.
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    cle_s3_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_PLATEFORME', 'ADMIN_ACTION', 'file_revue_manuelle',
    v_revue.id,
    CASE
      WHEN v_revue.service_en_echec = 'VERIFY_RIB_ETABLISSEMENT' THEN v_rib_key
      ELSE NULL
    END,
    jsonb_build_object(
      'sous_action', 'DECISION_REVUE_MANUELLE',
      'decision', v_decision,
      'service', v_revue.service_en_echec,
      'type_entite', v_revue.type_entite,
      'id_entite', v_revue.id_entite,
      'motif', v_motif,
      'source_snapshot', v_snapshot
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'idempotent', false,
    'decision', v_decision,
    'service', v_revue.service_en_echec
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_decider_revue_manuelle(
  uuid, text, text, text, jsonb
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_admin_decider_revue_manuelle(
  uuid, text, text, text, jsonb
) TO authenticated;

-- Les colonnes de provenance sont des champs serveur au meme titre que le
-- verdict SIRET. Le trigger historique est etendu sans modifier son contrat :
-- les anciens flux de reset qui baissent le verdict nettoient automatiquement
-- la nouvelle provenance, tandis qu'un client ne peut jamais la fabriquer.
CREATE OR REPLACE FUNCTION public.fn_proteger_verification_siret_liberal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.siret_liberal_verifie IS NOT TRUE
     OR NEW.siret_liberal_verifie_le IS NULL
     OR NEW.siret_liberal_coherence_identite IS NOT TRUE
     OR (
       NEW.siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE'
       AND NEW.siret_liberal_preuve_siret IS DISTINCT FROM NEW.siret_liberal
     ) THEN
    IF NEW.siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE'
       AND NEW.siret_liberal_preuve_siret IS DISTINCT FROM NEW.siret_liberal THEN
      NEW.siret_liberal_verifie := false;
      NEW.siret_liberal_verifie_le := NULL;
      NEW.siret_liberal_raison_sociale := NULL;
      NEW.siret_liberal_coherence_identite := NULL;
      NEW.tous_documents_valides := false;
    END IF;
    NEW.siret_liberal_source_verification := NULL;
    NEW.siret_liberal_preuve_siret := NULL;
    NEW.siret_liberal_preuve_identite_document_id := NULL;
    NEW.siret_liberal_preuve_identite_document_modifie_le := NULL;
    NEW.siret_liberal_preuve_identite_s3_bucket := NULL;
    NEW.siret_liberal_preuve_identite_s3_cle := NULL;
    NEW.siret_liberal_preuve_identite_s3_version_id := NULL;
    NEW.siret_liberal_preuve_identite_storage_object_id := NULL;
    NEW.siret_liberal_preuve_identite_storage_updated_at := NULL;
    NEW.siret_liberal_preuve_identite_valide_jusqua := NULL;
    NEW.siret_liberal_preuve_identite_empreinte_sha256 := NULL;
  END IF;

  IF COALESCE(
       auth.jwt() ->> 'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) = 'service_role'
     OR auth.uid() IS NULL
     OR public.est_admin() THEN
    RETURN NEW;
  END IF;

  IF COALESCE(current_setting('jolene.siret_liberal_reset', true), '') = 'true'
     AND NEW.siret_liberal_verifie IS FALSE
     AND NEW.siret_liberal_verifie_le IS NULL
     AND NEW.siret_liberal_raison_sociale IS NULL
     AND NEW.siret_liberal_coherence_identite IS NULL
     AND NEW.siret_liberal_source_verification IS NULL
     AND NEW.siret_liberal_preuve_identite_document_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.siret_liberal_verifie IS DISTINCT FROM OLD.siret_liberal_verifie
     OR NEW.siret_liberal_verifie_le IS DISTINCT FROM OLD.siret_liberal_verifie_le
     OR NEW.siret_liberal_raison_sociale IS DISTINCT FROM OLD.siret_liberal_raison_sociale
     OR NEW.siret_liberal_coherence_identite IS DISTINCT FROM OLD.siret_liberal_coherence_identite
     OR NEW.siret_liberal_source_verification IS DISTINCT FROM OLD.siret_liberal_source_verification
     OR NEW.siret_liberal_preuve_siret IS DISTINCT FROM OLD.siret_liberal_preuve_siret
     OR NEW.siret_liberal_preuve_identite_document_id IS DISTINCT FROM OLD.siret_liberal_preuve_identite_document_id
     OR NEW.siret_liberal_preuve_identite_document_modifie_le IS DISTINCT FROM OLD.siret_liberal_preuve_identite_document_modifie_le
     OR NEW.siret_liberal_preuve_identite_s3_bucket IS DISTINCT FROM OLD.siret_liberal_preuve_identite_s3_bucket
     OR NEW.siret_liberal_preuve_identite_s3_cle IS DISTINCT FROM OLD.siret_liberal_preuve_identite_s3_cle
     OR NEW.siret_liberal_preuve_identite_s3_version_id IS DISTINCT FROM OLD.siret_liberal_preuve_identite_s3_version_id
     OR NEW.siret_liberal_preuve_identite_storage_object_id IS DISTINCT FROM OLD.siret_liberal_preuve_identite_storage_object_id
     OR NEW.siret_liberal_preuve_identite_storage_updated_at IS DISTINCT FROM OLD.siret_liberal_preuve_identite_storage_updated_at
     OR NEW.siret_liberal_preuve_identite_valide_jusqua IS DISTINCT FROM OLD.siret_liberal_preuve_identite_valide_jusqua
     OR NEW.siret_liberal_preuve_identite_empreinte_sha256 IS DISTINCT FROM OLD.siret_liberal_preuve_identite_empreinte_sha256 THEN
    RAISE EXCEPTION 'Les preuves SIRET sont reservees au service de verification'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_proteger_verification_siret_liberal()
  FROM PUBLIC, anon, authenticated;

-- Toute mutation materielle de la piece qui a fonde une approbation manuelle
-- revoque immediatement le verdict. L'expiration par ecoulement du temps reste
-- en plus controlee dynamiquement par la fonction d'activation ci-dessous.
CREATE OR REPLACE FUNCTION public.fn_invalider_preuve_identite_siret_manuelle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_document_id uuid := OLD.id;
  v_previous_reset text := COALESCE(
    current_setting('jolene.siret_liberal_reset', true),
    ''
  );
BEGIN
  IF TG_OP = 'UPDATE'
     AND ROW(
       NEW.soignant_id,
       NEW.type_document,
       NEW.s3_bucket,
       NEW.s3_cle,
       NEW.s3_version_id,
       NEW.valide_jusqua,
       NEW.statut_verification,
       NEW.verifie_le,
       NEW.supprime_le,
       NEW.revoque_le,
       NEW.resultat_ia,
       NEW.nom_extrait_ia,
       NEW.prenom_extrait_ia,
       NEW.coherence_nom
     ) IS NOT DISTINCT FROM ROW(
       OLD.soignant_id,
       OLD.type_document,
       OLD.s3_bucket,
       OLD.s3_cle,
       OLD.s3_version_id,
       OLD.valide_jusqua,
       OLD.statut_verification,
       OLD.verifie_le,
       OLD.supprime_le,
       OLD.revoque_le,
       OLD.resultat_ia,
       OLD.nom_extrait_ia,
       OLD.prenom_extrait_ia,
       OLD.coherence_nom
     ) THEN
    RETURN NEW;
  END IF;

  PERFORM set_config('jolene.siret_liberal_reset', 'true', true);
  BEGIN
    UPDATE public.soignants
    SET siret_liberal_verifie = false,
        siret_liberal_verifie_le = NULL,
        siret_liberal_raison_sociale = NULL,
        siret_liberal_coherence_identite = NULL,
        siret_liberal_source_verification = NULL,
        siret_liberal_preuve_siret = NULL,
        siret_liberal_preuve_identite_document_id = NULL,
        siret_liberal_preuve_identite_document_modifie_le = NULL,
        siret_liberal_preuve_identite_s3_bucket = NULL,
        siret_liberal_preuve_identite_s3_cle = NULL,
        siret_liberal_preuve_identite_s3_version_id = NULL,
        siret_liberal_preuve_identite_storage_object_id = NULL,
        siret_liberal_preuve_identite_storage_updated_at = NULL,
        siret_liberal_preuve_identite_valide_jusqua = NULL,
        siret_liberal_preuve_identite_empreinte_sha256 = NULL,
        tous_documents_valides = false,
        modifie_le = now()
    WHERE siret_liberal_preuve_identite_document_id = v_document_id
      AND siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE';
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('jolene.siret_liberal_reset', v_previous_reset, true);
    RAISE;
  END;
  PERFORM set_config('jolene.siret_liberal_reset', v_previous_reset, true);

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_invalider_preuve_siret_identite_update
  ON public.documents_soignants;
CREATE TRIGGER trg_invalider_preuve_siret_identite_update
AFTER UPDATE OF
  soignant_id,
  type_document,
  s3_bucket,
  s3_cle,
  s3_version_id,
  valide_jusqua,
  statut_verification,
  verifie_le,
  supprime_le,
  revoque_le,
  resultat_ia,
  nom_extrait_ia,
  prenom_extrait_ia,
  coherence_nom
ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_preuve_identite_siret_manuelle();

DROP TRIGGER IF EXISTS trg_invalider_preuve_siret_identite_delete
  ON public.documents_soignants;
CREATE TRIGGER trg_invalider_preuve_siret_identite_delete
BEFORE DELETE ON public.documents_soignants
FOR EACH ROW
EXECUTE FUNCTION public.fn_invalider_preuve_identite_siret_manuelle();

REVOKE ALL ON FUNCTION public.fn_invalider_preuve_identite_siret_manuelle()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_invalider_preuve_identite_siret_manuelle()
  TO service_role;

-- L'expiration peut survenir sans UPDATE SQL a minuit et un objet Storage peut
-- etre remplace par son API. L'activation relit donc toujours la provenance
-- manuelle courante au lieu de faire confiance aux seuls booleens du profil.
CREATE OR REPLACE FUNCTION public.fn_activer_liberal()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_soignant record;
  v_taux jsonb;
  v_previous_system_update text := COALESCE(current_setting('jolene.system_update', true), '');
  v_previous_liberal_transition text := COALESCE(current_setting('jolene.liberal_transition', true), '');
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'NON_AUTHENTIFIE',
      'error', 'Non authentifie'
    );
  END IF;

  SELECT * INTO v_soignant
  FROM public.soignants
  WHERE id = v_uid AND supprime_le IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SOIGNANT_INTROUVABLE',
      'error', 'Soignant introuvable'
    );
  END IF;
  IF v_soignant.siret_liberal !~ '^[0-9]{14}$'
     OR v_soignant.siret_liberal_verifie IS NOT TRUE
     OR v_soignant.siret_liberal_verifie_le IS NULL
     OR v_soignant.siret_liberal_coherence_identite IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SIRET_LIBERAL_NON_VERIFIE',
      'error', 'Le SIRET doit etre verifie et correspondre a votre identite avant activation.'
    );
  END IF;
  IF v_soignant.siret_liberal_source_verification = 'REVUE_MANUELLE_IDENTITE'
     AND NOT private.fn_preuve_identite_siret_manuelle_courante(v_uid) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'SIRET_LIBERAL_PREUVE_IDENTITE_OBSOLETE',
      'error', 'La piece d identite ayant fonde la revue SIRET a expire, ete remplacee ou revoquee.'
    );
  END IF;
  IF v_soignant.profession NOT IN (
    SELECT profession FROM public.professions_liberal_eligible
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'PROFESSION_NON_ELIGIBLE',
      'error', 'Votre profession n est pas eligible au liberal'
    );
  END IF;

  v_taux := public.fn_calculer_taux_free_transition(v_uid);
  PERFORM set_config('jolene.liberal_transition', 'true', true);
  PERFORM set_config('jolene.system_update', 'true', true);
  UPDATE public.soignants
  SET type_exercice = 'LIBERAL',
      type_contrat = 'LIBERAL',
      statut_liberal = 'ACTIF',
      date_passage_liberal = current_date,
      code_ape = (
        SELECT code_ape
        FROM public.professions_liberal_eligible
        WHERE profession = v_soignant.profession
      ),
      modifie_le = now()
  WHERE id = v_uid;

  PERFORM public.fn_calculer_tous_documents_valides(v_uid);
  PERFORM set_config('jolene.system_update', v_previous_system_update, true);
  PERFORM set_config('jolene.liberal_transition', v_previous_liberal_transition, true);

  INSERT INTO public.conversions_liberal (
    soignant_id, heures_plateforme_au_demarrage, heures_externes_validees,
    heures_totales, statut, free_transition_eligible,
    taux_prise_en_charge, montant_pris_en_charge, complete_le
  ) VALUES (
    v_uid,
    v_soignant.heures_plateforme,
    COALESCE((
      SELECT sum(heures_declarees)
      FROM public.heures_externes
      WHERE soignant_id = v_uid AND statut = 'VALIDEE'
    ), 0),
    v_soignant.heures_cumulees,
    'COMPLET',
    (v_taux ->> 'eligible')::boolean,
    (v_taux ->> 'taux_prise_en_charge')::integer,
    (v_taux ->> 'montant_pris_en_charge')::numeric,
    now()
  ) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('success', true, 'taux', v_taux);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_activer_liberal() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_activer_liberal()
  TO authenticated, service_role;

-- Une verification automatique ulterieure constitue une nouvelle source plus
-- forte. Elle remplace explicitement toute provenance manuelle precedente au
-- lieu de laisser un document obsolete bloquer un SIRET recoupe par registre.
CREATE OR REPLACE FUNCTION public.fn_appliquer_verification_siret_soignant(
  p_soignant_id uuid,
  p_expected_prenom text,
  p_expected_nom text,
  p_expected_date_naissance date,
  p_expected_siret_liberal text,
  p_expected_statut_liberal text,
  p_expected_type_contrat text,
  p_siret text,
  p_raison_sociale text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_soignant record;
BEGIN
  IF COALESCE(
       auth.jwt() ->> 'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_soignant_id IS NULL
     OR NULLIF(btrim(p_expected_prenom), '') IS NULL
     OR NULLIF(btrim(p_expected_nom), '') IS NULL
     OR p_expected_date_naissance IS NULL
     OR COALESCE(p_siret, '') !~ '^[0-9]{14}$'
     OR p_siret ~ '^0+$' THEN
    RAISE EXCEPTION 'Snapshot SIRET ou identite incomplet'
      USING ERRCODE = '22023';
  END IF;

  SELECT
    s.prenom,
    s.nom,
    s.date_naissance,
    s.siret_liberal,
    s.statut_liberal,
    s.type_contrat::text AS type_contrat
  INTO v_soignant
  FROM public.soignants s
  WHERE s.id = p_soignant_id
    AND s.supprime_le IS NULL
  FOR UPDATE;

  IF NOT FOUND
     OR v_soignant.prenom IS DISTINCT FROM p_expected_prenom
     OR v_soignant.nom IS DISTINCT FROM p_expected_nom
     OR v_soignant.date_naissance IS DISTINCT FROM p_expected_date_naissance
     OR v_soignant.siret_liberal IS DISTINCT FROM p_expected_siret_liberal
     OR v_soignant.statut_liberal IS DISTINCT FROM p_expected_statut_liberal
     OR v_soignant.type_contrat IS DISTINCT FROM p_expected_type_contrat THEN
    RETURN false;
  END IF;

  IF (v_soignant.statut_liberal = 'ACTIF' OR v_soignant.type_contrat = 'LIBERAL')
     AND v_soignant.siret_liberal IS NOT NULL
     AND v_soignant.siret_liberal IS DISTINCT FROM p_siret THEN
    RETURN false;
  END IF;

  UPDATE public.soignants
  SET siret_liberal = p_siret,
      statut_liberal = CASE
        WHEN v_soignant.statut_liberal = 'ACTIF' THEN 'ACTIF'
        ELSE 'EN_COURS'
      END,
      siret_liberal_verifie = true,
      siret_liberal_verifie_le = now(),
      siret_liberal_raison_sociale = NULLIF(btrim(p_raison_sociale), ''),
      siret_liberal_coherence_identite = true,
      siret_liberal_source_verification = 'REGISTRE_OFFICIEL',
      siret_liberal_preuve_siret = NULL,
      siret_liberal_preuve_identite_document_id = NULL,
      siret_liberal_preuve_identite_document_modifie_le = NULL,
      siret_liberal_preuve_identite_s3_bucket = NULL,
      siret_liberal_preuve_identite_s3_cle = NULL,
      siret_liberal_preuve_identite_s3_version_id = NULL,
      siret_liberal_preuve_identite_storage_object_id = NULL,
      siret_liberal_preuve_identite_storage_updated_at = NULL,
      siret_liberal_preuve_identite_valide_jusqua = NULL,
      siret_liberal_preuve_identite_empreinte_sha256 = NULL,
      modifie_le = now()
  WHERE id = p_soignant_id;

  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_appliquer_verification_siret_soignant(
  uuid, text, text, date, text, text, text, text, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_appliquer_verification_siret_soignant(
  uuid, text, text, date, text, text, text, text, text
) TO service_role;
