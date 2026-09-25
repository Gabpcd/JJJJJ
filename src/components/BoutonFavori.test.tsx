import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { BoutonFavori } from './BoutonFavori';

const mocks=vi.hoisted(()=>({lecture:vi.fn(),insert:vi.fn(),suppression:vi.fn(),toast:vi.fn()}));
vi.mock('sonner',()=>({toast:{error:mocks.toast}}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{from:()=>({
  select:()=>{const q={eq:()=>q,maybeSingle:mocks.lecture};return q;},
  insert:mocks.insert,
  delete:()=>{const q={eq:()=>q,then:(resolve:(v:unknown)=>unknown,reject:(e:unknown)=>unknown)=>mocks.suppression().then(resolve,reject)};return q;},
})}}));

beforeEach(()=>{
  vi.clearAllMocks();
  mocks.lecture.mockResolvedValue({data:null,error:null});
  mocks.insert.mockResolvedValue({data:null,error:null});
  mocks.suppression.mockResolvedValue({data:null,error:null});
});

describe('favori établissement confirmé par le serveur',()=>{
  it('ne coche pas le favori lorsque son ajout échoue, puis permet de réessayer',async()=>{
    mocks.insert.mockResolvedValueOnce({data:null,error:{message:'503'}});
    render(<BoutonFavori soignantId="soignant-1" etablissementId="etab-1" />);
    const bouton=screen.getByRole('button',{name:'Ajouter ce soignant aux favoris'});
    await waitFor(()=>expect(bouton).toBeEnabled());fireEvent.click(bouton);
    await waitFor(()=>expect(mocks.toast).toHaveBeenCalledWith('Impossible d’ajouter ce soignant aux favoris. Veuillez réessayer.'));
    expect(bouton).toHaveAttribute('aria-pressed','false');
    fireEvent.click(bouton);
    await waitFor(()=>expect(bouton).toHaveAttribute('aria-pressed','true'));
    expect(mocks.insert).toHaveBeenCalledWith({etablissement_id:'etab-1',soignant_id:'soignant-1'});
  });
  it('conserve le favori lorsque sa suppression échoue',async()=>{
    mocks.lecture.mockResolvedValue({data:{id:'favori-1'},error:null});
    mocks.suppression.mockResolvedValue({data:null,error:{message:'503'}});
    render(<BoutonFavori soignantId="soignant-1" etablissementId="etab-1" />);
    const bouton=await screen.findByRole('button',{name:'Retirer ce soignant des favoris'});
    fireEvent.click(bouton);
    await waitFor(()=>expect(mocks.toast).toHaveBeenCalledWith('Impossible de retirer ce soignant des favoris. Veuillez réessayer.'));
    expect(bouton).toHaveAttribute('aria-pressed','true');expect(bouton).toBeEnabled();
  });
  it('une lecture en panne propose un réessai sans modifier un favori inconnu',async()=>{
    mocks.lecture.mockResolvedValueOnce({data:null,error:{message:'503'}}).mockResolvedValue({data:{id:'favori-1'},error:null});
    render(<BoutonFavori soignantId="soignant-1" etablissementId="etab-1" />);
    fireEvent.click(await screen.findByRole('button',{name:'Réessayer le chargement du favori'}));
    expect(await screen.findByRole('button',{name:'Retirer ce soignant des favoris'})).toHaveAttribute('aria-pressed','true');
    expect(mocks.insert).not.toHaveBeenCalled();expect(mocks.suppression).not.toHaveBeenCalled();
  });
});
