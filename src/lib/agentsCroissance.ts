/**
 * Agents de croissance — logique pure partagée par la page admin.
 * Les agents SQL écrivent des brouillons ; rien n'est envoyé automatiquement.
 * Sources : supabase/migrations/20261109140000_agents_croissance_brouillons.sql,
 * 20261124123500_prospection_zero_visible_liste_appels.sql (décompte des cibles, fiches d'appel).
 */

export type AgentCroissance =
  | 'PROSPECTION_ETABLISSEMENT'
  | 'APPEL_ETABLISSEMENT'
  | 'POST_SOCIAL'
  | 'MISSION_A_POURVOIR'
  | 'REACTIVATION';

export type CanalBrouillon = 'EMAIL' | 'TELEPHONE' | 'LINKEDIN' | 'FACEBOOK_GROUPE';
export type StatutBrouillon = 'BROUILLON' | 'VALIDE' | 'REJETE' | 'ENVOYE' | 'EXPIRE';
export type ActionBrouillon = 'MODIFIER' | 'VALIDER' | 'REJETER' | 'MARQUER_ENVOYE';

export interface BrouillonCroissance {
  id: string;
  agent: AgentCroissance;
  canal: CanalBrouillon;
  cible_type: string;
  cible_id: string | null;
  destinataire_nom: string | null;
  destinataire_email: string | null;
  departement: string | null;
  profession: string | null;
  sequence_etape: number | null;
  sujet: string | null;
  corps: string;
  lien: string | null;
  contexte: Record<string, unknown>;
  score: number | null;
  statut: StatutBrouillon;
  motif_rejet: string | null;
  cree_le: string;
  expire_le: string | null;
  valide_le: string | null;
  envoye_le: string | null;
}

export const AGENTS: Record<AgentCroissance, { libelle: string; description: string }> = {
  PROSPECTION_ETABLISSEMENT: {
    libelle: 'Prospection établissements',
    description:
      'Chaque matin, jusqu’à 20 premiers emails et les relances dues, pour les établissements des marchés pilotes (FINESS), en excluant les oppositions.',
  },
  APPEL_ETABLISSEMENT: {
    libelle: 'Appels établissements',
    description:
      'Chaque semaine, jusqu’à 30 fiches d’appel pour les établissements des marchés pilotes qui ont un téléphone, classées par potentiel, oppositions exclues. Vous appelez vous-même, puis vous notez le résultat.',
  },
  POST_SOCIAL: {
    libelle: 'Posts sociaux',
    description:
      'Chaque semaine, un post par département et par métier pour les groupes Facebook, et un post LinkedIn pour les directions d’établissement.',
  },
  MISSION_A_POURVOIR: {
    libelle: 'Missions à pourvoir',
    description:
      'Chaque mission réelle ouverte depuis plus de 6 h et sans candidature reçoit un post prêt à partager.',
  },
  REACTIVATION: {
    libelle: 'Réactivation des inscrits',
    description:
      'Inscrits réels bloqués (documents, vérification, première candidature ou première mission), préférences email respectées.',
  },
};

export const LIBELLE_CANAL: Record<CanalBrouillon, string> = {
  EMAIL: 'Email',
  TELEPHONE: 'Téléphone',
  LINKEDIN: 'LinkedIn',
  FACEBOOK_GROUPE: 'Groupe Facebook',
};

export const LIBELLE_STATUT: Record<StatutBrouillon, string> = {
  BROUILLON: 'À valider',
  VALIDE: 'Validé, à envoyer',
  REJETE: 'Rejeté',
  ENVOYE: 'Envoyé',
  EXPIRE: 'Expiré',
};

/** Un email part du Gmail de la fondatrice ; un post est copié-collé. */
export function estEmail(b: Pick<BrouillonCroissance, 'canal'>): boolean {
  return b.canal === 'EMAIL';
}

/** Une fiche d'appel : la fondatrice appelle elle-même, puis note le résultat. */
export function estAppel(b: Pick<BrouillonCroissance, 'canal'>): boolean {
  return b.canal === 'TELEPHONE';
}

