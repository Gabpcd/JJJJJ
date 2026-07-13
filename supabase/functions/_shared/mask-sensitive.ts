/**
 * mask-sensitive.ts — Masque les données sensibles dans une string
 * avant écriture en base (response_excerpt, logs).
 *
 * Réutilisable par toute edge function qui logge des réponses.
 */

const PATTERNS: { regex: RegExp; replacement: string }[] = [
  // IBAN français (FR + 2 digits + 23 alphanums avec espaces possibles)
  { regex: /FR\d{2}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{4}[\s]?[\dA-Z]{3}/gi, replacement: 'IBAN_MASKED' },
  // Email addresses
  { regex: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, replacement: 'EMAIL_MASKED' },
  // JWT tokens (eyJ...)
  { regex: /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g, replacement: 'JWT_MASKED' },
  // Stripe secret keys
  { regex: /sk_(live|test)_[A-Za-z0-9]{20,}/g, replacement: 'STRIPE_KEY_MASKED' },
  // Stripe publishable keys (less sensitive but still mask)
  { regex: /pk_(live|test)_[A-Za-z0-9]{20,}/g, replacement: 'STRIPE_PK_MASKED' },
  // Generic tokens: 40+ chars mixed alphanumeric (heuristic)
  { regex: /(?<![a-zA-Z0-9/+])[A-Za-z0-9]{40,}(?![a-zA-Z0-9/+=])/g, replacement: 'TOKEN_MASKED' },
];

/**
 * Mask sensitive data in a string.
 * Returns the masked string, truncated to maxLength.
 */
export function maskSensitive(input: string, maxLength = 500): string {
  let result = input;
  for (const { regex, replacement } of PATTERNS) {
    result = result.replace(regex, replacement);
  }
  return result.substring(0, maxLength);
}
