/** Données déclarées par l'employeur, figées dans l'original avant signature.
 * Mentions : L1242-12 ; essai facultatif : L1242-10. Aucun plafond ni taux inventé.
 * Le texte employeur permet les autres cadres sans leur appliquer le modèle privé.
 */
export type DonneesCdd = {
  cadre: 'PRIVE_TERME_PRECIS' | 'TEXTE_EMPLOYEUR';
  confirme: true;
  [champ: string]: string | boolean;
};

const COMMUNS = ['representant_nom', 'representant_qualite'];
const PRIVE = ['motif_type', 'motif_precis', 'poste', 'qualification', 'lieu_travail', 'risques',
  'convention_collective', 'renouvellement', 'essai', 'remuneration_accessoires',
  'temps_partiel', 'retraite_nom', 'retraite_adresse', 'prevoyance'];
const CHOIX: Record<string, readonly string[]> = {
  motif_type: ['REMPLACEMENT', 'ACCROISSEMENT', 'AUTRE'],
  risques: ['OUI', 'NON'], essai: ['AUCUN', 'CONVENU'],
  temps_partiel: ['OUI', 'NON'], prevoyance: ['OUI', 'NON'],
};

export function validerDonneesCdd(input: unknown): { donnees: DonneesCdd | null; champs: string[] } {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { donnees: null, champs: ['donnees_cdd'] };
  const source = input as Record<string, unknown>;
  const champs: string[] = [];
  const d: Record<string, string | boolean> = {};
  if (typeof source.cadre !== 'string' || !['PRIVE_TERME_PRECIS', 'TEXTE_EMPLOYEUR'].includes(source.cadre)) champs.push('cadre');
  if (source.confirme !== true) champs.push('confirmation_employeur');
  const requis = [...COMMUNS];
  if (source.cadre === 'PRIVE_TERME_PRECIS') {
    requis.push(...PRIVE);
    if (source.motif_type === 'REMPLACEMENT') requis.push('remplace_nom', 'remplace_qualification');
    if (source.risques === 'OUI') requis.push('risques_precisions');
    if (source.essai === 'CONVENU') requis.push('essai_duree', 'essai_conditions');
    if (source.temps_partiel === 'OUI') requis.push('temps_partiel_conditions');
    if (source.prevoyance === 'OUI') requis.push('prevoyance_nom', 'prevoyance_adresse');
  } else if (source.cadre === 'TEXTE_EMPLOYEUR') requis.push('cadre_declare', 'texte_employeur');
  for (const champ of requis) {
    const value = source[champ];
    const max = champ === 'texte_employeur' ? 60000 : 4000;
    if (typeof value !== 'string' || !value.trim() || value.length > max || /\u0000|\{\{/.test(value)) {
      champs.push(champ); continue;
    }
    d[champ] = value.trim();
    if (CHOIX[champ] && !CHOIX[champ].includes(value)) champs.push(champ);
  }
  if (champs.length) return { donnees: null, champs };
  return { donnees: { ...d, cadre: source.cadre as DonneesCdd['cadre'], confirme: true }, champs: [] };
}

function texte(value: unknown): string {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
    // Le filtre SQL historique retire certains schémas même dans le texte.
    // L'entité préserve le texte visible et les octets gelés avant le hash.
    .replace(/:/g, '&#58;')
    .replace(/\r?\n/g, '<br/>');
}

/** Les valeurs mission/profil sont déjà échappées par le générateur historique. */
export function rendreCddEmployeur(v: Record<string, string>, d: DonneesCdd, auteur: string, prepareLe: string): string {
  v = Object.fromEntries(Object.entries(v).map(([cle, valeur]) => [cle, valeur.replace(/:/g, '&#58;')]));
  const ligne = (label: string, value: unknown) => `<p><strong>${label} :</strong> ${texte(value)}</p>`;
  const trace = `<section data-jolene-cdd="employeur-v1" data-cadre="${d.cadre}" data-auteur="${texte(auteur)}" data-prepare-le="${texte(prepareLe)}">`;
  const representant = ligne('Représentant de l’employeur', `${d.representant_nom} — ${d.representant_qualite}`);
  if (d.cadre === 'TEXTE_EMPLOYEUR') {
    return `${trace}<h1>Contrat ${v.numero_contrat}</h1>${representant}
      ${ligne('Cadre déclaré par l’employeur', d.cadre_declare)}
      <p>Mission : ${v.intitule_mission}, du ${v.debut_le} au ${v.fin_le}.</p>
      <p>Établissement : ${v.etablissement_nom}, SIRET ${v.etablissement_siret}, ${v.etablissement_adresse}.
      Soignant : ${v.soignant_prenom} ${v.soignant_nom}, ${v.soignant_adresse}.</p>
      <p>Texte intégral fourni et confirmé par l’employeur. Jolene n’y ajoute pas les clauses du modèle CDD privé.</p>
      <article style="white-space:pre-wrap;overflow-wrap:anywhere">${texte(d.texte_employeur)}</article></section>`;
  }
  const motif = d.motif_type === 'REMPLACEMENT'
    ? `${ligne('Personne remplacée', d.remplace_nom)}${ligne('Qualification de la personne remplacée', d.remplace_qualification)}` : '';
  return `${trace}<h1>Contrat à durée déterminée — ${v.numero_contrat}</h1>
    <p>Contrat de droit privé à terme précis préparé à partir des informations confirmées par l’employeur.
    Jolene intervient comme plateforme technique ; l’établissement est l’employeur.</p>
    <h2>Parties</h2><p><strong>${v.etablissement_nom}</strong>, SIRET ${v.etablissement_siret}, ${v.etablissement_adresse}.</p>
    ${representant}<p><strong>${v.soignant_prenom} ${v.soignant_nom}</strong>, né(e) le ${v.soignant_date_naissance}, ${v.soignant_adresse}.</p>
    <h2>Motif et poste</h2>${ligne('Cas de recours déclaré', d.motif_type === 'REMPLACEMENT' ? 'Remplacement'
      : d.motif_type === 'ACCROISSEMENT' ? 'Accroissement temporaire d’activité' : 'Autre cas précisé par l’employeur')}
    ${ligne('Motif précis', d.motif_precis)}${motif}
    ${ligne('Poste', d.poste)}${ligne('Qualification', d.qualification)}${ligne('Lieu de travail', d.lieu_travail)}
    ${ligne('Poste présentant des risques particuliers', d.risques === 'OUI' ? d.risques_precisions : 'Non, selon la déclaration de l’employeur')}
    <h2>Terme et temps de travail</h2><p>Du ${v.debut_le} au ${v.fin_le}. Durée prévisionnelle : ${v.duree_heures} heures.
    Mission : ${v.intitule_mission}.</p>${ligne('Renouvellement éventuel', d.renouvellement)}
    ${ligne('Temps partiel', d.temps_partiel === 'OUI' ? d.temps_partiel_conditions : 'Non, selon la déclaration de l’employeur')}
    <h2>Convention collective</h2>${ligne('Convention collective applicable ou absence confirmée', d.convention_collective)}
    <h2>Période d’essai</h2>${d.essai === 'AUCUN' ? '<p>Aucune période d’essai n’est convenue.</p>'
      : `${ligne('Durée d’essai expressément convenue', d.essai_duree)}${ligne('Conditions et référence applicable confirmées par l’employeur', d.essai_conditions)}`}
    <h2>Rémunération</h2><p>Taux horaire brut enregistré pour la mission : ${v.taux_horaire} €.</p>
    ${ligne('Salaire, primes, indemnités et autres accessoires', d.remuneration_accessoires)}
    <h2>Retraite et prévoyance</h2>${ligne('Retraite complémentaire', `${d.retraite_nom} — ${d.retraite_adresse}`)}
    ${ligne('Prévoyance', d.prevoyance === 'OUI' ? `${d.prevoyance_nom} — ${d.prevoyance_adresse}` : 'Déclarée non applicable par l’employeur')}
    </section>`;
}
