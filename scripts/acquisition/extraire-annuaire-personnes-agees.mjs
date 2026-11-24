#!/usr/bin/env node
// Adresses de contact publiées par l'annuaire officiel des établissements pour personnes âgées
// (pour-les-personnes-agees.gouv.fr, portail de la CNSA), d'après le jeu ouvert de data.gouv.fr.
//
//   Jeu     : « Etablissements EHPAD, ESLD, résidences autonomie, accueils de jour »
//             https://www.data.gouv.fr/datasets/etablissements-ehpad-esld-residences-autonomie-accueils-de-jour
//             identifiant 5ca48257634f414eb3f14803, Licence Ouverte 2.0
//   Fichier : base-etablissements.csv, publié le 11/11/2020 (photographie de novembre 2020)
//   Site d'origine : mentions légales lues le 24/11/2026, « Droits de reproduction » : contenus
//             « librement et gratuitement réutilisables », à l'exception notamment de ceux
//             « contenant des données personnelles » — d'où le tri ci-dessous.
//
// Usage :
//   node scripts/acquisition/extraire-annuaire-personnes-agees.mjs <base-etablissements.csv>
//        [--json sortie.json] [--sql sortie.sql]
// Le fichier se télécharge à la main depuis la page du jeu : le script ne fait aucun accès réseau.
//
// Ce que le script retient, et rien d'autre :
//   * un FINESS d'établissement à neuf chiffres ;
//   * une adresse bien formée, hors messageries de santé fermées (MSSanté, Apicrypt) ;
//   * une adresse dont TOUT l'identifiant (avant « @ ») s'explique sans nommer une personne : mots de
//     fonction ou de type d'établissement (contact, direction, accueil, ehpad…), mots du nom de
//     l'établissement ou de sa commune. Il suffit d'un mot inexpliqué, ou d'une initiale isolée,
//     pour écarter l'adresse : « prenom.nom@ », « p.nom@ » et « pnom@ » ne passent pas, même quand
//     le nom de famille est aussi un mot de l'établissement.
//   * Le champ « gestionnaire » n'explique rien : c'est parfois une personne physique (revue de
//     #1180 : une adresse « nom.prenom@ » passait parce que le gestionnaire portait ce nom).
//   * Un prénom courant, même présent dans le nom de l'établissement (« Résidence Jean Moulin »),
//     ne passe qu'avec un mot de fonction : « jean.moulin@ » est écartée, « ehpad.jeanmoulin@ » non.
//   * Un sigle de deux lettres (rh, ch, mr) à côté d'un mot du nom de l'établissement se lit aussi
//     comme des initiales ou « Mr » : « mr.dupont@ » et « ch.dupont@ » sont écartées. À côté du nom
//     de la commune (« mr.sartilly@ »), le sigle passe : une commune n'est pas une personne.
//   * Un domaine à une faute de frappe d'un domaine courant (« orane.fr », « gmail.com.fr ») :
//     l'adresse n'atteindrait personne, ou quelqu'un d'autre.
// La règle reste une heuristique : une adresse au seul nom de l'établissement est retenue même si ce
// nom est un patronyme (« Résidence Dupont » → « dupont@ »). Chaque brouillon est relu avant envoi.
// Pourquoi : la prospection par courrier électronique d'une personne physique exige son
// consentement préalable (CPCE, art. L34-5) ; une adresse générique concerne la personne morale
// (CNIL, « La prospection commerciale par courrier électronique », onglet professionnels).
// Les adresses datent de 2020 : elles ne sont pas « vérifiées ». Chaque ligne garde sa source et
// la date de mise à jour publiée.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const SOURCE = {
  code: 'ANNUAIRE_PERSONNES_AGEES_DATA_GOUV',
  url: 'https://www.data.gouv.fr/datasets/etablissements-ehpad-esld-residences-autonomie-accueils-de-jour',
  fichier: 'https://static.data.gouv.fr/resources/etablissements-ehpad-esld-residences-autonomie-accueils-de-jour/20201111-100438/base-etablissements.csv',
  licence: 'Licence Ouverte 2.0',
  publie_le: '2020-11-11',
  releve_le: '2026-11-24',
  sha256: '6d57e557a44365ea2b41ea52f794e9a33df26cf1d21c0747dc3e67a3609b5670',
};

