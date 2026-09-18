import React, { type ReactNode } from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import InscriptionSoignant from '@/pages/InscriptionSoignant';
import InscriptionSoignantCompletion from '@/pages/InscriptionSoignantCompletion';

const mocks = vi.hoisted(() => ({
  enregistrer: vi.fn(),
  finaliser: vi.fn(),
  rpc: vi.fn(),
  maybeSingle: vi.fn(),
  update: vi.fn(),
  updateUser: vi.fn(),
  notification: vi.fn(),
  user: { id: 'review-user' },
  typesAutorises: ['SALARIE', 'LIBERAL'] as string[] | null,
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => {} }));
vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mocks.user, loading: false, inscriptionSoignant: vi.fn() }),
}));
vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.notification }),
}));
vi.mock('@/hooks/useTypesExerciceAutorises', () => ({
  useTypesExerciceAutorises: () => ({
    typesAutorises: mocks.typesAutorises,
    uniqueType: mocks.typesAutorises?.length === 1 ? mocks.typesAutorises[0] : null,
    loading: mocks.typesAutorises === null,
    indisponible: false,
  }),
}));
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'http://localhost',
  SUPABASE_PUBLISHABLE_KEY: 'test-key',
  supabase: {
    rpc: mocks.rpc,
    auth: { updateUser: mocks.updateUser },
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: mocks.maybeSingle }) }),
      update: mocks.update,
    }),
  },
}));
vi.mock('@/lib/inscriptionProgressive', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/inscriptionProgressive')>(),
  enregistrerParcours: mocks.enregistrer,
  finaliserProfil: mocks.finaliser,
}));
vi.mock('@/components/AuthLayout', () => ({
  AuthLayout: ({ children }: { children: ReactNode }) => <main>{children}</main>,
}));
vi.mock('@/components/ui/checkbox', () => ({
  Checkbox: ({ checked, onCheckedChange, ...props }: {
    checked: boolean;
    onCheckedChange: () => void;
    'aria-label'?: string;
  }) => <input type="checkbox" checked={checked} onChange={onCheckedChange} {...props} />,
}));
vi.mock('@/components/BoutonProSanteConnect', () => ({ BoutonProSanteConnect: () => null }));
vi.mock('@/components/CaptchaTurnstile', () => ({ CaptchaTurnstile: () => null, TURNSTILE_REQUIRED: false }));
vi.mock('@/components/inscription/ApercuMarche', () => ({ ApercuMarche: () => null }));
vi.mock('@/components/inscription/DeclarationEtudiant', () => ({
  DeclarationEtudiant: () => null,
  FORMATIONS_ETUDIANT: [],
}));
vi.mock('@/components/SelectProfession', () => ({
  SelectProfession: ({ value, onChange }: { value: string; onChange: (value: string) => void }) => (
    <select aria-label="Profession" value={value} onChange={(event) => onChange(event.target.value)}>
      <option value="IDE">IDE</option><option value="AS">AS</option>
    </select>
  ),
}));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.typesAutorises = ['SALARIE', 'LIBERAL'];
  mocks.enregistrer.mockResolvedValue({});
  mocks.rpc.mockResolvedValue({ error: null });
  mocks.maybeSingle.mockResolvedValue({
    data: { prenom: 'Camille', nom: 'Martin', profession: 'IDE', numero_rpps: null },
    error: null,
  });
});

const parcours = {
  user_id: 'review-user',
  type_compte: 'SOIGNANT' as const,
  modifie_le: '2026-09-18T10:00:00Z',
  donnees: { profession: 'IDE', typesContrat: ['LIBERAL', 'VACATION'] },
};

describe('Inscription progressive — reprise du profil soignant', () => {
  it('conserve les contrats du brouillon pendant le chargement du référentiel puis lors de la sauvegarde', async () => {
    mocks.typesAutorises = null;
    const contenu = () => <MemoryRouter><InscriptionSoignant parcours={parcours} /></MemoryRouter>;
    const view = render(contenu());

    mocks.typesAutorises = ['SALARIE', 'LIBERAL'];
    view.rerender(contenu());

    expect(screen.getByRole('checkbox', { name: 'Libéral' })).toBeChecked();
    expect(screen.getByRole('checkbox', { name: 'CDD court' })).toBeChecked();
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer et continuer plus tard' }));
    await waitFor(() => expect(mocks.enregistrer).toHaveBeenCalledWith(expect.objectContaining({
      typesContrat: ['LIBERAL', 'VACATION'],
    })));
  });

  it('retire les contrats incompatibles après un changement réel de profession', async () => {
    render(<MemoryRouter><InscriptionSoignant parcours={parcours} /></MemoryRouter>);
    expect(screen.getByRole('checkbox', { name: 'Libéral' })).toBeChecked();

    fireEvent.change(screen.getByRole('combobox', { name: 'Profession' }), { target: { value: 'AS' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer et continuer plus tard' }));

    await waitFor(() => expect(mocks.enregistrer).toHaveBeenCalledWith(expect.objectContaining({
      profession: 'AS', typesContrat: [],
    })));
  });
});

describe('Inscription PSC — préférences différées', () => {
  it.each(['telephone', 'motDePasse'] as const)(
    'permet de découvrir les missions après avoir masqué un %s incomplet',
    async (champ) => {
      render(<MemoryRouter><Routes>
        <Route path="/" element={<InscriptionSoignantCompletion />} />
        <Route path="/soignant/recherche-missions" element={<p>Missions disponibles</p>} />
      </Routes></MemoryRouter>);
      await screen.findByText('Votre compte est prêt.');
      fireEvent.click(screen.getByRole('button', { name: 'Personnaliser mes préférences (facultatif)' }));
      const type = champ === 'telephone' ? 'tel' : 'password';
      fireEvent.change(document.querySelector(`input[type="${type}"]`)!, { target: { value: '06' } });

      fireEvent.click(screen.getByRole('button', { name: 'Compléter mes préférences plus tard' }));
      fireEvent.click(screen.getByRole('checkbox', { name: /Conditions Générales d'Utilisation/ }));

      expect(document.querySelector(`input[type="${type}"]`)).toBeNull();
      const decouvrir = screen.getByRole('button', { name: 'Découvrir les missions' });
      expect(decouvrir).toBeEnabled();
      fireEvent.click(decouvrir);
      expect(await screen.findByText('Missions disponibles')).toBeVisible();
      expect(mocks.rpc).toHaveBeenCalledWith('fn_accepter_cgu_decouverte_soignant');
      expect(mocks.update).not.toHaveBeenCalled();
      expect(mocks.updateUser).not.toHaveBeenCalled();
    },
  );
});
