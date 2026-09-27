import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { FiltresSauvegardes } from './FiltresSauvegardes';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), error: vi.fn(), success: vi.fn(), echec: false }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('sonner', () => ({ toast: { error: mocks.error, success: mocks.success } }));

const filtres = {
  profession: 'IDE', type_exercice: 'SALARIE', ville: 'Paris', distance_max_km: '25',
  note_min: '4', score_min: '80', experience_min: '5', disponible_urgence: true,
  documents_valides: true, recherche_texte: 'pédiatrie',
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.echec = false;
  mocks.rpc.mockImplementation((nom: string) => Promise.resolve({
    data: nom === 'fn_lister_mes_filtres_sauvegardes' ? [] : mocks.echec ? null : { success: true },
    error: mocks.echec && nom === 'fn_creer_filtre_sauvegarde' ? { message: 'Service indisponible' } : null,
  }));
});

const ouvrir = async () => {
  render(<FiltresSauvegardes audience="ETAB_RECHERCHE_SOIGNANTS" filtresCourants={filtres} onCharger={vi.fn()} alertesDisponibles />);
  fireEvent.click(await screen.findByRole('button', { name: 'Sauvegarder cette recherche' }));
  fireEvent.change(screen.getByLabelText('Nom de la recherche'), { target: { value: 'IDE pédiatrie Paris' } });
};

describe('contrat UI des alertes établissement disponibles', () => {
  it('envoie les dix critères sans perte avec le choix quotidien', async () => {
    await ouvrir();
    expect(screen.getByRole('switch', { name: 'Recevoir des alertes email' })).toHaveAttribute('aria-checked', 'true');
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_creer_filtre_sauvegarde', {
      p_nom: 'IDE pédiatrie Paris', p_audience: 'ETAB_RECHERCHE_SOIGNANTS', p_filtres: filtres,
      p_alerte_active: true, p_frequence_alerte: 'QUOTIDIENNE',
    }));
    expect(mocks.success).toHaveBeenCalledWith('Recherche sauvegardée');
  });

  it('respecte le choix de sauvegarder sans email', async () => {
    await ouvrir();
    fireEvent.click(screen.getByRole('switch', { name: 'Recevoir des alertes email' }));
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_creer_filtre_sauvegarde', expect.objectContaining({ p_alerte_active: false })));
  });

  it('conserve la saisie et permet de réessayer après une panne sans faux succès', async () => {
    await ouvrir();
    mocks.echec = true;
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(mocks.error).toHaveBeenCalledWith('Erreur enregistrement'));
    expect(screen.getByLabelText('Nom de la recherche')).toHaveValue('IDE pédiatrie Paris');
    expect(mocks.success).not.toHaveBeenCalled();
    mocks.echec = false;
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(mocks.success).toHaveBeenCalledWith('Recherche sauvegardée'));
  });
});

it('une vérification tardive de capacité ne vide pas la saisie et ne coche pas une alerte sans choix', async()=>{
 const props={audience:'ETAB_RECHERCHE_SOIGNANTS' as const,filtresCourants:filtres,onCharger:vi.fn()};
 const vue=render(<FiltresSauvegardes {...props} alertesDisponibles={false}/>);
 fireEvent.click(await screen.findByRole('button',{name:'Sauvegarder cette recherche'}));
 fireEvent.change(screen.getByLabelText('Nom de la recherche'),{target:{value:'Saisie en cours'}});
 vue.rerender(<FiltresSauvegardes {...props} alertesDisponibles/>);
 expect(screen.getByLabelText('Nom de la recherche')).toHaveValue('Saisie en cours');
 expect(screen.getByRole('switch',{name:'Recevoir des alertes email'})).toHaveAttribute('aria-checked','false');
});

it('une panne de liste ne passe pas pour une liste vide et se recharge',async()=>{
 const implementation=mocks.rpc.getMockImplementation()!;let panne=true;
 mocks.rpc.mockImplementation((nom:string)=>nom==='fn_lister_mes_filtres_sauvegardes'&&panne?Promise.resolve({data:null,error:{message:'503'}}):implementation(nom));
 render(<FiltresSauvegardes audience="ETAB_RECHERCHE_SOIGNANTS" filtresCourants={filtres} onCharger={vi.fn()} alertesDisponibles/>);
 expect(await screen.findByRole('alert')).toHaveTextContent('n’ont pas pu être chargées');
 panne=false;fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));
 expect(await screen.findByRole('button',{name:'Sauvegarder cette recherche'})).toBeInTheDocument();
 expect(screen.queryByRole('alert')).not.toBeInTheDocument();
});
