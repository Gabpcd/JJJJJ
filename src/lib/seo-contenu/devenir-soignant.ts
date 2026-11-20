/**
 * Questions fréquentes de `/devenir-soignant`.
 *
 * Texte unique, lu par le composant React ET par le HTML statique (`src/lib/seo-routes.ts`) :
 * une question affichée par la page et la même question lue par un robot sans JavaScript
 * sont la même chaîne. Module pur (aucun import React/DOM). Déplacé tel quel depuis
 * `src/pages/DevenirSoignant.tsx` ; les gardes qui relisaient ce fichier relisent aussi celui-ci.
 */
import type { QuestionSEO } from './types';

export const FAQ_DEVENIR_SOIGNANT: QuestionSEO[] = [
  { q: "L'inscription est-elle vraiment gratuite ?", r: "Oui, l'inscription est entièrement gratuite pour les soignants, sans aucune commission prélevée sur votre rémunération." },
  { q: "Comment suis-je payé ?", r: "En libéral, l'établissement règle vos honoraires selon le délai indiqué sur la mission ; un paiement accéléré n'est proposé que lorsqu'il est explicitement affiché. En salarié, le salaire est versé par l'établissement employeur." },
  { q: "Quelles professions peuvent s'inscrire ?", r: "Infirmiers, aides-soignants, AES, kinésithérapeutes, pharmaciens, préparateurs en pharmacie, sages-femmes et d'autres professions de santé." },
  { q: "Quels documents dois-je fournir ?", r: "Selon votre profession : pièce d'identité, diplôme, et le cas échéant numéro RPPS et assurance. Tout est vérifié pour rassurer les établissements." },
  { q: "Suis-je obligé d'accepter des missions ?", r: "Non. Vous choisissez librement vos missions, vos dates et votre taux horaire, sans aucune obligation." },
  { q: "Puis-je cumuler avec mon emploi actuel ?", r: "Oui, de nombreux soignants complètent leur planning avec des missions ponctuelles selon leurs disponibilités." },
];
