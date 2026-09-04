import { fireEvent, render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { CarteContratElectroniqueMission } from './CarteContratElectroniqueMission';

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, iconeGauche: _icone, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement> & { iconeGauche?: React.ReactNode }) => (
    <button {...props}>{children}</button>
  ),
}));

describe('CarteContratElectroniqueMission', () => {
  it('donne à l’établissement un accès direct à sa signature', () => {
    const onOpen = vi.fn();
    render(
      <CarteContratElectroniqueMission
        viewerRole="ETABLISSEMENT"
        contrat={{
          id: 'contrat-1',
          numero_contrat: 'CDD-2026-42',
          statut: 'SIGNE_SOIGNANT',
          signature_soignant: true,
          signature_etablissement: false,
        }}
        onOpen={onOpen}
      />,
    );

    expect(screen.getByText(/Le soignant a signé/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Ouvrir et signer le contrat' }));
    expect(onOpen).toHaveBeenCalledWith('contrat-1');
  });

  it('présente un contrat complet en lecture seule', () => {
    render(
      <CarteContratElectroniqueMission
        viewerRole="ETABLISSEMENT"
        contrat={{
          id: 'contrat-2',
          numero_contrat: 'CDD-2026-43',
          statut: 'SIGNE_COMPLET',
          signature_soignant: true,
          signature_etablissement: true,
        }}
        onOpen={vi.fn()}
      />,
    );

    expect(screen.getByText(/signé par les deux parties/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Consulter le contrat' })).toBeInTheDocument();
  });

  it('oriente l’admin vers une action de supervision', () => {
    render(
      <CarteContratElectroniqueMission
        viewerRole="ADMIN"
        contrat={{
          id: 'contrat-3',
          numero_contrat: 'CDD-2026-44',
          statut: 'EN_ATTENTE_SIGNATURES',
          signature_soignant: false,
          signature_etablissement: false,
        }}
        onOpen={vi.fn()}
      />,
    );

    expect(screen.getByRole('button', { name: 'Superviser le contrat' })).toBeInTheDocument();
    expect(screen.getByText(/intervenez si une partie est bloquée/)).toBeInTheDocument();
  });
});
