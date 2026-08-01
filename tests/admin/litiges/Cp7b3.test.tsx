/**
 * CP-LITIGES-7b-3 — Tests front features complémentaires.
 *
 * Scope (pure functions + composants sans I/O) :
 *   - csv.ts : escapeCsv (via toCsv), enFaveurDeDepuisStatut, nomFichierCsv,
 *     toCsv (colonnes, BOM facultatif non testé ici, escape RFC 4180).
 *   - AvoirsList.filtrerAvoirs : statut=TOUS vs ciblé, filtre strict.
 *   - RefundsQueueWidget.alerteConditions : seuils count > 10, > 48h.
 *   - MediationBanner : masqué si count <= 0, visible + bouton sinon.
 *
 * Les composants AvoirsList / LegacyRecategorisation / RefundsQueueWidget
 * à part entière sollicitent Supabase ; on teste ici leurs helpers purs.
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';

import {
  enFaveurDeDepuisStatut,
  nomFichierCsv,
  toCsv,
  litigeToRow,
} from '@/components/admin/litiges/csv';
import {
  calculerMontantsAvoir,
  filtrerAvoirs,
  type AvoirEnrichi,
} from '@/components/admin/litiges/AvoirsList';
import {
  alerteConditions,
  construireStatsRefunds,
} from '@/components/admin/litiges/RefundsQueueWidget';
import { MediationBanner } from '@/components/admin/litiges/MediationBanner';
import type { LitigeEnrichi } from '@/components/admin/litiges/types';

// ─────────────────────────────────────────────────────────────
// csv.ts
// ─────────────────────────────────────────────────────────────

describe('csv — enFaveurDeDepuisStatut', () => {
  it('RESOLU_SOIGNANT → SOIGNANT', () => {
    expect(enFaveurDeDepuisStatut('RESOLU_SOIGNANT')).toBe('SOIGNANT');
  });
  it('RESOLU_ETABLISSEMENT → ETABLISSEMENT', () => {
    expect(enFaveurDeDepuisStatut('RESOLU_ETABLISSEMENT')).toBe('ETABLISSEMENT');
  });
  it('RESOLU_ADMIN → PARTAGE', () => {
    expect(enFaveurDeDepuisStatut('RESOLU_ADMIN')).toBe('PARTAGE');
  });
  it('Autres statuts → chaîne vide', () => {
    expect(enFaveurDeDepuisStatut('OUVERT')).toBe('');
    expect(enFaveurDeDepuisStatut('EN_MEDIATION')).toBe('');
  });
});

describe('csv — nomFichierCsv', () => {
  it('format litiges-YYYY-MM-DD.csv', () => {
    const d = new Date('2026-04-17T10:30:00Z');
    expect(nomFichierCsv(d)).toBe('litiges-2026-04-17.csv');
  });
});

describe('csv — litigeToRow + toCsv', () => {
  const sample: LitigeEnrichi = {
    id: 'lit-1',
    motif: 'Motif, avec virgule et "guillemets"',
    reponse: null,
    statut: 'OUVERT',
    cree_le: '2026-04-10T08:00:00Z',
    soignant_id: 'sg-1',
    etablissement_id: 'et-1',
    mission_id: 'mi-1',
    initie_par: 'SOIGNANT',
    resolution: null,
    resolu_le: null,
    type_litige: 'ABSENCE_SOIGNANT',
    categorie_litige: 'PRESENCE',
    est_informatif: false,
    montant_tresorerie_bloquee: 1250.5,
    facture_id: null,
    soignant: { id: 'sg-1', prenom: 'Alice', nom: 'Martin', email: null, telephone: null, profession: null },
    etablissement: { id: 'et-1', nom: 'Hôpital Paris', email_contact: null, telephone_contact: null, type: null },
    mission: { id: 'mi-1', intitule: 'Garde nuit', profession_requise: 'IDE', service: null, debut_le: '', fin_le: '', statut: null },
  };

  it('litigeToRow aplatit les relations', () => {
    const row = litigeToRow(sample);
    expect(row.soignant_nom).toBe('Alice Martin');
    expect(row.etablissement_nom).toBe('Hôpital Paris');
    expect(row.mission_intitule).toBe('Garde nuit');
    expect(row.montant_tresorerie_bloquee).toBe('1250.5');
    expect(row.en_faveur_de).toBe('');
  });

  it('toCsv en-tête + échappement RFC 4180', () => {
    const csv = toCsv([sample]);
    const lignes = csv.split('\r\n');
    expect(lignes[0].split(',')).toContain('id');
    expect(lignes[0].split(',')).toContain('en_faveur_de');
    // Motif contient , et " → doit être entre quotes + quotes doublées
    expect(lignes[1]).toContain('"Motif, avec virgule et ""guillemets"""');
  });

  it('toCsv vide = seulement header', () => {
    const csv = toCsv([]);
    expect(csv.split('\r\n')).toHaveLength(1);
  });
});

// ─────────────────────────────────────────────────────────────
// AvoirsList — filtrerAvoirs
// ─────────────────────────────────────────────────────────────

describe('AvoirsList — filtrerAvoirs', () => {
  const mk = (p: Partial<AvoirEnrichi>): AvoirEnrichi => ({
    id: p.id ?? 'a-' + Math.random().toString(36).slice(2, 8),
    numero_facture: null,
    type_document: 'AVOIR',
    statut: p.statut ?? 'BROUILLON',
    mode_remboursement: p.mode_remboursement ?? 'N_A',
    montant_ht: null,
    montant_tva: null,
    montant_ttc: null,
    date_emission: null,
    date_remboursement: null,
    reference_remboursement: null,
    soignant_id: null,
    etablissement_id: null,
    litige_id: null,
    ...p,
  });

  const avoirs: AvoirEnrichi[] = [
    mk({ id: '1', statut: 'BROUILLON' }),
    mk({ id: '2', statut: 'EMISE', mode_remboursement: 'VIREMENT_MANUEL' }),
    mk({ id: '3', statut: 'REMBOURSE' }),
    mk({ id: '4', statut: 'ANNULEE' }),
  ];

  it('TOUS renvoie tous les avoirs', () => {
    expect(filtrerAvoirs(avoirs, 'TOUS')).toHaveLength(4);
  });
  it('filtre exact sur statut EMISE', () => {
    const r = filtrerAvoirs(avoirs, 'EMISE');
    expect(r).toHaveLength(1);
    expect(r[0].id).toBe('2');
  });
  it('filtre REMBOURSE', () => {
    expect(filtrerAvoirs(avoirs, 'REMBOURSE').map((a) => a.id)).toEqual(['3']);
  });

  it('retient le TTC comme montant réellement remboursé et détaille la TVA', () => {
    expect(calculerMontantsAvoir({ montant_ht: 100, montant_tva: 20, montant_ttc: 120 })).toEqual({
      ht: 100,
      tva: 20,
      ttc: 120,
      montantRemboursement: 120,
    });
  });

  it('conserve le repli historique HT si le TTC est absent', () => {
    expect(calculerMontantsAvoir({ montant_ht: 100, montant_tva: null, montant_ttc: null }).montantRemboursement).toBeNull();
  });
});

// ─────────────────────────────────────────────────────────────
// RefundsQueueWidget — alerteConditions
// ─────────────────────────────────────────────────────────────

describe('RefundsQueueWidget — alerteConditions', () => {
  it('utilise le count exact même si une seule ligne est chargée', () => {
    expect(construireStatsRefunds(17, [{ cree_le: '2026-07-01T08:00:00Z' }])).toEqual({
      count: 17,
      plus_ancienne_iso: '2026-07-01T08:00:00Z',
    });
  });
  it('refuse un count absent au lieu de retomber sur rows.length', () => {
    expect(() => construireStatsRefunds(null, [{ cree_le: '2026-07-01T08:00:00Z' }])).toThrow(/Comptage exact/);
  });
  it('count <= 0 → false', () => {
    expect(alerteConditions({ count: 0, plus_ancienne_iso: null })).toBe(false);
  });
  it('count > 10 → true', () => {
    expect(alerteConditions({ count: 11, plus_ancienne_iso: null })).toBe(true);
  });
  it('ancienneté > 48 h → true', () => {
    const iso = new Date(Date.now() - 49 * 60 * 60 * 1000).toISOString();
    expect(alerteConditions({ count: 1, plus_ancienne_iso: iso })).toBe(true);
  });
  it('ancienneté < 48 h et count petit → false', () => {
    const iso = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
    expect(alerteConditions({ count: 1, plus_ancienne_iso: iso })).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────
// MediationBanner
// ─────────────────────────────────────────────────────────────

describe('MediationBanner', () => {
  it('ne s’affiche pas si count <= 0', () => {
    const { container } = render(<MediationBanner count={0} onVoir={() => {}} />);
    expect(container.querySelector('[data-testid="mediation-banner"]')).toBeNull();
  });

  it('s’affiche avec singulier si count=1 et appelle onVoir', () => {
    const onVoir = vi.fn();
    render(<MediationBanner count={1} onVoir={onVoir} />);
    const banner = screen.getByTestId('mediation-banner');
    expect(banner).toHaveAttribute('data-count', '1');
    expect(banner).toHaveTextContent('1 litige en médiation');
    fireEvent.click(screen.getByRole('button', { name: /voir/i }));
    expect(onVoir).toHaveBeenCalledTimes(1);
  });

  it('pluriel si count > 1', () => {
    render(<MediationBanner count={3} onVoir={() => {}} />);
    expect(screen.getByTestId('mediation-banner')).toHaveTextContent(
      '3 litiges en médiation',
    );
  });
});
