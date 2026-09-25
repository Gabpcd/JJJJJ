const nombre = (valeur, decimales = 0) => typeof valeur === 'number' && Number.isFinite(valeur) ? valeur.toFixed(decimales) : 'non mesuré';
export function resumeCharge(data, label, tag, options) {
  const metrics = data.metrics || {};
  const duree = metrics[`http_req_duration{name:${tag}}`]?.values;
  const echecs = metrics[`http_req_failed{name:${tag}}`]?.values?.rate;
  const controles = metrics.checks?.values?.rate;
  return [
    '', `=== ${label} — staging uniquement ===`,
    `Configuration effective : ${JSON.stringify(options.scenarios)}`,
    `Itérations : ${nombre(metrics.iterations?.values?.count)}`,
    `Contrôles fonctionnels réussis (%) : ${nombre(controles === undefined ? undefined : controles * 100, 2)}`,
    `Échecs HTTP mesurés (%) : ${nombre(echecs === undefined ? undefined : echecs * 100, 2)}`,
    `p50 / p95 / p99 (ms) : ${nombre(duree?.['p(50)'])} / ${nombre(duree?.['p(95)'])} / ${nombre(duree?.['p(99)'])}`,
    'Un préflight incomplet ou un seuil échoué invalide la campagne. Aucune extrapolation automatique en production.', '',
  ].join('\n');
}
