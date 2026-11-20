/**
 * Questions fréquentes de `/recruter-soignants`.
 *
 * Texte unique, lu par le composant React ET par le HTML statique (`src/lib/seo-routes.ts`) :
 * une question affichée par la page et la même question lue par un robot sans JavaScript
 * sont la même chaîne. Module pur (aucun import React/DOM). Déplacé tel quel depuis
 * `src/pages/RecruterSoignants.tsx` ; les gardes qui relisaient ce fichier relisent aussi celui-ci.
 */
import type { QuestionSEO } from './types';

export const FAQ_RECRUTER_SOIGNANTS: QuestionSEO[] = [
  { q: "Jolene Santé est-elle une agence d'intérim ?", r: "Non. Jolene Santé est une plateforme de mise en relation directe : vous publiez votre besoin, des soignants vérifiés candidatent, et vous contractualisez directement avec eux. Pas de marge d'agence." },
  { q: "Combien coûte le service ?", r: "15 % HT de commission sur le montant de la mission, soit 18 % TTC avec la TVA de 20 %, sans abonnement ni frais d'entrée. Vous ne payez que lorsque vous recrutez." },
  { q: "Comment les soignants sont-ils vérifiés ?", r: "L'identité et les qualifications professionnelles sont contrôlées pour tous les soignants, notamment via le RPPS lorsqu'il existe. Les justificatifs propres au libéral, comme la RCP, ne sont demandés que pour les missions libérales." },
  { q: "Quels types de contrats sont possibles ?", r: "Selon la mission : CDD, y compris CDD court, ou exercice libéral lorsqu'il est explicitement proposé. Les contrats sont générés automatiquement et les démarches administratives facilitées." },
  { q: "Quelles professions puis-je recruter ?", r: "Infirmiers (IDE), aides-soignants (AS et AES), kinésithérapeutes, pharmaciens, préparateurs en pharmacie, sages-femmes et d'autres professions de santé." },
  { q: "Suis-je engagé sur la durée ?", r: "Non, aucun engagement ni abonnement. Vous publiez un besoin uniquement lorsque vous en avez un." },
];
