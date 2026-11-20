/**
 * Textes de l'accueil (`/`) : titre, accroche, atouts, étapes et questions fréquentes.
 *
 * Texte unique, lu par le composant React ET par le HTML statique (`src/lib/seo-routes.ts`) :
 * une question affichée par la page et la même question lue par un robot sans JavaScript
 * sont la même chaîne. Module pur (aucun import React/DOM). Déplacé tel quel depuis
 * `src/pages/PageAccueil.tsx` ; les gardes qui relisaient ce fichier relisent aussi celui-ci.
 */
import type { QuestionSEO } from './types';

/** H1 de l'accueil. PageAccueil compose le même texte en deux morceaux (dégradé sur la fin). */
export const TITRE_ACCUEIL = 'Le remplacement santé, enfin simple.';

export const ACCROCHE_ACCUEIL = 'Établissements et soignants connectés en direct. Contrat signé en ligne, pointage GPS, paiement suivi — zéro paperasse.';

export interface AtoutAccueil { emoji: string; text: string }

export const ATOUTS_SOIGNANTS: AtoutAccueil[] = [
  { emoji: '📍', text: 'Missions près de chez vous, en liste ou en swipe' },
  { emoji: '💶', text: 'Rémunération affichée avant de postuler, paiement suivi' },
  { emoji: '📄', text: 'Contrats générés et signés en ligne' },
  { emoji: '🚀', text: 'Parcours vers le libéral adapté à votre profession' },
];

export const ATOUTS_ETABLISSEMENTS: AtoutAccueil[] = [
  { emoji: '✅', text: 'Identité professionnelle et pièces adaptées à la mission vérifiées' },
  { emoji: '⚡', text: 'Plan de secours activé en cas de désistement ou non-présentation' },
  { emoji: '⚖️', text: 'DPAE préparée, plafonds et contrôles de conformité visibles' },
  { emoji: '🧾', text: 'Documents de facturation par période et suivi Chorus Pro' },
];

export interface EtapeAccueil { num: string; emoji: string; titre: string; desc: string }

export const ETAPES_ACCUEIL: EtapeAccueil[] = [
  { num: '1', emoji: '📝', titre: 'Publiez ou postulez', desc: 'L\'établissement publie sa mission avec horaires et taux. Le soignant postule ou accepte en 1 clic.' },
  { num: '2', emoji: '✍️', titre: 'Le contrat se signe en ligne', desc: 'Contrat prérempli à partir de la mission, puis signé électroniquement par les deux parties, dans l’ordre de leur choix.' },
  { num: '3', emoji: '🎉', titre: 'Le suivi est centralisé', desc: 'Pointage, facturation et paiement sont suivis au même endroit. Pour une mission salariée, l’établissement transmet lui-même la DPAE à l’URSSAF.' },
];

export const FAQ_ACCUEIL: QuestionSEO[] = [
  { q: 'Comment fonctionne la commission ?', r: 'Jolene facture à l\'établissement une commission de 15 % HT sur la base financière validée : honoraires HT pour une mission libérale ou rémunération brute contractuelle pour une mission salariée, majorations et indemnités incluses lorsqu’elles entrent dans cette base. Avec une TVA de 20 %, la commission représente 18 % TTC. Aucun frais pour le soignant.' },
  { q: 'Jolene est-il une agence d\'intérim ?', r: 'Non. Jolene est une plateforme de mise en relation. Le contrat est signé directement entre l\'établissement et le soignant. Nous ne sommes pas employeur.' },
  { q: 'Comment sont vérifiés les soignants ?', r: 'Le numéro RPPS, lorsqu’il existe, est rapproché de l’Annuaire Santé officiel. Les pièces requises selon la profession et le contrat sont ensuite contrôlées automatiquement ou, pour les situations réglementaires sensibles, en revue humaine. L’assurance RCP est demandée pour les missions libérales.' },
  { q: 'Quels types de contrats sont générés ?', r: 'La plateforme génère automatiquement des CDD, y compris des CDD courts, signés électroniquement par les deux parties. Le libéral n’est proposé que pour les missions explicitement ouvertes par la matrice profession × établissement.' },
  { q: 'Comment fonctionne le pointage ?', r: 'Le soignant pointe son arrivée et son départ via l\'application mobile avec géolocalisation GPS. Le périmètre est vérifié automatiquement par rapport à l\'adresse de l\'établissement.' },
  { q: 'Puis-je passer en libéral via Jolene ?', r: 'Jolene peut suivre et expliquer les conditions propres à votre profession. Le repère de 3 200 heures ne concerne que certaines professions infirmières lorsqu’il est applicable ; aucun compteur ne remplace les autorisations, inscriptions ou justificatifs réglementaires.' },
];
