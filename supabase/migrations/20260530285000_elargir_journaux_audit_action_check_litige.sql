-- La contrainte CHECK journaux_audit_action_check rejetait 16 actions
-- pourtant écrites par des fonctions en place → tout le cycle de vie des
-- litiges (ouverture/réponse/résolution/clôture/escalade), la confirmation
-- de remboursement d'avoir, la modification d'établissement/TVA, la
-- suppression RGPD et l'alerte fraude pointage échouaient (23514).
-- On élargit la contrainte en y ajoutant les valeurs manquantes, sans rien
-- retirer de l'existant (reconstruction dynamique à partir de la def courante).
DO $mig$
DECLARE
  v_def text;
  v_expr text;
  v_additions text;
  v_new_expr text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
    FROM pg_constraint WHERE conname = 'journaux_audit_action_check';

  -- retire le préfixe "CHECK " → expression booléenne pure
  v_expr := substring(v_def from 7);

  v_additions := (
    SELECT string_agg(format(', %L::text', a), '')
    FROM unnest(ARRAY[
      'AVOIR_REMBOURSEMENT_CONFIRME',
      'ETABLISSEMENT_MODIFICATION',
      'LITIGE_ACCORD_CLOTURE',
      'LITIGE_AUTO_CREATION',
      'LITIGE_CLOTURE_AMIABLE',
      'LITIGE_CREATION',
      'LITIGE_ESCALADE_AUTO',
      'LITIGE_FORCE_CREATION',
      'LITIGE_OUVERTURE',
      'LITIGE_OUVERTURE_LEGACY',
      'LITIGE_RECATEGORISATION_LEGACY',
      'LITIGE_REPONSE',
      'LITIGE_RESOLUTION',
      'PRESENCE_ALERTE_FRAUDE',
      'RGPD_SUPPRESSION_DONNEES',
      'TVA_MODIFICATION'
    ]) AS a
  );

  -- injecte les nouvelles valeurs juste avant la fermeture du ARRAY[...]
  v_new_expr := regexp_replace(v_expr, '\]\)\)\)\s*$', v_additions || '])))');

  EXECUTE 'ALTER TABLE public.journaux_audit DROP CONSTRAINT journaux_audit_action_check';
  EXECUTE 'ALTER TABLE public.journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK ' || v_new_expr;
END $mig$;
