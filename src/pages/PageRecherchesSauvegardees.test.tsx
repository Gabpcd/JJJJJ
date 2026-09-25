import React from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import PageRecherchesSauvegardees from './PageRecherchesSauvegardees';

const mocks=vi.hoisted(()=>({rpc:vi.fn(),user:{id:'utilisateur-recette'},filtre:{id:'recherche-1',nom:'IDE Paris',audience:'ETAB_RECHERCHE_SOIGNANTS',filtres:{profession:'IDE',ville:'Paris'},alerte_active:false,frequence_alerte:'QUOTIDIENNE',dernier_check_le:'2026-09-24T10:00:00Z',nb_resultats_dernier_check:0}}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc}}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:mocks.user})}));
vi.mock('@/components/LayoutApp',()=>({LayoutApp:({children}:{children:React.ReactNode})=><main>{children}</main>}));
vi.mock('@/hooks/usePageTitle',()=>({usePageTitle:vi.fn()}));
vi.mock('sonner',()=>({toast:{error:vi.fn(),success:vi.fn()}}));

beforeEach(()=>{
 mocks.filtre.nom='IDE Paris';mocks.filtre.alerte_active=false;
 mocks.rpc.mockReset().mockImplementation((nom:string,p:Record<string,unknown>)=>{
  if(nom==='fn_lister_mes_filtres_sauvegardes')return Promise.resolve({data:[{...mocks.filtre}],error:null});
  if(typeof p.p_nom==='string')mocks.filtre.nom=p.p_nom;
  if(typeof p.p_alerte_active==='boolean')mocks.filtre.alerte_active=p.p_alerte_active;
  return Promise.resolve({data:{success:true},error:null});
 });
});
const afficher=(role:'SOIGNANT'|'ADMIN_ETABLISSEMENT'='ADMIN_ETABLISSEMENT')=>render(<MemoryRouter><PageRecherchesSauvegardees role={role} /></MemoryRouter>);

describe('gestion centrale des recherches établissement',()=>{
 it('une recherche inactive ne peut pas activer une alerte, même via Modifier',async()=>{
  afficher();fireEvent.click(await screen.findByRole('button',{name:'Modifier'}));
  expect(screen.queryByRole('button',{name:'Activer alertes'})).not.toBeInTheDocument();
  expect(screen.queryByRole('switch')).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText('Nom',{exact:true}),{target:{value:'IDE Paris renommée'}});
  fireEvent.click(screen.getByRole('button',{name:'Enregistrer'}));
  await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledWith('fn_modifier_filtre_sauvegarde',{p_id:'recherche-1',p_nom:'IDE Paris renommée'}));
 });
 it('renommer une alerte active ne la désactive pas et ne réécrit pas son activation',async()=>{
  mocks.filtre.alerte_active=true;afficher();fireEvent.click(await screen.findByRole('button',{name:'Modifier'}));
  expect(screen.getByRole('switch',{name:'Alertes email'})).toHaveAttribute('aria-checked','true');
  fireEvent.change(screen.getByLabelText('Nom',{exact:true}),{target:{value:'Ancienne alerte renommée'}});
  fireEvent.click(screen.getByRole('button',{name:'Enregistrer'}));
  await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledWith('fn_modifier_filtre_sauvegarde',{p_id:'recherche-1',p_nom:'Ancienne alerte renommée'}));
  expect(mocks.filtre.alerte_active).toBe(true);
 });
 it('permet de désactiver une alerte existante sans proposer de la réactiver',async()=>{
  mocks.filtre.alerte_active=true;afficher();fireEvent.click(await screen.findByRole('button',{name:'Désactiver alertes'}));
  await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledWith('fn_modifier_filtre_sauvegarde',{p_id:'recherche-1',p_alerte_active:false}));
  await screen.findByRole('button',{name:'Modifier'});
  expect(screen.queryByRole('button',{name:'Activer alertes'})).not.toBeInTheDocument();
 });
 it('permet la désactivation dans le formulaire et garde les options soignant existantes',async()=>{
  mocks.filtre.alerte_active=true;const vue=afficher();fireEvent.click(await screen.findByRole('button',{name:'Modifier'}));
  fireEvent.click(screen.getByRole('switch',{name:'Alertes email'}));fireEvent.click(screen.getByRole('button',{name:'Enregistrer'}));
  await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledWith('fn_modifier_filtre_sauvegarde',{p_id:'recherche-1',p_nom:'IDE Paris',p_alerte_active:false}));
  vue.unmount();afficher('SOIGNANT');
  expect(await screen.findByRole('button',{name:'Activer alertes'})).toBeInTheDocument();
 });
});
