import { fireEvent, render, screen, waitFor, cleanup, act } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useNavigate } from 'react-router-dom';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import MissionDepuisNotification from './MissionDepuisNotification';
// Les réponses RPC positives injectées pour SOIGNANT vérifient le routage seul.
// Le trigger de famille interdit normalement SOIGNANT + adhésion active ; le
// banc PostgreSQL prépare le refus réel, sans fabriquer cette association.
const M='11111111-1111-4111-8111-111111111111';
const mocks=vi.hoisted(()=>({ role: 'ADMIN_ETABLISSEMENT', roleLoading: false, roleResolved: true, roleError: null as Error | null, retryRole: vi.fn(), uid: 'user-A', rpc: vi.fn(), from: vi.fn(), props: null as any, navigate: null as any }));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc,from:mocks.from}}));
vi.mock('@/contexts/AuthContext',()=>({useAuth:()=>({user:{id:mocks.uid}})}));
vi.mock('@/hooks/useRole',()=>({useRole:()=>({role:mocks.role,loading:mocks.roleLoading,resolved:mocks.roleResolved,error:mocks.roleError,retry:mocks.retryRole})}));
vi.mock('@/components/ChargementPage',()=>({ChargementPage:()=> <p>Chargement</p>}));
vi.mock('@/pages/DetailMission',()=>({default:()=> <h1>Détail habituel</h1>}));
vi.mock('@/components/ListeCandidatures',()=>({ListeCandidatures:(props:any)=>{
  mocks.props=props;
  return <section><p>Contrôle des candidatures</p><button onClick={props.onAccepted}>Retour acceptation</button></section>;
}}));
const lecture=(overrides={})=>({mission:{id:M,intitule:'Mission B',etablissement_id:'B',etablissement_nom:'Établissement B',statut:'OUVERTE',mode_attribution:'CANDIDATURE',nb_creneaux:1,profession_requise:'IDE',specialite_medicale_requise:null,...overrides},creneaux:[{id:'slot',mission_id:M,debut:'2026-10-10T08:00:00Z',fin:'2026-10-10T16:00:00Z',est_pause:false,type_creneau:'PREVISIONNEL'}],candidatures:[{id:'C-B',statut:'EN_ATTENTE',soignant:{prenom:'Camille',nom:'T.'}}]});
function NavigationHarness(){mocks.navigate=useNavigate();return <Routes><Route path='/etablissement/missions/:id' element={<MissionDepuisNotification/>}/></Routes>;}
function affichage(path=`/etablissement/missions/${M}`){return render(<MemoryRouter initialEntries={[path]}><NavigationHarness/></MemoryRouter>);}
beforeEach(()=>{
  mocks.role='ADMIN_ETABLISSEMENT';mocks.roleLoading=false;mocks.roleResolved=true;mocks.roleError=null;mocks.retryRole.mockReset();mocks.uid='user-A';mocks.rpc.mockReset();mocks.from.mockReset();mocks.props=null;
  mocks.rpc.mockResolvedValue({data:lecture(),error:null});
  mocks.from.mockImplementation(table=>{expect(table).toBe('missions');const b:any={select:vi.fn(()=>b),eq:vi.fn(()=>b),maybeSingle:vi.fn().mockResolvedValue({data:null,error:null})};return b;});
  vi.stubGlobal('fetch',vi.fn(()=>{throw new Error('Réseau interdit dans cette recette mémoire');}));
});
afterEach(()=>{cleanup();vi.unstubAllGlobals();});
describe('Route de notification — DOM mémoire, transports simulés',()=>{
  it('attend le rôle local puis ouvre le détail canonique sans RPC bornée',async()=>{
    mocks.role='INCONNU';mocks.roleLoading=true;mocks.roleResolved=false;
    mocks.from.mockImplementation(()=>{const b:any={select:()=>b,eq:()=>b,maybeSingle:async()=>({data:{id:M},error:null})};return b;});
    const rendered=affichage();await act(async()=>{});
    expect(screen.getByText('Chargement')).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalled();expect(mocks.from).not.toHaveBeenCalled();
    mocks.role='ADMIN_ETABLISSEMENT';mocks.roleLoading=false;mocks.roleResolved=true;
    rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);
    expect(await screen.findByText('Détail habituel')).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it('attend le rôle groupe résolu avant sa première lecture bornée',async()=>{
    mocks.role='INCONNU';mocks.roleLoading=true;mocks.roleResolved=false;const rendered=affichage();await act(async()=>{});
    expect(mocks.rpc).not.toHaveBeenCalled();expect(mocks.from).not.toHaveBeenCalled();
    mocks.role='ADMIN_GROUPE';mocks.roleLoading=false;mocks.roleResolved=true;rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);
    await screen.findByText('Mission B');expect(mocks.rpc).toHaveBeenCalledTimes(1);expect(mocks.from).not.toHaveBeenCalled();
  });
  it('retire les données et anciens callbacks pendant la résolution du nouveau compte',async()=>{
    mocks.role='ADMIN_GROUPE';const rendered=affichage();await screen.findByText('Mission B');const ancienSucces=mocks.props.onSuccess;
    mocks.uid='user-C';mocks.roleLoading=true;mocks.roleResolved=false;rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);
    expect(screen.getByText('Chargement')).toBeTruthy();expect(screen.queryByText('Mission B')).toBeNull();expect(mocks.rpc).toHaveBeenCalledTimes(1);
    act(()=>ancienSucces('Ancien résultat'));expect(screen.queryByText('Ancien résultat')).toBeNull();
    mocks.rpc.mockResolvedValue({data:null,error:new Error('Accès refusé')});mocks.roleLoading=false;mocks.roleResolved=true;rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);
    await screen.findByRole('alert');expect(screen.queryByText('Mission B')).toBeNull();expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });
  it('ignore une réponse en vol après passage du rôle en revalidation',async()=>{
    mocks.role='ADMIN_GROUPE';let resolve:any;mocks.rpc.mockReturnValue(new Promise(r=>{resolve=r;}));const rendered=affichage();await waitFor(()=>expect(mocks.rpc).toHaveBeenCalledTimes(1));
    mocks.roleLoading=true;mocks.roleResolved=false;rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);
    await act(async()=>resolve({data:lecture(),error:null}));expect(screen.getByText('Chargement')).toBeTruthy();expect(screen.queryByText('Mission B')).toBeNull();
    mocks.rpc.mockResolvedValue({data:null,error:new Error('Accès refusé')});mocks.roleLoading=false;mocks.roleResolved=true;rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);
    await screen.findByRole('alert');expect(screen.queryByText('Mission B')).toBeNull();
  });
  it('retire les données si le rôle devient inconnu sans accorder une lecture',async()=>{
    mocks.role='ADMIN_GROUPE';const rendered=affichage();await screen.findByText('Mission B');const ancienSucces=mocks.props.onSuccess;
    mocks.role='INCONNU';rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);
    expect(screen.getByRole('alert')).toHaveTextContent('Impossible de vérifier votre accès');expect(screen.queryByText('Mission B')).toBeNull();expect(mocks.rpc).toHaveBeenCalledTimes(1);
    act(()=>ancienSucces('Ancien résultat du rôle'));expect(screen.queryByText('Ancien résultat du rôle')).toBeNull();fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));expect(mocks.retryRole).toHaveBeenCalledTimes(1);
  });
  it('réessaie une erreur de rôle par le hook avant toute lecture de mission',async()=>{
    mocks.role='INCONNU';mocks.roleResolved=false;mocks.roleError=new Error('Erreur rôle');const rendered=affichage();
    expect(screen.getByRole('alert')).toHaveTextContent('Impossible de vérifier votre accès');expect(mocks.rpc).not.toHaveBeenCalled();expect(mocks.from).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));expect(mocks.retryRole).toHaveBeenCalledTimes(1);
    mocks.roleError=null;mocks.roleLoading=true;rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);expect(screen.getByText('Chargement')).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalled();
    mocks.role='ADMIN_GROUPE';mocks.roleLoading=false;mocks.roleResolved=true;rendered.rerender(<MemoryRouter><NavigationHarness/></MemoryRouter>);await screen.findByText('Mission B');expect(mocks.rpc).toHaveBeenCalledTimes(1);
  });

  it.each([false, true])('réserve les safe-areas dans la structure autonome (erreur=%s)',async erreur=>{
    mocks.role='ADMIN_GROUPE';
    if(erreur)mocks.rpc.mockResolvedValue({data:null,error:new Error('Accès refusé')});
    affichage();
    if(erreur)await screen.findByRole('alert');else await screen.findByText('Mission B');
    // Le DOM vérifie la structure CSS ; seul un navigateur/device mesure env().
    const main=screen.getByRole('main');
    expect(main).toHaveClass('pt-[calc(env(safe-area-inset-top)+1.5rem)]');
    expect(main).toHaveClass('pb-[calc(env(safe-area-inset-bottom)+1.5rem)]');
    expect(main).not.toHaveClass('py-6');
    expect(main).toContainElement(screen.getByRole('link',{name:'Retour à mon espace'}));
  });

  it('conserve le détail actuel pour une mission déjà lisible par RLS',async()=>{
    mocks.from.mockImplementation(()=>{const b:any={select:()=>b,eq:()=>b,maybeSingle:async()=>({data:{id:M},error:null})};return b;});
    affichage();expect(await screen.findByText('Détail habituel')).toBeTruthy();expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it('charge la vraie mission B pour un membre secondaire sans changer le scope',async()=>{
    affichage();expect(await screen.findByText('Établissement B')).toBeTruthy();
    expect(screen.getByText('Mission B')).toBeTruthy();expect(mocks.props.missionId).toBe(M);
    expect(mocks.rpc).toHaveBeenCalledWith('fn_lire_candidatures_mission_habilitee',{p_mission_id:M});
    expect(mocks.rpc.mock.calls.every(([name])=>name==='fn_lire_candidatures_mission_habilitee')).toBe(true);
  });
  it('admet le vrai rôle applicatif ADMIN_GROUPE et revient au groupe',async()=>{
    mocks.role='ADMIN_GROUPE';affichage();await screen.findByText('Mission B');
    expect(mocks.from).not.toHaveBeenCalled();expect(screen.getByRole('link').getAttribute('href')).toBe('/groupe/tableau-de-bord');
  });
  it('soumet aussi le membre au rôle soignant à la même RPC bornée',async()=>{
    mocks.role='SOIGNANT';affichage();await screen.findByText('Mission B');expect(mocks.from).not.toHaveBeenCalled();
    expect(screen.getByRole('link').getAttribute('href')).toBe('/soignant/tableau-de-bord');
  });
  it('refuse un groupe non habilité sans révéler le titre B',async()=>{
    mocks.role='ADMIN_GROUPE';mocks.rpc.mockResolvedValue({data:null,error:new Error('Mission indisponible ou accès refusé')});
    affichage();expect(await screen.findByRole('alert')).toBeTruthy();expect(screen.queryByText('Mission B')).toBeNull();expect(mocks.props).toBeNull();
  });
  it('ne masque pas une erreur RLS/transport par une tentative de lecture privilégiée',async()=>{
    mocks.from.mockImplementation(()=>{const b:any={select:()=>b,eq:()=>b,maybeSingle:async()=>({data:null,error:new Error('Lecture indisponible')})};return b;});
    affichage();await screen.findByRole('alert');expect(mocks.rpc).not.toHaveBeenCalled();
  });
  it('propose un réessai après indisponibilité et relit les droits',async()=>{
    mocks.role='ADMIN_GROUPE';mocks.rpc.mockResolvedValueOnce({data:null,error:new Error('Indisponible')}).mockResolvedValue({data:lecture(),error:null});
    affichage();await screen.findByRole('alert');fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));
    expect(await screen.findByText('Mission B')).toBeTruthy();expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });
  it('relit après tap sur la même page déjà ouverte',async()=>{
    mocks.role='ADMIN_GROUPE';affichage();await screen.findByText('Mission B');
    mocks.rpc.mockResolvedValue({data:lecture({intitule:'Mission B actualisée'}),error:null});
    act(()=>window.dispatchEvent(new CustomEvent('jolene:notification-opened',{detail:{path:`/etablissement/missions/${M}`}})));
    expect(await screen.findByText('Mission B actualisée')).toBeTruthy();expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });
  it('ne réagit pas à la notification d’une autre mission',async()=>{
    mocks.role='ADMIN_GROUPE';affichage();await screen.findByText('Mission B');
    act(()=>window.dispatchEvent(new CustomEvent('jolene:notification-opened',{detail:{path:'/etablissement/missions/autre'}})));
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
  });
  it('retire les données après révocation constatée à la relecture',async()=>{
    mocks.role='ADMIN_GROUPE';affichage();await screen.findByText('Mission B');mocks.rpc.mockResolvedValue({data:null,error:new Error('Accès refusé')});
    act(()=>window.dispatchEvent(new CustomEvent('jolene:notification-opened',{detail:{path:`/etablissement/missions/${M}`}})));
    await screen.findByRole('alert');expect(screen.queryByText('Mission B')).toBeNull();expect(screen.queryByText('Contrôle des candidatures')).toBeNull();
  });
  it('reprend le résultat après acceptation puis après remontage/reload simulé',async()=>{
    mocks.role='ADMIN_GROUPE';const rendered=affichage();await screen.findByText('Mission B');
    const finale=lecture({statut:'ASSIGNEE'});finale.candidatures[0].statut='ACCEPTEE';mocks.rpc.mockResolvedValue({data:finale,error:null});
    fireEvent.click(screen.getByRole('button',{name:'Retour acceptation'}));await screen.findByText(/Camille T. — Acceptée/);
    expect(screen.queryByText('Contrôle des candidatures')).toBeNull();rendered.unmount();affichage();expect(await screen.findByText(/Camille T. — Acceptée/)).toBeTruthy();
  });
  it('revalide B pour chaque lecture de candidats et de planning injectée',async()=>{
    mocks.role='ADMIN_GROUPE';affichage();await screen.findByText('Mission B');
    const candidates=await mocks.props.chargerCandidaturesHabilitees();const planning=await mocks.props.chargerPlanningHabilite();
    expect(candidates[0].id).toBe('C-B');expect(planning[0].mission_id).toBe(M);expect(mocks.rpc).toHaveBeenCalledTimes(3);
  });
  it('refuse la réponse d’une autre mission',async()=>{
    mocks.role='ADMIN_GROUPE';mocks.rpc.mockResolvedValue({data:lecture({id:'autre-mission'}),error:null});affichage();await screen.findByRole('alert');expect(mocks.props).toBeNull();
  });

  it('relit les droits lors du changement de compte avec le même rôle',async()=>{
    mocks.role='ADMIN_GROUPE';const rendered=affichage();await screen.findByText('Mission B');const ancienSucces=mocks.props.onSuccess;const ancienneAcceptation=mocks.props.onAccepted;
    mocks.uid='user-C';mocks.rpc.mockResolvedValue({data:null,error:new Error('Accès refusé')});
    rendered.rerender(<MemoryRouter initialEntries={[`/etablissement/missions/${M}`]}><NavigationHarness/></MemoryRouter>);
    await screen.findByRole('alert');expect(screen.queryByText('Mission B')).toBeNull();expect(mocks.rpc).toHaveBeenCalledTimes(2);
    act(()=>{ancienSucces('Résultat ancien compte');ancienneAcceptation();});expect(screen.queryByText('Résultat ancien compte')).toBeNull();expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });

  it('ne conserve pas le résultat de décision B sur une autre mission C',async()=>{
    mocks.role='ADMIN_GROUPE';affichage();await screen.findByText('Mission B');
    act(()=>mocks.props.onSuccess('Candidature B refusée.'));expect(screen.getByText('Candidature B refusée.')).toBeTruthy();
    const C='22222222-2222-4222-8222-222222222222';mocks.rpc.mockResolvedValue({data:lecture({id:C,intitule:'Mission C'}),error:null});
    act(()=>mocks.navigate('/etablissement/missions/'+C));await screen.findByText('Mission C');expect(screen.queryByText('Candidature B refusée.')).toBeNull();
  });
  it('ignore un résultat tardif de B arrivé après ouverture de C',async()=>{
    mocks.role='ADMIN_GROUPE';affichage();await screen.findByText('Mission B');const ancienSucces=mocks.props.onSuccess;
    const C='22222222-2222-4222-8222-222222222222';mocks.rpc.mockResolvedValue({data:lecture({id:C,intitule:'Mission C'}),error:null});
    act(()=>mocks.navigate('/etablissement/missions/'+C));await screen.findByText('Mission C');act(()=>ancienSucces('Ancienne candidature B acceptée.'));
    expect(screen.queryByText('Ancienne candidature B acceptée.')).toBeNull();
  });
  it('refuse une projection incomplète',async()=>{
    mocks.role='ADMIN_GROUPE';const data:any=lecture();delete data.creneaux;mocks.rpc.mockResolvedValue({data,error:null});affichage();await screen.findByRole('alert');expect(mocks.props).toBeNull();
  });
});