// Caractères simples seulement : une adresse accentuée du fichier (« château.de… ») est une faute
// de saisie, et le bloc de données de la migration reste sans guillemet ni point-virgule.
const BIEN_FORMEE = /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/;
// Même règle que private.fn_growth_email_mssante (20261117060000).
const FERMEE = /[@.](mssante\.fr|apicrypt\.org)$/;

/** Mots de fonction, de service ou de type d'établissement : ils ne nomment personne. */
export const FONCTIONS = ['contact', 'accueil', 'direction', 'secretariat', 'administration', 'administratif',
  'admin', 'info', 'infos', 'information', 'informations', 'recrutement', 'rh', 'standard', 'reception',
  'comptabilite', 'compta', 'gestion', 'coordination', 'animation', 'admission', 'admissions', 'hebergement',
  'ehpad', 'ehpa', 'usld', 'residence', 'residences', 'resid', 'retraite', 'foyer', 'logement', 'logements',
  'marpa', 'mapa', 'mapad', 'mdr', 'mr', 'ccas', 'cias', 'mairie', 'hopital', 'hopitaux', 'hospitalier', 'ch',
  'association', 'asso', 'etablissement', 'siege', 'autonomie', 'seniors', 'geriatrie', 'gerontologie', 'ssiad',
  'accueildejour'];
/** Mots de liaison : ils n'expliquent rien à eux seuls, mais ne nomment personne. */
const LIAISONS = ['le', 'la', 'les', 'de', 'du', 'des', 'et', 'en', 'au', 'aux', 'sur', 'sous'];
/** Suites de deux liaisons qui se lisent en français (« résidence de la forêt »). « lesaux » n'en est pas une. */
const LIAISONS_DOUBLES = ['dela', 'etde', 'etdu', 'etdes', 'etla', 'etle', 'etles', 'surle', 'surla', 'surles',
  'sousle', 'sousla', 'sousles', 'enla', 'dele', 'deles'];
const SAINTS = ['saint', 'sainte', 'st', 'ste'];
/** Un intitulé qui présente une personne : ses mots n'expliquent aucune adresse. */
const CIVILITES = ['monsieur', 'madame', 'mademoiselle', 'mme', 'mlle'];
/**
 * Prénoms courants (liste indicative, sans accent). Un prénom qui figure dans le nom de
 * l'établissement ou de la commune ne suffit pas à expliquer une adresse : il faut un mot de fonction.
 */
export const PRENOMS = new Set(`adele adrien agathe agnes aime aimee alain albert alexandre alexis alfred alice aline
  alphonse amelie anais andre andree angele anne annie antoine antoinette armand arnaud arthur auguste augustin
  aurelie baptiste barbara beatrice benjamin benoit bernadette bernard berthe bertrand blanche brigitte bruno camille
  carole caroline catherine cecile cedric celine chantal charles charlotte christian christiane christine christophe
  claire clara claude claudine clement clementine colette constance corinne cyril damien daniel danielle david denis
  denise didier dominique edith edmond edouard eliane elisabeth elise elodie emile emilie emma emmanuel eric ernest
  estelle etienne eugene eugenie evelyne fabien fabrice felix fernand fernande florence francis francois francoise
  franck frederic gabriel gabrielle gaston genevieve georges georgette gerald gerard germaine ghislaine gilbert
  gilles ginette gisele guillaume gustave guy helene henri henriette herve hubert hugues huguette irene isabelle
  jacqueline jacques jean jeanne jeannine jerome joel joelle joseph josephine josette josiane julie julien juliette
  jules laure laurence laurent leon leonie liliane lionel louis louise luc lucas lucie lucien lucienne ludovic
  madeleine marc marcel marcelle marguerite maria marie marine marion marius marthe martin martine mathieu mathilde
  matthieu maurice maxime michel michele micheline michelle mireille monique muriel nadine nathalie nicolas nicole
  noel noelle odette odile olivier pascal pascale patrice patricia patrick paul paule paulette pauline philippe
  pierre pierrette rachel raoul raphael raymond raymonde rene renee richard robert roger roland romain rose roseline
  sabine samuel sandrine sarah sebastien serge simon simone solange sophie stephane stephanie suzanne sylvain sylvie
  therese thierry thomas valentin valerie veronique victor victoire victorine vincent virginie vivien xavier yann
  yannick yves yvette yvonne`.split(/\s+/).filter(Boolean));

