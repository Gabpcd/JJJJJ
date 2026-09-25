const objet = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const nombre = value => typeof value === 'number' && Number.isFinite(value);
const texte = value => typeof value === 'string' && value.length > 0;

/** Contrat de fn_missions_publiques_recherche, sans transformer un objet erreur en succès. */
export function rechercheValide(value) {
  return Array.isArray(value) && value.every(m => objet(m) && texte(m.id) && texte(m.intitule)
    && texte(m.profession_requise) && texte(m.debut_le) && texte(m.fin_le)
    && nombre(m.taux_horaire_base) && nombre(m.total_count) && m.total_count >= value.length);
}

/** Un auth.users sans profil métier ne constitue pas un dashboard soignant mesuré. */
export function dashboardValide(value) {
  return objet(value) && !value.error && objet(value.profil) && texte(value.profil.profession)
    && ['missions_ouvertes', 'mes_missions', 'documents', 'gains_6mois', 'missions_semaine_cal', 'propositions'].every(k => Array.isArray(value[k]))
    && nombre(value.heures_semaine) && nombre(value.notifs_non_lues)
    && objet(value.gains_mois) && ['net_total', 'brut_total', 'nb_missions'].every(k => nombre(value.gains_mois[k]));
}

export function exigerRecherchePeuplee(value) {
  if (!rechercheValide(value) || value.length === 0) throw new Error(
    'Préflight C : au moins une mission publique staging valide et visible est requise ; une base vide ne prouve pas cette charge.',
  );
  return value.length;
}

export function exigerDashboardMetier(value) {
  if (!dashboardValide(value)) throw new Error(
    'Préflight E : dashboard métier incomplet ou refusé ; vérifier le profil soignant du compte staging.',
  );
}

/** Scénarios historiques dangereux/non probants : aucune requête avant isolation correcte. */
export function refuserScenarioNonIsole(scenario) {
  const motif = scenario === 'D'
    ? 'fixtures de soignants éligibles, mission isolée et contrôle des candidatures réellement créées manquants'
    : 'lot facturable isolé, comparaison exacte avant/après et neutralisation des envois externes manquants';
  throw new Error(`Scénario ${scenario} indisponible : ${motif}. Aucune mutation exécutée ; aucun succès de charge ne peut être annoncé.`);
}
