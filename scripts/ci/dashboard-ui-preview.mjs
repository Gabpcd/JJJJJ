import { spawn } from 'node:child_process';
import { setTimeout as attendre } from 'node:timers/promises';
import { ORIGINE_UI } from './dashboard-ui-contract.mjs';

const codesReseau = new Set(['ECONNREFUSED','EADDRNOTAVAIL','EADDRINUSE','ENOTFOUND','EAI_AGAIN','ETIMEDOUT','ECONNRESET']);
function codeErreur(error) {
  if (codesReseau.has(error?.code)) return error.code;
  if (codesReseau.has(error?.cause?.code)) return error.cause.code;
  const causes = error?.cause?.errors;
  if (Array.isArray(causes)) for (const cause of causes) if (codesReseau.has(cause?.code)) return cause.code;
  return error?.name === 'TimeoutError' ? 'DELAI' : 'AUTRE';
}

/** Même origine numérique pour listen, fetch et WebKit : aucun choix DNS localhost. */
export async function demarrerPreview({ env = process.env, observer = () => {},
  lancer = spawn, sonder = fetch, pause = attendre } = {}) {
  const origine = new URL(ORIGINE_UI);
  const etat = { tentatives: 0, statut_http: null, code_reseau: null, code_sortie: null, erreur_lancement: null };
  const publier = () => observer({ ...etat });
  const preview = lancer(process.execPath, ['node_modules/vite/bin/vite.js','preview',
    '--host',origine.hostname,'--port',origine.port,'--strictPort'],
  { stdio: 'ignore', env: { PATH: env.PATH, HOME: env.HOME } });
  preview.on('error', error => { etat.erreur_lancement = codeErreur(error); publier(); });
  try {
    for (let i = 0; i < 60; i++) {
      etat.tentatives = i + 1;
      etat.code_sortie = Number.isInteger(preview.exitCode) ? preview.exitCode : null;
      if (etat.erreur_lancement || preview.exitCode !== null) { publier(); throw new Error('Preview UI indisponible.'); }
      try {
        const response = await sonder(ORIGINE_UI, { signal: AbortSignal.timeout(500), redirect: 'error' });
        etat.statut_http = Number.isInteger(response.status) && response.status >= 100 && response.status <= 599 ? response.status : null;
        etat.code_reseau = null; publier();
        if (response.ok && preview.exitCode === null && !etat.erreur_lancement) return preview;
      } catch (error) { etat.code_reseau = codeErreur(error); publier(); }
      if (i === 59) throw new Error('Preview UI non démarrée.');
      await pause(200);
    }
  } catch (error) { preview.kill('SIGTERM'); throw error; }
}
