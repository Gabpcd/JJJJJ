/**
 * Source unique des types de contrat salariés côté web.
 *
 * Couvre les valeurs de `contrats_mission.type_contrat` (CDD, CDDU, VACATION ;
 * REMPLACEMENT_LIBERAL est libéral) et les codes historiques de profil
 * (`soignants.type_contrat` / `types_contrat_acceptes` : CDD, VACATION, SALARIE).
 *
 * CDDU et VACATION sont des contrats salariés, au même titre que CDD et SALARIE :
 * - DPAE obligatoire pour tout salarié : C. trav. art. L.1221-10 et R.1221-1 s. ;
 * - le CDD d'usage est un CDD : C. trav. art. L.1242-2 3° et D.1242-1.
 * Décision prise par Claude sur délégation explicite de Gabrielle du 08/11/2026.
 *
 * Portée : le web applique cette règle via ce module. Côté serveur, seules
 * `fn_annuler_mission_etab` et `fn_declarer_empechement_imperieux` la suivaient
 * (`type_contrat IN ('CDD','CDDU','VACATION')`) ; les RPC DPAE appelées par le web
 * (`fn_generer_donnees_dpae`, `fn_enregistrer_numero_dpae`) ne filtrent pas le type.
 * `fn_mes_dpae`, `fn_rappel_dpae_quotidien`, `fn_pointer_arrivee`,
 * `fn_annuler_candidature_soignant` et `dec_email_contrat_signe_complet` excluaient
 * CDDU et VACATION : leur alignement vient de la PR de migration séparée
 * (branche fix/dpae-serveur-cddu-vacation).
 *
 * Ne jamais réécrire cette liste localement : tout lecteur passe par
 * `estContratSalarie` (garde : `src/lib/typesContrat.test.ts`).
 */
export const TYPES_CONTRAT_SALARIES = Object.freeze(['CDD', 'SALARIE', 'CDDU', 'VACATION'] as const);

export type TypeContratSalarie = typeof TYPES_CONTRAT_SALARIES[number];

export function estContratSalarie(type: string | null | undefined): type is TypeContratSalarie {
  return !!type && (TYPES_CONTRAT_SALARIES as readonly string[]).includes(type);
}
