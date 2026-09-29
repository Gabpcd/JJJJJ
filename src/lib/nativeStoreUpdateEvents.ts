export const VERIFIER_MISE_A_JOUR = 'jolene:check-store-update';
export const RESULTAT_MISE_A_JOUR = 'jolene:store-update-result';

export interface ResultatMiseAJour {
  enCours: boolean;
  message: string;
}

export function signalerVerification(enCours: boolean, message = '') {
  window.dispatchEvent(new CustomEvent<ResultatMiseAJour>(RESULTAT_MISE_A_JOUR, {
    detail: { enCours, message },
  }));
}