/** Libellé du statut : une fiche d'appel ne « s'envoie » pas. */
export function libelleStatut(b: Pick<BrouillonCroissance, 'canal' | 'statut'>): string {
  if (estAppel(b) && b.statut === 'VALIDE') return 'Validée, à appeler';
  if (estAppel(b) && b.statut === 'ENVOYE') return 'Appel noté';
  return LIBELLE_STATUT[b.statut];
}

/**
 * Résultats d'un appel, mêmes codes que « Actions du jour » du CRM
 * (fn_admin_crm_effectuer_action). `definitif` : le contact ne sera plus sollicité, tous canaux.
 */
export const RESULTATS_APPEL = [
  { code: 'APPEL_REPONDU', libelle: 'A répondu', definitif: false },
  { code: 'SANS_REPONSE', libelle: 'Sans réponse', definitif: false },
  { code: 'INTERESSE', libelle: 'Intéressé', definitif: false },
  { code: 'A_RAPPELER', libelle: 'À rappeler', definitif: false },
  { code: 'PAS_INTERESSE', libelle: 'Pas intéressé', definitif: true },
  { code: 'STOP', libelle: 'STOP', definitif: true },
] as const;

export type ResultatAppel = (typeof RESULTATS_APPEL)[number]['code'];

export function libelleResultatAppel(code: unknown): string | null {
  return RESULTATS_APPEL.find((r) => r.code === code)?.libelle ?? null;
}

/** Numéro d'une fiche d'appel, tel que l'annuaire le donne. */
export function telephoneFiche(contexte: Record<string, unknown>): string | null {
  const brut = contexte?.telephone;
  return typeof brut === 'string' && brut.trim() ? brut.trim() : null;
}

/**
 * Forme nationale d'un numéro français (dix chiffres commençant par 0), ou null si le champ n'en
 * contient pas exactement un. Miroir de private.fn_growth_telephone_national : « 01 23… »,
 * « +33 1 23… » et « 0033 1 23… » désignent le même numéro.
 */
export function telephoneNational(numero: string | null | undefined): string | null {
  const chiffres = (numero ?? '').replace(/\D/g, '');
  if (/^0[1-9]\d{8}$/.test(chiffres)) return chiffres;
  if (/^33[1-9]\d{8}$/.test(chiffres)) return `0${chiffres.slice(2)}`;
  if (/^0033[1-9]\d{8}$/.test(chiffres)) return `0${chiffres.slice(4)}`;
  return null;
}

/** Lien `tel:` sur la forme nationale. Null si le numéro n'est pas un numéro français complet. */
export function lienTel(numero: string | null | undefined): string | null {
  const national = telephoneNational(numero);
  return national ? `tel:${national}` : null;
}

/** Origine du numéro d'une fiche d'appel, pour répondre à « où avez-vous eu ce numéro ? ». */
export function sourceFiche(contexte: Record<string, unknown>): string | null {
  const brut = contexte?.source;
  return typeof brut === 'string' && brut.trim() ? brut.trim() : null;
}

export interface ResumeAppels {
  texte: string;
  /** Des places de la semaine sont restées vides : plus aucune cible appelable. */
  epuisee: boolean;
}

/** Ce que l'agent d'appels a fait à son dernier passage, pour que « 0 fiche » s'explique. */
export function resumeAppels(details: unknown): ResumeAppels | null {
  if (typeof details !== 'object' || details === null) return null;
  const d = details as Record<string, unknown>;
  const n = (cle: string) => (typeof d[cle] === 'number' && Number.isFinite(d[cle]) ? (d[cle] as number) : null);
  const places = n('places_de_la_semaine');
  const quota = n('quota_semaine');
  if (places === null || quota === null) return null;
  const vides = n('places_non_pourvues') ?? 0;
  const morceaux: string[] = [];
  morceaux.push(places === 0
    ? `Liste de la semaine complète (${quota} ${quota > 1 ? 'fiches' : 'fiche'}) : la prochaine arrive lundi`
    : `${places} ${places > 1 ? 'places restaient' : 'place restait'} sur ${quota} cette semaine`);
  const stop = n('exclus_stop') ?? 0;
  if (stop > 0) morceaux.push(`${stop} ${stop > 1 ? 'cibles écartées' : 'cible écartée'} pour opposition`);
  const numeros = n('numeros_deja_en_file') ?? 0;
  if (numeros > 0) morceaux.push(`${numeros} ${numeros > 1 ? 'numéros déjà proposés' : 'numéro déjà proposé'}`);
  if (vides > 0) morceaux.push(`${vides} ${vides > 1 ? 'places sans cible appelable' : 'place sans cible appelable'}`);
  return { texte: morceaux.join(' · '), epuisee: vides > 0 };
}

