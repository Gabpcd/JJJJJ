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
  it.each([
    ['LIBERAL_FACTURE_REQUISE', 'Pour une mission libérale, ouvrez Facturation et choisissez la facture à régler.'],
    ['PAIEMENT_HISTORIQUE_A_RAPPROCHER', 'Un paiement antérieur doit être rapproché de sa facture avant de déclarer un nouveau règlement.'],
    ['PAIEMENT_STRIPE_EN_COURS', 'Un règlement Stripe est déjà engagé pour cette facture. Consultez son état dans l’historique avant toute autre action.'],
    ['CONNECT_REFUND_RECONCILIATION_REQUIRED', 'Un remboursement est lié à cette tentative de paiement. Son rapprochement doit être terminé avant tout nouveau règlement de cette facture.'],
    ['PAIEMENT_FACTURE_DEJA_DECLARE', 'Un règlement a déjà été déclaré pour cette facture. Consultez l’historique des paiements.'],
    ['AVOIR_A_RAPPROCHER', 'Cette facture possède un avoir. Contactez l’assistance pour rapprocher son règlement avant de payer.'],
    ['MONTANT_FACTURE_INCOHERENT', 'Le règlement ne correspond pas à la facture sélectionnée. Rechargez la facturation pour vérifier ses informations.'],
    ['PERIODE_NON_PAYABLE', 'Cette période n’est pas encore payable. Consultez les échéances dans Facturation.'],
    ['DECLARATION_FACTURE_INVALIDE', 'La déclaration ne peut pas être enregistrée pour cette facture. Rechargez la facturation pour vérifier son état.'],
    ['PAIEMENT_FINANCIER_IMMUABLE', 'Les informations financières d’un paiement existant ne peuvent pas être réattribuées. Contactez l’assistance pour son rapprochement.'],
    ['PREUVE_STRIPE_REQUISE', 'Le règlement Stripe ne peut pas encore être vérifié. Consultez l’historique et contactez l’assistance avant tout nouveau paiement.'],
    ['PAIEMENT_STRIPE_REJEU_INCOHERENT', 'Le règlement Stripe ne correspond pas aux informations déjà enregistrées. Contactez l’assistance avant tout nouveau paiement.'],
  ])('oriente le refus financier %s sans exposer un code technique', (code, message) => {
    expect(extraireMessageErreur({ code })).toBe(message);
    expect(extraireMessageErreur({ error: code })).toBe(message);
    expect(extraireMessageErreur({ message: code })).toBe(message);
    expect(extraireMessageErreur({ code: '23514', message: code })).toBe(message);
  });

  it('utilise le code du refus courant même si un ancien message figure dans la réponse', () => {
    expect(extraireMessageErreur({ code: 'PAIEMENT_STRIPE_EN_COURS', message: 'PAIEMENT_HISTORIQUE_A_RAPPROCHER' }))
      .toBe('Un règlement Stripe est déjà engagé pour cette facture. Consultez son état dans l’historique avant toute autre action.');
  });

  it('should return empty string for null/undefined', () => {
    expect(extraireMessageErreur(null)).toBe('');
    expect(extraireMessageErreur(undefined)).toBe('');
  });

  it('should translate Invalid login credentials', () => {
    expect(extraireMessageErreur({ message: 'Invalid login credentials' }))
      .toBe('Email ou mot de passe incorrect.');
  });

  it.each([
    { code: 'PGRST301', message: 'JWT expired' },
    { code: 'PGRST301', message: 'JWSError JWSInvalidSignature' },
    { message: 'jwt expired' },
  ])('invite en français à se reconnecter après un refus JWT : %j', (error) => {
    expect(extraireMessageErreur(error)).toBe(
      'Votre session a expiré ou n’est plus valide. Reconnectez-vous puis réessayez.',
    );
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

  it.each(['Load failed', 'TypeError: Load failed'])('explique une coupure réseau Safari : %s', (message) => {
    expect(extraireMessageErreur({ message })).toBe('Erreur de connexion. Vérifiez votre accès internet.');
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
