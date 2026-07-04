-- Fix Documents: seed documents_requis_par_profession + fix enum mismatch + auto-recalculate trigger
-- See detailed SQL in MCP apply_migration call

-- 1. Seed documents_requis_par_profession (was empty since creation)
TRUNCATE public.documents_requis_par_profession CASCADE;

INSERT INTO public.documents_requis_par_profession (profession, type_document, est_critique, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'CARTE_IDENTITE'::type_document, true, true, 180, 'Carte d''identité ou passeport en cours de validité'
FROM unnest(enum_range(NULL::type_profession)) p;

INSERT INTO public.documents_requis_par_profession (profession, type_document, est_critique, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'DIPLOME'::type_document, true, false, NULL, 'Diplôme d''État ou équivalent'
FROM unnest(enum_range(NULL::type_profession)) p;

INSERT INTO public.documents_requis_par_profession (profession, type_document, est_critique, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'RCP_ASSURANCE'::type_document, false, true, 12, 'Assurance Responsabilité Civile Professionnelle (obligatoire pour exercice libéral/mixte)'
FROM unnest(enum_range(NULL::type_profession)) p;

INSERT INTO public.documents_requis_par_profession (profession, type_document, est_critique, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'RPPS_ADELI'::type_document, false, false, NULL, 'Attestation d''inscription RPPS ou ADELI'
FROM unnest(enum_range(NULL::type_profession)) p;

INSERT INTO public.documents_requis_par_profession (profession, type_document, est_critique, a_expiration, duree_validite_mois, description)
SELECT p::type_profession, 'KBIS'::type_document, false, true, 3, 'Extrait Kbis ou certificat d''inscription (libéraux)'
FROM unnest(enum_range(NULL::type_profession)) p
WHERE p::TEXT IN ('IDE','IBODE','IADE','KINE','SAGE_FEMME','MEDECIN','ORTHOPHONISTE','ERGOTHERAPEUTE','PSYCHOMOTRICIEN','DIETETICIEN');

-- 2. Fix fn_admin_moderer_document: correct enum values + dynamic calculation
-- Was: type_document IN ('PIECE_IDENTITE', 'DIPLOME', 'ASSURANCE_RCP')
-- Now: joins documents_requis_par_profession with est_critique = true
-- (see full function body in MCP apply_migration)

-- 3. Trigger to auto-recalculate tous_documents_valides on document changes
-- fn_recalculer_tous_documents_valides() fires AFTER INSERT/UPDATE/DELETE

NOTIFY pgrst, 'reload schema';
