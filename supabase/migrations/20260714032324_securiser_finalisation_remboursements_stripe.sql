-- Un remboursement Stripe n'est un succès métier qu'après confirmation du
-- Refund (`status = succeeded`). La création d'un Refund peut rester pending,
-- puis échouer : l'ancien flux soldait pourtant immédiatement la queue,
-- l'avoir et l'escrow. Cette migration introduit un état de gel explicite et
-- un rapprochement transactionnel queue + document/escrow + exposition.

ALTER TABLE public.paiements_escrow
  DROP CONSTRAINT IF EXISTS paiements_escrow_statut_check;

ALTER TABLE public.paiements_escrow
  ADD CONSTRAINT paiements_escrow_statut_check
  CHECK (statut = ANY (ARRAY[
    'INITIE'::text,
    'DEBITE'::text,
    'DISPONIBLE'::text,
    'RELEASE_PLANIFIE'::text,
    'PAYE'::text,
    'ECHOUE'::text,
    'REMBOURSE_EN_COURS'::text,
    'REMBOURSE'::text,
    'DISPUTE'::text
  ]));

ALTER TABLE public.stripe_refunds_queue
  ADD COLUMN IF NOT EXISTS escrow_statut_avant_remboursement text;

ALTER TABLE public.stripe_refunds_queue
  DROP CONSTRAINT IF EXISTS stripe_refunds_queue_origine_check;

ALTER TABLE public.stripe_refunds_queue
  ADD CONSTRAINT stripe_refunds_queue_origine_check
  CHECK (
    (
      avoir_id IS NOT NULL
      AND facture_origine_id IS NOT NULL
      AND paiement_escrow_id IS NULL
    )
    OR
    (
      avoir_id IS NULL
      AND facture_origine_id IS NULL
      AND paiement_escrow_id IS NOT NULL
    )
  );

ALTER TABLE public.stripe_refunds_queue
  DROP CONSTRAINT IF EXISTS stripe_refunds_queue_escrow_statut_avant_check;

ALTER TABLE public.stripe_refunds_queue
  ADD CONSTRAINT stripe_refunds_queue_escrow_statut_avant_check
  CHECK (
    escrow_statut_avant_remboursement IS NULL
    OR escrow_statut_avant_remboursement IN (
      'DEBITE', 'DISPONIBLE', 'PAYE'
    )
  );

CREATE UNIQUE INDEX IF NOT EXISTS
  uniq_stripe_refunds_queue_escrow_actif
ON public.stripe_refunds_queue (paiement_escrow_id)
WHERE paiement_escrow_id IS NOT NULL
  AND statut IN ('EN_ATTENTE', 'EN_COURS');

CREATE UNIQUE INDEX IF NOT EXISTS
  uniq_stripe_refunds_queue_stripe_refund_id
ON public.stripe_refunds_queue (stripe_refund_id)
WHERE stripe_refund_id IS NOT NULL;

COMMENT ON COLUMN
  public.stripe_refunds_queue.escrow_statut_avant_remboursement IS
  'État escrow restauré si Stripe confirme failed/canceled ; REMBOURSE seulement après succeeded.';

