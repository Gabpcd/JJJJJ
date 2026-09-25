/** Options pures : testables avec Node, sans lancer de charge ni importer k6. */
export function creerOptionsCharge(nom, scenario, thresholds, env = {}) {
  const vusBrut = env.LOAD_TEST_VUS || '';
  const duree = env.LOAD_TEST_DURATION || '';
  if (vusBrut && !/^[1-9][0-9]{0,2}$/.test(vusBrut)) throw new Error('LOAD_TEST_VUS : entier de 1 à 999 attendu.');
  if (duree && !/^[1-9][0-9]{0,3}(s|m)$/.test(duree)) throw new Error('LOAD_TEST_DURATION : durée positive en s ou m attendue.');
  if (duree && parseInt(duree, 10) * (duree.endsWith('m') ? 60 : 1) > 900) {
    throw new Error('LOAD_TEST_DURATION : maximum 15 minutes par scénario.');
  }
  let execution = { ...scenario };
  if (scenario.stages) execution.stages = scenario.stages.map(stage => ({ ...stage }));
  const vus = vusBrut ? Number(vusBrut) : undefined;
  if (execution.executor === 'ramping-vus') {
    if (vus) execution.stages = execution.stages.map(stage => ({ ...stage, target: stage.target ? vus : 0 }));
    // Une durée explicite est la durée totale à VUs constants, sans rampe cachée.
    if (duree) execution = {
      executor: 'constant-vus', vus: vus || Math.max(...execution.stages.map(stage => stage.target)),
      duration: duree, gracefulStop: '15s',
    };
  } else if (execution.executor === 'per-vu-iterations') {
    if (vus) execution.vus = vus;
    if (duree) execution.maxDuration = duree;
  } else throw new Error(`Executor non pris en charge : ${execution.executor}`);
  return {
    scenarios: { [nom]: execution },
    thresholds: { ...thresholds, checks: ['rate==1'], iterations: ['count>0'] },
  };
}
