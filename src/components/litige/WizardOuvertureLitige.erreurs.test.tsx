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
  vi.resetAllMocks();const q:any={};for(const method of ['select','eq','in'])q[method]=()=>q;
  q.order=()=>Promise.resolve({data:[1,2].map(n=>({id:`facture${n}`,numero_facture:`F-${n}`,montant_ttc:100,statut:'EMISE'})),error:null});mocks.from.mockReturnValue(q);
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
});
