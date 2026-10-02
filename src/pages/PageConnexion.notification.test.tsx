import React from 'react';
import { fireEvent, render, screen, waitFor, cleanup } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import PageConnexion from './PageConnexion';
import MissionDepuisNotification from './MissionDepuisNotification';
import { RouteProtegee } from '@/components/RouteProtegee';
// Les réponses RPC positives injectées pour SOIGNANT vérifient le routage seul.
// Le trigger de famille interdit normalement SOIGNANT + adhésion active ; le
// banc PostgreSQL prépare le refus réel, sans fabriquer cette association.
const M='11111111-1111-4111-8111-111111111111';
const mocks=vi.hoisted(()=>({role:'ADMIN_GROUPE',connected:false,allowed:true,signed:true,native:false,connexion:vi.fn(),rpc:vi.fn(),getSession:vi.fn(),afficherNotification:vi.fn()}));
vi.mock('@/hooks/usePageTitle',()=>({usePageTitle:()=>undefined}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({connexion:mocks.connexion,loading:false,user:mocks.connected?{id:'user-B'}:null,session:mocks.connected?{user:{id:'user-B',email_confirmed_at:'confirmed'}}:null})}));
vi.mock('@/hooks/useRole',()=>({useRole:()=>({role:mocks.role,loading:false,error:null,parcours:null})}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:mocks.afficherNotification})}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc,from:()=>{throw new Error('Lecture RLS non attendue pour groupe/soignant');},auth:{getSession:mocks.getSession,refreshSession:async()=>{mocks.connected=true;return {error:null};},signOut:vi.fn()}}}));
vi.mock('@/lib/platform',()=>({isNative:()=>mocks.native}));
vi.mock('@/lib/biometric',()=>({isBiometricAvailable:async()=>mocks.native,isBiometricEnabled:()=>mocks.native,authenticateWithBiometric:async()=> 'refresh-fictif',enableBiometric:vi.fn(),getBiometricLabel:()=> 'Face ID'}));
vi.mock('@/lib/haptics',()=>({hapticNotification:vi.fn()}));
vi.mock('@/lib/logger',()=>({logger:{debug:vi.fn(),error:vi.fn(),warn:vi.fn()}}));
vi.mock('@/components/AuthLayout',()=>({AuthLayout:({children}:any)=><>{children}</>}));
vi.mock('@/components/FooterLegal',()=>({FooterLegal:()=>null}));
vi.mock('@/components/BoutonProSanteConnect',()=>({BoutonProSanteConnect:()=>null}));
vi.mock('@/components/ChargementPage',()=>({ChargementPage:()=> <p>Chargement</p>}));
vi.mock('@/pages/DetailMission',()=>({default:()=> <h1>Détail habituel</h1>}));
vi.mock('@/components/ListeCandidatures',()=>({ListeCandidatures:()=> <p>Liste B autorisée</p>}));
function afficher(path=`/etablissement/missions/${M}`){return render(<MemoryRouter initialEntries={[path]}><Routes>
  <Route path='/connexion' element={<PageConnexion/>}/>
  <Route path='/etablissement/missions/:id' element={<RouteProtegee rolesAutorises={['ADMIN_ETABLISSEMENT','ADMIN_GROUPE','SOIGNANT','ADMIN_PLATEFORME']}><MissionDepuisNotification/></RouteProtegee>}/>
  <Route path='/groupe/tableau-de-bord' element={<p>Dashboard groupe</p>}/><Route path='/soignant/tableau-de-bord' element={<p>Dashboard soignant</p>}/>
</Routes></MemoryRouter>);}
async function connexion(){fireEvent.change(await screen.findByLabelText('Email'),{target:{value:'recette@example.invalid'}});fireEvent.change(screen.getByLabelText('Mot de passe'),{target:{value:'synthetique-valide'}});fireEvent.click(screen.getByRole('button',{name:'Se connecter'}));}
beforeEach(()=>{
 vi.clearAllMocks();mocks.role='ADMIN_GROUPE';mocks.connected=false;mocks.allowed=true;mocks.signed=true;mocks.native=false;
 mocks.connexion.mockImplementation(async()=>{mocks.connected=true;});mocks.getSession.mockImplementation(async()=>({data:{session:mocks.connected?{user:{id:'user-B',app_metadata:mocks.signed?{role:mocks.role}:{}}}:null}}));
 mocks.rpc.mockImplementation(async(name)=>{
  if(name==='fn_get_my_role')return {data:{role:mocks.role},error:null};
  if(name==='fn_lire_candidatures_mission_habilitee')return mocks.allowed?{data:{mission:{id:M,intitule:'Mission B',etablissement_nom:'Établissement B',statut:'OUVERTE',mode_attribution:'CANDIDATURE',nb_creneaux:1},candidatures:[],creneaux:[]},error:null}:{data:null,error:new Error('Accès refusé')};
  throw new Error('RPC inattendue '+name);
 });vi.stubGlobal('fetch',()=>{throw new Error('Réseau interdit');});
});
afterEach(()=>{cleanup();vi.unstubAllGlobals();});
it.each([true,false])('notification → vraie garde → connexion groupe → bonne mission (rôle signé=%s)',async signed=>{
 mocks.signed=signed;afficher();await connexion();expect(await screen.findByText('Établissement B')).toBeTruthy();expect(screen.getByText('Liste B autorisée')).toBeTruthy();
 expect(mocks.rpc).toHaveBeenCalledWith('fn_lire_candidatures_mission_habilitee',{p_mission_id:M});
});
it('la reprise groupe ne contourne pas une absence d’adhésion',async()=>{
 mocks.allowed=false;afficher();await connexion();await screen.findByRole('alert');expect(screen.queryByText('Établissement B')).toBeNull();expect(screen.queryByText('Liste B autorisée')).toBeNull();
});
it('la reprise fonctionne pour le membre au rôle applicatif soignant',async()=>{
 mocks.role='SOIGNANT';afficher();await connexion();expect(await screen.findByText('Établissement B')).toBeTruthy();
});
it('la reprise biométrique groupe conserve aussi la mission',async()=>{
 mocks.native=true;afficher();fireEvent.click(await screen.findByRole('button',{name:'Se connecter avec Face ID'}));expect(await screen.findByText('Établissement B')).toBeTruthy();
});
it('un retour externe reste refusé',async()=>{
 afficher('/connexion?return='+encodeURIComponent('https://evil.invalid/etablissement/missions/'+M));await connexion();expect(await screen.findByText('Dashboard groupe')).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalled();
});
