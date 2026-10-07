import { ORIGINE_UI } from './dashboard-ui-contract.mjs';
import { STAGING_URL } from './prepare-load-fixtures.mjs';

const phases = new Set(['backend','preview','browser','page','login','dashboard','reload','coupure','reprise','cleanup']);
const methodes = new Set(['GET','HEAD','POST','OPTIONS','PATCH','PUT','DELETE']);
const chemins = new Map([
  ['/auth/v1/token','auth-token'], ['/auth/v1/user','auth-user'],
  ...['fn_get_my_role','fn_compte_auth_actif','fn_dashboard_soignant_complet','fn_messages_non_lus',
    'fn_mon_profil_soignant_complet','fn_param_bool','fn_est_bloque','fn_audit_connexion',
    'fn_maj_activite_soignant','fn_update_presence'].map(n => [`/rest/v1/rpc/${n}`,n]),
]);

/** Projection fermée : jamais d'URL, query, corps, identité ou exception sérialisés. */
export function creerDiagnosticUI() {
  let phase = 'backend', slot = null, erreursJavascript = 0, omises = 0;
  const progression = [], reseau = new Map();
  return {
    phase(nouvelle, nouveauSlot = slot) {
      if (!phases.has(nouvelle) || ![null,0,1].includes(nouveauSlot)) throw new Error('Phase diagnostic invalide.');
      phase = nouvelle; slot = nouveauSlot;
      if (progression.length < 32) progression.push({ phase, slot });
    },
    javascript() { erreursJavascript++; },
    requete({ url, method, statut }) {
      let origine = 'invalide', chemin = 'invalide';
      try {
        const u = new URL(url);
        origine = u.origin === ORIGINE_UI ? 'preview' : u.origin === STAGING_URL ? 'staging' : 'externe';
        chemin = origine === 'preview' ? (u.pathname.startsWith('/assets/') ? 'asset-local' : 'page-locale')
          : origine === 'staging' ? (chemins.get(u.pathname) || (u.pathname.startsWith('/rest/v1/rpc/') ? 'rpc-autre'
            : u.pathname.startsWith('/rest/v1/') ? 'table-rest' : u.pathname.startsWith('/auth/') ? 'auth-autre'
            : u.pathname.startsWith('/functions/') ? 'edge' : u.pathname.startsWith('/storage/') ? 'storage' : 'autre'))
          : 'externe';
      } catch { /* URL malformée : conserver uniquement les catégories fermées. */ }
      const observation = { phase, slot, origine, chemin, methode: methodes.has(method) ? method : 'AUTRE',
        statut: ['refusee','corps-invalide','transport'].includes(statut) ? statut
          : Number.isInteger(statut) && statut >= 100 && statut <= 599 ? statut : 'inconnu' };
      const cle = JSON.stringify(observation);
      if (!reseau.has(cle) && reseau.size >= 64) { omises++; return; }
      reseau.set(cle, { ...observation, nombre: (reseau.get(cle)?.nombre || 0) + 1 });
    },
    resultat() { return { phase, slot, progression: structuredClone(progression), reseau: [...reseau.values()].map(r => ({ ...r })),
      erreurs_javascript: erreursJavascript, observations_omises: omises }; },
  };
}

/** Le cleanup et la preuve d'une connexion réussie restent deux constats séparés. */
export function bilanCleanupUI(lignes) {
  const complet = Array.isArray(lignes) && lignes.length === 2 && lignes.every((r,i) => r?.slot === i);
  const compte = cle => complet && lignes.every(r => Number.isInteger(r[cle]) && r[cle] >= 0)
    ? lignes.reduce((n,r) => n + r[cle],0) : null;
  return {
    donnees_absentes: complet && lignes.every(r => ['auth','profils','preferences','sessions','identites','notifications','presences'].every(k => r[k] === 0)),
    audits_connexion_attendus: 2, audits_observes: compte('audits'), audits_connexion_observes: compte('audits_connexion'),
  };
}
