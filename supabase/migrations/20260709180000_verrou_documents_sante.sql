-- VERROU (principe « gap verrouillé ») — interdit le stockage de documents de
-- santé. Décision actée : Jolene ne stocke AUCUNE donnée de santé (hors HDS,
-- art. L1111-8 CSP). Cf. docs/CONFORMITE.md §1.
--
-- On NE retire PAS les valeurs de l'enum type_document (drop d'une valeur d'enum
-- Postgres = migration à risque pour rien) : on pose un trigger BEFORE INSERT
-- qui rejette tout document de santé avec un message renvoyant à CONFORMITE.md.
--
-- PÉRIMÈTRE ACTUEL : VACCINATIONS + MEDECINE_TRAVAIL (aptitude médicale). Ces
-- deux types sont dormants (0 requis, 0 stocké) ET déjà exclus de l'upload
-- frontend (src/lib/documents.ts TYPES_DOCUMENTS_EXCLUS_UPLOAD).
--
-- ⚠️ ARRET_MALADIE VOLONTAIREMENT EXCLU DU VERROU pour l'instant : contrairement
-- aux 2 autres, c'est une FONCTIONNALITÉ VIVANTE (DetailMissionSoignant :
-- téléversement du certificat d'arrêt maladie pour justifier un désistement
-- médical). Le verrouiller casserait la feature. Décision produit requise
-- (remplacement par attestation sur l'honneur + vérif étab, sans stockage du
-- certificat) AVANT de l'ajouter ici. Cf. docs/CONFORMITE.md §1.4.

CREATE OR REPLACE FUNCTION public.fn_trg_bloquer_documents_sante()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF NEW.type_document::text IN ('VACCINATIONS', 'MEDECINE_TRAVAIL') THEN
    RAISE EXCEPTION 'Document de santé interdit au stockage (type %). Jolene ne stocke aucune donnée de santé (hors HDS, L1111-8 CSP). Remplacement : attestation sur l''honneur + vérification établissement. Cf. docs/CONFORMITE.md §1.', NEW.type_document
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_bloquer_documents_sante ON public.documents_soignants;
CREATE TRIGGER trg_bloquer_documents_sante
  BEFORE INSERT ON public.documents_soignants
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_trg_bloquer_documents_sante();
