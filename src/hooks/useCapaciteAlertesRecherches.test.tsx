import { beforeEach, describe, expect, it, vi } from 'vitest';
import { act, renderHook, waitFor } from '@testing-library/react';
import { useCapaciteAlertesRecherches } from './useCapaciteAlertesRecherches';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),user:{id:'membre-valide'}}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc}}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:mocks.user})}));
beforeEach(()=>{mocks.user={id:'membre-valide'};mocks.rpc.mockReset().mockResolvedValue({data:true,error:null});});
describe('découverte rétrocompatible puis capacité réelle du serveur',()=>{
 it('ancien backend : clé absente false, aucun appel au nouvel endpoint',async()=>{
  mocks.rpc.mockResolvedValue({data:false,error:null});
  const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
  expect(result.current.disponible).toBe(false);expect(result.current.erreur).toBeNull();
  expect(mocks.rpc.mock.calls).toEqual([['fn_param_bool',{p_cle:'api_alertes_recherches_v1',p_defaut:false}]]);
 });
 it('reste fermée après découverte tant que la capacité ne répond pas',async()=>{
  let resolve!:(result:unknown)=>void;
  mocks.rpc.mockImplementation((nom:string)=>nom==='fn_param_bool'?Promise.resolve({data:true,error:null}):new Promise(r=>{resolve=r;}));
  const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledWith('fn_capacite_alertes_recherches'));
  expect(result.current.disponible).toBe(false);
  await act(async()=>resolve({data:true,error:null}));
  expect(result.current.disponible).toBe(true);expect(result.current.erreur).toBeNull();
 });
 it('nouvelle API mais worker périmé ou compte hors périmètre : activation fermée',async()=>{
  mocks.rpc.mockImplementation((nom:string)=>Promise.resolve({data:nom==='fn_param_bool',error:null}));
  const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
  expect(result.current.disponible).toBe(false);expect(result.current.erreur).toBeNull();
 });
 it.each([{data:null,error:{code:'PGRST202'}},{data:{success:true},error:null}])('API annoncée mais absente/invalide : erreur explicite %j',async value=>{
  mocks.rpc.mockImplementation((nom:string)=>Promise.resolve(nom==='fn_param_bool'?{data:true,error:null}:value));
  const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
  expect(result.current.disponible).toBe(false);expect(result.current.erreur).toContain('service d’alertes annoncé');
 });
 it.each([{data:null,error:{message:'503'}},{data:'true',error:null}])('une découverte en panne/invalide reste une erreur et ne sonde pas la nouvelle API %j',async value=>{
  mocks.rpc.mockResolvedValue(value);const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
  expect(result.current.erreur).toContain('Impossible de vérifier');expect(mocks.rpc).toHaveBeenCalledTimes(1);
 });
 it('revérifie la découverte après déploiement puis conserve la vérification du worker',async()=>{
  mocks.rpc.mockResolvedValueOnce({data:false,error:null});const {result}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
  act(()=>result.current.reessayer());await waitFor(()=>expect(result.current.disponible).toBe(true));
  expect(mocks.rpc.mock.calls.map(c=>c[0])).toEqual(['fn_param_bool','fn_param_bool','fn_capacite_alertes_recherches']);
 });
 it('ne réutilise pas la capacité du précédent utilisateur',async()=>{
  const {result,rerender}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  await waitFor(()=>expect(result.current.disponible).toBe(true));
  mocks.user={id:'detache'};mocks.rpc.mockImplementation((nom:string)=>Promise.resolve({data:nom==='fn_param_bool',error:null}));rerender();
  expect(result.current.disponible).toBe(false);
  await waitFor(()=>expect(result.current.verificationEnCours).toBe(false));
 });
 it('ne change pas les alertes soignant et ne fait aucune découverte inutile',()=>{
  const {result}=renderHook(()=>useCapaciteAlertesRecherches('SOIGNANT_RECHERCHE_MISSIONS'));
  expect(result.current.disponible).toBe(true);expect(mocks.rpc).not.toHaveBeenCalled();
 });
 it('ne sonde pas la capacité après une découverte résolue après démontage',async()=>{
  let resolve!:(result:unknown)=>void;mocks.rpc.mockImplementation(()=>new Promise(r=>{resolve=r;}));
  const {unmount}=renderHook(()=>useCapaciteAlertesRecherches('ETAB_RECHERCHE_SOIGNANTS'));
  unmount();await act(async()=>resolve({data:true,error:null}));expect(mocks.rpc).toHaveBeenCalledTimes(1);
 });
});
