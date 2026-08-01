import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { FactureHonorairesCard } from './FactureHonorairesCard';

const mocks = vi.hoisted(() => ({
  data: [] as any[],
  error: null as { message: string } | null,
  from: vi.fn(),
  limit: vi.fn(),
  telecharger: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from },
}));

vi.mock('@/lib/facture-honoraires-pdf', () => ({
  telechargerFactureHonorairesPDF: mocks.telecharger,
}));

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({
    children,
    loading: _loading,
    iconeGauche: _iconeGauche,
    size: _size,
    variant: _variant,
    ...props
  }: React.ButtonHTMLAttributes<HTMLButtonElement> & {
    loading?: boolean;
    iconeGauche?: React.ReactNode;
    size?: string;
    variant?: string;
  }) => <button {...props}>{children}</button>,
}));

function construireRequete() {
  const reponse = Promise.resolve({ data: mocks.data, error: mocks.error });
  const builder: any = {
    select: vi.fn(() => builder),
    eq: vi.fn(() => builder),
    order: vi.fn(() => builder),
    limit: mocks.limit,
    then: reponse.then.bind(reponse),
  };
  return builder;
}

describe('FactureHonorairesCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.error = null;
    mocks.telecharger.mockResolvedValue(undefined);
    mocks.data = [
      {
        id: 'f-payee',
        numero_facture: 'F-S27',
        statut: 'PAYEE',
        type_document: 'FACTURE',
        montant_ttc: 500,
        montant_signe: 500,
        date_emission: '2026-07-06',
        date_paiement: '2026-07-15',
        numero_semaine_iso: 27,
        annee_iso: 2026,
        periode_debut: '2026-07-06',
        periode_fin: '2026-07-12',
      },
      {
        id: 'f-retard',
        numero_facture: 'F-S28',
        statut: 'EN_RETARD',
        type_document: 'FACTURE',
        montant_ttc: 600,
        montant_signe: 600,
        date_emission: '2026-07-13',
        date_echeance: '2026-07-20',
        numero_semaine_iso: 28,
        annee_iso: 2026,
      },
      {
        id: 'f-attente',
        numero_facture: 'F-S29',
        statut: 'EMISE',
        type_document: 'FACTURE',
        montant_ttc: 700,
        montant_signe: 700,
        date_emission: '2026-07-20',
        numero_semaine_iso: 29,
        annee_iso: 2026,
      },
      {
        id: 'avoir',
        numero_facture: 'AV-2026-1',
        statut: 'EMISE',
        type_document: 'AVOIR',
        montant_ttc: 100,
        montant_signe: -100,
        date_emission: '2026-07-21',
      },
      {
        id: 'erreur',
        numero_facture: 'F-ERREUR',
        statut: 'ERREUR_GENERATION',
        type_document: 'FACTURE',
        montant_ttc: 999,
        montant_signe: 999,
        date_emission: '2026-07-22',
      },
    ];
    mocks.from.mockImplementation(() => construireRequete());
  });

  it('affiche toutes les semaines, le retard et l avoir avec des agrégats exacts', async () => {
    render(<FactureHonorairesCard missionId="mission-longue" viewerRole="SOIGNANT" />);

    expect(await screen.findByText('F-S27')).toBeInTheDocument();
    expect(screen.getByText('F-S28')).toBeInTheDocument();
    expect(screen.getByText('F-S29')).toBeInTheDocument();
    expect(screen.getByText('AV-2026-1')).toBeInTheDocument();
    expect(screen.getByText('F-ERREUR')).toBeInTheDocument();
    expect(screen.getByText('Semaine 27/2026')).toBeInTheDocument();
    expect(screen.getByText('Semaine 28/2026')).toBeInTheDocument();
    expect(screen.getByText('Semaine 29/2026')).toBeInTheDocument();
    expect(screen.getAllByText('AVOIR')).toHaveLength(1);
    expect(screen.getByText(/régularisation distincte d’un paiement attendu/)).toBeInTheDocument();

    const netFacture = screen.getByText('Net facturé').parentElement!;
    const paye = screen.getByText('Payé').parentElement!;
    const attente = screen.getByText(/En attente · 1 en retard/).parentElement!;
    expect(within(netFacture).getByText(/1\s*700,00/)).toBeInTheDocument();
    expect(within(paye).getByText(/500,00/)).toBeInTheDocument();
    expect(within(attente).getByText(/1\s*300,00/)).toBeInTheDocument();
    expect(screen.getByText(/1 avoir comptabilisé en négatif/)).toBeInTheDocument();

    expect(mocks.limit).not.toHaveBeenCalled();
    expect(screen.getAllByRole('button', { name: /Télécharger le PDF/ })).toHaveLength(4);
    fireEvent.click(screen.getByRole('button', { name: 'Télécharger le PDF F-S28' }));
    await waitFor(() => expect(mocks.telecharger).toHaveBeenCalledWith('f-retard'));
  });

  it('affiche l erreur de lecture et permet de relancer la requête', async () => {
    mocks.error = { message: 'RLS indisponible' };
    render(<FactureHonorairesCard missionId="mission-longue" />);

    const alerte = await screen.findByRole('alert');
    expect(alerte).toHaveTextContent('RLS indisponible');
    expect(mocks.from).toHaveBeenCalledTimes(1);

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await waitFor(() => expect(mocks.from).toHaveBeenCalledTimes(2));
  });
});
