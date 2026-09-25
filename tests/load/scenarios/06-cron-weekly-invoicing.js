/**
 * Scénario F suspendu : l’ancien script pouvait annoncer un succès sans acte métier.
 * Voir docs/tests-charge.md. Aucun signup, candidature, cron ou email n’est déclenché.
 */
import '../helpers/auth.js'; // Conserver la garde staging, sans requête réseau à l’import.
import { creerOptionsCharge } from '../helpers/options.js';
import { refuserScenarioNonIsole } from '../helpers/contrats.js';

export const options = creerOptionsCharge('cron_weekly_invoicing', {
  executor: 'per-vu-iterations', vus: 1, iterations: 1, maxDuration: '15m',
}, {}, __ENV);

export function setup() { refuserScenarioNonIsole('F'); }
// Échec explicite même si un appelant désactive setup avec --no-setup.
export default function () { refuserScenarioNonIsole('F'); }

export function handleSummary(data) {
  return {
    stdout: 'Scénario F non validé : fixtures et isolation insuffisantes. Aucune mutation exécutée.\n',
    'tests/load/results/06-cron-weekly-invoicing.json': JSON.stringify({ ...data, preuve_metier: false, scenario_indisponible: 'F' }, null, 2),
  };
}