CREATE OR REPLACE FUNCTION public.fn_escrow_rembourser(
  p_paiement_escrow_id uuid,
  p_montant_honoraires_cts integer,
  p_annulation_totale boolean DEFAULT false,
  p_motif text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.paiements_escrow%ROWTYPE;
  v_queue public.stripe_refunds_queue%ROWTYPE;
  v_absorbe boolean;
  v_reverse boolean;
  v_fee_cts integer;
  v_montant_total integer;
  v_rows integer;
BEGIN
  SELECT pe.*
    INTO v_row
    FROM public.paiements_escrow pe
   WHERE pe.id = p_paiement_escrow_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ESCROW_INCONNU');
  END IF;

  IF v_row.statut = 'REMBOURSE_EN_COURS' THEN
    SELECT q.*
      INTO v_queue
      FROM public.stripe_refunds_queue q
     WHERE q.paiement_escrow_id = v_row.id
       AND q.statut IN ('EN_ATTENTE', 'EN_COURS')
     ORDER BY q.cree_le DESC
     LIMIT 1;
    RETURN jsonb_build_object(
      'success', true,
      'already_queued', true,
      'queue_id', v_queue.id,
      'statut', v_row.statut
    );
  END IF;

  IF v_row.statut = 'REMBOURSE' THEN
    RETURN jsonb_build_object(
      'success', true,
      'already_refunded', true,
      'statut', v_row.statut
    );
  END IF;

  IF p_montant_honoraires_cts IS NULL
     OR p_montant_honoraires_cts <= 0
     OR p_montant_honoraires_cts > v_row.honoraires_cents THEN
    RETURN jsonb_build_object('success', false, 'error', 'MONTANT_INVALIDE');
  END IF;

  IF v_row.stripe_payment_intent_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAS_DE_DEBIT');
  END IF;

  -- Une fois le payout créé, un refund destination-charge et l'annulation du
  -- payout doivent être orchestrés ensemble. Aucun automatisme approximatif.
  IF v_row.statut = 'RELEASE_PLANIFIE' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PAYOUT_DEJA_PLANIFIE',
      'manual_resolution_required', true
    );
  END IF;

  IF v_row.statut NOT IN ('DEBITE', 'DISPONIBLE', 'PAYE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'STATUT_REMBOURSEMENT_INVALIDE',
      'statut', v_row.statut
    );
  END IF;

  -- Avant release, le partiel reste interdit : il laisserait un reliquat sur
  -- le compte connecté sans payout correspondant.
  IF NOT p_annulation_totale
     AND p_montant_honoraires_cts < v_row.honoraires_cents
     AND v_row.statut IN ('DEBITE', 'DISPONIBLE') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'REMBOURSEMENT_PARTIEL_PRE_RELEASE_INDISPONIBLE',
      'manual_resolution_required', true
    );
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.stripe_refunds_queue q
     WHERE q.paiement_escrow_id = v_row.id
       AND q.statut IN ('EN_ATTENTE', 'EN_COURS')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'REMBOURSEMENT_DEJA_EN_COURS'
    );
  END IF;

  v_absorbe := v_row.statut = 'PAYE';
  v_reverse := NOT v_absorbe;

  IF p_annulation_totale THEN
    v_fee_cts := v_row.commission_cents;
  ELSE
    v_fee_cts := round(
      v_row.commission_cents::numeric
      * p_montant_honoraires_cts
      / v_row.honoraires_cents
    )::integer;
  END IF;
  v_montant_total := p_montant_honoraires_cts + v_fee_cts;

  IF v_montant_total <= 0 OR v_montant_total > v_row.montant_total_cents THEN
    RETURN jsonb_build_object('success', false, 'error', 'MONTANT_TOTAL_INVALIDE');
  END IF;

  INSERT INTO public.stripe_refunds_queue (
    avoir_id,
    facture_origine_id,
    stripe_payment_intent_id,
    montant_cts,
    statut,
    paiement_escrow_id,
    reverse_transfer,
    refund_application_fee_cts,
    absorbe_plateforme,
    escrow_statut_avant_remboursement
  ) VALUES (
    NULL,
    NULL,
    v_row.stripe_payment_intent_id,
    v_montant_total,
    'EN_ATTENTE',
    v_row.id,
    v_reverse,
    v_fee_cts,
    v_absorbe,
    v_row.statut
  )
  RETURNING * INTO v_queue;

  UPDATE public.paiements_escrow
     SET statut = 'REMBOURSE_EN_COURS',
         erreur = NULL,
         modifie_le = now()
   WHERE id = v_row.id
     AND statut = v_row.statut;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Gel escrow concurrent refusé';
  END IF;

  -- Audit obligatoire dans la même transaction que le gel : le wrapper
  -- `fn_ecrire_audit_safe` avale volontairement ses erreurs et ne convient pas
  -- à une transition financière.
  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    details, navigateur_acteur
  ) VALUES (
    '00000000-0000-0000-0000-000000000000'::uuid,
    'SYSTEME',
    'ESCROW_REMBOURSEMENT_ENFILE',
    'mission',
    v_row.mission_id,
    jsonb_build_object(
      'paiement_escrow_id', v_row.id,
      'queue_id', v_queue.id,
      'montant_honoraires_cts', p_montant_honoraires_cts,
      'refund_application_fee_cts', v_fee_cts,
      'montant_total_cts', v_montant_total,
      'reverse_transfer', v_reverse,
      'absorbe_plateforme', v_absorbe,
      'annulation_totale', p_annulation_totale,
      'motif', p_motif
    ),
    'fn_escrow_rembourser'
  );

  RETURN jsonb_build_object(
    'success', true,
    'queue_id', v_queue.id,
    'statut', 'REMBOURSE_EN_COURS',
    'reverse_transfer', v_reverse,
    'absorbe_plateforme', v_absorbe,
    'refund_application_fee_cts', v_fee_cts,
    'montant_total_cts', v_montant_total
  );
END;
$function$;