/** Actions proposées pour un statut donné (miroir des règles SQL). */
export function actionsPossibles(statut: StatutBrouillon): ActionBrouillon[] {
  if (statut === 'BROUILLON') return ['MODIFIER', 'VALIDER', 'REJETER'];
  if (statut === 'VALIDE') return ['MODIFIER', 'MARQUER_ENVOYE', 'REJETER'];
  return [];
}

/** Lien de rédaction Gmail pré-rempli (même schéma que le CRM). */
export function lienGmail(email: string, sujet: string | null, corps: string): string {
  return (
    'https://mail.google.com/mail/?view=cm&fs=1' +
    `&to=${encodeURIComponent(email)}` +
    `&su=${encodeURIComponent(sujet ?? '')}` +
    `&body=${encodeURIComponent(corps)}`
  );
}

export interface GroupeSuggere {
  nom: string;
  url: string | null;
  membres: number | null;
}

export function groupesSuggeres(contexte: Record<string, unknown>): GroupeSuggere[] {
  const brut = contexte?.groupes_suggeres;
  if (!Array.isArray(brut)) return [];
  return brut
    .filter((g): g is Record<string, unknown> => typeof g === 'object' && g !== null)
    .map((g) => ({
      nom: String(g.nom ?? ''),
      url: typeof g.url === 'string' && /^https?:\/\//.test(g.url) ? g.url : null,
      membres: typeof g.membres === 'number' ? g.membres : null,
    }))
    .filter((g) => g.nom.length > 0);
}

/** Résumé lisible du « pourquoi cette cible ». */
export function raisonsCible(b: Pick<BrouillonCroissance, 'agent' | 'contexte' | 'departement'>): string[] {
  const c = b.contexte ?? {};
  const raisons: string[] = [];
  if (b.agent === 'PROSPECTION_ETABLISSEMENT' || b.agent === 'APPEL_ETABLISSEMENT') {
    if (typeof c.type_etablissement === 'string') raisons.push(c.type_etablissement.replace(/_/g, ' '));
    if (typeof c.ville === 'string' && c.ville) raisons.push(c.ville);
    if (b.departement) raisons.push(`dépt ${b.departement}`);
    const score = (c.score ?? {}) as Record<string, number>;
    if (score.signal_boamp_90j > 0) raisons.push('avis BOAMP récent');
    const bmo = c.bmo_as as { difficulte_pct?: number } | null | undefined;
    if (bmo && typeof bmo.difficulte_pct === 'number') {
      raisons.push(`recrutement AS jugé difficile à ${bmo.difficulte_pct} % (BMO)`);
    }
    if (c.relance_crm) raisons.push('relance de séquence CRM');
  } else if (b.agent === 'REACTIVATION' && typeof c.blocage === 'string') {
    const libelles: Record<string, string> = {
      DOCUMENTS: 'aucun document déposé',
      VERIFICATION: 'documents en attente',
      CANDIDATURE: 'jamais candidaté',
      PUBLICATION: 'jamais publié de mission',
    };
    raisons.push(libelles[c.blocage] ?? c.blocage);
  } else if (b.agent === 'MISSION_A_POURVOIR') {
    raisons.push('aucune candidature');
    if (typeof c.soignants_verifies_meme_profession === 'number') {
      raisons.push(`${c.soignants_verifies_meme_profession} soignant(s) vérifié(s) de ce métier`);
    }
  }
  return raisons;
}

// ---------------------------------------------------------------------------
// Cibles de la prospection : un zéro ne doit pas rester muet
// ---------------------------------------------------------------------------

/** Décompte de private.fn_growth_cibles_prospection() (résultat de l'agent email, entonnoir). */
export interface CiblesProspection {
  departements: string[];
  etablissements_cibles: number;
  adresses_fermees: number;
  adresses_utilisables: number;
  adresses_restantes: number;
  telephones_utilisables: number;
  telephones_restants: number;
}

