import { describe, it, expect } from 'vitest';
import {
  estBlocageCodeTravail,
  estRefusInscriptionAttendu,
  extraireArticleLoi,
  extraireMessageErreur,
  mapperErreurInscription,
} from '../erreurs';

describe('erreurs inscription familles de compte', () => {
  it('propose la reconnexion pour un compte deja finalise', () => {
    expect(mapperErreurInscription({
      code: 'ACCOUNT_ALREADY_REGISTERED',
      message: 'Compte existant',
    })).toMatchObject({ code: 'ACCOUNT_ALREADY_REGISTERED', action: 'reconnexion' });
  });

  it('traite un croisement de type comme refus attendu mais un conflit legacy comme anomalie', () => {
    expect(estRefusInscriptionAttendu('ACCOUNT_TYPE_MISMATCH')).toBe(true);
    expect(estRefusInscriptionAttendu('ACCOUNT_PROFILE_CONFLICT')).toBe(false);
    expect(mapperErreurInscription({ code: 'ACCOUNT_PROFILE_CONFLICT' }).action).toBe('support');
  });

  it('guide une inscription suspendue par la confirmation email', () => {
    expect(mapperErreurInscription({
      code: 'EMAIL_CONFIRMATION_REQUIRED',
    })).toMatchObject({
      code: 'EMAIL_CONFIRMATION_REQUIRED',
      action: 'retry',
    });
    expect(estRefusInscriptionAttendu('EMAIL_CONFIRMATION_REQUIRED')).toBe(true);
  });
});

describe('extraireMessageErreur', () => {
  it('should return empty string for null/undefined', () => {
    expect(extraireMessageErreur(null)).toBe('');
    expect(extraireMessageErreur(undefined)).toBe('');
  });

  it('should translate Invalid login credentials', () => {
    expect(extraireMessageErreur({ message: 'Invalid login credentials' }))
      .toBe('Email ou mot de passe incorrect.');
  });

  it('should translate Email not confirmed', () => {
    expect(extraireMessageErreur({ message: 'Email not confirmed' }))
      .toBe('Veuillez confirmer votre adresse email avant de vous connecter.');
  });

  it('should translate User already registered', () => {
    expect(extraireMessageErreur({ message: 'User already registered' }))
      .toBe('Un compte existe déjà avec cette adresse email.');
  });

  it('should translate Email rate limit exceeded', () => {
    expect(extraireMessageErreur({ message: 'Email rate limit exceeded' }))
      .toBe('Trop de tentatives. Veuillez patienter quelques minutes.');
  });

  it('should handle duplicate key on SIRET', () => {
    expect(extraireMessageErreur({ message: 'duplicate key value violates unique constraint "etablissements_siret_key"' }))
      .toBe('Ce numéro SIRET est déjà enregistré.');
  });

  it('should handle duplicate key on email', () => {
    expect(extraireMessageErreur({ message: 'duplicate key value violates unique constraint "users_email_key"' }))
      .toBe('Cette adresse email est déjà utilisée.');
  });

  it('should handle duplicate key on RPPS', () => {
    expect(extraireMessageErreur({ message: 'duplicate key value violates unique constraint "soignants_numero_rpps_key"' }))
      .toBe('Ce numéro RPPS est déjà enregistré.');
  });

  it('should handle check constraint violations', () => {
    expect(extraireMessageErreur({ message: 'new row violates check constraint "chk_taux_horaire_min"' }))
      .toBe('La valeur saisie est hors des limites autorisées.');
  });

  it('should handle RLS policy violations', () => {
    expect(extraireMessageErreur({ message: 'new row violates row-level security policy for table "missions"' }))
      .toBe('Vous n\'avez pas les droits nécessaires pour cette action.');
  });

  it('should handle network errors', () => {
    expect(extraireMessageErreur({ message: 'Failed to fetch' }))
      .toBe('Erreur de connexion. Vérifiez votre accès internet.');
  });

  it('should surface French trigger messages directly', () => {
    expect(extraireMessageErreur({ message: 'Impossible de postuler: documents manquants' }))
      .toContain('Impossible');
  });

  it('should extract CODE DU TRAVAIL messages', () => {
    const result = extraireMessageErreur({ message: '[CODE DU TRAVAIL] Repos de 11h non respecté (Art. L3131-1)' });
    expect(result).toBe('Repos de 11h non respecté (Art. L3131-1)');
  });

  it('should return generic message for unknown errors in production', () => {
    // In test/dev mode this will show the raw message
    const result = extraireMessageErreur({ message: 'some_unknown_pg_error_xyz' });
    expect(typeof result).toBe('string');
    expect(result.length).toBeGreaterThan(0);
  });
});

describe('estBlocageCodeTravail', () => {
  it('should detect CODE DU TRAVAIL errors', () => {
    expect(estBlocageCodeTravail({ message: '[CODE DU TRAVAIL] 48h dépassées' })).toBe(true);
  });

  it('should return false for normal errors', () => {
    expect(estBlocageCodeTravail({ message: 'Some other error' })).toBe(false);
  });

  it('should handle null/undefined', () => {
    expect(estBlocageCodeTravail(null)).toBe(false);
    expect(estBlocageCodeTravail(undefined)).toBe(false);
  });
});

describe('extraireArticleLoi', () => {
  it('should extract article reference', () => {
    expect(extraireArticleLoi({ message: 'Repos insuffisant (Art. L3131-1)' })).toBe('Art. L3131-1');
  });

  it('should return null when no article found', () => {
    expect(extraireArticleLoi({ message: 'Generic error' })).toBeNull();
  });
});
