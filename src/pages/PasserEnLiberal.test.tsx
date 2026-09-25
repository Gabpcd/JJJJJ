import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, it, vi, expect } from 'vitest';
import PasserEnLiberal from './PasserEnLiberal';

const mocks=vi.hoisted(()=>({parcours:vi.fn()}));
vi.mock('@/hooks/useRole',()=>({useRole:()=>({loading:false,parcours:{type_compte:'SOIGNANT',donnees:{profession:'IDE'}}})}));
vi.mock('@/components/LayoutApp',()=>({LayoutApp:({children}:any)=><main>{children}</main>}));
vi.mock('@/hooks/useParcoursLiberal',()=>({useParcoursLiberal:mocks.parcours}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:{id:'simulation'}})}));

describe('Passer en libéral — compte minimal',()=>{
 it('explique la préparation facultative sans créer de parcours métier ni attendre indéfiniment',()=>{
  render(<MemoryRouter><PasserEnLiberal/></MemoryRouter>);
  expect(screen.getByRole('heading',{name:'Votre parcours libéral, à votre rythme'})).toBeVisible();
  expect(screen.getByRole('link',{name:'Préparer mon profil'})).toHaveAttribute('href','/soignant/profil');
  expect(screen.getByRole('link',{name:'Explorer les missions'})).toHaveAttribute('href','/soignant/recherche-missions');
  expect(mocks.parcours).not.toHaveBeenCalled();
 });
});