const CLES_CIBLES = [
  'etablissements_cibles', 'adresses_fermees', 'adresses_utilisables', 'adresses_restantes',
  'telephones_utilisables', 'telephones_restants',
] as const;

/** Lit un décompte ; null s'il est absent ou incomplet (passage antérieur à la migration). */
export function lireCibles(brut: unknown): CiblesProspection | null {
  if (typeof brut !== 'object' || brut === null) return null;
  const c = brut as Record<string, unknown>;
  if (!CLES_CIBLES.every((cle) => typeof c[cle] === 'number' && Number.isFinite(c[cle]))) return null;
  return {
    departements: Array.isArray(c.departements) ? c.departements.map(String) : [],
    etablissements_cibles: c.etablissements_cibles as number,
    adresses_fermees: c.adresses_fermees as number,
    adresses_utilisables: c.adresses_utilisables as number,
    adresses_restantes: c.adresses_restantes as number,
    telephones_utilisables: c.telephones_utilisables as number,
    telephones_restants: c.telephones_restants as number,
  };
}

export interface AlerteCibles {
  /** « alerte » : aucune adresse utilisable ; « info » : toutes déjà traitées. */
  niveau: 'alerte' | 'info';
  titre: string;
  texte: string;
}

const fr = (n: number) => n.toLocaleString('fr-FR');
const pluriel = (n: number, un: string, plusieurs: string) => (n > 1 ? plusieurs : un);

/** Ce que l'agent email dit de son dernier passage (résultat de private.fn_growth_agent_prospection). */
export interface PassageProspection {
  premiers_contacts: number;
  places_non_pourvues: number;
}

export function lirePassage(details: unknown): PassageProspection | null {
  if (typeof details !== 'object' || details === null) return null;
  const d = details as Record<string, unknown>;
  if (typeof d.premiers_contacts !== 'number' || typeof d.places_non_pourvues !== 'number') return null;
  return { premiers_contacts: d.premiers_contacts, places_non_pourvues: d.places_non_pourvues };
}

/** Avertissement à afficher quand l'agent email ne peut plus rien préparer, sinon null. */
export function alerteCibles(c: CiblesProspection | null, passage: PassageProspection | null = null): AlerteCibles | null {
  if (!c) return null;
  const marches = c.departements.length > 0 ? ` (${c.departements.join(', ')})` : '';
  if (c.etablissements_cibles === 0) {
    return {
      niveau: 'alerte',
      titre: 'Prospection sans cible',
      texte: `Aucun établissement ne correspond aux départements et aux types ciblés${marches}. Les agents de prospection ne peuvent rien préparer.`,
    };
  }
  const telephones = c.telephones_utilisables > 0
    ? ` ${fr(c.telephones_utilisables)} ${pluriel(c.telephones_utilisables, 'a', 'ont')} un téléphone : les fiches d’appel de la semaine sont dans « Appels établissements ».`
    : ' Aucun n’a de téléphone non plus.';
  if (c.adresses_utilisables === 0) {
    const fermees = c.adresses_fermees > 0
      ? ` ${fr(c.adresses_fermees)} ${pluriel(c.adresses_fermees, 'a une adresse, en', 'ont une adresse, toutes en')} messagerie de santé fermée (MSSanté, Apicrypt), où un email envoyé depuis Gmail est rejeté.`
      : '';
    return {
      niveau: 'alerte',
      titre: 'Prospection par email à l’arrêt',
      texte: `Aucune adresse utilisable parmi les ${fr(c.etablissements_cibles)} établissements ciblés${marches}.${fermees}${telephones}`,
    };
  }
  if (c.adresses_restantes === 0) {
    return {
      niveau: 'info',
      titre: 'Plus aucune adresse à contacter par email',
      texte: `${pluriel(c.adresses_utilisables, 'La seule adresse utilisable', `Les ${fr(c.adresses_utilisables)} adresses utilisables`)} des ${fr(c.etablissements_cibles)} établissements ciblés${marches} ${pluriel(c.adresses_utilisables, 'est déjà contactée, au CRM ou en file', 'sont déjà contactées, au CRM ou en file')}.${telephones}`,
    };
  }
  // Il reste des adresses, mais le passage n'en a retenu aucune alors qu'il avait de la place :
  // elles ont toutes été écartées cible par cible (opposition, adresse déjà en séquence).
  if (passage && passage.premiers_contacts === 0 && passage.places_non_pourvues > 0) {
    return {
      niveau: 'info',
      titre: 'Aucun nouvel email préparé',
      texte: `${pluriel(c.adresses_restantes, 'Il reste 1 adresse utilisable non contactée, mais elle a été écartée', `Il reste ${fr(c.adresses_restantes)} adresses utilisables non contactées, mais elles ont toutes été écartées`)} au dernier passage (opposition, ou adresse déjà en séquence).${telephones}`,
    };
  }
  return null;
}

