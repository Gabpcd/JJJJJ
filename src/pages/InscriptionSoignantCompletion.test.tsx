import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import InscriptionSoignantCompletion from './InscriptionSoignantCompletion';

const mocks = vi.hoisted(() => ({
  from: vi.fn(), notifier: vi.fn(),
  user: { id: 'profil-psc-simule' },
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.user, loading: false }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notifier }) }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from } }));
vi.mock('@/hooks/useTypesExerciceAutorises', () => ({
  useTypesExerciceAutorises: () => ({ typesAutorises: ['SALARIE'], uniqueType: 'SALARIE', loading: false, indisponible: false, reessayer: vi.fn() }),
}));
afterEach(() => { cleanup(); vi.clearAllMocks(); });

describe('complétion PSC — repère principal accessible', () => {
  it('identifie le contenu pendant le chargement puis le formulaire, sans englober le pied de page', async () => {
    let repondre!: (valeur: unknown) => void;
    const chargement = new Promise(resolve => { repondre = resolve; });
    mocks.from.mockImplementation((table: string) => {
      expect(table).toBe('soignants');
      return { select: (colonnes: string) => {
        expect(colonnes).toBe('prenom, nom, profession, numero_rpps, telephone, type_contrat, types_contrat_acceptes');
        return { eq: (cle: string, id: string) => {
          expect([cle, id]).toEqual(['id', 'profil-psc-simule']);
          return { maybeSingle: () => chargement };
        } };
      } };
    });
    render(<MemoryRouter><InscriptionSoignantCompletion /></MemoryRouter>);
    expect(screen.getAllByRole('main')).toHaveLength(1);
    expect(screen.getByRole('main', { name: 'Chargement du profil' })).toHaveAttribute('aria-busy', 'true');
    await act(async () => {
      repondre({ data: { prenom: 'Camille', nom: 'Recette', profession: 'AS', numero_rpps: null, telephone: '', type_contrat: 'VACATION', types_contrat_acceptes: 'VACATION' }, error: null });
    });
    const principal = await screen.findByRole('main', { name: 'Votre compte est prêt.' });
    expect(screen.getAllByRole('main')).toHaveLength(1);
    expect(within(principal).getByRole('heading', { level: 1, name: 'Votre compte est prêt.' })).toBeVisible();
    expect(principal).not.toContainElement(screen.getByRole('contentinfo'));
    expect(within(principal).getByRole('button', { name: 'Découvrir les missions' })).toBeVisible();
    fireEvent.click(within(principal).getByRole('button', { name: 'Personnaliser mes préférences (facultatif)' }));
    expect(within(principal).getByRole('group', { name: 'Modes d’exercice recherchés' })).toBeVisible();
    expect(within(principal).getByRole('checkbox', { name: 'Salarié (CDD compris)' })).toBeChecked();
    expect(mocks.notifier).not.toHaveBeenCalled();
  });
});
