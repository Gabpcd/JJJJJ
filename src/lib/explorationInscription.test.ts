import { beforeEach, expect, it, vi } from 'vitest';
import { chargerMissionsInscription, missionCorrespondProfessionInscription, preparerCandidatureInscription } from './explorationInscription';
const mocks = vi.hoisted(() => ({ rpc: vi.fn(), enregistrer: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({supabase:{rpc:mocks.rpc}}));
vi.mock('@/lib/inscriptionProgressive', () => ({enregistrerParcours:mocks.enregistrer}));
beforeEach(()=>vi.resetAllMocks());
it('ne perd pas les offres après la première page et conserve la rétrocession et le planning', async ()=>{
  const mission = (id: string) => ({id,mode_remuneration:'RETROCESSION',retrocession_pct:70,nb_creneaux:1,
    debut_le:'2027-01-12T07:00:00Z',fin_le:'2027-01-12T15:00:00Z',creneaux:[{id:`c-${id}`,mission_id:id,debut:'2027-01-12T07:00:00Z',fin:'2027-01-12T15:00:00Z',est_pause:false,type_creneau:'PREVISIONNEL'}]});
  mocks.rpc.mockResolvedValueOnce({data:Array.from({length:100},(_,i)=>mission(String(i))),error:null})
    .mockResolvedValueOnce({data:[mission('derniere')],error:null});
  const offres=await chargerMissionsInscription();
  expect(offres).toHaveLength(101);
  expect(offres[100]).toMatchObject({id:'derniere',mode_remuneration:'RETROCESSION',retrocession_pct:70,creneaux:[expect.objectContaining({mission_id:'derniere'})]});
  expect(mocks.rpc).toHaveBeenLastCalledWith('fn_explorer_missions_inscription',{p_mission_id:null,p_offset:100,p_limit:100});
});
it('mémorise la mission sans envoyer de candidature', async ()=>{
  expect(await preparerCandidatureInscription('mission-cible')).toBe('/inscription/completer');
  expect(mocks.enregistrer).toHaveBeenCalledWith({missionChoisie:'mission-cible'});
  expect(mocks.rpc).not.toHaveBeenCalled();
});
it('conserve la hiérarchie professionnelle déjà utilisée pour les profils complets',()=>{
  expect(missionCorrespondProfessionInscription('IDE','','IADE')).toBe(true);
  expect(missionCorrespondProfessionInscription('IADE','','IDE')).toBe(false);
  expect(missionCorrespondProfessionInscription('IDE','SAGE_FEMME','IADE')).toBe(false);
  expect(missionCorrespondProfessionInscription('SAGE_FEMME','SAGE_FEMME','IADE')).toBe(true);
});
