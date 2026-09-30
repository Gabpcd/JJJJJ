-- API additive : les contrats et la RPC v1.0 ne sont ni modifiés ni requalifiés.
-- La préparation est immuable ; la signature ne porte que sur les octets présentés.
CREATE TABLE public.contrats_service_preparations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL REFERENCES public.etablissements(id) ON DELETE CASCADE,
  prepare_par uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  version text NOT NULL CHECK (version = 'v1.1'),
  template_fingerprint text NOT NULL CHECK (template_fingerprint ~ '^[a-f0-9]{64}$'),
  donnees_etablissement jsonb NOT NULL,
  donnees_hash text NOT NULL CHECK (donnees_hash ~ '^[a-f0-9]{64}$'),
  contenu_texte text NOT NULL,
  contenu_hash text NOT NULL CHECK (contenu_hash ~ '^[a-f0-9]{64}$'),
  prepare_le timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_contrat_preparation_reprise ON public.contrats_service_preparations (etablissement_id, prepare_par, donnees_hash);
ALTER TABLE public.contrats_service_preparations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.contrats_service_preparations FROM PUBLIC, anon, authenticated, service_role;
ALTER TABLE public.contrats_service_signatures
  ADD COLUMN preparation_id uuid UNIQUE REFERENCES public.contrats_service_preparations(id);
COMMENT ON COLUMN public.contrats_service_signatures.preparation_id IS
  'Document immuable présenté avant signature v1.1 ; NULL pour les preuves historiques, jamais reconstruites.';

CREATE FUNCTION public.fn_proteger_preparation_contrat_service() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
BEGIN
  -- Les drafts peuvent être purgés par le propriétaire SQL / helper privé.
  -- Aucune signature, même révoquée, ne peut perdre son document présenté.
  IF TG_OP = 'DELETE' AND NOT EXISTS (
    SELECT 1 FROM public.contrats_service_signatures WHERE preparation_id = OLD.id
  ) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'Préparation contractuelle immuable' USING ERRCODE = 'insufficient_privilege';
END;
$fn$;
REVOKE ALL ON FUNCTION public.fn_proteger_preparation_contrat_service() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_preparation_contrat_service_immuable
  BEFORE UPDATE OR DELETE ON public.contrats_service_preparations
  FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_preparation_contrat_service();

