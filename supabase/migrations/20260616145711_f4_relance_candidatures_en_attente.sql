-- Session F4 : relancer l'établissement quand des candidatures restent EN_ATTENTE
-- depuis plus de 24h sur une mission OUVERTE (le temps de réponse est sacré).

-- 1) Nouveau type de notification (liste CHECK complète + RAPPEL_CANDIDATURES).
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type = ANY (ARRAY[
  'CANDIDATURE_ACCEPTEE','CANDIDATURE_REFUSEE','CANDIDATURE_PROPOSEE','MISSION_ACCEPTEE','MISSION_ANNULEE',
  'MISSION_TERMINEE','MISSION_URGENTE','MISSION_NON_POURVUE','MISSION_ASSIGNEE','CONTRAT_A_SIGNER','CONTRAT_SIGNE',
  'FACTURE_EMISE','FACTURE_PAYEE','DOCUMENT_EXPIRANT','RAPPEL_DOCUMENTS','DOCUMENT_VERIFIE','DOCUMENT_REJETE',
  'MESSAGE_RECU','MESSAGE_ADMIN','POINTAGE_ARRIVEE','POINTAGE_DEPART','EVALUATION_RECUE','PARRAINAGE','RAPPEL_MISSION',
  'POOL_URGENCE','POOL_URGENCE_ACCEPTATION','SYSTEM','LITIGE_OUVERT','LITIGE_REPONSE','LITIGE_RESOLU','LITIGE_MEDIATION',
  'CHORUS_DEPOSEE','CHORUS_MISE_A_DISPOSITION','CHORUS_PAIEMENT_EN_COURS','CHORUS_PAIEMENT_COMPTABILISE','CHORUS_REJETEE',
  'FAVORI_NOUVELLE_MISSION','CREDIT_PARRAINAGE','PARRAINAGE_PRIME_VERSEE','LITIGE_RESOLU_AJUSTE','AVOIR_EMIS',
  'COMMISSION_AJUSTEE','LITIGE_ESCALADE_ADMIN','LITIGE_MEDIATION_PRIORITAIRE','LITIGE_RAPPEL_J1','LITIGE_RAPPEL_J3',
  'LITIGE_RAPPEL_J5','REMBOURSEMENT_MANUEL_A_FAIRE','REMBOURSEMENT_CONFIRME','MISSION_A_POURVOIR','RAPPEL_CANDIDATURES'
]::text[]));

-- 2) Dédup : ne pas relancer plus d'une fois par 24h.
ALTER TABLE public.missions ADD COLUMN IF NOT EXISTS derniere_relance_candidatures_le timestamptz;

-- 3) Fonction de relance.
CREATE OR REPLACE FUNCTION public.fn_relancer_candidatures_en_attente()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r RECORD;
  v_nb integer := 0;
BEGIN
  FOR r IN
    SELECT m.id, m.etablissement_id, m.intitule,
           count(c.id) AS nb_attente,
           min(c.cree_le) AS plus_ancienne
    FROM missions m
    JOIN candidatures c ON c.mission_id = m.id AND c.statut = 'EN_ATTENTE'
    WHERE m.statut = 'OUVERTE'
    GROUP BY m.id, m.etablissement_id, m.intitule, m.derniere_relance_candidatures_le
    HAVING min(c.cree_le) < now() - interval '24 hours'
       AND (m.derniere_relance_candidatures_le IS NULL
            OR m.derniere_relance_candidatures_le < now() - interval '24 hours')
  LOOP
    PERFORM public.fn_creer_notification(
      r.etablissement_id, 'ETABLISSEMENT', 'RAPPEL_CANDIDATURES',
      r.nb_attente || ' candidature(s) en attente',
      'Vous avez ' || r.nb_attente || ' candidature(s) à traiter sur « ' || r.intitule ||
        ' », dont la plus ancienne depuis plus de 24h. Répondez vite pour ne pas perdre le soignant.',
      '/etablissement/missions/' || r.id::text,
      'mission', r.id
    );
    UPDATE missions SET derniere_relance_candidatures_le = now() WHERE id = r.id;
    v_nb := v_nb + 1;
  END LOOP;
  RETURN v_nb;
END;
$function$;

-- 4) Cron quotidien à 9h.
SELECT cron.schedule('relance-candidatures-en-attente', '0 9 * * *',
  'SELECT public.fn_relancer_candidatures_en_attente()');
