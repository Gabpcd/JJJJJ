import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { getEmailDeliveryStatus } from '@/lib/adminEmailDelivery';
import { libellePerimetreRapport } from '@/pages/admin/AdminFacturation';
import { statutOperationCritique } from '@/components/admin/FinancialOperationsMonitor';

describe('sécurité des retours send-email admin', () => {
  it('ne compte comme envoyé qu’un succès explicite non neutralisé', () => {
    expect(getEmailDeliveryStatus({ success: true }, null)).toBe('sent');
    expect(getEmailDeliveryStatus({ success: true, skipped: true }, null)).toBe('skipped');
    expect(getEmailDeliveryStatus({ success: true, test_skipped: true }, null)).toBe('skipped');
    expect(getEmailDeliveryStatus({ success: true, pending: true }, null)).toBe('pending');
  });

  it('échoue fermé sur erreur, payload ambigu ou succès false', () => {
    expect(getEmailDeliveryStatus({ success: true }, new Error('réseau'))).toBe('failed');
    expect(getEmailDeliveryStatus(undefined, null)).toBe('failed');
    expect(getEmailDeliveryStatus({ success: false }, null)).toBe('failed');
    expect(getEmailDeliveryStatus({ error: 'fournisseur indisponible' }, null)).toBe('failed');
  });
});

describe('rapport et suivi financier admin', () => {
  it('décrit le périmètre réellement affiché', () => {
    expect(libellePerimetreRapport('TOUS', '')).toBe('tous statuts');
    expect(libellePerimetreRapport('PAYEE', 'Clinique')).toBe('statut Payée · recherche « Clinique »');
  });

  it('charge les champs signés et interdit les relances sur les avoirs', () => {
    const impayees = readFileSync('src/pages/admin/AdminImpayees.tsx', 'utf8');
    const finances = readFileSync('src/pages/admin/AdminFinances.tsx', 'utf8');
    const facturation = readFileSync('src/pages/admin/AdminFacturation.tsx', 'utf8');

    expect(impayees).toContain(".eq('type_document', 'FACTURE')");
    expect(finances).toContain('montant_signe, type_document');
    expect(facturation).toContain('montant_signe, type_document');
    expect(finances).toContain('filter(estFactureRelancable)');
  });

  it('identifie les états financiers nécessitant une alerte', () => {
    expect(statutOperationCritique('ECHOUE')).toBe(true);
    expect(statutOperationCritique('ECHEC')).toBe(true);
    expect(statutOperationCritique('DISPUTE')).toBe(true);
    expect(statutOperationCritique('EN_ATTENTE')).toBe(false);
  });
});
