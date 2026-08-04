import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { BlocagePostulation } from './BlocagePostulation';

describe('BlocagePostulation', () => {
  it('ne présente pas un profil comme bloquant quand seuls les documents manquent', () => {
    render(
      <MemoryRouter>
        <BlocagePostulation
          completionProfil={86}
          documentsValides={false}
          champsManquants={[]}
        />
      </MemoryRouter>,
    );

    expect(screen.queryByText(/Profil incomplet/i)).not.toBeInTheDocument();
    expect(screen.getByText(/Documents en cours/i)).toBeInTheDocument();
  });

  it('nomme les informations obligatoires réellement manquantes', () => {
    render(
      <MemoryRouter>
        <BlocagePostulation
          completionProfil={86}
          documentsValides={true}
          champsManquants={['Téléphone']}
        />
      </MemoryRouter>,
    );

    expect(screen.getByText(/Profil incomplet \(86%\)/i)).toBeInTheDocument();
    expect(screen.getByText(/Téléphone/i)).toBeInTheDocument();
  });
});
