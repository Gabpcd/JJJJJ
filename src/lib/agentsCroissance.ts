/**
 * Agents de croissance — logique pure partagée par la page admin.
 * Les agents SQL écrivent des brouillons ; rien n'est envoyé automatiquement.
 * Source : supabase/migrations/20261109082510_agents_croissance_brouillons.sql
 */

export type AgentCroissance =
  | 'PROSPECTION_ETABLISSEMENT'
  | 'POST_SOCIAL'
  | 'MISSION_A_POURVOIR'
  | 'REACTIVATION';

export type CanalBrouillon = 'EMAIL' | 'LINKEDIN' | 'FACEBOOK_GROUPE';
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
  if (b.agent === 'PROSPECTION_ETABLISSEMENT') {
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
