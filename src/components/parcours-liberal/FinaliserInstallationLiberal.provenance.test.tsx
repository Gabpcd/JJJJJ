import React from 'react';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { FinaliserInstallationLiberal } from './FinaliserInstallationLiberal';

const mocks = vi.hoisted(() => ({
  user: { id: 'simulation-source-siret' },
  profile: {} as Record<string, unknown>,
  select: vi.fn(),
  rpc: vi.fn(),
  invoke: vi.fn(),
}));
vi.mock('@tanstack/react-query', () => ({ useQueryClient: () => ({ invalidateQueries: vi.fn() }) }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.user }) }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: () => ({ select: mocks.select }), rpc: mocks.rpc, functions: { invoke: mocks.invoke } },
}));

beforeEach(() => {
  vi.clearAllMocks();
  mocks.profile = {
    siret_liberal: '99000000000000',
    siret_liberal_verifie: true,
    siret_liberal_verifie_le: '2026-10-15T00:00:00.000Z',
    siret_liberal_raison_sociale: null,
    siret_liberal_coherence_identite: true,
    siret_liberal_source_verification: null,
    statut_liberal: 'NON_LIBERAL',
    type_contrat: 'CDD',
    assujetti_tva: false,
    numero_tva: null,
  };
  mocks.select.mockImplementation(() => ({
    eq: () => ({ maybeSingle: async () => ({ data: mocks.profile, error: null }) }),
  }));
});
afterEach(cleanup);

describe('Installation libérale — provenance affichée sans modifier les critères', () => {
  it.each([
    ['REGISTRE_OFFICIEL', 'Source : registre officiel — concordance d’identité vérifiée.'],
    ['REVUE_MANUELLE_IDENTITE', 'Source : revue manuelle de l’identité.'],
    [null, 'SIRET enregistré — source de vérification non renseignée.'],
    [undefined, 'SIRET enregistré — source de vérification non renseignée.'],
    ['SOURCE_INCONNUE', 'SIRET enregistré — source de vérification non renseignée.'],
  ])('rend la source %s sans la déduire des flags', async (source, texte) => {
    mocks.profile.siret_liberal_source_verification = source;
    render(<FinaliserInstallationLiberal />);

    expect(await screen.findByText(texte)).toBeVisible();
    expect(screen.getByRole('status')).toHaveTextContent(texte);
    expect(screen.queryByText('SIRET officiel actif et identité vérifiée.')).not.toBeInTheDocument();
    if (source !== 'REGISTRE_OFFICIEL') {
      expect(screen.queryByText(/Source : registre officiel/)).not.toBeInTheDocument();
    }
    // Même décision d'activation : seuls les critères existants sont utilisés.
    expect(screen.getByRole('button', { name: 'Activer mon statut libéral' })).toBeEnabled();
    expect(mocks.select).toHaveBeenCalledWith(expect.stringContaining('siret_liberal_source_verification'));
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it('une source officielle seule ne débloque pas une concordance non vérifiée', async () => {
    mocks.profile.siret_liberal_source_verification = 'REGISTRE_OFFICIEL';
    mocks.profile.siret_liberal_coherence_identite = false;
    render(<FinaliserInstallationLiberal />);

    expect(await screen.findByText('Ce SIRET n’est pas encore vérifié. Relance la vérification avant l’activation.')).toBeVisible();
    expect(screen.queryByText(/Source : registre officiel/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Activer mon statut libéral' })).toBeDisabled();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it('ne rattache pas la source enregistrée à un nouveau numéro seulement saisi', async () => {
    mocks.profile.siret_liberal_source_verification = 'REGISTRE_OFFICIEL';
    render(<FinaliserInstallationLiberal />);
    expect(await screen.findByText('Source : registre officiel — concordance d’identité vérifiée.')).toBeVisible();

    fireEvent.change(screen.getByLabelText('SIRET'), { target: { value: '99000000000001' } });

    expect(screen.queryByText(/Source : registre officiel/)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Activer mon statut libéral' })).toBeDisabled();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });
});
