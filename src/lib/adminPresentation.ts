import { getLabelTypeEtablissement } from '@/lib/constantes';
import { validerSiret } from '@/lib/luhn';

const MARQUEURS_TEST = ['[pw-test', '[playwright-test', 'playwright-', '@example.test'];

export function estDonneeTestAdmin(...valeurs: unknown[]): boolean {
  return valeurs.some((valeur) => {
    if (valeur === true) return true;
    if (typeof valeur !== 'string') return false;
    const texte = valeur.toLowerCase();
    return MARQUEURS_TEST.some((marqueur) => texte.includes(marqueur));
  });
}

function commeObjet(valeur: unknown): Record<string, unknown> {
  return valeur && typeof valeur === 'object' ? valeur as Record<string, unknown> : {};
}

export function estMissionTestAdmin(mission: unknown): boolean {
  const m = commeObjet(mission);
  const etablissement = commeObjet(m.etablissements);
  const soignant = commeObjet(m.soignants);
  return estDonneeTestAdmin(
    m.est_compte_test,
    m.intitule,
    etablissement.est_compte_test,
    soignant.est_compte_test,
  );
}

export function estUtilisateurTestAdmin(utilisateur: unknown): boolean {
  const u = commeObjet(utilisateur);
  return estDonneeTestAdmin(
    u.est_compte_test,
    u.nom,
    u.prenom,
    u.email,
    u.email_contact,
  );
}

export function normaliserZero(valeur: number): number {
  return Math.abs(valeur) < 0.005 ? 0 : valeur;
}

export function formatEuroAdmin(
  valeur: number | string | null | undefined,
  options: { decimales?: number; suffixe?: 'HT' | 'TTC' } = {},
): string {
  if (valeur == null || valeur === '') return '—';
  const nombre = Number(valeur);
  if (!Number.isFinite(nombre)) return '—';
  const decimales = options.decimales ?? 2;
  const montant = new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency: 'EUR',
    minimumFractionDigits: decimales,
    maximumFractionDigits: decimales,
  }).format(normaliserZero(nombre));
  return options.suffixe ? `${montant} ${options.suffixe}` : montant;
}

export function formatDateAdmin(date: string | Date | null | undefined): string {
  if (!date) return '—';
  const parsed = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(parsed.getTime())) return '—';
  return parsed
    .toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })
    .replace(/ /g, '\u00a0');
}

export function libelleTypeEtablissementAdmin(type: string | null | undefined): string {
  if (!type) return 'Type non renseigné';
  return getLabelTypeEtablissement(type);
}

export type AlerteVetting = {
  code: 'SIRET_INVALIDE' | 'NAF_INHABITUEL';
  message: string;
};

// Familles NAF santé / médico-social. Les officines ne publient pas de missions
// Jolene (Lot 21), leur code NAF ne doit donc pas être auto-validé ici.
// il ne valide ni ne rejette automatiquement un dossier.
export function estCodeNafSante(codeNaf: string | null | undefined): boolean {
  if (!codeNaf) return false;
  const code = codeNaf.trim().toUpperCase();
  return /^(86|87|88)/.test(code);
}

export function analyserVettingEtablissement(
  siret: string | null | undefined,
  codeNaf: string | null | undefined,
): AlerteVetting[] {
  const alertes: AlerteVetting[] = [];
  if (!siret || !validerSiret(siret).valide) {
    alertes.push({
      code: 'SIRET_INVALIDE',
      message: 'SIRET invalide : vérifiez les 14 chiffres et la clé Luhn avant validation.',
    });
  }
  if (codeNaf && !estCodeNafSante(codeNaf)) {
    alertes.push({
      code: 'NAF_INHABITUEL',
      message: `${codeNaf} : inhabituel pour un établissement de santé. Vérification manuelle recommandée.`,
    });
  }
  return alertes;
}

export function urlAnnuaireEntreprise(siret: string | null | undefined): string | null {
  const propre = (siret || '').replace(/\s/g, '');
  return /^\d{14}$/.test(propre)
    ? `https://annuaire-entreprises.data.gouv.fr/etablissement/${propre}`
    : null;
}
