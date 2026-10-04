import React from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useLocation, useNavigate } from 'react-router-dom';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import PageConnexion from './PageConnexion';
import PscCallback from './PscCallback';
import MissionDepuisNotification from './MissionDepuisNotification';
import { RouteProtegee } from '@/components/RouteProtegee';
// Les réponses RPC positives injectées pour SOIGNANT vérifient le routage seul.
// Le trigger de famille interdit normalement SOIGNANT + adhésion active ; le
// banc PostgreSQL prépare le refus réel, sans fabriquer cette association.
const M='11111111-1111-4111-8111-111111111111';
const retour='/etablissement/missions/'+M;
const mocks=vi.hoisted(()=>({role:'SOIGNANT',connected:false,allowed:true,invoke:vi.fn(),verifyOtp:vi.fn(),rpc:vi.fn(),ouvrir:vi.fn(),afficherNotification:vi.fn()}));
vi.mock('@/hooks/usePageTitle',()=>({usePageTitle:()=>undefined}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({connexion:vi.fn(),loading:false,user:mocks.connected?{id:'psc-membre-B'}:null,session:mocks.connected?{user:{id:'psc-membre-B',email_confirmed_at:'confirmed'}}:null})}));
vi.mock('@/hooks/useRole',()=>({useRole:()=>({role:mocks.role,loading:false,resolved:true,error:null,retry:vi.fn(),parcours:null})}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:mocks.afficherNotification})}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc,functions:{invoke:mocks.invoke},from:()=>{throw new Error('Lecture RLS inattendue');},auth:{verifyOtp:mocks.verifyOtp,getSession:async()=>({data:{session:null}})}}}));
vi.mock('@/lib/platform',()=>({isNative:()=>false}));
vi.mock('@/lib/biometric',()=>({isBiometricAvailable:async()=>false,isBiometricEnabled:()=>false,getBiometricLabel:()=> 'Face ID'}));
vi.mock('@/lib/haptics',()=>({hapticNotification:vi.fn()}));
vi.mock('@/lib/logger',()=>({logger:{debug:vi.fn(),error:vi.fn(),warn:vi.fn()}}));
vi.mock('@/lib/pscNavigation',()=>({ouvrirUrlPsc:mocks.ouvrir}));
vi.mock('@/components/AuthLayout',()=>({AuthLayout:({children}:any)=><>{children}</>}));
vi.mock('@/components/FooterLegal',()=>({FooterLegal:()=>null}));
vi.mock('@/components/LogoJolene',()=>({LogoJolene:()=>null}));
vi.mock('@/components/ModalePscPreAuth',()=>({ModalePscPreAuth:({open,onContinue}:any)=>open?<button onClick={onContinue}>Continuer vers Pro Santé Connect</button>:null}));
vi.mock('@/components/ChargementPage',()=>({ChargementPage:()=> <p>Chargement</p>}));
vi.mock('@/pages/DetailMission',()=>({default:()=> <h1>Détail habituel</h1>}));
vi.mock('@/components/ListeCandidatures',()=>({ListeCandidatures:()=> <p>Liste B autorisée</p>}));
function Position(){const location=useLocation(),navigate=useNavigate();return <><output data-testid='position'>{location.pathname+location.search}</output><button onClick={()=>navigate('/autre')}>Quitter la reprise</button></>;}
function afficher(path:string){return render(<MemoryRouter initialEntries={[path]}><Position/><Routes>
 <Route path='/connexion' element={<PageConnexion/>}/><Route path='/auth/psc/callback' element={<PscCallback/>}/>
 <Route path='/etablissement/missions/:id' element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT','ADMIN_GROUPE','SOIGNANT','ADMIN_PLATEFORME']}><MissionDepuisNotification/></RouteProtegee>}/>
 <Route path='/soignant/tableau-de-bord' element={<p>Dashboard soignant</p>}/><Route path='/inscription/soignant/completion' element={<p>Complétion obligatoire</p>}/>
 <Route path='/' element={<p>Accueil</p>}/><Route path='/autre' element={<p>Autre page choisie</p>}/>
 </Routes></MemoryRouter>);}
