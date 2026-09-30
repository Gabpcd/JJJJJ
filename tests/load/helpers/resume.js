const nombre = (valeur, decimales = 0) => typeof valeur === 'number' && Number.isFinite(valeur) ? valeur.toFixed(decimales) : 'non mesuré';

// k6 ajoute les valeurs retournées par setup(), dont le JWT du scénario E.
// Un rapport ne conserve que les agrégats : jamais la session ni les futurs
// champs racine ajoutés par le moteur (ne pas sérialiser data par propagation).
export function donneesRapportCharge(data) {
  return {
    metrics: data.metrics,
    root_group: data.root_group,
    state: data.state,
    options: {
      summaryTrendStats: data.options?.summaryTrendStats,
      summaryTimeUnit: data.options?.summaryTimeUnit,
      noColor: data.options?.noColor,
    },
  };
}

// Les options consolidées viennent de k6/execution, pas de l'objet exporté
// réinjecté par k6. Ne jamais sérialiser env/tags/options navigateur ici.
export function scenariosPourRapport(options) {
  const scenarios = Object.entries(options?.scenarios || {}).map(([nom, scenario]) => {
    const sortie = {};
    for (const cle of ['executor','vus','startVUs','duration','gracefulStop','gracefulRampDown','iterations','maxDuration']) {
      if (typeof scenario?.[cle] === 'string' || typeof scenario?.[cle] === 'number') sortie[cle] = scenario[cle];
    }
    if (Array.isArray(scenario?.stages)) sortie.stages = scenario.stages.map(({ duration, target }) => ({ duration, target }));
    return [nom, sortie];
  });
  return scenarios.length ? Object.fromEntries(scenarios) : null;
}

export function resumeCharge(data, label, tag, options) {
  const metrics = data.metrics || {};
  const scenarios = scenariosPourRapport(options);
  const duree = metrics[`http_req_duration{name:${tag}}`]?.values;
  const echecs = metrics[`http_req_failed{name:${tag}}`]?.values?.rate;
  const controles = metrics.checks?.values?.rate;
  return [
    '', `=== ${label} — staging uniquement ===`,
    `Configuration effective : ${scenarios ? JSON.stringify(scenarios) : 'non disponible'}`,
    `Itérations : ${nombre(metrics.iterations?.values?.count)}`,
    `Contrôles fonctionnels réussis (%) : ${nombre(controles === undefined ? undefined : controles * 100, 2)}`,
    `Échecs HTTP mesurés (%) : ${nombre(echecs === undefined ? undefined : echecs * 100, 2)}`,
    `p50 / p95 / p99 (ms) : ${nombre(duree?.['p(50)'] ?? duree?.med)} / ${nombre(duree?.['p(95)'])} / ${nombre(duree?.['p(99)'])}`,
    'Un préflight incomplet ou un seuil échoué invalide la campagne. Aucune extrapolation automatique en production.', '',
  ].join('\n');
}
