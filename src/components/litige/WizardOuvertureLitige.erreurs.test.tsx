import React from 'react';
import {act,fireEvent,render,screen,waitFor} from '@testing-library/react';
import {beforeEach,describe,expect,it,vi} from 'vitest';
import {WizardOuvertureLitige} from './WizardOuvertureLitige';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),from:vi.fn(),notify:vi.fn(),close:vi.fn(),success:vi.fn()}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc,from:mocks.from}}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:mocks.notify})}));
const detail='La période contestée contient une différence à vérifier.';
async function remplir(){
 render(<WizardOuvertureLitige missionId="mission" factureHonorairesId="facture2" initialType="PAIEMENT" onClose={mocks.close} onSuccess={mocks.success}/>);
 await waitFor(()=>expect(screen.getByLabelText(/Facture concernée/)).toHaveValue('facture2'));
 fireEvent.click(screen.getByRole('button',{name:'Suivant'}));
 fireEvent.change(screen.getByLabelText('Décrivez précisément le problème'),{target:{value:detail}});
 fireEvent.click(screen.getByRole('button',{name:'Suivant'}));
 expect(screen.getByText('Le suivi du litige est disponible dans l’app.')).toBeInTheDocument();
 expect(screen.queryByText(/notification \+ email immédiate/)).not.toBeInTheDocument();
 return screen.getByRole('button',{name:"Confirmer l'ouverture du litige"});
}
describe('Litige — erreurs dans le formulaire',()=>{
 beforeEach(()=>{
  vi.resetAllMocks();const q:any={};for(const method of ['select','eq','in','order','range'])q[method]=()=>q;
  q.abortSignal=()=>Promise.resolve({data:[{id:'facture2',mission_id:'mission',numero_facture:'F-2',montant_ttc:100,statut:'EMISE'}],count:1,error:null});mocks.from.mockReturnValue(q);
 });
 it.each(['metier','retour-session','rejet-reseau'] as const)('conserve étape, facture et détail après %s puis réessaie une seule fois',async(mode)=>{
  if(mode==='rejet-reseau')mocks.rpc.mockRejectedValueOnce(new TypeError('Failed to fetch'));
  else mocks.rpc.mockResolvedValueOnce(mode==='metier'?{data:{error:'Cette échéance ne peut pas être contestée.'},error:null}:{data:null,error:{code:'PGRST301',message:'JWT expired'}});
  let envoyer=await remplir();fireEvent.click(envoyer);
  const erreur=await screen.findByRole('alert');expect(erreur).toHaveTextContent(mode==='metier'?'Cette échéance':mode==='retour-session'?'Votre session a expiré':'Erreur de connexion');
  expect(envoyer).toBeEnabled();expect(mocks.close).not.toHaveBeenCalled();expect(mocks.notify).not.toHaveBeenCalled();expect(mocks.success).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button',{name:'Précédent'}));expect(screen.getByLabelText('Décrivez précisément le problème')).toHaveValue(detail);
  fireEvent.click(screen.getByRole('button',{name:'Suivant'}));
  envoyer=screen.getByRole('button',{name:"Confirmer l'ouverture du litige"});
  let finir!:(value:unknown)=>void;mocks.rpc.mockImplementationOnce(()=>new Promise(resolve=>{finir=resolve;}));
  fireEvent.click(envoyer);fireEvent.click(envoyer);
  expect(envoyer).toBeDisabled();expect(screen.getByRole('button',{name:'Précédent'})).toBeDisabled();
  fireEvent.click(screen.getByRole('button',{name:'Fermer'}));expect(mocks.close).not.toHaveBeenCalled();expect(mocks.rpc).toHaveBeenCalledTimes(2);
  await act(async()=>finir({data:{success:true,litige_id:'litige'},error:null}));
  expect(mocks.close).toHaveBeenCalledTimes(1);expect(mocks.success).toHaveBeenCalledTimes(1);expect(mocks.notify).toHaveBeenCalledWith(expect.objectContaining({type:'succes'}));
  for(const [name,body] of mocks.rpc.mock.calls)expect({name,body}).toEqual({name:'fn_ouvrir_litige_rate_limited',body:{p_mission_id:'mission',p_type_litige:'DESACCORD_MONTANT_FACTURE',p_motif:`[PAIEMENT] ${detail}`,p_facture_id:'facture2'}});
 });
 it('bloque la lecture en erreur, reprend la pièce exacte et refuse une réponse de création ambiguë',async()=>{
  const q=mocks.from();q.abortSignal=vi.fn().mockResolvedValueOnce({data:null,count:null,error:{message:'technical detail'}})
   .mockResolvedValue({data:[{id:'facture2',mission_id:'mission',numero_facture:'F-2',montant_ttc:100,statut:'PAYEE'}],count:1,error:null});
  render(<WizardOuvertureLitige missionId="mission" factureHonorairesId="facture2" initialType="PAIEMENT" onClose={mocks.close}/>);
  expect(screen.getByRole('button',{name:'Suivant'})).toBeDisabled();
  expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de vérifier la facture');
  expect(mocks.rpc).not.toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button',{name:'Réessayer le chargement des factures'}));
  await waitFor(()=>expect(screen.getByRole('button',{name:'Suivant'})).toBeEnabled());
  expect(screen.getByLabelText(/Facture concernée/)).toBeDisabled();
  fireEvent.click(screen.getByRole('button',{name:'Suivant'}));
  fireEvent.change(screen.getByLabelText('Décrivez précisément le problème'),{target:{value:detail}});
  fireEvent.click(screen.getByRole('button',{name:'Suivant'}));
  mocks.rpc.mockResolvedValueOnce({data:{success:false},error:null});
  fireEvent.click(screen.getByRole('button',{name:"Confirmer l'ouverture du litige"}));
  expect(await screen.findByRole('alert')).toHaveTextContent('n’a pas pu être confirmée');
  expect(mocks.close).not.toHaveBeenCalled();expect(mocks.notify).not.toHaveBeenCalled();
 });
 it('n’envoie pas la pièce de la mission précédente pendant une lecture retenue puis refusée',async()=>{
  const q=mocks.from();let terminer!:(value:unknown)=>void;
  q.abortSignal=vi.fn().mockResolvedValueOnce({data:[{id:'facture2',mission_id:'mission',numero_facture:'F-2',montant_ttc:100,statut:'PAYEE'}],count:1,error:null})
   .mockImplementationOnce(()=>new Promise(resolve=>{terminer=resolve;}));
  const {rerender}=render(<WizardOuvertureLitige missionId="mission" initialType="CONDITIONS" onClose={mocks.close}/>);
  await act(async()=>{});
  fireEvent.click(screen.getByRole('button',{name:'Suivant'}));
  fireEvent.change(screen.getByLabelText('Décrivez précisément le problème'),{target:{value:detail}});
  fireEvent.click(screen.getByRole('button',{name:'Suivant'}));
  expect(screen.getByText('F-2')).toBeInTheDocument();
  rerender(<WizardOuvertureLitige missionId="mission-b" initialType="CONDITIONS" onClose={mocks.close}/>);
  expect(screen.queryByText('F-2')).not.toBeInTheDocument();
  expect(screen.queryByText('Facture ciblée')).not.toBeInTheDocument();
  mocks.rpc.mockResolvedValue({data:{error:'Refus métier simulé'},error:null});
  fireEvent.click(screen.getByRole('button',{name:"Confirmer l'ouverture du litige"}));
  await screen.findByRole('alert');
  await act(async()=>terminer({data:null,count:null,error:{code:'42501'}}));
  expect(screen.queryByText('Facture ciblée')).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('button',{name:"Confirmer l'ouverture du litige"}));
  await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledTimes(2));
  for(const [,body] of mocks.rpc.mock.calls)expect(body).toEqual({p_mission_id:'mission-b',p_type_litige:'CONDITIONS_MISSION_NON_RESPECTEES',p_motif:`[CONDITIONS] ${detail}`});
  expect(mocks.close).not.toHaveBeenCalled();expect(mocks.notify).not.toHaveBeenCalled();
 });
});
