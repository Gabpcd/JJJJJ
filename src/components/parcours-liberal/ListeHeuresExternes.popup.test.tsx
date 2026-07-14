import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ListeHeuresExternes } from './ListeHeuresExternes';
import type { HeureExterne } from '@/hooks/useParcoursLiberal';

const mocks = vi.hoisted(() => ({
  createSignedUrl: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, iconeGauche, variant: _variant, size: _size, loading: _loading, ...props }: any) => (
    <button type="button" {...props}>{iconeGauche}{children}</button>
  ),
}));

vi.mock('sonner', () => ({
  toast: { error: mocks.toastError, success: vi.fn() },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    storage: {
      from: vi.fn(() => ({ createSignedUrl: mocks.createSignedUrl })),
    },
  },
}));

const heure: HeureExterne = {
  id: 'heure-1',
  soignant_id: 'soignant-1',
  etablissement_nom: 'Clinique Jolene',
  etablissement_type: 'CLINIQUE',
  date_debut: '2026-07-01T08:00:00.000Z',
  date_fin: '2026-07-01T18:00:00.000Z',
  heures_declarees: 10,
  attestation_url: 'soignants/soignant-1/heures-externes/attestation.pdf',
  attestation_nom_fichier: 'attestation.pdf',
  statut_validation: 'EN_ATTENTE',
  commentaire_validation: null,
  heures_extraites_ia: null,
  coherence_ia: null,
  verifie_ia_le: null,
  cree_le: '2026-07-01T18:00:00.000Z',
};

describe('ListeHeuresExternes — ouverture Safari', () => {
  beforeEach(() => {
    mocks.createSignedUrl.mockReset();
    mocks.toastError.mockReset();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('préouvre l’onglet pendant le clic puis le navigue après signature', async () => {
    let resoudreUrl!: (value: { data: { signedUrl: string }; error: null }) => void;
    mocks.createSignedUrl.mockReturnValue(new Promise((resolve) => { resoudreUrl = resolve; }));

    const remplacer = vi.fn();
    const fermer = vi.fn();
    const preview = { opener: {} as unknown, location: { replace: remplacer }, close: fermer };
    const ouvrir = vi.spyOn(window, 'open').mockReturnValue(preview as unknown as Window);

    render(<ListeHeuresExternes heures={[heure]} onSupprimer={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Voir' }));

    expect(ouvrir).toHaveBeenCalledWith('about:blank', '_blank');
    expect(preview.opener).toBeNull();
    expect(ouvrir.mock.invocationCallOrder[0]).toBeLessThan(mocks.createSignedUrl.mock.invocationCallOrder[0]);
    expect(remplacer).not.toHaveBeenCalled();

    resoudreUrl({ data: { signedUrl: 'https://signed.example/attestation' }, error: null });
    await waitFor(() => expect(remplacer).toHaveBeenCalledWith('https://signed.example/attestation'));
    expect(fermer).not.toHaveBeenCalled();
  });

  it('n’appelle pas Storage si Safari bloque la fenêtre', () => {
    vi.spyOn(window, 'open').mockReturnValue(null);

    render(<ListeHeuresExternes heures={[heure]} onSupprimer={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Voir' }));

    expect(mocks.createSignedUrl).not.toHaveBeenCalled();
    expect(mocks.toastError).toHaveBeenCalledWith(expect.stringMatching(/fenêtres contextuelles/i));
  });
});
