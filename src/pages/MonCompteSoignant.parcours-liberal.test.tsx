import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import MonCompteSoignant from './MonCompteSoignant';

vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: () => undefined }));
vi.mock('@/hooks/useTheme', () => ({ useTheme: () => ({ theme: 'light', toggleTheme: vi.fn() }) }));
vi.mock('@/components/BadgeRPPS', () => ({ BadgeRPPS: () => null }));
vi.mock('@/components/mascotte/Mascotte', () => ({ Mascotte: () => null }));
vi.mock('@/components/profil-soignant/SectionPaiements', () => ({ SectionPaiements: () => null }));
vi.mock('@/components/soignant/ChangementMotDePasse', () => ({ ChangementMotDePasse: () => null }));
vi.mock('@/components/ModalContacterJolene', () => ({ ModalContacterJolene: () => null }));
vi.mock('@/components/BuildStamp', () => ({ BuildStamp: () => null }));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({
    user: { id: 'soignant-ide', email: 'marie@example.test' },
    deconnexion: vi.fn(),
  }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => {
      const builder = {
        select: () => builder,
        eq: () => builder,
        maybeSingle: () => Promise.resolve({
          data: {
            prenom: 'Marie',
            nom: 'Lefèvre',
            avatar_url: null,
            type_exercice: 'SALARIE',
            rpps_verifie: true,
            numero_rpps: '10123456789',
            profession: 'IDE',
            statut_liberal: null,
            mandat_facturation_signe: false,
            mandat_facturation_signe_le: null,
            est_compte_test: true,
          },
          error: null,
        }),
      };
      return builder;
    },
  },
}));

describe('MonCompteSoignant — parcours libéral', () => {
  it('le rend accessible sur le hub compte pour une IDE non libérale', async () => {
    render(
      <MemoryRouter>
        <MonCompteSoignant />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('button', { name: 'Passer en libéral' })).toBeInTheDocument();
  });
});
