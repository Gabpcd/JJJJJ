import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const sales = readFileSync('src/pages/admin/AdminSales.tsx', 'utf8');

function entre(debut: string, fin: string): string {
  const indexDebut = sales.indexOf(debut);
  const indexFin = sales.indexOf(fin, indexDebut + debut.length);
  expect(indexDebut).toBeGreaterThanOrEqual(0);
  expect(indexFin).toBeGreaterThan(indexDebut);
  return sales.slice(indexDebut, indexFin);
}

describe('CRM admin à grande échelle', () => {
  it('charge les contacts par pages bornées et séparées par cible', () => {
    expect(sales).toContain('const CONTACTS_PAGE_SIZE = 100');
    expect(sales).toContain("requeteContacts('SOIGNANT', paginationContacts.SOIGNANT.page)");
    expect(sales).toContain("requeteContacts('ETABLISSEMENT', paginationContacts.ETABLISSEMENT.page)");
    expect(sales).toContain('.range(from, from + CONTACTS_PAGE_SIZE - 1)');
    expect(sales).toContain('contact(s) affiché(s) sur cette page');
    expect(sales).toContain('Page {pagination.page}/{totalPages}');
    expect(sales).not.toMatch(/from\('sales_contacts' as any\)\.select\('\*'\)/);
  });

  it('distingue une réponse positive d’une inscription explicite sans activer de contact automatique', () => {
    const miseAJourReponse = entre('const majReponseContact', 'const toggleARappeler');
    expect(miseAJourReponse).toContain("if (c.statut !== 'INSCRIT') patch.statut = 'CONTACTE'");
    expect(miseAJourReponse).toContain("patch.derniere_action_type = 'INTERESSE'");
    expect(miseAJourReponse).toContain('patch.ne_plus_contacter = false');
    expect(miseAJourReponse).toContain('patch.sequence_active = false');
    expect(miseAJourReponse).toContain('patch.prochaine_action_le = null');
    expect(miseAJourReponse).not.toContain("patch.statut = 'INSCRIT'");
    expect(sales).toContain("const STATUTS_CONTACT = ['PROSPECT', 'CONTACTE', 'RELANCE', 'INSCRIT', 'PERDU']");
  });

  it('dédoublonne les soignants via le RPC canonique avant de les placer dans le CRM', () => {
    const prospectionSoignants = entre('function ProspectionSoignants', 'function badgeStatutAnnuaire');
    expect(prospectionSoignants).toContain("supabase.rpc('fn_admin_sourcing_ajouter_crm'");
    expect(prospectionSoignants).toContain("p_cible: 'SOIGNANT'");
    expect(prospectionSoignants).toContain('p_prospect_id: pr.cle');
    expect(prospectionSoignants).not.toContain("from('sales_contacts' as any).insert");
  });

  it('dédoublonne aussi les établissements avant tout ajout ou suivi d’appel', () => {
    const prospectionEtablissements = entre('function ProspectionEtab', 'function EnvoiMasseBar');
    expect(prospectionEtablissements).toContain("supabase.rpc('fn_admin_sourcing_ajouter_crm'");
    expect(prospectionEtablissements).toContain("p_cible: 'ETABLISSEMENT'");
    expect(prospectionEtablissements).toContain('p_prospect_id: pr.finess');
    expect(prospectionEtablissements).toContain(".eq('id', contactId)");
    expect(prospectionEtablissements).not.toContain("from('sales_contacts' as any).upsert");
    expect(prospectionEtablissements).not.toContain("from('sales_contacts' as any).insert");
  });

  it('présente fidèlement la couverture Annuaire Santé et RPPS', () => {
    expect(sales).toContain('Base officielle Annuaire Santé / RPPS');
    expect(sales).toContain('salariés, libéraux et étudiants');
    expect(sales).toContain("rattachement à une structure lorsqu'il est publié");
    expect(sales).not.toContain('Annuaire Santé (CNAM)');
    expect(sales).not.toContain("Les salariés n'apparaissent dans aucune base publique");
  });
});
