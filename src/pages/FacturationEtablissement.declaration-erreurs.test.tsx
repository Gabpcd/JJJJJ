import React from 'react';
import {act,fireEvent,render,screen,waitFor,within} from '@testing-library/react';
import {MemoryRouter} from 'react-router-dom';
import {beforeEach,describe,expect,it,vi} from 'vitest';
import FacturationEtablissement from './FacturationEtablissement';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),from:vi.fn(),invoke:vi.fn(),success:vi.fn(),error:vi.fn(),info:vi.fn(),logWarning:vi.fn(),logInfo:vi.fn(),scope:{user:{id:'membre'},etablissementId:'etab',parcours:null,loading:false,resolved:true,error:null,retry:vi.fn()},permissions:{loading:false,permissions:{lecture_paiement:true,paiement:true,contrats:true},error:null,recharger:vi.fn()}}));
vi.mock('@/hooks/usePageTitle',()=>({usePageTitle:()=>undefined}));
vi.mock('@/hooks/useEtablissementScope',()=>({useEtablissementScope:()=>mocks.scope}));
vi.mock('@/hooks/useEtabPermissions',()=>({useEtabPermissions:()=>mocks.permissions}));
vi.mock('@/contexts/NotificationContext',()=>({useNotification:()=>({afficherNotification:vi.fn()})}));
vi.mock('@/components/LayoutApp',()=>({LayoutApp:({children}:React.PropsWithChildren)=><>{children}</>}));
vi.mock('@/components/FadeInView',()=>({FadeInView:({children}:React.PropsWithChildren)=><>{children}</>}));
vi.mock('@/lib/stripe',()=>({stripePromise:null}));
vi.mock('@stripe/react-stripe-js',()=>({EmbeddedCheckoutProvider:({children}:React.PropsWithChildren)=><>{children}</>,EmbeddedCheckout:()=>null}));
vi.mock('@/lib/logger',()=>({logger:{error:vi.fn(),warn:mocks.logWarning,info:mocks.logInfo}}));
vi.mock('sonner',()=>({toast:{success:mocks.success,error:mocks.error,info:mocks.info}}));
vi.mock('@/integrations/supabase/client',()=>({supabase:{rpc:mocks.rpc,from:mocks.from,functions:{invoke:mocks.invoke},auth:{getSession:vi.fn()}}}));
const declaration=vi.fn();
const reference='FACTURE-2026-001';
function preparer(mode:'facture'|'salarie'|'legacy'){
 const mission={mission_id:'mission',intitule:'Mission fictive',soignant_nom:'Camille Test',type_contrat_applique:mode==='salarie'?'SALARIE':'LIBERAL',facture_honoraires_id:mode==='facture'?'facture':null,net_a_payer:100,jours_depuis_fin:1};
 mocks.rpc.mockImplementation((name:string,body:unknown)=>{
  if(name.startsWith('fn_declarer_paiement'))return declaration(name,body);
  if(name==='fn_mon_etablissement_complet')return Promise.resolve({data:{id:'etab'},error:null});
  if(name==='fn_obligations_financieres')return Promise.resolve({data:{total_du:100,total_soignants_du:100,total_commissions_du:0,missions_non_payees:[mission],factures_impayees:[],paiements_soignants_en_attente:[],paiements_soignants_confirmes:[],factures_commission_historique:[],missions_non_facturees:[]},error:null});
  if(name==='fn_mes_factures'||name==='fn_paiements_etablissement')return Promise.resolve({data:name==='fn_mes_factures'?[]:{paiements:[]},error:null});
  throw new Error(`RPC inattendue ${name}`);
 });
}
async function ouvrir(mode:'facture'|'salarie'|'legacy'){
 preparer(mode);render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
 fireEvent.click(await screen.findByRole('button',{name:'Déclarer un paiement'}));
 const dialog=within(screen.getByRole('dialog'));
 if(mode==='salarie'){
  fireEvent.change(dialog.getByLabelText('Total net dû selon le bulletin officiel'),{target:{value:'100'}});
  fireEvent.change(dialog.getByLabelText('Montant net réellement versé'),{target:{value:'100'}});
 }
 fireEvent.change(dialog.getByLabelText(/Référence/),{target:{value:reference}});
 fireEvent.change(dialog.getByLabelText('Date du paiement'),{target:{value:'2026-09-30'}});
 fireEvent.click(dialog.getByRole('checkbox'));
 return dialog;
}
describe('Déclaration paiement — erreur locale et envoi unique',()=>{
 beforeEach(()=>{
  vi.resetAllMocks();const q:any={};for(const method of ['select','eq','in','order','limit','range'])q[method]=()=>q;q.then=(resolve:unknown)=>Promise.resolve({data:[],error:null,count:0}).then(resolve as never);mocks.from.mockReturnValue(q);mocks.invoke.mockResolvedValue({data:{success:true},error:null});
 });
 it.each(['facture','salarie'] as const)('préserve la déclaration %s et sa RPC après refus',async(mode)=>{
  declaration.mockResolvedValueOnce({data:{error:'ATTESTATION_REQUISE'},error:null});
  const dialog=await ouvrir(mode);const envoyer=dialog.getByRole('button',{name:'Valider la déclaration'});fireEvent.click(envoyer);
  expect(await dialog.findByRole('alert')).toHaveTextContent("Attestation sur l'honneur obligatoire");
  expect(dialog.getByLabelText(/Référence/)).toHaveValue(reference);expect(dialog.getByLabelText('Date du paiement')).toHaveValue('2026-09-30');expect(dialog.getByRole('checkbox')).toBeChecked();expect(mocks.invoke).not.toHaveBeenCalled();expect(mocks.error).not.toHaveBeenCalled();
  let finir!:(value:unknown)=>void;declaration.mockImplementationOnce(()=>new Promise(resolve=>{finir=resolve;}));fireEvent.click(envoyer);fireEvent.click(envoyer);
  expect(dialog.getByRole('button',{name:'Envoi…'})).toBeDisabled();expect(dialog.getByRole('button',{name:'Annuler'})).toBeDisabled();expect(dialog.getByLabelText(/Référence/)).toBeDisabled();
  fireEvent.click(dialog.getByRole('button',{name:'Fermer'}));expect(screen.getByRole('dialog')).toBeInTheDocument();expect(declaration).toHaveBeenCalledTimes(2);
  await act(async()=>finir({data:{success:true,soignant_id:'soignant',mission_intitule:'Mission fictive'},error:null}));
  await waitFor(()=>expect(screen.queryByRole('dialog')).not.toBeInTheDocument());expect(mocks.invoke).toHaveBeenCalledTimes(1);expect(mocks.success).toHaveBeenCalledTimes(1);
  const commun={p_methode:'VIREMENT',p_reference:reference,p_date_paiement:'2026-09-30',p_attestation_sur_l_honneur:true};
  const attendu=mode==='facture'?['fn_declarer_paiement_facture_soignant',{...commun,p_facture_honoraire_id:'facture',p_montant:100}]:mode==='salarie'?['fn_declarer_paiement_soignant_v2',{...commun,p_mission_id:'mission',p_montant_verse:100,p_montant_total_du:100}]:['fn_declarer_paiement_soignant',{...commun,p_mission_id:'mission',p_montant:100}];
  for(const call of declaration.mock.calls)expect(call).toEqual(attendu);
 });
 it.each(['session','reseau'] as const)('traduit une erreur %s retournée, sans email ni fermeture',async(mode)=>{
  declaration.mockResolvedValueOnce({data:null,error:mode==='session'?{code:'PGRST301',message:'JWT expired'}:{message:'Failed to fetch'}});
  const dialog=await ouvrir('facture');fireEvent.click(dialog.getByRole('button',{name:'Valider la déclaration'}));
  expect(await dialog.findByRole('alert')).toHaveTextContent(mode==='session'?'Votre session a expiré':'Erreur de connexion');expect(dialog.getByRole('button',{name:'Valider la déclaration'})).toBeEnabled();expect(mocks.invoke).not.toHaveBeenCalled();expect(mocks.success).not.toHaveBeenCalled();
 });
 it('refuse Connect sans clé avant toute préparation et conserve la page après rechargement',async()=>{
  preparer('facture');const lire=mocks.rpc.getMockImplementation()!;
  mocks.rpc.mockImplementation(async(name:string,body:unknown)=>{
   const result=await lire(name,body);
   if(name==='fn_obligations_financieres')result.data.missions_non_payees[0].soignant_stripe_connect=true;
   return result;
  });
  const first=render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  fireEvent.click(await screen.findByRole('button',{name:'Payer via Stripe'}));
  expect(mocks.error).toHaveBeenLastCalledWith('Le paiement par carte est momentanément indisponible. Réessayez plus tard.');
  expect(mocks.invoke).not.toHaveBeenCalled();expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  first.unmount();render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  fireEvent.click(await screen.findByRole('button',{name:'Payer via Stripe'}));
  expect(mocks.error).toHaveBeenCalledTimes(2);expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it('conserve la redirection informative Stripe sans déclarer de paiement',async()=>{
  declaration.mockResolvedValueOnce({data:{error:'use_stripe_connect'},error:null});const dialog=await ouvrir('facture');fireEvent.click(dialog.getByRole('button',{name:'Valider la déclaration'}));
  await waitFor(()=>expect(screen.queryByRole('dialog')).not.toBeInTheDocument());expect(mocks.info).toHaveBeenCalledTimes(1);expect(mocks.invoke).not.toHaveBeenCalled();expect(mocks.success).not.toHaveBeenCalled();
 });
 it.each(['sent','skipped','failed','payload-failed','rejected'] as const)('une déclaration réussie reste unique quand email %s',async(etat)=>{
  declaration.mockResolvedValueOnce({data:{success:true,soignant_id:'soignant'},error:null});
  if(etat==='rejected')mocks.invoke.mockRejectedValueOnce(new TypeError('Failed to fetch'));
  else mocks.invoke.mockResolvedValueOnce(etat==='failed'?{data:null,error:{message:'Service indisponible'}}:etat==='payload-failed'?{data:{success:false,error:'Fournisseur email indisponible'},error:null}:{data:{success:true,...(etat==='skipped'?{skipped:true,reason:'preference_user_off'}:{})},error:null});
  const dialog=await ouvrir('facture');fireEvent.click(dialog.getByRole('button',{name:'Valider la déclaration'}));
  await waitFor(()=>expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  expect(declaration).toHaveBeenCalledTimes(1);expect(mocks.invoke).toHaveBeenCalledTimes(1);expect(mocks.error).not.toHaveBeenCalled();
  expect(mocks.success).toHaveBeenCalledExactlyOnceWith('Paiement déclaré — en attente de confirmation du soignant');
  expect(mocks.logWarning).toHaveBeenCalledTimes(['failed','payload-failed','rejected'].includes(etat)?1:0);
  expect(mocks.logInfo).toHaveBeenCalledTimes(etat==='skipped'?1:0);
 });

 it('refuse une obligation libérale sans pièce identifiée',async()=>{
  preparer('legacy');render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByRole('alert')).toHaveTextContent('Facture identifiée requise');
  expect(screen.queryByRole('button',{name:'Déclarer un paiement'})).not.toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Payer via Stripe'})).not.toBeInTheDocument();
  expect(declaration).not.toHaveBeenCalled();expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it.each(['DECLARE','CONFIRME','CONTESTE','RESOLU'])('conserve un paiement historique %s sans l’attribuer ni présenter une nouvelle dette',async(statut)=>{
  preparer('facture');mocks.from.mockImplementation((table:string)=>{
   const q:any={};for(const method of ['select','eq','in','order','limit','range'])q[method]=vi.fn(()=>q);
   q.then=(resolve:unknown)=>Promise.resolve({data:table==='paiements_soignant'?[{id:'historique',mission_id:'mission',facture_honoraire_id:null,statut}]:[],error:null,count:table==='paiements_soignant'?1:0}).then(resolve as never);return q;
  });
  render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByRole('alert')).toHaveTextContent('Un paiement antérieur doit être rapproché');
  expect(screen.getByText('Total payable non établi')).toBeInTheDocument();
  expect(screen.getByText('Montant de la pièce · solde à rapprocher')).toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Déclarer un paiement'})).not.toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Payer via Stripe'})).not.toBeInTheDocument();
  expect(declaration).not.toHaveBeenCalled();expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it('refuse les actions si la lecture de l’historique échoue puis propose la reprise',async()=>{
  preparer('facture');mocks.from.mockImplementation((table:string)=>{
   const q:any={};for(const method of ['select','eq','in','order','limit','range'])q[method]=()=>q;
   q.then=(resolve:unknown)=>Promise.resolve(table==='paiements_soignant'?{data:null,error:{code:'42501',message:'permission denied'}}:{data:[],error:null,count:0}).then(resolve as never);return q;
  });
  render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('Impossible de charger les données de facturation en toute sécurité.')).toBeInTheDocument();
  expect(screen.getByRole('button',{name:'Réessayer'})).toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Déclarer un paiement'})).not.toBeInTheDocument();
  expect(declaration).not.toHaveBeenCalled();expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it.each(['LIBERAL_FACTURE_REQUISE','PAIEMENT_HISTORIQUE_A_RAPPROCHER'])('rend le refus documentaire %s sans nouvel effet',async(code)=>{
  declaration.mockResolvedValueOnce({data:{error:code},error:null});const dialog=await ouvrir('facture');
  fireEvent.click(dialog.getByRole('button',{name:'Valider la déclaration'}));
  expect(await dialog.findByRole('alert')).toHaveTextContent(code==='LIBERAL_FACTURE_REQUISE'?'ouvrez Facturation et choisissez la facture':'Un paiement antérieur doit être rapproché');
  expect(dialog.getByLabelText(/Référence/)).toHaveValue(reference);expect(mocks.invoke).not.toHaveBeenCalled();expect(mocks.success).not.toHaveBeenCalled();
 });

});