-- L'indemnité d'annulation est une dette de l'établissement envers le
-- soignant. Pour une mission salariée elle passe par la paie de l'employeur ;
-- Jolene ne la vire jamais via Stripe Connect et ne l'annonce jamais versée
-- avant preuve. Pour un remplacement libéral, le règlement reste également
-- manuel tant qu'aucun encaissement dédié et réversible n'existe.
CREATE OR REPLACE FUNCTION public.fn_annuler_mission_etab(
  p_mission_id uuid,
  p_motif_categorie text,
  p_texte_libre text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_mission public.missions%ROWTYPE;
  v_contrat public.contrats_mission%ROWTYPE;
  v_presence_id uuid;
  v_indemnite jsonb;
  v_delta_mission interval;
  v_points integer := 0;
  v_type_evt text;
  v_event_id uuid;
  v_montant_indem numeric := 0;
  v_salarie boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'NON_AUTHENTIFIE',
      'error', 'Non authentifié'
    );
  END IF;
  IF p_motif_categorie IS NULL OR p_motif_categorie NOT IN (
    'BESOIN_DISPARU', 'BUDGET_REVU', 'REMPLACEMENT_INTERNE',
    'CHANGEMENT_PLANNING', 'CAS_FORCE_MAJEURE', 'AUTRE'
  ) THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'MOTIF_INVALIDE',
      'error', 'Motif requis'
    );
  END IF;
  IF p_texte_libre IS NULL OR length(btrim(p_texte_libre)) < 10 THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'TEXTE_REQUIS',
      'error', 'Texte libre obligatoire (min 10 caractères)'
    );
  END IF;

  SELECT m.*
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'MISSION_INTROUVABLE',
      'error', 'Mission introuvable'
    );
  END IF;
  IF public.est_admin() IS NOT TRUE
     AND (
       v_mission.etablissement_id IS DISTINCT FROM public.mon_etablissement_id()
       OR public.fn_a_permission_etablissement(
         'missions', v_mission.etablissement_id
       ) IS NOT TRUE
     ) THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'NON_AUTORISE',
      'error', 'Non autorisé à annuler cette mission'
    );
  END IF;
  IF v_mission.statut IN (
    'LITIGE', 'ANNULEE_PAR_ETABLISSEMENT', 'TERMINEE'
  ) THEN
    RETURN jsonb_build_object(
      'success', false, 'error_code', 'STATUT_INVALIDE',
      'error', 'Mission déjà annulée ou terminée'
    );
  END IF;

  v_delta_mission := v_mission.debut_le - now();
  IF v_mission.statut = 'OUVERTE' THEN
    UPDATE public.missions
       SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = now()
     WHERE id = p_mission_id
       AND statut = 'OUVERTE';
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details
    ) VALUES (
      v_uid, 'ADMIN_ETABLISSEMENT', 'ANNULATION_MISSION', 'mission',
      p_mission_id,
      jsonb_build_object(
        'evenement', 'MISSION_ANNULEE_ETAB',
        'motif_categorie', p_motif_categorie,
        'texte_libre', p_texte_libre,
        'libre', true,
        'statut_initial', 'OUVERTE'
      )
    );
    RETURN jsonb_build_object(
      'success', true, 'libre', true, 'points', 0,
      'indemnite_montant', 0,
      'message', 'Mission ouverte annulée sans impact'
    );
  END IF;

  SELECT c.*
    INTO v_contrat
    FROM public.contrats_mission c
   WHERE c.mission_id = p_mission_id
   ORDER BY c.cree_le DESC
   LIMIT 1
   FOR UPDATE;
  SELECT p.id
    INTO v_presence_id
    FROM public.presences p
   WHERE p.mission_id = p_mission_id
   ORDER BY p.cree_le
   LIMIT 1
   FOR UPDATE;
  v_salarie := v_contrat.id IS NOT NULL
    AND v_contrat.type_contrat IN ('CDD', 'CDDU', 'VACATION');

  IF v_presence_id IS NOT NULL THEN
    UPDATE public.missions
       SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = now()
     WHERE id = p_mission_id;
    UPDATE public.presences
       SET motif_litige = btrim(
             COALESCE(motif_litige, '') || ' ANNULEE_ETAB_APRES_POINTAGE'
           ),
           modifie_le = now()
     WHERE id = v_presence_id;
    v_points := -20;
    v_type_evt := 'ANNULATION_APRES_POINTAGE';
    v_indemnite := public.fn_calculer_indemnite_annulation_etab(
      COALESCE(
        v_contrat.type_contrat,
        v_mission.type_contrat_applique::text,
        'SALARIE'
      ),
      COALESCE(v_mission.duree_heures, 0)
        * COALESCE(v_mission.taux_horaire_base, 0),
      v_mission.duree_heures,
      v_mission.taux_horaire_base,
      interval '0'
    );
    v_montant_indem := COALESCE((v_indemnite->>'montant')::numeric, 0);
  ELSIF v_contrat.id IS NOT NULL AND v_contrat.statut = 'SIGNE_COMPLET' THEN
    UPDATE public.missions
       SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = now()
     WHERE id = p_mission_id;
    UPDATE public.contrats_mission
       SET statut = 'RUPTURE_ETAB', modifie_le = now()
     WHERE id = v_contrat.id
       AND statut = 'SIGNE_COMPLET';
    v_indemnite := public.fn_calculer_indemnite_annulation_etab(
      v_contrat.type_contrat,
      COALESCE(v_mission.duree_heures, 0)
        * COALESCE(v_mission.taux_horaire_base, 0),
      v_mission.duree_heures,
      v_mission.taux_horaire_base,
      v_delta_mission
    );
    v_montant_indem := COALESCE((v_indemnite->>'montant')::numeric, 0);
    v_points := -10;
    v_type_evt := CASE
      WHEN v_salarie THEN 'ANNULATION_CDD_SIGNE'
      ELSE 'ANNULATION_LIBERAL_SIGNE'
    END;
    IF v_salarie THEN
      INSERT INTO public.externalisation_actions (
        type_action, payload, source, source_id
      ) VALUES (
        'DPAE_ANNULATION',
        jsonb_build_object(
          'contrat_id', v_contrat.id,
          'mission_id', p_mission_id,
          'motif', 'ANNULATION_ETAB',
          'echeance_legale_h', 48
        ),
        'ANNULATION_MISSION', p_mission_id
      );
    END IF;
  ELSE
    UPDATE public.missions
       SET statut = 'ANNULEE_PAR_ETABLISSEMENT', modifie_le = now()
     WHERE id = p_mission_id;
    v_points := -3;
    v_type_evt := 'ANNULATION_AVANT_CONTRAT';
    v_indemnite := jsonb_build_object(
      'montant', 0,
      'motif', 'AUCUNE_INDEMNITE_AVANT_CONTRAT'
    );
  END IF;

  INSERT INTO public.evenements_score_etab (
    etablissement_id, type_evenement, points, motif, contestable,
    mission_id, details
  ) VALUES (
    v_mission.etablissement_id, v_type_evt, v_points,
    p_motif_categorie || ' : ' || left(p_texte_libre, 200),
    true, p_mission_id,
    jsonb_build_object(
      'motif_categorie', p_motif_categorie,
      'texte_libre', p_texte_libre,
      'delta_mission_h', extract(epoch FROM v_delta_mission) / 3600,
      'indemnite', v_indemnite,
      'indemnite_statut', CASE
        WHEN v_montant_indem > 0 THEN 'DUE_TRAITEMENT_ETABLISSEMENT'
        ELSE 'NON_DUE'
      END,
      'pointage_existant', v_presence_id IS NOT NULL,
      'contrat_signe', v_contrat.id IS NOT NULL
        AND v_contrat.statut = 'SIGNE_COMPLET'
    )
  ) RETURNING id INTO v_event_id;

  -- Suivi honnête : dette à traiter par l'établissement, sans mouvement
  -- Stripe/SWAN automatique et sans type REFUND détourné.
  IF v_montant_indem > 0 THEN
    INSERT INTO public.notifications (
      destinataire_id, type_destinataire, type, titre, corps, lien,
      type_ressource, id_ressource
    ) VALUES (
      v_mission.etablissement_id,
      'ETABLISSEMENT',
      'SYSTEM',
      'Indemnité d''annulation à traiter',
      'Une indemnité de ' || v_montant_indem
        || '€ est due au soignant. ' || CASE
          WHEN v_salarie THEN 'Intégrez-la à la paie et conservez la preuve.'
          ELSE 'Réglez-la selon le contrat et conservez la preuve.'
        END,
      '/etablissement/facturation',
      'mission',
      p_mission_id
    );
  END IF;

  INSERT INTO public.externalisation_actions (
    type_action, payload, source, source_id
  ) VALUES (
    'AVOIR_PDF_GENERATION',
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type', 'ANNULATION_ETAB',
      'motif_avoir', 'ANNULATION_MISSION_ETAB',
      'montant_indemnite', v_montant_indem
    ),
    'ANNULATION_MISSION', p_mission_id
  );

  IF v_mission.soignant_assigne_id IS NOT NULL THEN
    INSERT INTO public.externalisation_actions (
      type_action, payload, source, source_id
    ) VALUES
      (
        'EMAIL_NOTIF',
        jsonb_build_object(
          'destinataire_id', v_mission.soignant_assigne_id,
          'type', 'MISSION_ANNULEE_ETAB',
          'data', jsonb_build_object(
            'mission_id', p_mission_id,
            'motif_categorie', p_motif_categorie,
            'indemnite_montant', v_montant_indem,
            'indemnite_motif', v_indemnite->>'motif',
            'indemnite_statut', CASE
              WHEN v_montant_indem > 0 THEN 'DUE_EN_COURS_DE_TRAITEMENT'
              ELSE 'NON_DUE'
            END
          )
        ),
        'ANNULATION_MISSION', p_mission_id
      ),
      (
        'PUSH_NOTIF',
        jsonb_build_object(
          'destinataire_id', v_mission.soignant_assigne_id,
          'type_evenement', 'MISSION_ANNULEE_ETAB',
          'titre', 'Mission annulée par l''établissement',
          'corps', CASE
            WHEN v_montant_indem > 0 THEN
              'Une indemnité de ' || v_montant_indem
                || '€ est due et doit être traitée par l''établissement.'
            ELSE 'Aucun contrat signé, pas d''indemnité.'
          END
        ),
        'ANNULATION_MISSION', p_mission_id
      );
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource, details
  ) VALUES (
    v_uid, 'ADMIN_ETABLISSEMENT', 'ANNULATION_MISSION', 'mission',
    p_mission_id,
    jsonb_build_object(
      'evenement', 'MISSION_ANNULEE_ETAB',
      'motif_categorie', p_motif_categorie,
      'texte_libre', p_texte_libre,
      'points', v_points,
      'type_evenement', v_type_evt,
      'indemnite', v_indemnite,
      'indemnite_statut', CASE
        WHEN v_montant_indem > 0 THEN 'DUE_TRAITEMENT_ETABLISSEMENT'
        ELSE 'NON_DUE'
      END,
      'mode_traitement', CASE
        WHEN v_salarie THEN 'PAIE_ETABLISSEMENT'
        ELSE 'REGLEMENT_CONTRACTUEL_ETABLISSEMENT'
      END,
      'pointage_existant', v_presence_id IS NOT NULL,
      'contrat_signe', v_contrat.id IS NOT NULL
        AND v_contrat.statut = 'SIGNE_COMPLET',
      'event_score_id', v_event_id
    )
  );

  RETURN jsonb_build_object(
    'success', true,
    'libre', v_points = 0,
    'points', v_points,
    'type_evenement', v_type_evt,
    'event_score_id', v_event_id,
    'indemnite', v_indemnite,
    'indemnite_statut', CASE
      WHEN v_montant_indem > 0 THEN 'DUE_TRAITEMENT_ETABLISSEMENT'
      ELSE 'NON_DUE'
    END,
    'message', CASE
      WHEN v_montant_indem > 0 THEN
        'Indemnité de ' || v_montant_indem
          || '€ due au soignant, à traiter par l''établissement'
      WHEN v_points = -3 THEN
        'Annulation enregistrée, pas d''indemnité (contrat non signé)'
      ELSE 'Annulation enregistrée'
    END
  );
