export class NativeAccountError extends Error {
  constructor(message: string, readonly code = 'ACCOUNT_ERROR') { super(message); this.name = 'NativeAccountError'; }
}
export function accountErrorMessage(error: unknown): string {
  if (error instanceof NativeAccountError) return error.message;
  const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
  if (code === 'email_not_confirmed') return 'Confirmez votre adresse email avec le lien reçu, puis reconnectez-vous.';
  if (code === 'invalid_credentials') return 'Vérifiez votre adresse email et votre mot de passe.';
  if (/rate_limit|over_.*limit/.test(code)) return 'Trop de tentatives. Patientez avant de réessayer.';
  return 'La demande n’a pas abouti. Vérifiez votre connexion puis réessayez ; votre saisie reste disponible.';
}