const callback=(target=retour,extra='')=>'/auth/psc/callback?status=success&token_hash=synthetique&return='+encodeURIComponent(target)+extra;
async function finaliser(path:string){vi.useFakeTimers();window.history.replaceState(null,'',path);afficher(path);await act(async()=>{});await act(async()=>{await vi.advanceTimersByTimeAsync(1500);});}
beforeEach(()=>{vi.clearAllMocks();mocks.role='SOIGNANT';mocks.connected=false;mocks.allowed=true;
 mocks.verifyOtp.mockImplementation(async()=>{mocks.connected=true;return {error:null};});mocks.ouvrir.mockResolvedValue(true);
 mocks.invoke.mockResolvedValue({data:{authorization_url:'https://auth.esw.esante.gouv.fr/auth'},error:null});
 mocks.rpc.mockImplementation(async(name)=>{
  if(name==='fn_get_my_role')return {data:{role:mocks.role},error:null};
  if(name==='fn_lire_candidatures_mission_habilitee')return mocks.allowed?{data:{mission:{id:M,intitule:'Mission B',etablissement_nom:'Établissement B',statut:'OUVERTE',mode_attribution:'CANDIDATURE',nb_creneaux:1},candidatures:[],creneaux:[]},error:null}:{data:null,error:new Error('Accès refusé')};
  throw new Error('RPC inattendue '+name);
 });vi.stubGlobal('fetch',()=>{throw new Error('Réseau interdit');});
});
afterEach(()=>{cleanup();vi.useRealTimers();vi.unstubAllGlobals();window.history.replaceState(null,'','/');});
it.each([retour,'https://evil.invalid'+retour])('connexion → vrai bouton PSC transmet seulement un retour canonique (%s)',async target=>{
 afficher('/connexion?return='+encodeURIComponent(target));
 fireEvent.click(await screen.findByRole('button',{name:"S'identifier avec Pro Santé Connect"}));
 expect(mocks.invoke).not.toHaveBeenCalled();
 fireEvent.click(screen.getByRole('button',{name:'Continuer vers Pro Santé Connect'}));
 await waitFor(()=>expect(mocks.invoke).toHaveBeenCalledWith('psc-authorize',{body:{intention:'login',...(target===retour?{return_to:retour}:{})}}));
 expect(mocks.ouvrir).toHaveBeenCalledTimes(1);
});
it('callback réel → OTP → rôle soignant → vraie garde → mission B habilitée',async()=>{
 mocks.verifyOtp.mockImplementation(async()=>{expect(window.location.search).not.toContain('token_hash');mocks.connected=true;return {error:null};});
 await finaliser(callback());expect(screen.getByText('Établissement B')).toBeTruthy();expect(screen.getByText('Liste B autorisée')).toBeTruthy();
 expect(mocks.verifyOtp).toHaveBeenCalledWith({token_hash:'synthetique',type:'magiclink'});expect(window.location.search).not.toContain('token_hash');
 expect(mocks.rpc).toHaveBeenCalledWith('fn_lire_candidatures_mission_habilitee',{p_mission_id:M});
});
it('la reprise PSC ne crée aucune permission de candidature',async()=>{
 mocks.allowed=false;await finaliser(callback());expect(screen.getByRole('alert')).toBeTruthy();expect(screen.queryByText('Liste B autorisée')).toBeNull();
});
it('PSC ne connecte pas un rôle applicatif groupe à la route notification',async()=>{
 mocks.role='ADMIN_GROUPE';await finaliser(callback());expect(screen.getByText('Accueil')).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalledWith('fn_lire_candidatures_mission_habilitee',expect.anything());
});
it('la complétion du nouveau soignant reste prioritaire',async()=>{
 await finaliser(callback(retour,'&new_user=1'));expect(screen.getByText('Complétion obligatoire')).toBeTruthy();expect(screen.queryByText('Liste B autorisée')).toBeNull();
});
it('le callback ignore un retour externe et conserve le dashboard soignant',async()=>{
 await finaliser(callback('https://evil.invalid'+retour));expect(screen.getByText('Dashboard soignant')).toBeTruthy();
});
it('un échec OTP ne lit pas la mission et la relance conserve seulement le retour canonique',async()=>{
 mocks.verifyOtp.mockResolvedValue({error:new Error('OTP invalide')});mocks.ouvrir.mockResolvedValue(false);
 afficher(callback());fireEvent.click(await screen.findByRole('button',{name:'Réessayer Pro Santé Connect'}));
 await waitFor(()=>expect(screen.getByTestId('position').textContent).toBe('/connexion?return='+encodeURIComponent(retour)));
 expect(mocks.invoke).toHaveBeenCalledWith('psc-authorize',{body:{intention:'login',return_to:retour}});expect(mocks.rpc).not.toHaveBeenCalled();
});
it('quitter pendant le délai empêche une redirection PSC tardive',async()=>{
 vi.useFakeTimers();afficher(callback());await act(async()=>{});expect(screen.getByText('Ouverture de ton espace…')).toBeTruthy();
 fireEvent.click(screen.getByRole('button',{name:'Quitter la reprise'}));await act(async()=>{await vi.advanceTimersByTimeAsync(1500);});
 expect(screen.getByText('Autre page choisie')).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalled();
});
