import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import MesDisponibilites from './MesDisponibilites';
import { ConformiteContent } from './ConformiteSoignant';

const mocks = vi.hoisted(()=>({user:{id:'soignant-recette'},result:{data:[] as any[],error:null as any},rpc:vi.fn(),success:vi.fn(),error:vi.fn()}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:mocks.user})}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:vi.fn()})}));
vi.mock('@/components/LayoutApp',()=>({LayoutApp:({children}:any)=><main>{children}</main>}));
vi.mock('@/components/ui/EmptyState',()=>({EmptyState:({titre}:any)=><h2>{titre}</h2>}));
vi.mock('@/lib/etablissements',()=>({fetchEtablissementsSafe:async()=>({})}));
vi.mock('@/lib/handleError',()=>({handleErrorSilent:vi.fn()}));
vi.mock('sonner',()=>({toast:{success:mocks.success,error:mocks.error}}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc,from:()=>{
 const query:any={};for(const method of ['select','eq','gte','order','limit'])query[method]=()=>query;
 query.then=(resolve:any,reject:any)=>Promise.resolve(mocks.result).then(resolve,reject);return query;
}}}));

beforeEach(()=>{vi.clearAllMocks();mocks.result={data:[],error:null};mocks.rpc.mockResolvedValue({data:null,error:null});});
describe('lectures secondaires soignant',()=>{
 it('bloque la modification des disponibilités inconnues, puis permet une reprise réussie',async()=>{
  mocks.result.error=new Error('503');render(<MesDisponibilites/>);
  expect(await screen.findByRole('alert')).toHaveTextContent('Disponibilités indisponibles');expect(screen.queryByRole('button',{name:'Jour'})).not.toBeInTheDocument();
  mocks.result.error=null;fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));expect((await screen.findAllByRole('button',{name:'Jour'})).length).toBe(28);
 });
 it('ne présente pas un historique de conformité vide à la place d’une panne',async()=>{
  mocks.result.error=new Error('503');render(<ConformiteContent/>);
  expect(await screen.findByRole('alert')).toHaveTextContent('Conformité indisponible');expect(screen.queryByText('Aucun contrôle de conformité')).not.toBeInTheDocument();
  mocks.result.error=null;fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));expect(await screen.findByText('Aucun contrôle de conformité')).toBeVisible();
 });
 it('signale un export refusé sans annoncer une copie réussie',async()=>{
  Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:vi.fn().mockRejectedValue(new Error('denied'))}});render(<ConformiteContent/>);
  fireEvent.click(await screen.findByRole('button',{name:'Exporter'}));await waitFor(()=>expect(mocks.error).toHaveBeenCalledWith('Impossible de copier l’historique. Réessayez.'));expect(mocks.success).not.toHaveBeenCalled();
 });
});
