import { fireEvent, render, screen, cleanup, waitFor } from '@testing-library/react';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import { ListeCandidatures } from './ListeCandidatures';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),from:vi.fn(),score:vi.fn()}));
vi.mock('@/integrations/supabase/client',()=>({supabase:mocks}));
vi.mock('@/components/score/PopoverScoreSoignant',()=>({PopoverScoreSoignant:()=>{mocks.score();return <button>Profil complet</button>;}}));
const slot={id:'slot-B',mission_id:'mission-B',debut:'2026-10-10T08:00:00Z',fin:'2026-10-10T16:00:00Z',est_pause:false,type_creneau:'PREVISIONNEL'};
const candidate={id:'candidate-B',soignant_id:'soignant-B',statut:'EN_ATTENTE',cree_le:'2026-10-02T00:00:00Z',message:null,soignant:{id:'soignant-B',prenom:'Camille',nom:'T.',profession:'IDE',est_etudiant:false,tous_documents_valides:true}};
beforeEach(()=>{mocks.rpc.mockReset();mocks.from.mockReset();mocks.score.mockReset();mocks.from.mockImplementation(()=>{throw new Error('Lecture générique RLS inattendue pour le lecteur habilité');});mocks.rpc.mockResolvedValue({data:{success:true},error:null});vi.stubGlobal('fetch',()=>{throw new Error('Réseau interdit');});window.matchMedia=vi.fn(()=>({matches:false,addEventListener:vi.fn(),removeEventListener:vi.fn(),addListener:vi.fn(),removeListener:vi.fn(),dispatchEvent:vi.fn(),media:'',onchange:null}));});
afterEach(()=>{cleanup();vi.unstubAllGlobals();});
it('utilise les lecteurs B injectés et reconfirme un planning modifié avant la décision',async()=>{
 const lire=vi.fn().mockResolvedValue([candidate]);const changed={...slot,fin:'2026-10-10T17:00:00Z'};
 const planning=vi.fn().mockResolvedValueOnce([slot]).mockResolvedValue([changed]);const success=vi.fn();const accepted=vi.fn();
 render(<ListeCandidatures missionId='mission-B' missionCreneaux={[slot]} missionNbCreneaux={1} chargerCandidaturesHabilitees={lire} chargerPlanningHabilite={planning} onAccepted={accepted} onSuccess={success} onError={vi.fn()}/>);
 fireEvent.click(await screen.findByRole('button',{name:'Accepter cette candidature'}));
 fireEvent.click(await screen.findByRole('button',{name:'Confirmer et assigner'}));
 expect(await screen.findByText(/Le planning a changé depuis l’ouverture/)).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalled();
 fireEvent.click(screen.getByRole('button',{name:'Confirmer et assigner'}));
 await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledWith('fn_traiter_candidature_planning_v1',{p_candidature_id:'candidate-B',p_decision:'ACCEPTEE',p_creneaux_confirmes:[{debut:changed.debut,fin:changed.fin}],p_motif:null}));
 expect(mocks.from).not.toHaveBeenCalled();await waitFor(()=>expect(accepted).toHaveBeenCalledTimes(1));expect(planning).toHaveBeenCalledTimes(3);
});
it('un lecteur habilité refusé ne retombe jamais sur la lecture générique',async()=>{
 render(<ListeCandidatures missionId='mission-B' missionCreneaux={[slot]} missionNbCreneaux={1} chargerCandidaturesHabilitees={async()=>{throw new Error('Adhésion révoquée');}} chargerPlanningHabilite={async()=>[slot]} onAccepted={vi.fn()} onSuccess={vi.fn()} onError={vi.fn()}/>);
 expect(await screen.findByText(/Adhésion révoquée/)).toBeTruthy();expect(mocks.from).not.toHaveBeenCalled();expect(mocks.rpc).not.toHaveBeenCalled();expect(screen.queryByRole('button',{name:'Accepter cette candidature'})).toBeNull();
});

it('affiche les évaluations connues sans proposer le profil groupe non routé',async()=>{
 const note={...candidate,soignant:{...candidate.soignant,score_fiabilite:84,total_missions_terminees:9,note_moyenne:4.6,nb_evaluations:7}};
 render(<ListeCandidatures missionId='mission-B' missionCreneaux={[slot]} missionNbCreneaux={1} chargerCandidaturesHabilitees={async()=>[note]} chargerPlanningHabilite={async()=>[slot]} afficherDetailScore={false} onAccepted={vi.fn()} onSuccess={vi.fn()} onError={vi.fn()}/>);
 expect(await screen.findByText(/84\/100/)).toBeTruthy();expect(screen.getByText(/4.6\/5/)).toBeTruthy();
 expect(screen.queryByText("Pas encore d'évaluation")).toBeNull();expect(mocks.score).not.toHaveBeenCalled();
});
