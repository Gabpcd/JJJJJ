-- Durcissements pre-lancement issus des advisors Supabase.
--
-- Cette migration ne modifie aucune donnee metier : elle fige le search_path
-- d'un trigger, ferme ses appels RPC directs, resserre une RPC authentifiee,
-- ajoute trois index de FK et conserve exactement la semantique de cinq
-- politiques RLS en evitant les reevaluations par ligne.

-- Un trigger ne doit jamais etre exposable comme RPC. PostgreSQL conserve son
-- execution par les triggers existants ; le proprietaire peut aussi l'utiliser
-- lors de futures creations de trigger.
ALTER FUNCTION public.fn_trg_bloquer_documents_sante()
  SET search_path = pg_catalog, public;

DO $revoke_trigger_rpc$
DECLARE
  v_trigger record;
BEGIN
  FOR v_trigger IN
    SELECT p.oid
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.prorettype = 'pg_catalog.trigger'::regtype
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_trigger.oid::regprocedure
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %s TO service_role',
      v_trigger.oid::regprocedure
    );
  END LOOP;
END;
$revoke_trigger_rpc$;

-- La page prevoyance est une route SOIGNANT authentifiee. Une inscription
-- anonyme directe n'est donc ni necessaire ni souhaitable.
REVOKE ALL ON FUNCTION public.fn_inscrire_liste_attente_prevoyance(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_inscrire_liste_attente_prevoyance(text, text)
  TO authenticated, service_role;

-- Index couvrant les FK signalees par le conseiller de performance.
CREATE INDEX IF NOT EXISTS idx_escrow_release_queue_mission_id
  ON public.escrow_release_queue (mission_id);
CREATE INDEX IF NOT EXISTS idx_stripe_refunds_queue_paiement_escrow_id
  ON public.stripe_refunds_queue (paiement_escrow_id);
CREATE INDEX IF NOT EXISTS idx_utilisateurs_bloques_bloque_id
  ON public.utilisateurs_bloques (bloque_id);

-- Missions sauvegardees : meme isolation par auth.uid(), evaluee une seule
-- fois par requete grace au sous-select initPlan.
DROP POLICY IF EXISTS missions_sauvegardees_delete ON public.missions_sauvegardees;
CREATE POLICY missions_sauvegardees_delete
  ON public.missions_sauvegardees
  FOR DELETE TO authenticated
  USING (soignant_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS missions_sauvegardees_insert ON public.missions_sauvegardees;
CREATE POLICY missions_sauvegardees_insert
  ON public.missions_sauvegardees
  FOR INSERT TO authenticated
  WITH CHECK (soignant_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS missions_sauvegardees_select ON public.missions_sauvegardees;
CREATE POLICY missions_sauvegardees_select
  ON public.missions_sauvegardees
  FOR SELECT TO authenticated
  USING (soignant_id = (SELECT auth.uid()));

-- Les trois politiques permissives historiques etaient un OR implicite. Une
-- politique unique garde strictement le meme resultat, n'est plus visible par
-- anon et n'evalue chaque helper qu'une seule fois.
DROP POLICY IF EXISTS paiements_escrow_select_admin ON public.paiements_escrow;
DROP POLICY IF EXISTS paiements_escrow_select_etab ON public.paiements_escrow;
DROP POLICY IF EXISTS paiements_escrow_select_soignant ON public.paiements_escrow;
CREATE POLICY paiements_escrow_select_participant
  ON public.paiements_escrow
  FOR SELECT TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR etablissement_id = (SELECT public.mon_etablissement_id())
    OR (SELECT public.est_admin())
  );

DROP POLICY IF EXISTS dispos_soignant_select ON public.disponibilites_soignant;
CREATE POLICY dispos_soignant_select
  ON public.disponibilites_soignant
  FOR SELECT TO authenticated
  USING (
    soignant_id = (SELECT auth.uid())
    OR (SELECT public.est_admin())
  );

COMMENT ON POLICY paiements_escrow_select_participant ON public.paiements_escrow IS
  'Lecture limitee au soignant, a son etablissement ou a un administrateur Jolene valide.';

NOTIFY pgrst, 'reload schema';
