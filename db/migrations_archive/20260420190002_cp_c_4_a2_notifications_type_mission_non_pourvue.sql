-- ============================================================
-- CP-C-4 A.2 — Ajout MISSION_NON_POURVUE au CHECK notifications
-- ============================================================
-- Bug existant : fn_auto_transitions_missions insérait déjà ce
-- type dans notifications mais le CHECK constraint le rejetait.
-- Jamais atteint côté prod faute de missions éligibles.
-- ============================================================

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'CANDIDATURE_ACCEPTEE'::text, 'CANDIDATURE_REFUSEE'::text, 'CANDIDATURE_PROPOSEE'::text,
    'MISSION_ACCEPTEE'::text, 'MISSION_ANNULEE'::text, 'MISSION_TERMINEE'::text, 'MISSION_URGENTE'::text, 'MISSION_NON_POURVUE'::text,
    'CONTRAT_A_SIGNER'::text, 'CONTRAT_SIGNE'::text,
    'FACTURE_EMISE'::text, 'FACTURE_PAYEE'::text,
    'DOCUMENT_EXPIRANT'::text, 'RAPPEL_DOCUMENTS'::text, 'DOCUMENT_VERIFIE'::text, 'DOCUMENT_REJETE'::text,
    'MESSAGE_RECU'::text, 'MESSAGE_ADMIN'::text,
    'POINTAGE_ARRIVEE'::text, 'POINTAGE_DEPART'::text,
    'EVALUATION_RECUE'::text, 'PARRAINAGE'::text,
    'RAPPEL_MISSION'::text, 'POOL_URGENCE'::text,
    'SYSTEM'::text,
    'LITIGE_OUVERT'::text, 'LITIGE_REPONSE'::text, 'LITIGE_RESOLU'::text, 'LITIGE_MEDIATION'::text
  ]));
