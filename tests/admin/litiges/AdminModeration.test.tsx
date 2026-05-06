/**
 * CP-LITIGES-7b-2 — Tests front AdminModeration (refonte UI litiges).
 *
 * Tests unitaires + composants (React Testing Library + vitest).
 * Scope :
 *   1. Pure helpers (rangGravite, couleurBadgeCategorie, alerteTresorerie,
 *      joursDepuis, filtrerEtTrier).
 *   2. LitigesFilters : état, onChange, bouton reset.
 *   3. LitigesList : tri gravité, badges colorés, alerte trésorerie,
 *      badge "Informatif" masque le bouton Résoudre.
 *
 * Le test évite de monter AdminModeration complet (dépend de Supabase +
 * LayoutAdmin). Les sous-composants testés portent l'essentiel de la
 * logique introduite par CP7b-2.
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';

import {
  alerteTresorerie,
  couleurBadgeCategorie,
  FILTRES_DEFAUT,
  joursDepuis,
  rangGravite,
  type FiltresLitiges,
  type LitigeEnrichi,
} from '@/components/admin/litiges/types';
import { LitigesFilters } from '@/components/admin/litiges/LitigesFilters';
import {
  LitigesList,
  filtrerEtTrier,
} from '@/components/admin/litiges/LitigesList';

const isoDepuisJours = (j: number): string =>
  new Date(Date.now() - j * 24 * 60 * 60 * 1000).toISOString();

const makeLitige = (p: Partial<LitigeEnrichi>): LitigeEnrichi => ({
  id: p.id ?? 'id-' + Math.random().toString(36).slice(2, 8),
  motif: p.motif ?? 'Motif test',
  reponse: null,
  statut: p.statut ?? 'OUVERT',
  cree_le: p.cree_le ?? new Date().toISOString(),
  soignant_id: 'sg-1',
  etablissement_id: 'et-1',
  mission_id: 'mi-1',
  initie_par: 'SOIGNANT',
  resolution: null,
  resolu_le: null,
  type_litige: p.type_litige ?? null,
  categorie_litige: p.categorie_litige ?? null,
  est_informatif: p.est_informatif ?? false,
  montant_tresorerie_bloquee: p.montant_tresorerie_bloquee ?? null,
  facture_id: null,
  soignant: null,
  etablissement: null,
  mission: null,
  ...p,
});

// ─────────────────────────────────────────────────────────────
// Helpers purs
// ─────────────────────────────────────────────────────────────

describe('types — rangGravite', () => {
  it('SECURITE_DANGER = rang 1', () => {
    expect(rangGravite({ type_litige: 'SECURITE_DANGER' })).toBe(1);
  });
  it('COMPORTEMENT_* = rang 2', () => {
    expect(rangGravite({ type_litige: 'COMPORTEMENT_SOIGNANT' })).toBe(2);
    expect(rangGravite({ type_litige: 'COMPORTEMENT_ETABLISSEMENT' })).toBe(2);
    expect(rangGravite({ categorie_litige: 'COMPORTEMENT' })).toBe(2);
  });
  it('NON_PAIEMENT avant reste FINANCIER', () => {
    expect(
      rangGravite({ type_litige: 'NON_PAIEMENT', categorie_litige: 'FINANCIER' }),
    ).toBe(3);
    expect(
      rangGravite({
        type_litige: 'DESACCORD_MONTANT_FACTURE',
        categorie_litige: 'FINANCIER',
      }),
    ).toBe(4);
  });
  it('PRESENCE=5, CONDITIONS=6, AUTRE=7', () => {
    expect(rangGravite({ categorie_litige: 'PRESENCE' })).toBe(5);
    expect(rangGravite({ categorie_litige: 'CONDITIONS' })).toBe(6);
    expect(rangGravite({ categorie_litige: 'AUTRE' })).toBe(7);
    expect(rangGravite({})).toBe(7);
  });
});

describe('types — couleurBadgeCategorie', () => {
  it('rouge pour SECURITE_DANGER et COMPORTEMENT', () => {
    expect(couleurBadgeCategorie(null, 'SECURITE_DANGER')).toBe('rouge');
    expect(couleurBadgeCategorie('COMPORTEMENT', null)).toBe('rouge');
  });
  it('orange/jaune/vert/gris selon catégorie', () => {
    expect(couleurBadgeCategorie('FINANCIER', null)).toBe('orange');
    expect(couleurBadgeCategorie('PRESENCE', null)).toBe('jaune');
    expect(couleurBadgeCategorie('CONDITIONS', null)).toBe('vert');
    expect(couleurBadgeCategorie('AUTRE', null)).toBe('gris');
    expect(couleurBadgeCategorie(null, null)).toBe('gris');
  });
});

describe('types — alerteTresorerie', () => {
  it('alerte TRUE si > 5 jours ET > 500 €', () => {
    expect(
      alerteTresorerie({
        cree_le: isoDepuisJours(10),
        montant_tresorerie_bloquee: 1000,
      }),
    ).toBe(true);
  });
  it('pas d alerte si <= 5 jours', () => {
    expect(
      alerteTresorerie({
        cree_le: isoDepuisJours(3),
        montant_tresorerie_bloquee: 10000,
      }),
    ).toBe(false);
  });
  it('pas d alerte si <= 500 €', () => {
    expect(
      alerteTresorerie({
        cree_le: isoDepuisJours(30),
        montant_tresorerie_bloquee: 500,
      }),
    ).toBe(false);
  });
  it('0 € → pas d alerte', () => {
    expect(
      alerteTresorerie({
        cree_le: isoDepuisJours(30),
        montant_tresorerie_bloquee: 0,
      }),
    ).toBe(false);
  });
});

describe('types — joursDepuis', () => {
  it('retourne 0 pour null / undefined', () => {
    expect(joursDepuis(null)).toBe(0);
    expect(joursDepuis(undefined)).toBe(0);
  });
  it('retourne ~N jours pour date passée', () => {
    const j = joursDepuis(isoDepuisJours(7));
    expect(j).toBeGreaterThanOrEqual(6);
    expect(j).toBeLessThanOrEqual(8);
  });
});

// ─────────────────────────────────────────────────────────────
// filtrerEtTrier (logique cœur de la liste)
// ─────────────────────────────────────────────────────────────

describe('filtrerEtTrier', () => {
  const jeu: LitigeEnrichi[] = [
    makeLitige({
      id: 'autre',
      type_litige: 'AUTRE',
      categorie_litige: 'AUTRE',
      cree_le: isoDepuisJours(1),
    }),
    makeLitige({
      id: 'secu',
      type_litige: 'SECURITE_DANGER',
      categorie_litige: 'CONDITIONS',
      cree_le: isoDepuisJours(2),
    }),
    makeLitige({
      id: 'fin',
      type_litige: 'DESACCORD_MONTANT_FACTURE',
      categorie_litige: 'FINANCIER',
      montant_tresorerie_bloquee: 800,
      cree_le: isoDepuisJours(10),
    }),
    makeLitige({
      id: 'non_paie',
      type_litige: 'NON_PAIEMENT',
      categorie_litige: 'FINANCIER',
      montant_tresorerie_bloquee: 10000,
      cree_le: isoDepuisJours(15),
    }),
    makeLitige({
      id: 'pres',
      type_litige: 'ABSENCE_SOIGNANT',
      categorie_litige: 'PRESENCE',
      statut: 'EN_MEDIATION',
    }),
  ];

  it('tri GRAVITE : SECURITE_DANGER → COMPORTEMENT → NON_PAIEMENT → FINANCIER → PRESENCE → AUTRE', () => {
    const sorted = filtrerEtTrier(jeu, { ...FILTRES_DEFAUT, tri: 'GRAVITE' });
    expect(sorted.map((l) => l.id)).toEqual([
      'secu',
      'non_paie',
      'fin',
      'pres',
      'autre',
    ]);
  });

  it('tri TRESORERIE : montant DESC, fallback gravité', () => {
    const sorted = filtrerEtTrier(jeu, { ...FILTRES_DEFAUT, tri: 'TRESORERIE' });
    expect(sorted[0].id).toBe('non_paie');
    expect(sorted[1].id).toBe('fin');
  });

  it('filtre type_litige (AND)', () => {
    const sorted = filtrerEtTrier(jeu, {
      ...FILTRES_DEFAUT,
      type_litige: 'NON_PAIEMENT',
    });
    expect(sorted).toHaveLength(1);
    expect(sorted[0].id).toBe('non_paie');
  });

  it('filtre categorie_litige + statut combinés (AND)', () => {
    const sorted = filtrerEtTrier(jeu, {
      ...FILTRES_DEFAUT,
      categorie_litige: 'FINANCIER',
      statut: 'OUVERT',
    });
    expect(sorted.map((l) => l.id).sort()).toEqual(['fin', 'non_paie']);
  });

  it('filtre statut EN_MEDIATION exclut les autres', () => {
    const sorted = filtrerEtTrier(jeu, {
      ...FILTRES_DEFAUT,
      statut: 'EN_MEDIATION',
    });
    expect(sorted).toHaveLength(1);
    expect(sorted[0].id).toBe('pres');
  });
});

// ─────────────────────────────────────────────────────────────
// LitigesFilters (composant)
// ─────────────────────────────────────────────────────────────

describe('LitigesFilters', () => {
  it('bouton Reset filtres rappelle onChange avec FILTRES_DEFAUT', () => {
    const onChange = vi.fn();
    const filtresModifies: FiltresLitiges = {
      type_litige: 'NON_PAIEMENT',
      categorie_litige: 'FINANCIER',
      statut: 'OUVERT',
      tri: 'TRESORERIE',
    };
    render(<LitigesFilters filtres={filtresModifies} onChange={onChange} />);
    fireEvent.click(screen.getByRole('button', { name: /Réinitialiser les filtres/i }));
    expect(onChange).toHaveBeenCalledWith(FILTRES_DEFAUT);
  });

  it('rend 4 selects aria-labellisés', () => {
    render(<LitigesFilters filtres={FILTRES_DEFAUT} onChange={() => {}} />);
    expect(screen.getByLabelText(/Filtre type de litige/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Filtre catégorie/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Filtre statut/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/^Tri$/i)).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────
// LitigesList (composant)
// ─────────────────────────────────────────────────────────────

describe('LitigesList', () => {
  it('affiche les cards dans l ordre gravité (SECURITE_DANGER en tête)', () => {
    const litiges: LitigeEnrichi[] = [
      makeLitige({ id: 'a', type_litige: 'AUTRE', categorie_litige: 'AUTRE' }),
      makeLitige({
        id: 'b',
        type_litige: 'SECURITE_DANGER',
        categorie_litige: 'CONDITIONS',
      }),
    ];
    render(
      <LitigesList
        litiges={litiges}
        filtres={FILTRES_DEFAUT}
        onOpenPreuves={() => {}}
        onOpenResolution={() => {}}
      />,
    );
    const cards = screen.getAllByTestId('litige-card');
    expect(cards).toHaveLength(2);
    expect(cards[0].getAttribute('data-litige-id')).toBe('b');
    expect(cards[0].getAttribute('data-gravite')).toBe('1');
    expect(cards[1].getAttribute('data-litige-id')).toBe('a');
  });

  it('badge coloré rouge pour SECURITE_DANGER, orange pour FINANCIER', () => {
    const litiges: LitigeEnrichi[] = [
      makeLitige({
        id: 'secu',
        type_litige: 'SECURITE_DANGER',
        categorie_litige: 'CONDITIONS',
      }),
      makeLitige({
        id: 'fin',
        type_litige: 'DESACCORD_MONTANT_FACTURE',
        categorie_litige: 'FINANCIER',
      }),
    ];
    render(
      <LitigesList
        litiges={litiges}
        filtres={FILTRES_DEFAUT}
        onOpenPreuves={() => {}}
        onOpenResolution={() => {}}
      />,
    );
    const cards = screen.getAllByTestId('litige-card');
    const badgeSecu = within(cards[0]).getByTestId('badge-gravite');
    const badgeFin = within(cards[1]).getByTestId('badge-gravite');
    expect(badgeSecu.getAttribute('data-couleur')).toBe('rouge');
    expect(badgeFin.getAttribute('data-couleur')).toBe('orange');
  });

  it('alerte trésorerie affichée si > 5 j et > 500 €', () => {
    const litiges: LitigeEnrichi[] = [
      makeLitige({
        id: 'alerte',
        type_litige: 'NON_PAIEMENT',
        categorie_litige: 'FINANCIER',
        cree_le: isoDepuisJours(10),
        montant_tresorerie_bloquee: 1200,
      }),
      makeLitige({
        id: 'neutre',
        type_litige: 'DESACCORD_MONTANT_FACTURE',
        categorie_litige: 'FINANCIER',
        cree_le: isoDepuisJours(2),
        montant_tresorerie_bloquee: 100,
      }),
    ];
    render(
      <LitigesList
        litiges={litiges}
        filtres={{ ...FILTRES_DEFAUT, tri: 'TRESORERIE' }}
        onOpenPreuves={() => {}}
        onOpenResolution={() => {}}
      />,
    );
    const cellAlerte = screen.getAllByTestId('tresorerie-cell');
    expect(cellAlerte[0].getAttribute('data-alerte')).toBe('1');
    expect(cellAlerte[1].getAttribute('data-alerte')).toBe('0');
  });

  it('litige est_informatif → badge "Informatif" + pas de bouton Résoudre', () => {
    const litiges: LitigeEnrichi[] = [
      makeLitige({
        id: 'info',
        type_litige: 'AUTRE',
        categorie_litige: 'AUTRE',
        est_informatif: true,
      }),
    ];
    render(
      <LitigesList
        litiges={litiges}
        filtres={FILTRES_DEFAUT}
        onOpenPreuves={() => {}}
        onOpenResolution={() => {}}
      />,
    );
    expect(screen.getByTestId('badge-informatif')).toBeInTheDocument();
    expect(
      screen.queryByRole('button', { name: /Résoudre litige info/i }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: /Voir preuves litige info/i }),
    ).toBeInTheDocument();
  });

  it('onOpenPreuves + onOpenResolution déclenchés au clic', () => {
    const onPreuves = vi.fn();
    const onResolution = vi.fn();
    const litiges = [
      makeLitige({
        id: 'x',
        type_litige: 'NON_PAIEMENT',
        categorie_litige: 'FINANCIER',
      }),
    ];
    render(
      <LitigesList
        litiges={litiges}
        filtres={FILTRES_DEFAUT}
        onOpenPreuves={onPreuves}
        onOpenResolution={onResolution}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: /Voir preuves litige x/i }));
    fireEvent.click(screen.getByRole('button', { name: /Résoudre litige x/i }));
    expect(onPreuves).toHaveBeenCalledTimes(1);
    expect(onResolution).toHaveBeenCalledTimes(1);
    expect(onPreuves.mock.calls[0][0].id).toBe('x');
  });

  it('liste vide si aucun litige ne matche les filtres', () => {
    const litiges = [
      makeLitige({ id: '1', categorie_litige: 'PRESENCE' }),
    ];
    render(
      <LitigesList
        litiges={litiges}
        filtres={{ ...FILTRES_DEFAUT, categorie_litige: 'FINANCIER' }}
        onOpenPreuves={() => {}}
        onOpenResolution={() => {}}
      />,
    );
    expect(screen.getByTestId('litiges-empty')).toBeInTheDocument();
  });
});
