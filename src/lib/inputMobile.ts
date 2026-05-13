/**
 * Helpers `inputMode` / `autocomplete` / `enterKeyHint` mobile-friendly.
 * Sprint 8 PR 5 (chantier 5.7).
 *
 * Usage :
 *   <input {...PROPS_INPUT_EMAIL} />
 *   <input {...PROPS_INPUT_TELEPHONE} />
 *   <input {...PROPS_INPUT_OTP} />
 *
 * Combine inputMode + autoComplete + autoCapitalize + spellCheck + enterKeyHint.
 * Active le clavier numérique mobile, désactive l'auto-capitalize sur emails/codes,
 * et affiche la bonne touche entrée selon le contexte.
 */

import type { InputHTMLAttributes } from 'react';

type AttrsInput = Partial<InputHTMLAttributes<HTMLInputElement>>;

export const PROPS_INPUT_EMAIL: AttrsInput = {
  type: 'email',
  inputMode: 'email',
  autoComplete: 'email',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
};

export const PROPS_INPUT_TELEPHONE: AttrsInput = {
  type: 'tel',
  inputMode: 'tel',
  autoComplete: 'tel',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
};

export const PROPS_INPUT_OTP: AttrsInput = {
  type: 'text',
  inputMode: 'numeric',
  autoComplete: 'one-time-code',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'go',
  pattern: '[0-9]*',
};

export const PROPS_INPUT_MONTANT: AttrsInput = {
  type: 'text',
  inputMode: 'decimal',
  autoComplete: 'off',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
};

export const PROPS_INPUT_ENTIER: AttrsInput = {
  type: 'text',
  inputMode: 'numeric',
  autoComplete: 'off',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
  pattern: '[0-9]*',
};

export const PROPS_INPUT_NIR: AttrsInput = {
  type: 'text',
  inputMode: 'numeric',
  autoComplete: 'off',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
  pattern: '[0-9 ]*',
  maxLength: 18,
};

export const PROPS_INPUT_SIRET: AttrsInput = {
  type: 'text',
  inputMode: 'numeric',
  autoComplete: 'off',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
  pattern: '[0-9 ]*',
  maxLength: 17,
};

export const PROPS_INPUT_CODE_POSTAL: AttrsInput = {
  type: 'text',
  inputMode: 'numeric',
  autoComplete: 'postal-code',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
  pattern: '[0-9]*',
  maxLength: 5,
};

export const PROPS_INPUT_RECHERCHE: AttrsInput = {
  type: 'search',
  inputMode: 'search',
  autoComplete: 'off',
  enterKeyHint: 'search',
};

export const PROPS_INPUT_NOM: AttrsInput = {
  type: 'text',
  autoComplete: 'family-name',
  autoCapitalize: 'words',
  spellCheck: false,
  enterKeyHint: 'next',
};

export const PROPS_INPUT_PRENOM: AttrsInput = {
  type: 'text',
  autoComplete: 'given-name',
  autoCapitalize: 'words',
  spellCheck: false,
  enterKeyHint: 'next',
};

export const PROPS_INPUT_MDP: AttrsInput = {
  type: 'password',
  autoComplete: 'current-password',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'go',
};

export const PROPS_INPUT_NOUVEAU_MDP: AttrsInput = {
  type: 'password',
  autoComplete: 'new-password',
  autoCapitalize: 'none',
  spellCheck: false,
  enterKeyHint: 'next',
};
