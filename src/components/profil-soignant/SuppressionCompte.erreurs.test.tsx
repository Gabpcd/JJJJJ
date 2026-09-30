import {fireEvent,render,screen,waitFor} from '@testing-library/react';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {SectionConfidentialite} from './SectionConfidentialite';
import {ProfilEtablissementContent} from '@/pages/ProfilEtablissement';

const mocks=vi.hoisted(()=>({invoke:vi.fn(),rpc:vi.fn(),signOut:vi.fn(),notification:vi.fn(),navigate:vi.fn(),user:{id:'compte-fictif'}}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{functions:{invoke:mocks.invoke},rpc:mocks.rpc,auth:{signOut:mocks.signOut}},SUPABASE_URL:'http://localhost',SUPABASE_PUBLISHABLE_KEY:'test'}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:mocks.user,deconnexion:vi.fn()})}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:mocks.notification})}));
vi.mock('@/hooks/useRole',()=>({useRole:()=>({role:'SOIGNANT'})}));
vi.mock('react-router-dom',()=>({useNavigate:()=>mocks.navigate}));
vi.mock('@tanstack/react-query',()=>({useQueryClient:()=>({})}));
vi.mock('@/lib/sentry',()=>({capturerErreurSentry:vi.fn()}));
vi.mock('@/components/LayoutApp',()=>({LayoutApp:()=>null}));
vi.mock('@/lib/stripe',()=>({isStripeConfigured:false,stripePromise:null}));
vi.mock('@stripe/react-stripe-js',()=>({Elements:()=>null,IbanElement:()=>null,useStripe:()=>null,useElements:()=>null}));

beforeEach(()=>{
  vi.stubEnv('DEV',false); // Même message utilisateur que la preview compilée.
  vi.clearAllMocks();mocks.invoke.mockReset();
  mocks.rpc.mockResolvedValue({data:{id:'compte-fictif',nom:'Recette',type:'CLINIQUE_PRIVEE',siret:'00000000000000'},error:null});
  mocks.signOut.mockResolvedValue({error:null});
});
afterEach(()=>vi.unstubAllEnvs());

for(const famille of ['soignant','etablissement'] as const)describe(`suppression ${famille}`,()=>{
  async function ouvrir(){
    render(famille==='soignant'?<SectionConfidentialite userId="compte-fictif"/>:<ProfilEtablissementContent sections={['securite']}/>);
    fireEvent.click(await screen.findByRole('button',{name:'Supprimer mon compte'}));
    const champ=screen.getByPlaceholderText(famille==='soignant'?'Tape SUPPRIMER':'SUPPRIMER');
    const bouton=screen.getByRole('button',{name:famille==='soignant'?'Supprimer définitivement':'Confirmer la suppression'});
    expect(bouton).toBeDisabled();fireEvent.change(champ,{target:{value:'SUPPRIMER'}});
    return {champ,bouton};
  }
  it.each([
    [{data:{success:false,error:'Suppression refusée pour le moment.'},error:null},'Suppression refusée pour le moment.'],
    [{data:null,error:{message:'Failed to fetch'}},'Erreur de connexion. Vérifiez votre accès internet.'],
    [{data:null,error:{code:'PGRST301',message:'JWT expired'}},'Votre session a expiré ou n’est plus valide. Reconnectez-vous puis réessayez.'],
    [{data:null,error:{name:'FunctionsHttpError',message:'Edge Function returned a non-2xx status code'}},'Une erreur est survenue. Veuillez réessayer.'],
    [{data:null,error:null},'Suppression impossible.'],
  ])('garde le refus %j et permet un unique réessai',async(reponse,message)=>{
    mocks.invoke.mockResolvedValueOnce(reponse).mockResolvedValueOnce({data:{success:true},error:null});
    const {champ,bouton}=await ouvrir();fireEvent.click(bouton);
    expect(await screen.findByRole('alert')).toHaveTextContent(message);
    expect(champ).toHaveValue('SUPPRIMER');expect(bouton).toBeEnabled();
    expect(mocks.notification).not.toHaveBeenCalled();expect(mocks.signOut).not.toHaveBeenCalled();expect(mocks.navigate).not.toHaveBeenCalled();
    fireEvent.click(bouton);await waitFor(()=>expect(mocks.navigate).toHaveBeenCalledWith('/'));
    expect(mocks.invoke).toHaveBeenCalledTimes(2);expect(mocks.invoke.mock.calls[0]).toEqual(['delete-account',{body:{}}]);
    expect(mocks.invoke.mock.calls[1]).toEqual(mocks.invoke.mock.calls[0]);
    expect(mocks.signOut).toHaveBeenCalledExactlyOnceWith({scope:'local'});
    expect(mocks.notification).toHaveBeenCalledOnce();expect(mocks.notification.mock.calls[0][0].type).toBe('succes');
  });
  it('conserve la confirmation après une exception réseau',async()=>{
    mocks.invoke.mockRejectedValueOnce(new TypeError('Failed to fetch'));
    const {champ,bouton}=await ouvrir();fireEvent.click(bouton);
    expect(await screen.findByRole('alert')).toHaveTextContent('Erreur de connexion. Vérifiez votre accès internet.');
    expect(champ).toHaveValue('SUPPRIMER');expect(bouton).toBeEnabled();expect(mocks.signOut).not.toHaveBeenCalled();
  });
  it('bloque double clic, annulation et modification pendant la requête',async()=>{
    let terminer!:(value:unknown)=>void;mocks.invoke.mockReturnValue(new Promise(resolve=>{terminer=resolve;}));
    const {champ,bouton}=await ouvrir();fireEvent.click(bouton);fireEvent.click(bouton);
    const annuler=screen.getByRole('button',{name:'Annuler'});
    expect(bouton).toBeDisabled();expect(champ).toBeDisabled();expect(annuler).toBeDisabled();
    fireEvent.click(annuler);expect(champ).toBeInTheDocument();expect(mocks.invoke).toHaveBeenCalledOnce();
    terminer({data:{success:true},error:null});await waitFor(()=>expect(mocks.navigate).toHaveBeenCalledWith('/'));
  });
});
