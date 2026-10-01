import React from 'react';
import {act,cleanup,fireEvent,render,screen} from '@testing-library/react';
import {MemoryRouter} from 'react-router-dom';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import ProfilSoignant from './ProfilSoignant';

const mocks=vi.hoisted(()=>({user:{id:'profil-a'} as {id:string}|null,rpc:vi.fn(),notification:vi.fn(),query:{invalidateQueries:vi.fn()}}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:mocks.user,deconnexion:vi.fn()})}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:mocks.notification})}));
vi.mock('@tanstack/react-query',()=>({useQueryClient:()=>mocks.query}));
vi.mock('@/hooks/usePageTitle',()=>({usePageTitle:vi.fn()}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc}}));
vi.mock('@/components/LayoutApp',()=>({LayoutApp:({children}:{children:React.ReactNode})=><main>{children}</main>}));
vi.mock('@/components/AvatarUpload',()=>({AvatarUpload:()=>null}));
vi.mock('@/components/BadgeRPPS',()=>({BadgeRPPS:()=>null}));
vi.mock('@/components/BadgesGamification',()=>({BadgesGamification:()=>null}));
vi.mock('@/components/BadgeNiveauV2',()=>({BadgeNiveauV2:()=>null}));
vi.mock('@/components/score/SectionEvenementsScore',()=>({SectionEvenementsScore:()=>null}));
vi.mock('@/components/profil-soignant/SectionDpaeIdentite',()=>({SectionDpaeIdentite:()=>null}));
vi.mock('@/components/profil-soignant/SectionProfilPrincipal',()=>({SectionProfilPrincipal:({prenom}:{prenom:string})=><input aria-label="Prénom du profil" value={prenom} readOnly/>}));
vi.mock('@/components/profil-soignant/SectionPreferences',()=>({SectionPreferences:()=>null}));
vi.mock('@/components/profil-soignant/SectionConfidentialite',()=>({SectionConfidentialite:({userId}:{userId:string})=><p>Confidentialité de {userId}</p>}));

const profil=(id='profil-a',prenom='Camille')=>({id,prenom,nom:'Recette',email:'fixture@example.invalid',profession:'IDE',specialites:[]});
const pending:{resolve:(value:unknown)=>void;reject:(error:Error)=>void;signal?:AbortSignal}[]=[];
beforeEach(()=>{
  vi.stubGlobal('ResizeObserver',class { observe() {} disconnect() {} unobserve() {} });
  mocks.user={id:'profil-a'};mocks.rpc.mockReset();mocks.notification.mockClear();pending.length=0;
  mocks.rpc.mockImplementation((name:string)=>{
    if(name==='fn_mon_profil_soignant_complet'){
      let resolve!:(v:unknown)=>void,reject!:(e:Error)=>void;const promise=new Promise((a,b)=>{resolve=a;reject=b;});const call={resolve,reject,signal:undefined as AbortSignal|undefined};pending.push(call);
      return {abortSignal(signal:AbortSignal){call.signal=signal;return promise;}};
    }
    const promise=Promise.resolve({data:null,error:null});return Object.assign(promise,{abortSignal:()=>promise});
  });
});
afterEach(()=>{cleanup();vi.useRealTimers();vi.unstubAllGlobals();});
const afficher=(route='/soignant/profil')=>render(<MemoryRouter initialEntries={[route]}><ProfilSoignant/></MemoryRouter>);
const recevoir=async(index:number,data:unknown)=>act(async()=>{pending[index].resolve({data,error:null});});

