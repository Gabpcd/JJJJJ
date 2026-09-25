import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, renderHook, waitFor } from '@testing-library/react';
import { useCapaciteAlertesRecherches } from './useCapaciteAlertesRecherches';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),user:{id:'membre-valide'}}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc}}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:mocks.user})}));
beforeEach(()=>{mocks.user={id:'membre-valide'};mocks.rpc.mockReset().mockResolvedValue({data:true,error:null});});
describe('activation établissement liée à la capacité réelle du serveur',()=>{
 it('reste fermée tant que la RPC ne répond pas puis active seulement true',async()=>{
  let resolve!:(result:unknown)=>void;mocks.rpc.mockImplementation(()=>new Promise(r=>{resolve=r;}));
  const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  expect(result.current.disponible).toBe(false);
  await act(async()=>resolve({data:true,error:null}));
  expect(result.current.disponible).toBe(true);
 });
 it.each([{data:null,error:{code:'PGRST202'}},{data:false,error:null},{data:{success:true},error:null}])('capacité absente/invalide ne déverrouille pas %j',async value=>{
  mocks.rpc.mockResolvedValue(value);const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));expect(result.current.disponible).toBe(false);
 });
 it('permet de revérifier après déploiement ou panne',async()=>{
  mocks.rpc.mockResolvedValueOnce({error:{message:'503'}});const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
  act(()=>result.current.reessayer());await waitFor(()=>expect(result.current.disponible).toBe(true));
 });
 it('ne réutilise pas la capacité du précédent utilisateur',async()=>{
  const {result,rerender}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.disponible).toBe(true));
  mocks.user={id:'detache'};mocks.rpc.mockResolvedValue({data:false,error:null});rerender();
  expect(result.current.disponible).toBe(false);
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
 });
});
