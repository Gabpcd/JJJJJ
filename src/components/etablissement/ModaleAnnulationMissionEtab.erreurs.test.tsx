import React from 'react';
import {act,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {beforeEach,describe,expect,it,vi} from 'vitest';
import {ModaleAnnulationMissionEtab} from './ModaleAnnulationMissionEtab';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),from:vi.fn(),notify:vi.fn(),close:vi.fn(),annulee:vi.fn()}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc,from:mocks.from}}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:mocks.notify})}));
const mission={id:'mission',intitule:'Mission fictive',statut:'ASSIGNEE',debut_le:'2099-10-01T07:00Z',fin_le:'2099-10-01T11:00Z',duree_heures:4,taux_horaire_base:30,type_contrat_applique:'LIBERAL'};
const detail='Le service nécessite une vérification avant de poursuivre.';
describe('Annulation — erreur et reprise',()=>{
 beforeEach(()=>{vi.resetAllMocks();const q:any={};q.select=q.eq=()=>q;q.limit=()=>Promise.resolve({data:[],error:null});q.maybeSingle=()=>Promise.resolve({data:null,error:null});mocks.from.mockReturnValue(q);});
 it('ne promet pas de notification à un soignant absent pour une mission ouverte',async()=>{
  render(<ModaleAnnulationMissionEtab ouvert mission={{...mission,statut:'OUVERTE'}} onFermer={mocks.close}/>);
  expect(await screen.findByText('La mission ne sera plus proposée aux soignants.')).toBeInTheDocument();
  expect(screen.queryByText(/notifié immédiatement|push \+ email/)).not.toBeInTheDocument();
 });
 it.each(['annulation','force-majeure','transport'] as const)('conserve le formulaire et la bonne branche %s',async(mode)=>{
  const forceMajeure=mode==='force-majeure';
  mocks.rpc.mockResolvedValueOnce(mode==='transport'?{data:null,error:{message:'Failed to fetch'}}:{data:{success:false,error_code:'NON_AUTORISE',...(forceMajeure?{error:'La revue ne peut pas être ouverte.'}:{})},error:null});
  render(<ModaleAnnulationMissionEtab ouvert mission={mission} onFermer={mocks.close} onAnnulee={mocks.annulee}/>);
  const motif=screen.getByLabelText(/Motif de l'annulation/);fireEvent.change(motif,{target:{value:forceMajeure?'CAS_FORCE_MAJEURE':'AUTRE'}});
  const texte=screen.getByLabelText(/Explication détaillée/);fireEvent.change(texte,{target:{value:detail}});fireEvent.click(screen.getByRole('checkbox'));
  const envoyer=screen.getByRole('button',{name:forceMajeure?'Demander la revue':'Confirmer l’annulation'});await waitFor(()=>expect(envoyer).toBeEnabled());
  if(!forceMajeure)expect(screen.getByText(/Le soignant pourra consulter l’annulation dans son suivi de mission/)).toBeInTheDocument();
  fireEvent.click(envoyer);
  expect(await screen.findByRole('alert')).toHaveTextContent(mode==='transport'?'Erreur de connexion':forceMajeure?'La revue ne peut pas':"Vous n'êtes pas autorisé");
  expect(texte).toHaveValue(detail);expect(motif).toHaveValue(forceMajeure?'CAS_FORCE_MAJEURE':'AUTRE');expect(screen.getByRole('checkbox')).toBeChecked();
  expect(mocks.close).not.toHaveBeenCalled();expect(mocks.annulee).not.toHaveBeenCalled();expect(mocks.notify).not.toHaveBeenCalled();
  let finir!:(value:unknown)=>void;mocks.rpc.mockImplementationOnce(()=>new Promise(resolve=>{finir=resolve;}));fireEvent.click(envoyer);fireEvent.click(envoyer);
  expect(envoyer).toBeDisabled();expect(screen.getByRole('button',{name:'Garder la mission'})).toBeDisabled();fireEvent.click(screen.getByRole('button',{name:'Fermer'}));expect(mocks.close).not.toHaveBeenCalled();
  await act(async()=>finir({data:{success:true,indemnite_montant:0},error:null}));
  expect(mocks.rpc).toHaveBeenCalledTimes(2);expect(mocks.close).toHaveBeenCalledTimes(1);expect(mocks.annulee).toHaveBeenCalledTimes(forceMajeure?0:1);
  const name=forceMajeure?'fn_ouvrir_litige_rate_limited':'fn_annuler_mission_etab';
  const body=forceMajeure?{p_mission_id:'mission',p_type_litige:'AUTRE',p_motif:`Demande de revue avant annulation pour force majeure : ${detail}`}:{p_mission_id:'mission',p_motif_categorie:'AUTRE',p_texte_libre:detail};
  for(const call of mocks.rpc.mock.calls)expect(call).toEqual([name,body]);expect(mocks.notify).toHaveBeenCalledWith(expect.objectContaining({type:'succes'}));
 });
});
