import { act, cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ApercuMarche } from './ApercuMarche';

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc } }));
const reponse = (n: number) => ({ data: { nb_missions: n, taux_max: 25, taux_moyen: 20, nb_etablissements: 2, zone: 'national' }, error: null });
const rechercher = () => act(async () => { await vi.advanceTimersByTimeAsync(300); });

describe('ApercuMarche — réponses liées aux critères courants', () => {
  beforeEach(() => { vi.useFakeTimers(); rpc.mockReset(); });
  afterEach(() => { cleanup(); vi.useRealTimers(); });

  it('retire immédiatement le nombre de la profession précédente, même si la nouvelle recherche échoue', async () => {
    rpc.mockResolvedValueOnce(reponse(12)).mockResolvedValueOnce({ data: null, error: { code: '42501' } });
    const { rerender } = render(<ApercuMarche profession="IDE" />);
    await rechercher();
    expect(screen.getByRole('status')).toHaveTextContent('12 missions');
    rerender(<ApercuMarche profession="AS" />);
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
    await rechercher();
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
    expect(rpc).toHaveBeenLastCalledWith('fn_apercu_marche_profession', expect.objectContaining({ p_profession: 'AS' }));
  });

  it('ne remplace pas la nouvelle réponse par une ancienne réponse retardée', async () => {
    let ancienne!: (value: ReturnType<typeof reponse>) => void;
    rpc.mockReturnValueOnce(new Promise(resolve => { ancienne = resolve; })).mockResolvedValueOnce(reponse(3));
    const { rerender } = render(<ApercuMarche profession="IDE" />);
    await rechercher();
    rerender(<ApercuMarche profession="AS" />);
    await rechercher();
    expect(screen.getByRole('status')).toHaveTextContent('3 missions');
    await act(async () => { ancienne(reponse(99)); });
    expect(screen.getByRole('status')).toHaveTextContent('3 missions');
    expect(screen.queryByText('99 missions')).not.toBeInTheDocument();
  });

  it('invalide aussi les anciens chiffres lors du changement de zone', async () => {
    rpc.mockResolvedValueOnce(reponse(12)).mockResolvedValueOnce(reponse(2));
    const { rerender } = render(<ApercuMarche profession="IDE" lat={48.85} lng={2.35} rayonKm={30} />);
    await rechercher();
    rerender(<ApercuMarche profession="IDE" lat={45.75} lng={4.85} rayonKm={50} />);
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
    await rechercher();
    expect(screen.getByRole('status')).toHaveTextContent('2 missions');
    expect(rpc).toHaveBeenLastCalledWith('fn_apercu_marche_profession', { p_profession: 'IDE', p_lat: 45.75, p_lng: 4.85, p_rayon_km: 50 });
  });

  it('absorbe un rejet de transport sans casser le formulaire parent', async () => {
    rpc.mockRejectedValueOnce(new Error('transport indisponible'));
    render(<><button>Continuer</button><ApercuMarche /></>);
    await rechercher();
    expect(screen.getByRole('button', { name: 'Continuer' })).toBeEnabled();
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });
});