/** Résumé d'une ligne pour la carte de l'agent. */
export function resumeCibles(c: CiblesProspection): string {
  return [
    `${fr(c.etablissements_cibles)} ${pluriel(c.etablissements_cibles, 'établissement ciblé', 'établissements ciblés')}`,
    `${fr(c.adresses_utilisables)} ${pluriel(c.adresses_utilisables, 'adresse utilisable', 'adresses utilisables')}`,
    `${fr(c.adresses_fermees)} en messagerie fermée`,
    `${fr(c.telephones_utilisables)} ${pluriel(c.telephones_utilisables, 'téléphone', 'téléphones')}`,
  ].join(' · ');
}

// ---------------------------------------------------------------------------
// Entonnoir
// ---------------------------------------------------------------------------

export interface EntonnoirCroissance {
  periode: { debut: string; fin: string };
  soignants: Record<string, number>;
  etablissements: Record<string, number>;
  missions: Record<string, number>;
  prospection: Record<string, unknown>;
  agents: Record<string, unknown>;
  sources_inscriptions_periode: Record<string, number>;
  exclus_cohorte_test: Record<string, number>;
}

export interface EtapeEntonnoir {
  cle: string;
  libelle: string;
  valeur: number;
  /** Part de l'étape précédente, en %, null pour la première étape ou si 0. */
  conversionPct: number | null;
}

function nombre(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}

function etapes(definitions: Array<[string, string, unknown]>): EtapeEntonnoir[] {
  return definitions.map(([cle, libelle, brut], i) => {
    const valeur = nombre(brut);
    const precedente = i > 0 ? nombre(definitions[i - 1][2]) : 0;
    return {
      cle,
      libelle,
      valeur,
      conversionPct: i === 0 || precedente === 0 ? null : Math.round((valeur / precedente) * 100),
    };
  });
}

export function etapesSoignants(e: EntonnoirCroissance): EtapeEntonnoir[] {
  const s = e.soignants ?? {};
  return etapes([
    ['inscrits_total', 'Inscrits', s.inscrits_total],
    ['avec_document', 'Au moins un document', s.avec_document],
    ['documents_valides', 'Documents validés', s.documents_valides],
    ['ayant_candidate', 'Ont candidaté', s.ayant_candidate],
    ['ayant_realise_mission', 'Ont réalisé une mission', s.ayant_realise_mission],
  ]);
}

export function etapesEtablissements(e: EntonnoirCroissance): EtapeEntonnoir[] {
  const p = e.prospection ?? {};
  const t = e.etablissements ?? {};
  return etapes([
    ['prospects_avec_email', 'Prospects avec email', p.prospects_avec_email],
    ['prospects_contactes_total', 'Contactés', p.prospects_contactes_total],
    ['inscrits_total', 'Inscrits', t.inscrits_total],
    ['peuvent_publier', 'Peuvent publier', t.peuvent_publier],
    ['ayant_publie', 'Ont publié', t.ayant_publie],
  ]);
}

/** Le goulot = la première étape après la tête dont la conversion est la plus faible. */
export function goulot(etapesListe: EtapeEntonnoir[]): EtapeEntonnoir | null {
  const candidates = etapesListe.slice(1).filter((x) => x.conversionPct !== null || x.valeur === 0);
  if (candidates.length === 0) return null;
  const zero = etapesListe.slice(1).find((x) => x.valeur === 0);
  if (zero) return zero;
  return candidates.reduce((a, b) => ((b.conversionPct ?? 0) < (a.conversionPct ?? 0) ? b : a));
}