const sansAccents = t => String(t ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const mots = texte => sansAccents(texte).split(/[^a-z0-9]+/).filter(Boolean);

/**
 * Classe d'une adresse : 'FONCTION' (un mot de fonction ou de type d'établissement),
 * 'STRUCTURE' (le nom de l'établissement ou de sa commune), ou la raison pour laquelle elle
 * n'est pas retenue. Le gestionnaire n'est pas lu : ce peut être une personne physique.
 */
export function classerAdresse(adresse, { nom, ville } = {}) {
  const email = String(adresse ?? '').trim().toLowerCase();
  if (!email) return 'ABSENTE';
  if (!BIEN_FORMEE.test(email)) return 'MAL_FORMEE';
  if (FERMEE.test(email)) return 'MESSAGERIE_FERMEE';
  const identifiant = sansAccents(email.slice(0, email.lastIndexOf('@')));
  const morceaux = identifiant.split(/[^a-z0-9]+/).filter(Boolean);
  // Une initiale isolée (« p.martin », « m.joseph ») : on ne sait pas dire si elle abrège un
  // prénom. L'adresse est écartée, quitte à perdre « m.r.village » (maison de retraite).
  if (morceaux.some(m => m.replace(/[0-9]/g, '').length === 1)) return 'A_VERIFIER';

  // Un intitulé qui présente une personne (« Accueil de jour Madame X ») n'explique rien.
  const nomLu = mots(nom).some(m => CIVILITES.includes(m)) ? '' : nom;
  // Un prénom de saint (« Saint-Martin », « Sainte-Marie »), dans le nom ou dans la commune, ne vaut
  // que si l'identifiant dit aussi « saint » ou porte un mot de fonction : « martin@ » seul peut
  // être une personne.
  const prenomsDeSaints = new Set([nomLu, ville].flatMap(t => { const ms = mots(t); return ms.filter((m, i) => i > 0 && SAINTS.includes(ms[i - 1])); }));
  const ditSaint = SAINTS.some(s => s.length > 2 ? identifiant.includes(s) : morceaux.some(m => m.startsWith(s)));
  const textes = [nomLu, ville].map(sansAccents);
  const elisions = t => [...t.matchAll(/(?:^|[^a-z0-9])([ld])['’`]\s*([a-z0-9]{3,})/g)].map(e => e[1] + e[2]);
  const motsDeLaCommune = new Set([...mots(ville), ...elisions(sansAccents(ville))]);
  const propres = new Set(textes.flatMap(t => t.split(/[^a-z0-9]+/))
    .filter(m => m.length >= 3 && !/^[0-9]+$/.test(m) && !LIAISONS.includes(m) && !SAINTS.includes(m)));
  // Élisions écrites dans le nom (« L'Arbois », « d'Automne ») : « larbois », « dautomne ».
  for (const t of textes) for (const e of elisions(t)) propres.add(e);
  let aFonction = false; let aSigle = false; let aCommune = false; let aNom = false; let aPrenomDeSaint = false; let aPrenom = false;
  const vocabulaire = [...new Set([...FONCTIONS, ...propres])].sort((a, b) => b.length - a.length);

  for (const morceau of morceaux) {
    let reste = morceau.replace(/[0-9]+/g, '');
    if (reste === '') continue;
    let reconnu = false;
    for (const mot of vocabulaire) {
      // Un sigle de deux lettres (rh, ch, mr) ne compte que s'il reste seul, plus bas.
      if (mot.length < 3 || !reste.includes(mot)) continue;
      reste = reste.split(mot).join(' ');
      reconnu = true;
      if (FONCTIONS.includes(mot)) aFonction = true;
      else if (prenomsDeSaints.has(mot)) aPrenomDeSaint = true;
      else if (PRENOMS.has(mot)) aPrenom = true;
      else if (motsDeLaCommune.has(mot)) aCommune = true;
      else aNom = true;
    }
    // Entre les mots reconnus, il ne peut rester qu'une liaison (ou deux qui se lisent : « de la »),
    // « saint » ou un sigle de fonction entier. Une lettre seule (« pmartin ») écarte l'adresse, et
    // un morceau fait seulement de liaisons collées (« lesaux », « dela ») aussi : c'est un nom.
    for (const bout of reste.split(' ').filter(Boolean)) {
      if (LIAISONS.includes(bout) || SAINTS.includes(bout)) continue;
      if (FONCTIONS.includes(bout)) { aSigle = true; continue; }
      if (!reconnu) return 'A_VERIFIER';
      let b = bout;
      for (const petit of [...SAINTS].sort((x, y) => y.length - x.length)) b = b.split(petit).join(' ');
      for (const fragment of b.split(' ').filter(Boolean)) {
        if (LIAISONS.includes(fragment) || LIAISONS_DOUBLES.includes(fragment)) continue;
        if (!FONCTIONS.includes(fragment)) return 'A_VERIFIER';
        aSigle = true;
      }
    }
  }
  // Un prénom, de saint ou non, ne passe qu'avec un mot de fonction (ou « saint » pour un saint).
  if (((aPrenomDeSaint && !ditSaint) || aPrenom) && !aFonction) return 'A_VERIFIER';
  // « mr.dupont », « ch.dupont » : sigle et mot du nom de l'établissement, sans mot de fonction,
  // lisible comme une personne. Avec le seul nom de la commune (« mr.sartilly »), le sigle vaut.
  if (aSigle && !aFonction && (aNom || aPrenomDeSaint)) return 'A_VERIFIER';
  if (aFonction || aSigle) return 'FONCTION';
  return aNom || aCommune || aPrenomDeSaint ? 'STRUCTURE' : 'A_VERIFIER';
}

/** Domaines grand public : une faute de frappe sur l'un d'eux envoie le message ailleurs. */
const DOMAINES_COURANTS = ['orange.fr', 'wanadoo.fr', 'gmail.com', 'free.fr', 'hotmail.fr', 'hotmail.com', 'yahoo.fr',
  'yahoo.com', 'laposte.net', 'sfr.fr', 'neuf.fr', 'live.fr', 'outlook.fr', 'outlook.com', 'bbox.fr', 'aol.com',
  'club-internet.fr', 'nordnet.fr', 'numericable.fr', 'cegetel.net', 'aliceadsl.fr', 'ymail.com'];

function distance(a, b) {
  if (Math.abs(a.length - b.length) > 1) return 2;
  let ligne = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i += 1) {
    const suivante = [i];
    for (let j = 1; j <= b.length; j += 1) suivante[j] = Math.min(ligne[j] + 1, suivante[j - 1] + 1, ligne[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    ligne = suivante;
  }
  return ligne[b.length];
}

/**
 * Domaine probablement fautif : à une lettre d'un domaine grand public ou d'un domaine très présent
 * dans le fichier (`frequents` : domaines portés par au moins dix lignes), ou un domaine grand public
 * suivi d'une extension de trop (« gmail.com.fr »).
 */
export function domaineDouteux(domaine, frequents = []) {
  const d = String(domaine ?? '').toLowerCase();
  const reperes = [...new Set([...DOMAINES_COURANTS, ...frequents])];
  if (reperes.includes(d)) return false;
  return reperes.some(r => distance(d, r) === 1) || DOMAINES_COURANTS.some(r => d.startsWith(`${r}.`));
}

/** Lecture CSV (RFC 4180 : guillemets doublés, virgules et retours à la ligne dans un champ). */
export function lireCsv(texte) {
  const lignes = []; let champ = ''; let ligne = []; let entreGuillemets = false;
  const t = texte.charCodeAt(0) === 0xfeff ? texte.slice(1) : texte;
  for (let i = 0; i < t.length; i += 1) {
    const c = t[i];
    if (entreGuillemets) {
      if (c === '"' && t[i + 1] === '"') { champ += '"'; i += 1; } else if (c === '"') entreGuillemets = false; else champ += c;
    } else if (c === '"') entreGuillemets = true;
    else if (c === ',') { ligne.push(champ); champ = ''; }
    else if (c === '\n') { ligne.push(champ); lignes.push(ligne); ligne = []; champ = ''; }
    else if (c !== '\r') champ += c;
  }
  if (champ !== '' || ligne.length > 0) { ligne.push(champ); lignes.push(ligne); }
  const entetes = lignes.shift();
  return lignes.filter(l => l.length === entetes.length).map(l => Object.fromEntries(entetes.map((e, i) => [e, l[i]])));
}

/** Extrait les adresses retenues (une par FINESS) et le décompte de ce qui ne l'est pas. */
export function extraire(texteCsv) {
  const comptes = { lignes: 0, finess_invalide: 0, ABSENTE: 0, MAL_FORMEE: 0, MESSAGERIE_FERMEE: 0, A_VERIFIER: 0, DOMAINE_DOUTEUX: 0, FONCTION: 0, STRUCTURE: 0, doublon_finess: 0 };
  const parFiness = new Map();
  const lignes = lireCsv(texteCsv);
  // Domaines portés par au moins dix lignes du fichier : repères pour les fautes de frappe.
  const parDomaine = new Map();
  for (const l of lignes) {
    const e = String(l['coordinates.emailContact'] ?? '').trim().toLowerCase();
    if (BIEN_FORMEE.test(e)) { const d = e.slice(e.lastIndexOf('@') + 1); parDomaine.set(d, (parDomaine.get(d) ?? 0) + 1); }
  }
  const frequents = [...parDomaine].filter(([, n]) => n >= 10).map(([d]) => d);
  for (const l of lignes) {
    comptes.lignes += 1;
    const finess = String(l.noFinesset ?? '').replace(/\D/g, '');
    if (finess.length !== 9) { comptes.finess_invalide += 1; continue; }
    let classe = classerAdresse(l['coordinates.emailContact'], { nom: l.title, ville: l['coordinates.city'] });
    if (classe === 'FONCTION' || classe === 'STRUCTURE') {
      const e = l['coordinates.emailContact'].trim().toLowerCase();
      if (domaineDouteux(e.slice(e.lastIndexOf('@') + 1), frequents)) classe = 'DOMAINE_DOUTEUX';
    }
    comptes[classe] += 1;
    if (classe !== 'FONCTION' && classe !== 'STRUCTURE') continue;
    if (parFiness.has(finess)) { comptes.doublon_finess += 1; continue; }
    const maj = /^\d{4}-\d{2}-\d{2}/.exec(String(l.updatedAt ?? ''))?.[0] ?? null;
    parFiness.set(finess, { finess, email: l['coordinates.emailContact'].trim().toLowerCase(), classe, maj, departement: String(l['coordinates.deptcode'] ?? '').trim() });
  }
  const adresses = [...parFiness.values()].sort((a, b) => a.finess.localeCompare(b.finess));
  return { comptes: { ...comptes, retenues: adresses.length, adresses_distinctes: new Set(adresses.map(a => a.email)).size }, adresses };
}

/** Bloc de données de la migration : une ligne par adresse, « finess;adresse;classe;date de mise à jour ». */
export function blocSql(adresses) {
  return adresses.map(a => `${a.finess};${a.email};${a.classe === 'FONCTION' ? 'F' : 'S'};${a.maj ?? ''}`).join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , chemin, ...options] = process.argv;
  if (!chemin) { console.error('Usage : node scripts/acquisition/extraire-annuaire-personnes-agees.mjs <base-etablissements.csv> [--json sortie.json] [--sql sortie.sql]'); process.exit(2); }
  const brut = readFileSync(chemin);
  const empreinte = createHash('sha256').update(brut).digest('hex');
  if (empreinte !== SOURCE.sha256) { console.error(`Fichier inattendu (sha256 ${empreinte}) : ce script décrit la publication du 11/11/2020 (${SOURCE.sha256}). Relire les colonnes avant d'importer une autre version.`); process.exit(1); }
  const { comptes, adresses } = extraire(brut.toString('utf8'));
  console.log(JSON.stringify(comptes, null, 2));
  console.log('départements pilotes', Object.fromEntries(['56', '75', '92'].map(d => [d, adresses.filter(a => a.departement === d).length])));
  const option = nom => (options.includes(nom) ? options[options.indexOf(nom) + 1] : null);
  if (option('--json')) { writeFileSync(option('--json'), `${JSON.stringify({ source: SOURCE, comptes, adresses })}\n`); console.log('écrit', option('--json')); }
  if (option('--sql')) {
    const bloc = blocSql(adresses);
    writeFileSync(option('--sql'), `${bloc}\n`);
    console.log('écrit', option('--sql'), '— lignes', adresses.length, '— sha256 du bloc', createHash('sha256').update(bloc).digest('hex'));
  }
}