-- Protocole interne de nettoyage : pas de RPC exposée ni de durée légale
-- supposée. La ligne établissement sérialise nettoyage et signature v1.1.
CREATE FUNCTION private.fn_purger_preparations_contrat_non_signees(p_etablissement_id uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE v_nombre integer;
BEGIN
  PERFORM 1 FROM public.etablissements WHERE id = p_etablissement_id FOR UPDATE;
  DELETE FROM public.contrats_service_preparations p WHERE p.etablissement_id = p_etablissement_id
    AND NOT EXISTS (SELECT 1 FROM public.contrats_service_signatures s WHERE s.preparation_id = p.id);
  GET DIAGNOSTICS v_nombre = ROW_COUNT;
  RETURN v_nombre;
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_purger_preparations_contrat_non_signees(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION private.fn_purger_preparations_apres_anonymisation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, private AS $fn$
BEGIN
  IF NEW.type_profil = 'ETABLISSEMENT' THEN
    PERFORM private.fn_purger_preparations_contrat_non_signees(NEW.utilisateur_id);
  END IF;
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION private.fn_purger_preparations_apres_anonymisation() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_purger_preparations_apres_anonymisation
  AFTER INSERT OR UPDATE ON private.suppressions_compte_confirmees
  FOR EACH ROW EXECUTE FUNCTION private.fn_purger_preparations_apres_anonymisation();

-- Données brutes comparées à la signature, même si leur rendu ne change pas.
CREATE FUNCTION public.fn_donnees_contrat_service(p_etablissement_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $fn$
  SELECT jsonb_build_object(
    'etablissement_id', id, 'nom', COALESCE(nom, ''), 'siret', COALESCE(siret, ''),
    'type', COALESCE(type::text, ''), 'adresse_rue', COALESCE(adresse_rue, ''),
    'adresse_code_postal', COALESCE(adresse_code_postal, ''), 'adresse_ville', COALESCE(adresse_ville, ''),
    'email_contact', COALESCE(email_contact, ''), 'representant_nom', COALESCE(representant_nom, ''),
    'representant_prenom', COALESCE(representant_prenom, ''))
  FROM public.etablissements WHERE id = p_etablissement_id AND supprime_le IS NULL;
$fn$;
REVOKE ALL ON FUNCTION public.fn_donnees_contrat_service(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- L'identité ne peut injecter une nouvelle section Markdown. Le snapshot brut est conservé.
CREATE FUNCTION public.fn_valeur_contrat_service(p_valeur text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog AS $fn$
  SELECT COALESCE(NULLIF(btrim(regexp_replace(translate(COALESCE(p_valeur, ''), '*#`<>', '     '), '[[:cntrl:]]', ' ', 'g')), ''), '—');
$fn$;
REVOKE ALL ON FUNCTION public.fn_valeur_contrat_service(text) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_texte_contrat_service_v11(p_donnees jsonb) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $fn$
  SELECT format($contrat$# Contrat de service Jolene

---

## Parties

**JOLENE**, société par actions simplifiée unipersonnelle au capital de 1 000 euros, immatriculée au Registre du Commerce et des Sociétés de Paris sous le numéro 103 305 744, dont le siège social est situé 103 rue de Vaugirard, 75006 Paris, représentée par Madame Gabrielle Nahida Lina PICARD, en sa qualité de Présidente,

ci-après dénommée « Jolene »,

**ET :**

**%1$s**, établissement de santé de type %3$s, SIRET %2$s, situé %4$s, contact %5$s,

ci-après dénommé « l'Établissement »,

ci-après désignés ensemble « les Parties ».

---

## Article 1 — Objet

Le présent contrat a pour objet de définir les conditions dans lesquelles Jolene met à disposition de l'Établissement la plateforme numérique jolene.app permettant de :
- publier des missions de remplacement de professionnels de santé,
- recevoir des candidatures de soignants inscrits sur la plateforme,
- assigner les missions et gérer leur exécution,
- suivre les éléments administratifs et les règlements liés aux missions, proposer des simulations indicatives de paie pour les missions salariées et permettre à l’Établissement de déposer, à destination du salarié concerné, une copie du bulletin officiel déjà remis par son service paie ; gérer la facturation des missions libérales dans le cadre du mandat prévu au présent contrat.

---

## Article 2 — Nature de la relation

2.1 Jolene agit en qualité d'intermédiaire technique et de mandataire de facturation au sens de l'article 289 I-2 du Code général des impôts pour les soignants exerçant en libéral.

2.2 Pour les soignants en exercice salarié (CDD notamment), l'Établissement demeure **seul employeur** du soignant. Jolene n'est en aucun cas employeur des soignants. L'Établissement assume l'intégralité des obligations légales afférentes à la qualité d'employeur, notamment le respect du Code du travail, la déclaration aux organismes sociaux, et la responsabilité de la sécurité du soignant pendant la mission.

2.3 Pour les missions salariées, l’Établissement assure le paiement du salaire ainsi que l’établissement et la remise du bulletin de paie, directement ou par son prestataire de paie. Jolene fournit des outils de suivi administratif et des simulations indicatives de paie, qui ne constituent pas des bulletins officiels. La plateforme permet à l’Établissement de déposer une copie PDF d’un bulletin officiel déjà remis par son service paie, afin que le salarié concerné puisse la consulter et la télécharger. Ce dépôt ne remplace pas la remise du bulletin par l’employeur et ne confirme pas le paiement du salaire. Jolene n’établit pas le bulletin officiel et ne verse pas le salaire au titre de ce service.

---

## Article 3 — Inscription et accès à la plateforme

3.1 L'Établissement déclare exercer une activité d'établissement de santé légalement constituée et autorisée à employer ou faire intervenir des professionnels de santé.

3.2 L'Établissement fournit lors de son inscription :
- un numéro SIRET valide,
- les coordonnées d'un représentant légal habilité à signer le présent contrat,
- un relevé d'identité bancaire (RIB) pour les opérations de paiement,
- toute pièce demandée par Jolene aux fins de vérification d'identité.

3.3 L'Établissement s'engage à maintenir ses informations à jour pendant toute la durée du contrat.

---

## Article 4 — Commission Jolene

4.1 En contrepartie du service rendu, Jolene perçoit une commission sur chaque mission réalisée par l'intermédiaire de la plateforme.

4.2 Le taux de commission applicable est exprimé hors taxes et correspond à celui défini sur le profil Établissement au moment de l'assignation de la mission. Le taux standard est de 15 %% HT. Il peut être négocié individuellement ou au niveau du groupe de santé d'appartenance.

4.3 La commission est calculée sur le montant brut total de la mission (heures travaillées multipliées par le taux horaire, majorations incluses). La TVA au taux en vigueur s'y ajoute ; au taux de 20 %%, la commission standard de 15 %% HT représente 18 %% TTC. Elle est due exclusivement par l'Établissement à Jolene et ne réduit jamais la rémunération du Soignant.

4.4 La commission est figée au moment de l'assignation de la mission et ne peut être modifiée a posteriori sauf renégociation explicite.

4.5 Jolene émet une facture de commission à l'Établissement selon une fréquence mensuelle ou hebdomadaire selon les modalités de la mission. Cette facture est payable à 30 jours date d'émission.

---

## Article 5 — Obligations de l'Établissement

5.1 L'Établissement s'engage à :
- décrire les missions publiées de manière sincère et complète,
- respecter les taux de majoration légaux et conventionnels (nuit, dimanche, fériés),
- déclarer dans les 48 heures les heures réellement travaillées par le soignant via la plateforme,
- payer les sommes dues aux soignants (paie pour les salariés, factures pour les libéraux par l'intermédiaire de Jolene),
- assurer les conditions de sécurité du soignant pendant la mission,
- conclure, le cas échéant, un contrat de travail individuel (CDD notamment) avec le soignant pour les missions salariées, dans les formes et délais prévus par le Code du travail.

5.2 L'Établissement s'engage à uploader sur la plateforme une copie signée du contrat de travail conclu avec le soignant pour chaque mission salariée, au plus tard le premier jour de la mission.

5.3 L'Établissement s'engage à respecter la convention collective applicable à son secteur (FHP, FEHAP, CCU, Croix-Rouge, FPH ou autre).

---

## Article 6 — Obligations de Jolene

6.1 Jolene s'engage à :
- mettre à disposition la plateforme avec une disponibilité raisonnable (objectif 99 %% mensuel hors maintenance planifiée),
- assurer le support utilisateur durant les heures ouvrables,
- préserver la confidentialité des données conformément au Règlement Général sur la Protection des Données (RGPD),
- établir les factures d’honoraires libérales dans le cadre du mandat de facturation prévu au présent contrat,
- mettre à disposition les outils de suivi administratif des missions salariées, les simulations indicatives de paie et le service de dépôt et de consultation des copies de bulletins officiels décrit à l’article 2.3.

6.2 Jolene n'est pas garante du choix du soignant ni de la qualité des prestations fournies par celui-ci. Elle agit comme intermédiaire neutre.

---

## Article 7 — Données personnelles

7.1 Dans le cadre de ce contrat, chaque Partie agit en qualité de responsable de traitement pour les données qu'elle collecte directement.

7.2 Jolene est sous-traitant de l'Établissement pour le traitement des données salariés et libéraux dans le cadre du suivi administratif des missions, des simulations indicatives de paie, du dépôt et de la mise à disposition des copies de bulletins officiels, et de l’établissement des factures d’honoraires libérales, conformément à l'article 28 du RGPD. Un accord de sous-traitance des données (DPA) est annexé au présent contrat.

---

## Article 8 — Durée et résiliation

8.1 Le contrat est conclu pour une durée indéterminée à compter de sa signature électronique sur la plateforme.

8.2 Chaque Partie peut résilier le contrat à tout moment moyennant un préavis de 30 jours notifié par écrit.

8.3 En cas de manquement grave de l'une des Parties à ses obligations, l'autre Partie peut résilier le contrat sans préavis, sous réserve d'une mise en demeure préalable de 8 jours non suivie d'effet.

8.4 La résiliation n'éteint pas les obligations nées avant la résiliation, notamment le paiement des commissions et des sommes dues aux soignants.

---

## Article 9 — Responsabilité

9.1 Chaque Partie est responsable des conséquences de ses propres manquements.

9.2 La responsabilité de Jolene au titre du présent contrat est plafonnée au montant des commissions effectivement perçues par Jolene au titre des 12 mois précédant le fait générateur, sauf cas de faute lourde ou intentionnelle.

---

## Article 10 — Confidentialité

Chaque Partie s'engage à conserver confidentielles toutes informations auxquelles elle pourrait avoir accès dans le cadre du présent contrat, et à ne pas les divulguer à des tiers sans autorisation écrite préalable de l'autre Partie.

---

## Article 11 — Modifications

Toute modification du présent contrat doit faire l'objet d'un avenant écrit, notifié à l'Établissement avec un préavis de 30 jours et accepté par celui-ci.

---

## Article 12 — Droit applicable et juridiction

Le présent contrat est régi par le droit français. Tout litige relatif à son exécution ou son interprétation sera soumis aux tribunaux compétents de Paris.

---

## Article 13 — Signature électronique

Le présent contrat est signé électroniquement par l'Établissement via la plateforme jolene.app. Cette signature électronique vaut accord et engagement ferme et définitif sur l'ensemble des clauses, conformément aux articles 1366 et 1367 du Code civil.

---

**Version du contrat** : v1.1
**Dernière mise à jour** : 30 septembre 2026$contrat$,
    public.fn_valeur_contrat_service(p_donnees->>'nom'),
    public.fn_valeur_contrat_service(p_donnees->>'siret'),
    public.fn_valeur_contrat_service(p_donnees->>'type'),
    public.fn_valeur_contrat_service(concat_ws(', ', NULLIF(p_donnees->>'adresse_rue', ''), NULLIF(p_donnees->>'adresse_code_postal', ''), NULLIF(p_donnees->>'adresse_ville', ''))),
    public.fn_valeur_contrat_service(p_donnees->>'email_contact'));
$fn$;
REVOKE ALL ON FUNCTION public.fn_texte_contrat_service_v11(jsonb) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.fn_preparer_contrat_service_v11() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, extensions AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_etab uuid := public.mon_etablissement_id();
  v_donnees jsonb;
  v_texte text;
  v_preparation public.contrats_service_preparations%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() OR v_etab IS NULL
    OR NOT public.fn_a_permission_etablissement('profil_etab', v_etab) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ACCES_REFUSE');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_etab::text, 0));
  IF EXISTS (SELECT 1 FROM public.contrats_service_signatures WHERE etablissement_id = v_etab AND revoked_at IS NULL) THEN
    RETURN jsonb_build_object('success', false, 'error', 'CONTRAT_DEJA_SIGNE');
  END IF;
  PERFORM 1 FROM public.etablissements WHERE id = v_etab AND supprime_le IS NULL FOR SHARE;
  v_donnees := public.fn_donnees_contrat_service(v_etab);
  IF v_donnees IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'ETABLISSEMENT_INTROUVABLE'); END IF;
  v_texte := public.fn_texte_contrat_service_v11(v_donnees);
  SELECT p.* INTO v_preparation FROM public.contrats_service_preparations p
    WHERE p.etablissement_id = v_etab AND p.prepare_par = v_uid AND p.version = 'v1.1'
      AND p.donnees_hash = encode(extensions.digest(convert_to(v_donnees::text, 'UTF8'), 'sha256'), 'hex')
      AND NOT EXISTS (SELECT 1 FROM public.contrats_service_signatures s WHERE s.preparation_id = p.id)
    ORDER BY p.prepare_le DESC LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO public.contrats_service_preparations
      (etablissement_id, prepare_par, version, template_fingerprint, donnees_etablissement, donnees_hash, contenu_texte, contenu_hash)
    VALUES (v_etab, v_uid, 'v1.1', encode(extensions.digest(convert_to(public.fn_texte_contrat_service_v11('{}'::jsonb), 'UTF8'), 'sha256'), 'hex'),
      v_donnees, encode(extensions.digest(convert_to(v_donnees::text, 'UTF8'), 'sha256'), 'hex'),
      v_texte, encode(extensions.digest(convert_to(v_texte, 'UTF8'), 'sha256'), 'hex'))
    RETURNING * INTO v_preparation;
  END IF;
  RETURN jsonb_build_object('success', true, 'preparation_id', v_preparation.id,
    'etablissement_id', v_etab, 'prepare_par', v_uid, 'version', v_preparation.version,
    'contenu_texte', v_preparation.contenu_texte, 'contenu_hash', v_preparation.contenu_hash);
END;
$fn$;
REVOKE ALL ON FUNCTION public.fn_preparer_contrat_service_v11() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_preparer_contrat_service_v11() TO authenticated, service_role;

CREATE FUNCTION public.fn_signer_contrat_service_v11(p_preparation_id uuid, p_contenu_hash text, p_signature_s3_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, storage, extensions AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_etab uuid := public.mon_etablissement_id();
  v_preparation public.contrats_service_preparations%ROWTYPE;
  v_signature public.contrats_service_signatures%ROWTYPE;
  v_headers jsonb;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() OR v_etab IS NULL
    OR NOT public.fn_a_permission_etablissement('profil_etab', v_etab) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ACCES_REFUSE');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_etab::text, 0));
  -- Même ordre que le cleanup d'anonymisation, qui tient déjà cette ligne.
  PERFORM 1 FROM public.etablissements WHERE id = v_etab AND supprime_le IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'ACCES_REFUSE'); END IF;
  SELECT * INTO v_preparation FROM public.contrats_service_preparations
    WHERE id = p_preparation_id AND etablissement_id = v_etab AND prepare_par = v_uid FOR SHARE;
  IF NOT FOUND OR p_contenu_hash IS DISTINCT FROM v_preparation.contenu_hash THEN
    RETURN jsonb_build_object('success', false, 'error', 'PREPARATION_INVALIDE');
  END IF;
  SELECT * INTO v_signature FROM public.contrats_service_signatures WHERE etablissement_id = v_etab AND revoked_at IS NULL;
  IF FOUND THEN
    -- Réponse perdue : renvoyer la preuve existante, sans changer l'image ou le hash.
    IF v_signature.preparation_id IS DISTINCT FROM p_preparation_id THEN
      RETURN jsonb_build_object('success', false, 'error', 'CONTRAT_DEJA_SIGNE');
    END IF;
    RETURN jsonb_build_object('success', true, 'version', v_signature.version, 'signed_at', v_signature.signed_at, 'contenu_hash', v_signature.contenu_hash);
  END IF;
  -- Une ancienne préparation déjà signée puis révoquée n'est jamais réutilisée.
  IF EXISTS (SELECT 1 FROM public.contrats_service_signatures WHERE preparation_id = p_preparation_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'PREPARATION_DEJA_UTILISEE');
  END IF;
  IF public.fn_donnees_contrat_service(v_etab) IS DISTINCT FROM v_preparation.donnees_etablissement THEN
    RETURN jsonb_build_object('success', false, 'error', 'PROFIL_MODIFIE');
  END IF;
  IF p_signature_s3_key IS NULL OR p_signature_s3_key NOT LIKE v_uid::text || '/signatures/contrat-service-%'
    OR p_signature_s3_key LIKE '%..%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'SIGNATURE_INVALIDE');
  END IF;
  -- Le verrou empêche le nettoyage d'un upload entre contrôle et signature.
  PERFORM 1 FROM storage.objects WHERE bucket_id = 'jolene-documents' AND name = p_signature_s3_key
    AND COALESCE(metadata->>'mimetype', '') IN ('image/png', 'image/jpeg') FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'SIGNATURE_INVALIDE'); END IF;
  BEGIN v_headers := current_setting('request.headers', true)::jsonb;
  EXCEPTION WHEN OTHERS THEN v_headers := '{}'::jsonb; END;
  INSERT INTO public.contrats_service_signatures
    (etablissement_id, version, ip_address, user_agent, contenu_hash, signature_s3_key, preparation_id)
  VALUES (v_etab, v_preparation.version,
    COALESCE(NULLIF(v_headers->>'cf-connecting-ip', ''), NULLIF(split_part(COALESCE(v_headers->>'x-forwarded-for', ''), ',', 1), ''), NULLIF(v_headers->>'x-real-ip', ''), 'unknown'),
    left(COALESCE(NULLIF(v_headers->>'user-agent', ''), 'unknown'), 500),
    v_preparation.contenu_hash, p_signature_s3_key, p_preparation_id)
  RETURNING * INTO v_signature;
  UPDATE public.etablissements SET contrat_service_signe = true, contrat_service_signe_le = v_signature.signed_at, modifie_le = now() WHERE id = v_etab;
  PERFORM public.fn_ecrire_audit_safe(p_acteur_id := v_uid, p_type_acteur := 'ADMIN_ETABLISSEMENT', p_action := 'CONTRAT_SIGNE', p_type_ressource := 'etablissement', p_id_ressource := v_etab,
    p_details := jsonb_build_object('type', 'contrat_service_jolene', 'version', v_signature.version, 'empreinte_serveur', true, 'has_signature_image', true, 'preparation_id', p_preparation_id));
  RETURN jsonb_build_object('success', true, 'version', v_signature.version, 'signed_at', v_signature.signed_at, 'contenu_hash', v_signature.contenu_hash);
END;
$fn$;
REVOKE ALL ON FUNCTION public.fn_signer_contrat_service_v11(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_signer_contrat_service_v11(uuid, text, text) TO authenticated, service_role;

-- Lecture du seul contrat actif du tenant canonique : aucune mutation,
-- aucun accès direct à la table privée, aucune IP/UA ni identité du préparateur.
CREATE FUNCTION public.fn_lire_contrat_service_signe() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_etab uuid := public.mon_etablissement_id();
  v_signature public.contrats_service_signatures%ROWTYPE;
  v_document public.contrats_service_preparations%ROWTYPE;
BEGIN
  IF v_uid IS NULL OR NOT public.fn_compte_auth_actif() OR v_etab IS NULL
    OR NOT public.fn_a_permission_etablissement('profil_etab', v_etab) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ACCES_REFUSE');
  END IF;
  SELECT * INTO v_signature FROM public.contrats_service_signatures
    WHERE etablissement_id = v_etab AND revoked_at IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'CONTRAT_NON_SIGNE'); END IF;
  IF v_signature.preparation_id IS NULL THEN
    -- La preuve v1.0 existe, mais son texte exact n'a jamais été conservé.
    -- Ne jamais le recomposer avec le profil ou le modèle courant.
    IF v_signature.version IS DISTINCT FROM 'v1.0' THEN
      RETURN jsonb_build_object('success', false, 'error', 'DOCUMENT_INDISPONIBLE');
    END IF;
    RETURN jsonb_build_object('success', true, 'etablissement_id', v_etab,
      'signature_id', v_signature.id, 'version', v_signature.version, 'signed_at', v_signature.signed_at,
      'statut_document', 'HISTORIQUE_SANS_DOCUMENT', 'preparation_id', NULL,
      'contenu_texte', NULL, 'contenu_hash', NULL);
  END IF;
  SELECT * INTO v_document FROM public.contrats_service_preparations
    WHERE id = v_signature.preparation_id AND etablissement_id = v_etab;
  IF NOT FOUND OR v_document.version IS DISTINCT FROM v_signature.version
    OR v_document.contenu_hash IS DISTINCT FROM v_signature.contenu_hash THEN
    RETURN jsonb_build_object('success', false, 'error', 'DOCUMENT_INDISPONIBLE');
  END IF;
  RETURN jsonb_build_object('success', true, 'etablissement_id', v_etab,
    'signature_id', v_signature.id, 'version', v_document.version, 'signed_at', v_signature.signed_at,
    'statut_document', 'CONSERVE', 'preparation_id', v_document.id,
    'contenu_texte', v_document.contenu_texte, 'contenu_hash', v_document.contenu_hash);
END;
$fn$;
REVOKE ALL ON FUNCTION public.fn_lire_contrat_service_signe() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.fn_lire_contrat_service_signe() TO authenticated;

-- Seuls les champs de révocation restent modifiables pour une preuve v1.1.
CREATE FUNCTION public.fn_proteger_signature_contrat_preparee() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.preparation_id IS NOT NULL THEN RAISE EXCEPTION 'Preuve contractuelle immuable' USING ERRCODE = 'insufficient_privilege'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.preparation_id IS DISTINCT FROM NEW.preparation_id
    OR (OLD.preparation_id IS NOT NULL AND
      (to_jsonb(OLD) - ARRAY['revoked_at','motif_revocation']) IS DISTINCT FROM
      (to_jsonb(NEW) - ARRAY['revoked_at','motif_revocation'])) THEN
    RAISE EXCEPTION 'Preuve contractuelle immuable' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION public.fn_proteger_signature_contrat_preparee() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_signature_contrat_preparee_immuable BEFORE UPDATE OR DELETE ON public.contrats_service_signatures
  FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_signature_contrat_preparee();

-- Un cleanup serveur (notamment finalize-etablissement-proof-upload) ne peut
-- supprimer ou réécrire une image référencée, y compris une ancienne preuve v1.0.
CREATE INDEX IF NOT EXISTS idx_contrat_service_signature_image ON public.contrats_service_signatures(signature_s3_key);
CREATE FUNCTION public.fn_proteger_image_signature_service() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $fn$
BEGIN
  IF OLD.bucket_id = 'jolene-documents' AND EXISTS (
    SELECT 1 FROM public.contrats_service_signatures WHERE signature_s3_key = OLD.name
  ) THEN
    RAISE EXCEPTION 'Image de signature contractuelle immuable' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION public.fn_proteger_image_signature_service() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER trg_image_signature_service_immuable BEFORE UPDATE OR DELETE ON storage.objects
  FOR EACH ROW EXECUTE FUNCTION public.fn_proteger_image_signature_service();

-- Classification explicite des seules nouvelles RPC exposées.
INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification) VALUES
  ('fn_lire_contrat_service_signe()','RPC_UTILISATEUR_AUTH_INTERNE','fb7f19f4ca466e3b0b1578cf8b523ece','Lecture seule du document lié : compte actif, tenant canonique, droit profil_etab, jamais de reconstruction historique.'),
  ('fn_preparer_contrat_service_v11()','RPC_UTILISATEUR_AUTH_INTERNE','900b1c6580f03127ae79dc633dbad7c7','Contrat v1.1 : compte actif, droit profil_etab, snapshot serveur immuable et aucun remplacement de preuve historique.'),
  ('fn_signer_contrat_service_v11(uuid,text,text)','RPC_UTILISATEUR_AUTH_INTERNE','0b22571451faa32216a39549d02c23b7','Contrat v1.1 : préparation du même acteur/établissement, profil inchangé, image verrouillée et signature idempotente.')
ON CONFLICT(signature) DO UPDATE SET categorie=EXCLUDED.categorie,definition_md5=EXCLUDED.definition_md5,justification=EXCLUDED.justification;
