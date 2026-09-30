import {fireEvent,render,screen,waitFor} from '@testing-library/react';
import {beforeEach,describe,expect,it,vi} from 'vitest';
import {ModaleEvaluerSoignant} from './ModaleEvaluerSoignant';

const mocks=vi.hoisted(()=>({rpc:vi.fn(),notification:vi.fn()}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc}}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:mocks.notification})}));
const mission={mission_id:'mission-synthetique',intitule:'Mission de recette',soignant_prenom:'Camille',soignant_nom:'Recette',soignant_profession:'IDE',fin_le:'2026-09-29T15:00:00Z'};
function ouvrir(){
  const fermer=vi.fn(),evaluee=vi.fn();
  render(<ModaleEvaluerSoignant mission={mission} onFermer={fermer} onEvaluee={evaluee}/>);
  for(const critere of ['Ponctualité','Qualité technique','Relationnel équipe','Conformité protocole'])
    fireEvent.click(screen.getByRole('button',{name:`${critere} : 5/5`}));
  fireEvent.change(screen.getByRole('textbox'),{target:{value:'Commentaire conservé'}});
  return {fermer,evaluee,envoyer:screen.getByRole('button',{name:"Envoyer l'évaluation"})};
}
beforeEach(()=>{mocks.rpc.mockReset();mocks.notification.mockReset();});
describe('erreur de notation dans le dialogue établissement',()=>{
  it('annonce le refus dans le formulaire et conserve la saisie pour le réessai',async()=>{
    mocks.rpc.mockResolvedValueOnce({data:{success:false,error:'Accès non autorisé à cette mission.'},error:null})
      .mockResolvedValueOnce({data:{success:true},error:null});
    const {fermer,evaluee,envoyer}=ouvrir();
    fireEvent.click(envoyer);
    expect(await screen.findByRole('alert')).toHaveTextContent('Accès non autorisé à cette mission.');
    expect(screen.getByRole('dialog')).toContainElement(screen.getByRole('alert'));
    expect(screen.getByRole('textbox')).toHaveValue('Commentaire conservé');
    expect(fermer).not.toHaveBeenCalled();expect(evaluee).not.toHaveBeenCalled();expect(mocks.notification).not.toHaveBeenCalled();
    fireEvent.click(envoyer);
    await waitFor(()=>expect(evaluee).toHaveBeenCalledOnce());
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
    expect(mocks.rpc.mock.calls[1]).toEqual(mocks.rpc.mock.calls[0]);
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(mocks.notification).toHaveBeenCalledWith({type:'succes',message:'Évaluation enregistrée. Merci !'});
  });
  it('désactive l’envoi pendant la requête et empêche le double appel',async()=>{
    let terminer!: (r:unknown)=>void;
    mocks.rpc.mockReturnValue(new Promise(resolve=>{terminer=resolve;}));
    const {envoyer,evaluee}=ouvrir();
    fireEvent.click(envoyer);fireEvent.click(envoyer);
    expect(envoyer).toBeDisabled();expect(mocks.rpc).toHaveBeenCalledOnce();
    terminer({data:{success:true},error:null});
    await waitFor(()=>expect(evaluee).toHaveBeenCalledOnce());
  });
  it('rend le formulaire réutilisable après une exception réseau',async()=>{
    mocks.rpc.mockRejectedValueOnce(new TypeError('Failed to fetch'));
    const {envoyer,fermer,evaluee}=ouvrir();fireEvent.click(envoyer);
    expect(await screen.findByRole('alert')).toHaveTextContent('Erreur de connexion. Vérifiez votre accès internet.');
    expect(envoyer).toBeEnabled();expect(screen.getByRole('textbox')).toHaveValue('Commentaire conservé');
    expect(fermer).not.toHaveBeenCalled();expect(evaluee).not.toHaveBeenCalled();
  });
  it.each([
    [{code:'PGRST301',message:'JWT expired'},'Votre session a expiré ou n’est plus valide. Reconnectez-vous puis réessayez.'],
    [{message:'Failed to fetch'},'Erreur de connexion. Vérifiez votre accès internet.'],
  ])('traduit aussi une erreur renvoyée par Supabase : %j',async(error,message)=>{
    mocks.rpc.mockResolvedValueOnce({data:null,error});
    const {envoyer,evaluee}=ouvrir();fireEvent.click(envoyer);
    expect(await screen.findByRole('alert')).toHaveTextContent(message);
    expect(envoyer).toBeEnabled();expect(evaluee).not.toHaveBeenCalled();
    expect(screen.getByRole('textbox')).toHaveValue('Commentaire conservé');
  });
  it('ne transforme pas une réponse absente en succès',async()=>{
    mocks.rpc.mockResolvedValueOnce({data:null,error:null});
    const {envoyer,evaluee}=ouvrir();fireEvent.click(envoyer);
    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible d’enregistrer l’évaluation.');
    expect(evaluee).not.toHaveBeenCalled();expect(mocks.notification).not.toHaveBeenCalled();
  });
});
