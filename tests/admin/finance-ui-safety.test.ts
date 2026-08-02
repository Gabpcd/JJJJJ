import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { getEmailDeliveryStatus } from '@/lib/adminEmailDelivery';
import { libellePerimetreRapport } from '@/pages/admin/AdminFacturation';
import { estFactureProduction } from '@/lib/adminInvoiceScope';
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
    expect(libellePerimetreRapport('TOUS', '')).toBe('production uniquement · tous statuts');
    expect(libellePerimetreRapport('PAYEE', 'Clinique')).toBe('production uniquement · statut Payée · recherche « Clinique »');
  });

  it('échoue fermé pour le périmètre comptable de production', () => {
    expect(estFactureProduction({ etablissements: { est_compte_test: false } })).toBe(true);
    expect(estFactureProduction({ etablissements: { est_compte_test: true } })).toBe(false);
    expect(estFactureProduction({ etablissements: { est_compte_test: null } })).toBe(false);
    expect(estFactureProduction({ etablissements: null })).toBe(false);
    expect(estFactureProduction({})).toBe(false);
  });

  it('charge les champs signés et interdit les relances sur les avoirs', () => {
    const impayees = readFileSync('src/pages/admin/AdminImpayees.tsx', 'utf8');
    const finances = readFileSync('src/pages/admin/AdminFinances.tsx', 'utf8');
    const facturation = readFileSync('src/pages/admin/AdminFacturation.tsx', 'utf8');

    expect(impayees).toContain(".eq('type_document', 'FACTURE')");
    expect(finances).toContain('montant_signe, type_document');
    expect(facturation).toContain('montant_signe, type_document');
    expect(facturation).toContain('etablissements(nom, est_compte_test)');
    expect(facturation).toContain('filtered.filter(estFactureProduction).filter(estDocumentComptabilise)');
    expect(facturation).toContain("estFactureProduction(f) && STATUTS_A_TRAITER.includes(f.statut)");
    expect(facturation).toContain("perimetre === 'TEST' ? 'TEST' : 'PÉRIMÈTRE À VÉRIFIER'");
    const detailMission = readFileSync('src/pages/DetailMission.tsx', 'utf8');
    expect(detailMission).toContain('montant_commission_ht, montant_commission_tva, montant_commission_ttc');
    expect(detailMission).toContain('taux_commission_fige, taux_commission, commission_facturee');
    expect(finances).toContain('filter(facture => estFactureRelancable(facture))');
  });

  it('exclut les comptes test et les factures non échues des urgences admin', () => {
    const impayees = readFileSync('src/pages/admin/AdminImpayees.tsx', 'utf8');
    const finances = readFileSync('src/pages/admin/AdminFinances.tsx', 'utf8');
    const dashboard = readFileSync('src/pages/admin/AdminDashboard.tsx', 'utf8');
    const facturation = readFileSync('src/pages/admin/AdminFacturation.tsx', 'utf8');

    expect(finances).toContain('est_compte_test');
    expect(finances).toContain('missionsProduction');
    expect(impayees).toContain('f.etablissement?.est_compte_test === false');
    expect(impayees).toContain('estFactureRelancable(f)');
    expect(dashboard).toContain("etablissements!inner(nom, est_compte_test)");
    expect(dashboard).toContain(".lt('date_echeance', aujourdhuiIso)");
    expect(dashboard).toContain(".eq('etablissements.est_compte_test', false)");

    const fec = readFileSync(
      'supabase/migrations/20260801230100_exclure_donnees_test_export_fec.sql',
      'utf8',
    );
    expect(fec).toContain('e.est_compte_test IS FALSE');
    expect(fec).toContain("f.statut NOT IN ('BROUILLON', 'ANNULEE')");
    expect(fec).toContain('"JournalCode" text');
    expect(fec).toContain('"Idevise" text');
    expect(fec).toContain("'411000'::text");
    expect(fec).toContain("'706000'::text");
    expect(fec).toContain("'445710'::text");
    expect(fec).toContain('CASE WHEN d.est_avoir THEN');
    expect(fec).toContain("AT TIME ZONE 'Europe/Paris'");
    expect(fec).toContain('HT, TVA ou TTC incohérents');
    expect(fec).toContain('pg_catalog.round(pg_catalog.abs(f.montant_ttc), 2) <= 0');
    expect(fec).toContain('NULL::numeric');
    expect(fec).toContain('NULL::text');
    expect(fec).toContain("'VE-' || p_annee::text");

    expect(facturation).toContain('Journal des ventes');
    expect(facturation).toContain('JOURNAL_VENTES_');
    expect(facturation).not.toContain('Exporter FEC');
  });

  it('identifie les états financiers nécessitant une alerte', () => {
    expect(statutOperationCritique('ECHOUE')).toBe(true);
    expect(statutOperationCritique('ECHEC')).toBe(true);
    expect(statutOperationCritique('DISPUTE')).toBe(true);
    expect(statutOperationCritique('EN_ATTENTE')).toBe(false);
  });
});
