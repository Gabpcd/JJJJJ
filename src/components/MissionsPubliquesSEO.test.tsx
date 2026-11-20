import { render, screen, cleanup } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { MissionsPubliquesSEO } from './MissionsPubliquesSEO';

const etat = vi.hoisted(() => ({ missions: [] as unknown[] | null, total: 0, loading: false, erreur: null as string | null }));
vi.mock('@/hooks/useMissionsPubliques', () => ({
  useMissionsPubliques: () => ({ ...etat, rechercher: vi.fn() }),
}));

afterEach(cleanup);
const ouvrir = () => render(<MemoryRouter><MissionsPubliquesSEO ville="Lyon" profession="AS" campagne="seo-ville-lyon" /></MemoryRouter>);

describe('MissionsPubliquesSEO', () => {
  it('sans mission : invite à créer un compte, sans promettre de missions à voir', () => {
    Object.assign(etat, { missions: [], total: 0, loading: false, erreur: null });
    ouvrir();
    expect(screen.getByText(/Aucune mission ne correspond à ces critères pour le moment\. Créez votre compte pour retrouver cette recherche/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Créer mon compte et retrouver ma recherche/ })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Voir toutes les missions/ })).not.toBeInTheDocument();
  });

  it('avec des missions : le bouton propose de les voir et de postuler', () => {
    Object.assign(etat, {
      missions: [{ id: 'm1', intitule: 'Aide-soignant de nuit', ville: 'Lyon', code_postal: '69003', debut_le: '2026-12-01T20:00:00Z', fin_le: '2026-12-02T06:00:00Z', taux_horaire_base: 18, est_urgente: false, type_contrat_recherche: 'SALARIE' }],
      total: 1, loading: false, erreur: null,
    });
    ouvrir();
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('1 mission disponible en ce moment');
    expect(screen.getByRole('button', { name: /Voir toutes les missions et postuler/ })).toBeInTheDocument();
    expect(screen.queryByText(/Aucune mission ne correspond/)).not.toBeInTheDocument();
  });

  it('pendant le chargement : ni message d\'absence ni libellé de création de compte', () => {
    Object.assign(etat, { missions: null, total: 0, loading: true, erreur: null });
    ouvrir();
    expect(screen.getByRole('status')).toHaveTextContent('Recherche des missions…');
    expect(screen.queryByText(/Aucune mission ne correspond/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Voir toutes les missions et postuler/ })).toBeInTheDocument();
  });
});
