/**
 * Scénario D suspendu : l’ancien script pouvait annoncer un succès sans acte métier.
 * Voir docs/tests-charge.md. Aucun signup, candidature, cron ou email n’est déclenché.
 */
import '../helpers/auth.js'; // Conserver la garde staging, sans requête réseau à l’import.
import { creerOptionsCharge } from '../helpers/options.js';
import { refuserScenarioNonIsole } from '../helpers/contrats.js';

export const options = creerOptionsCharge('candidatures_simultanees', {
  executor: 'per-vu-iterations', vus: 50, iterations: 1, maxDuration: '60s',
}, {}, __ENV);

export function setup() { refuserScenarioNonIsole('D'); }
// Échec explicite même si un appelant désactive setup avec --no-setup.
export default function () { refuserScenarioNonIsole('D'); }

export function handleSummary(data) {
  return {
    stdout: 'Scénario D non validé : fixtures et isolation insuffisantes. Aucune mutation exécutée.\n',
    'tests/load/results/04-candidatures-simultanees.json': JSON.stringify({ ...data, preuve_metier: false, scenario_indisponible: 'D' }, null, 2),
  };
}