END;
$function$;

-- Les acquittements du worker font partie de la transaction métier : un RPC
-- qui ne modifie aucune ligne ne doit plus prétendre avoir réussi.
CREATE OR REPLACE FUNCTION public.fn_externalisation_succes(
  p_id uuid,
  p_resultat jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_action public.externalisation_actions%ROWTYPE;
  v_rows integer;
BEGIN
  IF p_id IS NULL
     OR (p_resultat IS NOT NULL AND jsonb_typeof(p_resultat) <> 'object') THEN
    RAISE EXCEPTION 'Acquittement externalisation invalide' USING ERRCODE = '22023';
  END IF;

  SELECT ea.*
    INTO v_action
    FROM public.externalisation_actions ea
   WHERE ea.id = p_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action externalisation introuvable' USING ERRCODE = 'P0001';
  END IF;

  IF v_action.statut = 'DONE' THEN
    RETURN jsonb_build_object('success', true, 'already_done', true);
  END IF;
  IF v_action.statut = 'CANCELLED' THEN
    RAISE EXCEPTION 'Action externalisation annulée' USING ERRCODE = 'P0001';
  END IF;
  IF v_action.statut NOT IN ('PROCESSING', 'PENDING', 'ERROR', 'PENDING_AIFE') THEN
    RAISE EXCEPTION 'État externalisation non acquittable: %', v_action.statut;
  END IF;

  UPDATE public.externalisation_actions
     SET statut = 'DONE',
         traite_le = now(),
         resultat = COALESCE(p_resultat, '{}'::jsonb),
         derniere_erreur = NULL,
         cron_lock_at = NULL,
         cron_lock_par = NULL,
         next_retry_at = NULL
   WHERE id = p_id
     AND statut = v_action.statut;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Acquittement externalisation concurrent refusé';
  END IF;
  RETURN jsonb_build_object('success', true, 'statut', 'DONE');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_externalisation_echec(
  p_id uuid,
  p_erreur text,
  p_special_statut text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_action public.externalisation_actions%ROWTYPE;
  v_new_tentatives integer;
  v_new_statut text;
  v_next_retry timestamptz;
  v_rows integer;
BEGIN
  IF p_id IS NULL OR btrim(COALESCE(p_erreur, '')) = '' THEN
    RAISE EXCEPTION 'Échec externalisation invalide' USING ERRCODE = '22023';
  END IF;
  SELECT ea.*
    INTO v_action
    FROM public.externalisation_actions ea
   WHERE ea.id = p_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Action externalisation introuvable' USING ERRCODE = 'P0001';
  END IF;
  IF v_action.statut = 'DONE' THEN
    RETURN jsonb_build_object('success', true, 'already_done', true);
  END IF;
  IF v_action.statut = 'CANCELLED' THEN
    RETURN jsonb_build_object('success', true, 'cancelled', true);
  END IF;

  IF p_special_statut = 'PENDING_AIFE' THEN
    v_new_statut := 'PENDING_AIFE';
    v_next_retry := now() + interval '24 hours';
    v_new_tentatives := v_action.tentatives;
  ELSIF p_special_statut IS NOT NULL THEN
    RAISE EXCEPTION 'Statut spécial externalisation invalide' USING ERRCODE = '22023';
  ELSE
    v_new_tentatives := COALESCE(v_action.tentatives, 0) + 1;
    IF v_new_tentatives >= 3 THEN
      v_new_statut := 'ERROR';
      v_next_retry := NULL;
    ELSIF v_new_tentatives = 1 THEN
      v_new_statut := 'PENDING';
      v_next_retry := now() + interval '1 minute';
    ELSE
      v_new_statut := 'PENDING';
      v_next_retry := now() + interval '5 minutes';
    END IF;
  END IF;

  UPDATE public.externalisation_actions
     SET statut = v_new_statut,
         tentatives = v_new_tentatives,
         derniere_tentative_le = now(),
         derniere_erreur = left(p_erreur, 1000),
         next_retry_at = v_next_retry,
         cron_lock_at = NULL,
         cron_lock_par = NULL,
         traite_le = CASE WHEN v_new_statut = 'ERROR' THEN now() ELSE traite_le END
   WHERE id = p_id
     AND statut = v_action.statut;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Échec externalisation concurrent refusé';
  END IF;

  IF v_new_statut = 'ERROR' THEN
    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource, details,
      navigateur_acteur
    ) VALUES (
      '00000000-0000-0000-0000-000000000000'::uuid,
      'SYSTEME', 'SYSTEM', 'externalisation_action', p_id,
      jsonb_build_object(
        'evenement', 'EXTERNALISATION_ECHEC_DEFINITIF',
        'type_action', v_action.type_action,
        'tentatives', v_new_tentatives,
        'derniere_erreur', left(p_erreur, 200)
      ),
      'fn_externalisation_echec'
    );
  END IF;
  RETURN jsonb_build_object(
    'success', true,
    'statut', v_new_statut,
    'tentatives', v_new_tentatives
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_externalisation_succes(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_externalisation_echec(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_externalisation_succes(uuid, jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_externalisation_echec(uuid, text, text)
  TO service_role;

REVOKE ALL ON FUNCTION public.fn_escrow_rembourser(
  uuid, integer, boolean, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_escrow_rembourser(
  uuid, integer, boolean, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_stripe_refund_rapprocher(
  p_queue_id uuid,
  p_stripe_refund_id text,
  p_resultat text,
  p_detail text DEFAULT NULL,
  p_finalise_le timestamptz DEFAULT now()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_queue public.stripe_refunds_queue%ROWTYPE;
  v_avoir public.factures_honoraires%ROWTYPE;
  v_escrow public.paiements_escrow%ROWTYPE;
  v_rows integer;
  v_legacy_escrow boolean := false;
BEGIN
  IF COALESCE(
       auth.jwt()->>'role',
       current_setting('request.jwt.claim.role', true),
       ''
     ) <> 'service_role'
     AND session_user NOT IN ('postgres', 'supabase_admin') THEN
    RAISE EXCEPTION 'Service role requis' USING ERRCODE = '42501';
  END IF;

  IF p_queue_id IS NULL
     OR p_resultat NOT IN ('SUCCEEDED', 'FAILED', 'CANCELED') THEN
    RAISE EXCEPTION 'Rapprochement refund invalide' USING ERRCODE = '22023';
  END IF;

  -- Un refund effectivement créé porte toujours son identifiant Stripe. Un
  -- échec de validation/création peut être terminal avant que Stripe n'ait
  -- créé le moindre objet ; NULL reste alors une provenance explicite.
  IF p_resultat IN ('SUCCEEDED', 'CANCELED')
     AND (p_stripe_refund_id IS NULL
          OR p_stripe_refund_id !~ '^re_[A-Za-z0-9]+$') THEN
    RAISE EXCEPTION 'Identifiant Stripe refund requis' USING ERRCODE = '22023';
  END IF;
  IF p_stripe_refund_id IS NOT NULL
     AND p_stripe_refund_id !~ '^re_[A-Za-z0-9]+$' THEN
    RAISE EXCEPTION 'Identifiant Stripe refund invalide' USING ERRCODE = '22023';
  END IF;

  SELECT q.*
    INTO v_queue
    FROM public.stripe_refunds_queue q
   WHERE q.id = p_queue_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue refund introuvable' USING ERRCODE = 'P0001';
  END IF;

  IF v_queue.stripe_refund_id IS NOT NULL
     AND v_queue.stripe_refund_id <> p_stripe_refund_id THEN
    RAISE EXCEPTION 'Refund Stripe différent déjà lié à la queue'
      USING ERRCODE = 'P0001';
  END IF;

  IF p_resultat = 'SUCCEEDED' AND v_queue.statut = 'TRAITE' THEN
    IF v_queue.stripe_refund_id = p_stripe_refund_id THEN
      RETURN jsonb_build_object('success', true, 'already_processed', true);
    END IF;
    RAISE EXCEPTION 'Queue traitée sans le refund attendu' USING ERRCODE = 'P0001';
  END IF;

  IF p_resultat IN ('FAILED', 'CANCELED') AND v_queue.statut = 'ECHEC' THEN
    IF v_queue.stripe_refund_id IS NOT DISTINCT FROM p_stripe_refund_id THEN
      RETURN jsonb_build_object('success', true, 'already_processed', true);
    END IF;
    RAISE EXCEPTION 'Queue en échec sans le refund attendu' USING ERRCODE = 'P0001';
  END IF;

  IF v_queue.statut NOT IN ('EN_ATTENTE', 'EN_COURS') THEN
    RAISE EXCEPTION 'Transition refund interdite depuis %', v_queue.statut
      USING ERRCODE = 'P0001';
  END IF;

  IF p_resultat = 'SUCCEEDED' THEN
    IF v_queue.avoir_id IS NOT NULL THEN
      SELECT fh.*
        INTO v_avoir
        FROM public.factures_honoraires fh
       WHERE fh.id = v_queue.avoir_id
         AND fh.type_document = 'AVOIR'
       FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Avoir de la queue introuvable' USING ERRCODE = 'P0001';
      END IF;
      IF round(abs(v_avoir.montant_ttc) * 100)::integer <> v_queue.montant_cts THEN
        RAISE EXCEPTION 'Montant de l''avoir incohérent avec la queue'
          USING ERRCODE = 'P0001';
      END IF;

      IF v_avoir.statut = 'REMBOURSE' THEN
        IF v_avoir.reference_remboursement IS DISTINCT FROM p_stripe_refund_id THEN
          RAISE EXCEPTION 'Avoir déjà rapproché avec une autre référence'
            USING ERRCODE = 'P0001';
        END IF;
      ELSE
        UPDATE public.factures_honoraires
           SET statut = 'REMBOURSE',
               date_remboursement = COALESCE(p_finalise_le, now()),
               reference_remboursement = p_stripe_refund_id
         WHERE id = v_avoir.id
           AND statut IN ('EMISE', 'EN_RETARD');
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'État de l''avoir non remboursable: %', v_avoir.statut
            USING ERRCODE = 'P0001';
        END IF;
      END IF;
    END IF;

    IF v_queue.paiement_escrow_id IS NOT NULL THEN
      SELECT pe.*
        INTO v_escrow
        FROM public.paiements_escrow pe
       WHERE pe.id = v_queue.paiement_escrow_id
       FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Escrow de la queue introuvable' USING ERRCODE = 'P0001';
      END IF;

      IF v_escrow.statut = 'REMBOURSE' THEN
        -- Compatibilité défensive pour une éventuelle ligne créée avant cette
        -- migration. La production était vide lors de l'audit pré-déploiement.
        v_legacy_escrow := true;
      ELSIF v_escrow.statut = 'REMBOURSE_EN_COURS' THEN
        UPDATE public.paiements_escrow
           SET statut = 'REMBOURSE',
               erreur = NULL,
               modifie_le = now()
         WHERE id = v_escrow.id
           AND statut = 'REMBOURSE_EN_COURS';
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> 1 THEN
          RAISE EXCEPTION 'Finalisation escrow concurrente refusée';
        END IF;
      ELSE
        RAISE EXCEPTION 'État escrow incompatible avec refund réussi: %',
          v_escrow.statut USING ERRCODE = 'P0001';
      END IF;

      UPDATE public.escrow_exposition_releases
         SET statut = 'REGLE'
       WHERE paiement_escrow_id = v_escrow.id
         AND statut = 'ACTIF';
    END IF;

    UPDATE public.stripe_refunds_queue
       SET statut = 'TRAITE',
           stripe_refund_id = p_stripe_refund_id,
           traite_le = COALESCE(p_finalise_le, now()),
           dernier_essai_le = now(),
           erreur = NULL
     WHERE id = v_queue.id
       AND statut IN ('EN_ATTENTE', 'EN_COURS');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Finalisation queue concurrente refusée';
    END IF;

    INSERT INTO public.journaux_audit (
      acteur_id, type_acteur, action, type_ressource, id_ressource,
      details, navigateur_acteur
    ) VALUES (
      '00000000-0000-0000-0000-000000000000'::uuid,
      'SYSTEME',
      CASE
        WHEN v_queue.avoir_id IS NOT NULL THEN 'AVOIR_REMBOURSEMENT_CONFIRME'
        WHEN v_queue.paiement_escrow_id IS NOT NULL THEN 'ESCROW_REMBOURSE'
        ELSE 'FINANCE_CHARGE_REFUNDED'
      END,
      CASE
        WHEN v_queue.avoir_id IS NOT NULL THEN 'facture_honoraires'
        WHEN v_queue.paiement_escrow_id IS NOT NULL THEN 'paiement_escrow'
        ELSE 'stripe_refunds_queue'
      END,
      COALESCE(v_queue.avoir_id, v_queue.paiement_escrow_id, v_queue.id),
      jsonb_build_object(
        'queue_id', v_queue.id,
        'stripe_refund_id', p_stripe_refund_id,
        'stripe_payment_intent_id', v_queue.stripe_payment_intent_id,
        'montant_cts', v_queue.montant_cts
      ),
      'fn_stripe_refund_rapprocher'
    );

    RETURN jsonb_build_object(
      'success', true,
      'resultat', 'SUCCEEDED',
      'legacy_escrow', v_legacy_escrow
    );
  END IF;

  -- failed/canceled : le remboursement n'a pas eu lieu. Restaurer l'escrow
  -- exactement dans son état antérieur ; ne jamais solder son exposition.
  IF v_queue.paiement_escrow_id IS NOT NULL THEN
    SELECT pe.*
      INTO v_escrow
      FROM public.paiements_escrow pe
     WHERE pe.id = v_queue.paiement_escrow_id
     FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Escrow de la queue introuvable' USING ERRCODE = 'P0001';
    END IF;

    IF v_escrow.statut = 'REMBOURSE_EN_COURS' THEN
      IF v_queue.escrow_statut_avant_remboursement NOT IN (
        'DEBITE', 'DISPONIBLE', 'PAYE'
      ) THEN
        RAISE EXCEPTION 'État escrow antérieur absent ou invalide'
          USING ERRCODE = 'P0001';
      END IF;
      UPDATE public.paiements_escrow
         SET statut = v_queue.escrow_statut_avant_remboursement,
             erreur = left(COALESCE(p_detail, p_resultat), 500),
             modifie_le = now()
       WHERE id = v_escrow.id
         AND statut = 'REMBOURSE_EN_COURS';
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Restauration escrow concurrente refusée';
      END IF;
    ELSIF v_escrow.statut <> 'REMBOURSE' THEN
      RAISE EXCEPTION 'État escrow incompatible avec refund échoué: %',
        v_escrow.statut USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.stripe_refunds_queue
     SET statut = 'ECHEC',
         stripe_refund_id = COALESCE(p_stripe_refund_id, stripe_refund_id),
         dernier_essai_le = now(),
         erreur = left(COALESCE(p_detail, p_resultat), 500)
   WHERE id = v_queue.id
     AND statut IN ('EN_ATTENTE', 'EN_COURS');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'Échec queue concurrent refusé';
  END IF;

  INSERT INTO public.journaux_audit (
    acteur_id, type_acteur, action, type_ressource, id_ressource,
    details, navigateur_acteur
  ) VALUES (
    '00000000-0000-0000-0000-000000000000'::uuid,
    'SYSTEME',
    'ADMIN_ACTION',
    'stripe_refunds_queue',
    v_queue.id,
    jsonb_build_object(
      'evenement', 'FINANCE_REFUND_TERMINE_SANS_SUCCES',
      'queue_id', v_queue.id,
      'stripe_refund_id', p_stripe_refund_id,
      'resultat', p_resultat,
      'detail', p_detail
    ),
    'fn_stripe_refund_rapprocher'
  );

  RETURN jsonb_build_object('success', true, 'resultat', p_resultat);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_stripe_refund_rapprocher(
  uuid, text, text, text, timestamptz
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stripe_refund_rapprocher(
  uuid, text, text, text, timestamptz
) TO service_role;

-- Les deux helpers d'accord utilisent désormais le circuit escrow dédié et
-- n'enfilent une externalisation legacy que pour un PI de mission non-Connect.
CREATE OR REPLACE FUNCTION public.fn_annuler_mission_complete(
  p_mission_id uuid,
  p_motif text,
  p_source_litige_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_presence_id uuid;
  v_escrow public.paiements_escrow%ROWTYPE;
  v_refund jsonb;
BEGIN
  SELECT m.*
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.stripe_transfers st
     WHERE st.mission_id = p_mission_id
       AND st.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
      'error', 'Un paiement Stripe Connect actif exige un reversal manuel vérifié.'
    );
  END IF;

  SELECT pe.*
    INTO v_escrow
    FROM public.paiements_escrow pe
   WHERE pe.mission_id = p_mission_id
     AND pe.statut NOT IN ('ECHOUE', 'DISPUTE')
   ORDER BY pe.cree_le DESC
   LIMIT 1
   FOR UPDATE;

  IF FOUND AND v_escrow.statut <> 'REMBOURSE' THEN
    v_refund := public.fn_escrow_rembourser(
      v_escrow.id,
      v_escrow.honoraires_cents,
      true,
      p_motif
    );
    IF COALESCE(v_refund @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
      RETURN v_refund;
    END IF;
  ELSIF v_mission.stripe_payment_intent_id IS NOT NULL THEN
    INSERT INTO public.externalisation_actions (
      type_action, payload, source, source_id
    ) VALUES (
      'STRIPE_REFUND_TOTAL',
      jsonb_build_object('mission_id', p_mission_id, 'motif', p_motif),
      'LITIGE_EXEC',
      p_source_litige_id
    );
  END IF;

  UPDATE public.missions
     SET statut = 'LITIGE',
         modifie_le = now()
   WHERE id = p_mission_id;

  SELECT p.id
    INTO v_presence_id
    FROM public.presences p
   WHERE p.mission_id = p_mission_id
   ORDER BY p.cree_le
   LIMIT 1
   FOR UPDATE;
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.presences
       SET heures_ajustees_litige = 0,
           ajustement_litige_id = p_source_litige_id,
           motif_litige = p_motif,
           modifie_le = now()
     WHERE id = v_presence_id;
  END IF;

  INSERT INTO public.externalisation_actions (
    type_action, payload, source, source_id
  ) VALUES
    (
      'CHORUS_RECYCLER_FACTURE',
      jsonb_build_object('mission_id', p_mission_id, 'motif', 'ANNULATION'),
      'LITIGE_EXEC', p_source_litige_id
    ),
    (
      'DPAE_ANNULATION',
      jsonb_build_object('mission_id', p_mission_id, 'motif', p_motif),
      'LITIGE_EXEC', p_source_litige_id
    ),
    (
      'AVOIR_PDF_GENERATION',
      jsonb_build_object(
        'mission_id', p_mission_id,
        'type', 'TOTAL',
        'motif_avoir', 'ANNULATION_MISSION_SOIGNANT'
      ),
      'LITIGE_EXEC', p_source_litige_id
    );

  RETURN jsonb_build_object(
    'success', true,
    'mission_id', p_mission_id,
    'presence_id', v_presence_id,
    'refund', v_refund
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_appliquer_compensation_partielle(
  p_mission_id uuid,
  p_pourcentage numeric,
  p_motif text,
  p_source_litige_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_mission public.missions%ROWTYPE;
  v_presence_id uuid;
  v_taux numeric;
  v_escrow public.paiements_escrow%ROWTYPE;
  v_refund jsonb;
  v_honoraires_refund integer;
BEGIN
  IF p_pourcentage IS NULL OR p_pourcentage <= 0 OR p_pourcentage > 100 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Pourcentage doit être entre 0 et 100'
    );
  END IF;

  SELECT m.*
    INTO v_mission
    FROM public.missions m
   WHERE m.id = p_mission_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Mission introuvable');
  END IF;

  IF EXISTS (
    SELECT 1
      FROM public.stripe_transfers st
     WHERE st.mission_id = p_mission_id
       AND st.statut NOT IN ('ECHOUE', 'ANNULEE', 'REMBOURSE')
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error_code', 'RESOLUTION_FINANCIERE_MANUELLE_REQUISE',
      'error', 'Un paiement Stripe Connect actif exige un reversal manuel vérifié.'
    );
  END IF;

  SELECT pe.*
    INTO v_escrow
    FROM public.paiements_escrow pe
   WHERE pe.mission_id = p_mission_id
     AND pe.statut NOT IN ('ECHOUE', 'DISPUTE', 'REMBOURSE')
   ORDER BY pe.cree_le DESC
   LIMIT 1
   FOR UPDATE;

  IF FOUND THEN
    v_honoraires_refund := round(
      v_escrow.honoraires_cents::numeric * p_pourcentage / 100
    )::integer;
    v_refund := public.fn_escrow_rembourser(
      v_escrow.id,
      v_honoraires_refund,
      p_pourcentage = 100,
      p_motif
    );
    IF COALESCE(v_refund @> '{"success": true}'::jsonb, false) IS NOT TRUE THEN
      RETURN v_refund;
    END IF;
  ELSIF v_mission.stripe_payment_intent_id IS NOT NULL THEN
    INSERT INTO public.externalisation_actions (
      type_action, payload, source, source_id
    ) VALUES (
      'STRIPE_REFUND_PARTIEL',
      jsonb_build_object(
        'mission_id', p_mission_id,
        'pourcentage', p_pourcentage
      ),
      'LITIGE_EXEC',
      p_source_litige_id
    );
  END IF;

  v_taux := (100 - p_pourcentage) / 100.0;
  SELECT p.id
    INTO v_presence_id
    FROM public.presences p
   WHERE p.mission_id = p_mission_id
   ORDER BY p.cree_le
   LIMIT 1
   FOR UPDATE;
  IF v_presence_id IS NOT NULL THEN
    UPDATE public.presences
       SET heures_ajustees_litige = round(
             duree_brute_min::numeric / 60 * v_taux,
             2
           ),
           ajustement_litige_id = p_source_litige_id,
           motif_litige = p_motif,
           modifie_le = now()
     WHERE id = v_presence_id;
  END IF;

  INSERT INTO public.externalisation_actions (
    type_action, payload, source, source_id
  ) VALUES (
    'AVOIR_PDF_GENERATION',
    jsonb_build_object(
      'mission_id', p_mission_id,
      'type', 'PARTIEL',
      'pourcentage', p_pourcentage,
      'motif_avoir', 'COMPENSATION_PARTIELLE'
    ),
    'LITIGE_EXEC',
    p_source_litige_id
  );

  RETURN jsonb_build_object(
    'success', true,
    'mission_id', p_mission_id,
    'pourcentage_compensation', p_pourcentage,
    'presence_id', v_presence_id,
    'refund', v_refund
  );
END;
$function$;
