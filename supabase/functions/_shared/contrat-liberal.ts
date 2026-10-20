const TIME_ZONE = 'Europe/Paris';
const CLAUSE_RETROCESSION = "Si rétrocession : le Titulaire encaisse les honoraires afférents aux actes réalisés par le Remplaçant et lui rétrocède <strong>{{retrocession_pct}} %</strong> des honoraires bruts encaissés, déclarés sur la plateforme à l'issue du remplacement. ";
const CLAUSE_HORAIRE = 'Si taux horaire : la rémunération est de <strong>{{taux_horaire}} € par heure</strong>, facturée en honoraires. ';

type Ligne = Record<string, unknown>;
type RenduLiberal = { html: string; champs: [] } | { html: null; champs: string[] };

function nombrePositif(value: unknown): number | null {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+(?:\.\d+)?$/.test(value))) return null;
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function instant(value: unknown): Date | null {
  // Les dates métier sont des timestamptz : ne jamais interpréter une heure
  // sans zone selon celle du serveur qui exécute le rendu.
  if (typeof value !== 'string' || !/T.*(?:Z|[+-]\d{2}:\d{2})$/i.test(value)) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

function echapper(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/**
 * Prépare uniquement un nouvel original libéral. Les valeurs communes sont
 * déjà échappées par le générateur. Aucun défaut métier n'est remplacé par
 * une chaîne vide : le modèle et ses données doivent être complets.
 */
export function rendreContratLiberal(
  template: string, communes: Record<string, string>, mission: Ligne, etablissement: Ligne,
): RenduLiberal {
  const champs: string[] = [];
  const debut = instant(mission.debut_le);
  const fin = instant(mission.fin_le);
  if (!debut) champs.push('debut_le');
  if (!fin || (debut && fin.getTime() <= debut.getTime())) champs.push('fin_le');
  const duree = nombrePositif(mission.duree_heures);
  if (duree === null) champs.push('duree_heures');
  const mode = mission.mode_remuneration;
  if (mode !== 'TAUX_HORAIRE' && mode !== 'RETROCESSION') champs.push('mode_remuneration');
  const lieu = typeof etablissement.adresse_ville === 'string' ? etablissement.adresse_ville.trim() : '';
  if (!lieu) champs.push('lieu');
  const taux = nombrePositif(mission.taux_horaire_base);
  const retrocession = nombrePositif(mission.retrocession_pct);
  if (mode === 'TAUX_HORAIRE' && taux === null) champs.push('taux_horaire_base');
  if (mode === 'RETROCESSION' && (retrocession === null || retrocession > 100)) champs.push('retrocession_pct');
  if (champs.length) return { html: null, champs };

  // Le master contient deux clauses conditionnelles. Conserver seulement
  // celle de la mission, sans ajouter ou reformuler les autres clauses.
  let adapte = template;
  if (mode === 'TAUX_HORAIRE' && /\{\{\s*retrocession_pct\s*\}\}/.test(adapte)) {
    if (!adapte.includes(CLAUSE_RETROCESSION)) return { html: null, champs: ['clause_retrocession'] };
    adapte = adapte.replace(CLAUSE_RETROCESSION, '');
  }
  if (mode === 'RETROCESSION' && /\{\{\s*taux_horaire\s*\}\}/.test(adapte)) {
    if (!adapte.includes(CLAUSE_HORAIRE)) return { html: null, champs: ['clause_taux_horaire'] };
    adapte = adapte.replace(CLAUSE_HORAIRE, '');
  }
  const formatDate = (d: Date) => d.toLocaleDateString('fr-FR', {
    day: '2-digit', month: '2-digit', year: 'numeric', timeZone: TIME_ZONE,
  });
  const formatHeure = (d: Date) => d.toLocaleTimeString('fr-FR', {
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: TIME_ZONE,
  });
  const variables: Record<string, string> = {
    ...communes,
    debut_date: formatDate(debut!),
    debut_heure: formatHeure(debut!),
    fin_date: formatDate(fin!),
    fin_heure: formatHeure(fin!),
    duree_heures: String(duree),
    mode_remuneration: mode === 'RETROCESSION' ? 'Rétrocession d’honoraires' : 'Taux horaire',
    ...(mode === 'RETROCESSION' ? { retrocession_pct: String(retrocession) } : { taux_horaire: taux!.toFixed(2) }),
    lieu: echapper(lieu),
  };
  const html = adapte.replace(/\{\{\s*([^}]+?)\s*\}\}/g, (balise, cle: string) => {
    const nom = cle.trim();
    if (!Object.hasOwn(variables, nom) || !variables[nom]?.trim() || variables[nom] === '—') {
      champs.push(nom);
      return balise;
    }
    return variables[nom];
  });
  // Une valeur utilisateur ne doit pas pouvoir introduire un nouveau marqueur
  // qui serait pris à tort pour un original complet.
  if (/\{\{\s*[^}]+\s*\}\}/.test(html) && !champs.length) champs.push('variables_non_rendues');
  return champs.length ? { html: null, champs: [...new Set(champs)] } : { html, champs: [] };
}
