import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { FiltresSauvegardes } from './FiltresSauvegardes';

const mocks = vi.hoisted(() => ({ rpc:vi.fn(), liste:[] as Record<string, unknown>[] }));
vi.mock('@/integrations/supabase/client', () => ({ supabase:{rpc:mocks.rpc} }));
vi.mock('sonner', () => ({ toast:{error:vi.fn(),success:vi.fn()} }));

beforeEach(() => {
  mocks.liste=[];
  mocks.rpc.mockReset().mockImplementation((nom:string) => Promise.resolve({data:nom==='fn_lister_mes_filtres_sauvegardes'?mocks.liste:{success:true},error:null}));
});

describe('sauvegarde des recherches sans nouvelle alerte établissement', () => {
  it('conserve le choix d’alerte du parcours soignant existant par défaut', async () => {
    render(<FiltresSauvegardes audience="SOIGNANT_RECHERCHE_MISSIONS" filtresCourants={{profession:'IDE'}} onCharger={vi.fn()} />);
    fireEvent.click(await screen.findByRole('button',{name:'Sauvegarder cette recherche'}));
    expect(screen.getByRole('switch',{name:'Recevoir des alertes email'})).toHaveAttribute('aria-checked','true');
  });

  it('crée une sauvegarde établissement avec tous les filtres et alerte false', async () => {
    render(<FiltresSauvegardes audience="ETAB_RECHERCHE_SOIGNANTS" filtresCourants={{profession:'IDE',ville:'Paris'}} onCharger={vi.fn()} alertesDisponibles={false} />);
    fireEvent.click(await screen.findByRole('button',{name:'Sauvegarder cette recherche'}));
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Nom de la recherche'),{target:{value:'IDE Paris'}});
    fireEvent.click(screen.getByRole('button',{name:'Enregistrer'}));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_creer_filtre_sauvegarde',{p_nom:'IDE Paris',p_audience:'ETAB_RECHERCHE_SOIGNANTS',p_filtres:{profession:'IDE',ville:'Paris'},p_alerte_active:false,p_frequence_alerte:'QUOTIDIENNE'}));
  });

  it('renomme une recherche existante sans envoyer de changement de ses alertes', async () => {
    mocks.liste=[{id:'recherche-1',nom:'Ancienne recherche',audience:'ETAB_RECHERCHE_SOIGNANTS',filtres:{profession:'IDE'},alerte_active:true,frequence_alerte:'HEBDOMADAIRE'}];
    render(<FiltresSauvegardes audience="ETAB_RECHERCHE_SOIGNANTS" filtresCourants={{}} onCharger={vi.fn()} alertesDisponibles={false} />);
    fireEvent.click(await screen.findByRole('button',{name:'Modifier'}));
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Nom',{exact:true}),{target:{value:'Recherche renommée'}});
    fireEvent.click(screen.getByRole('button',{name:'Enregistrer'}));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_modifier_filtre_sauvegarde',{p_id:'recherche-1',p_nom:'Recherche renommée'}));
  });
});