describe('ProfilSoignant — lecture bornée et état explicite',()=>{
  it('récupère un rejet réseau par un vrai retry sans exposer de formulaire vide',async()=>{
    afficher();await act(async()=>{pending[0].reject(Error('CANARI-token-et-url'));});
    expect(screen.getByRole('alert')).toHaveTextContent('Ton profil n’a pas pu être chargé.');
    expect(screen.queryByRole('status')).not.toBeInTheDocument();expect(screen.queryByLabelText('Prénom du profil')).not.toBeInTheDocument();
    expect(document.body.textContent).not.toContain('CANARI');
    fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));expect(pending[0].signal?.aborted).toBe(true);
    await recevoir(1,profil());expect(screen.getByLabelText('Prénom du profil')).toHaveValue('Camille');expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });
  it('traite aussi l’erreur PostgREST résolue sans données ni message technique affiché',async()=>{
    afficher();await act(async()=>{pending[0].resolve({data:null,error:{message:'CANARI-RPC-503'}});});
    expect(screen.getByRole('alert')).toBeInTheDocument();expect(screen.queryByRole('status')).not.toBeInTheDocument();
    expect(document.body.textContent).not.toContain('CANARI');expect(screen.queryByLabelText('Prénom du profil')).not.toBeInTheDocument();
  });
  it.each([null,{},{id:'profil-a'},[],{error:'Profil introuvable'},profil('autre'),{...profil(),specialites:'{invalide'}])('refuse une réponse invalide %j sans audit de consultation',async data=>{
    afficher();await recevoir(0,data);expect(screen.getByRole('alert')).toBeInTheDocument();expect(screen.queryByLabelText('Prénom du profil')).not.toBeInTheDocument();
    expect(mocks.rpc.mock.calls.filter(([name])=>name==='fn_ecrire_audit_safe')).toHaveLength(0);
  });
  it('libère le spinner à 10s, abort la lecture puis ignore sa réponse après retry',async()=>{
    vi.useFakeTimers();afficher();await act(async()=>{await vi.advanceTimersByTimeAsync(10000);});
    expect(pending[0].signal?.aborted).toBe(true);expect(screen.getByRole('alert')).toBeInTheDocument();expect(screen.queryByRole('status')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));await recevoir(1,profil());await recevoir(0,profil('profil-a','Périmé'));
    expect(screen.getByLabelText('Prénom du profil')).toHaveValue('Camille');expect(mocks.rpc.mock.calls.filter(([name])=>name==='fn_ecrire_audit_safe')).toHaveLength(1);
  });
  it('ignore les réponses d’un autre acteur après changement de session',async()=>{
    const vue=afficher();mocks.user={id:'profil-b'};vue.rerender(<MemoryRouter><ProfilSoignant/></MemoryRouter>);
    expect(pending[0].signal?.aborted).toBe(true);await recevoir(1,profil('profil-b','Nouvelle'));await recevoir(0,profil());
    expect(screen.getByLabelText('Prénom du profil')).toHaveValue('Nouvelle');
    const audits=mocks.rpc.mock.calls.filter(([name])=>name==='fn_ecrire_audit_safe');expect(audits).toHaveLength(1);expect(audits[0][1].p_acteur_id).toBe('profil-b');
  });
  it('annule au démontage sans audit ni application d’une réponse tardive',async()=>{
    const vue=afficher();vue.unmount();expect(pending[0].signal?.aborted).toBe(true);await recevoir(0,profil());expect(mocks.rpc.mock.calls.some(([name])=>name==='fn_ecrire_audit_safe')).toBe(false);
  });
  it('la confidentialité garde seulement l’identité Auth pendant une lecture en vol',async()=>{
    afficher('/soignant/profil?tab=confidentialite');expect(screen.getByText('Confidentialité de profil-a')).toBeInTheDocument();expect(screen.queryByRole('status')).not.toBeInTheDocument();
    await recevoir(0,{error:'indisponible'});expect(screen.getByText('Confidentialité de profil-a')).toBeInTheDocument();
  });
  it('sans session aucune confidentialité ni lecture ne se monte',()=>{
    mocks.user=null;afficher('/soignant/profil?tab=confidentialite');expect(screen.queryByText(/Confidentialité de/)).not.toBeInTheDocument();expect(pending).toHaveLength(0);
  });
});
