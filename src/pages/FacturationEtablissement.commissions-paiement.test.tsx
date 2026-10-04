import React from 'react';
import {act,fireEvent,render,screen,waitFor,within} from '@testing-library/react';
import {MemoryRouter,useLocation} from 'react-router-dom';
import {beforeEach,describe,expect,it,vi} from 'vitest';
import FacturationEtablissement from './FacturationEtablissement';
const mocks=vi.hoisted(()=>({rpc:vi.fn(),from:vi.fn(),invoke:vi.fn(),success:vi.fn(),error:vi.fn(),info:vi.fn(),logWarning:vi.fn(),logInfo:vi.fn(),checkout:vi.fn(),pdf:vi.fn(),scope:{user:{id:'membre'},etablissementId:'etab',parcours:null,loading:false,resolved:true,error:null,retry:vi.fn()},permissions:{loading:false,permissions:{lecture_paiement:true,paiement:true,contrats:true},error:null,recharger:vi.fn()}}));
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

vi.mock('@/components/StripeEmbeddedCheckout',()=>({StripeEmbeddedCheckout:(props:unknown)=>{mocks.checkout(props);return <div>Checkout commission</div>;}}));
vi.mock('@/lib/facture-commission-pdf',()=>({telechargerFactureCommissionPDF:mocks.pdf}));

let mode='CARTE';
let commission:Record<string,unknown>;
let lignes:Record<string,unknown>[];
function Localisation(){const l=useLocation();return <output data-testid="destination">{l.pathname}{l.search}</output>;}
function ouvrir(){return render(<MemoryRouter initialEntries={['/etablissement/facturation?tab=commissions']}><Localisation/><FacturationEtablissement/></MemoryRouter>);}
function sansPaiementDirect(){
 expect(screen.queryByRole('button',{name:'Payer par carte'})).not.toBeInTheDocument();
 expect(screen.queryByRole('button',{name:'Virement'})).not.toBeInTheDocument();
 expect(screen.queryByText(/automatique programmé/)).not.toBeInTheDocument();
 expect(mocks.checkout).not.toHaveBeenCalled();
 expect(mocks.invoke).not.toHaveBeenCalled();
}
describe('Commissions — le détail vérifie les modalités de règlement',()=>{
 beforeEach(()=>{
  vi.resetAllMocks();mode='CARTE';mocks.permissions.permissions.paiement=true;
  Element.prototype.scrollIntoView=vi.fn();
  commission={facture_id:'commission-cible',numero_facture:'COM-CIBLE',statut:'EMISE',montant_ht:12,montant_tva:2.4,montant_ttc:14.4,nombre_missions:1,est_secteur_public:false};
  lignes=[commission];
  mocks.rpc.mockImplementation((name:string)=>{
   if(name==='fn_mon_etablissement_complet')return Promise.resolve({data:{id:'etab',mode_paiement_commission:mode},error:null});
   if(name==='fn_obligations_financieres')return Promise.resolve({data:{total_du:14.4,total_soignants_du:0,total_commissions_du:14.4,missions_non_payees:[],factures_impayees:lignes,paiements_soignants_en_attente:[],paiements_soignants_confirmes:[],factures_commission_historique:[],missions_non_facturees:[]},error:null});
   if(name==='fn_mes_factures')return Promise.resolve({data:[],error:null});
   if(name==='fn_paiements_etablissement')return Promise.resolve({data:{paiements:[]},error:null});
   throw new Error(`RPC inattendue ${name}`);
  });
  mocks.from.mockImplementation(()=>{
   const q:any={};for(const method of ['select','eq','in','order','limit','range'])q[method]=()=>q;
   q.then=(resolve:unknown)=>Promise.resolve({data:[],error:null,count:0}).then(resolve as never);return q;
  });
 });
 it.each(['CARTE','SEPA_DEBIT'])('ne déduit aucun paiement autonome du résumé sans liaison (%s), y compris après rechargement',async(valeur)=>{
  mode=valeur;const vue=ouvrir();
  fireEvent.click(await screen.findByRole('button',{name:'Consulter les modalités de règlement'}));
  expect(screen.getByTestId('destination')).toHaveTextContent('/etablissement/facturation/commission-cible');
  sansPaiementDirect();
  vue.unmount();ouvrir();await screen.findByRole('button',{name:'Consulter les modalités de règlement'});sansPaiementDirect();
 });
 it.each(['FACTURE','FACTURE_COMPLEMENTAIRE','AVOIR'])('ne choisit pas un moyen de paiement sur le résumé %s',async(type)=>{
  commission.type_document=type;ouvrir();
  fireEvent.click(await screen.findByRole('button',{name:'Consulter les modalités de règlement'}));
  expect(screen.getByTestId('destination')).toHaveTextContent('/etablissement/facturation/commission-cible');sansPaiementDirect();
 });
 it('renvoie la commission choisie, jamais une commission voisine',async()=>{
  lignes.unshift({...commission,facture_id:'autre-commission',numero_facture:'COM-AUTRE'});ouvrir();
  const boutons=await screen.findAllByRole('button',{name:'Consulter les modalités de règlement'});
  fireEvent.click(boutons[1]);expect(screen.getByTestId('destination')).toHaveTextContent('/etablissement/facturation/commission-cible');sansPaiementDirect();
 });
 it.each(['VIREMENT_DECLARE','PAYEE'])('reste une consultation quand le statut vaut %s',async(statut)=>{
  commission.statut=statut;ouvrir();fireEvent.click(await screen.findByRole('button',{name:'Consulter les modalités de règlement'}));sansPaiementDirect();
 });
 it('permet aux membres en lecture seule de consulter le détail sans initier de paiement',async()=>{
  mocks.permissions.permissions.paiement=false;ouvrir();
  fireEvent.click(await screen.findByRole('button',{name:'Consulter les modalités de règlement'}));
  expect(screen.getByTestId('destination')).toHaveTextContent('/etablissement/facturation/commission-cible');sansPaiementDirect();
 });
 it('conserve le PDF et le lien de détail pour le secteur public',async()=>{
  commission.est_secteur_public=true;ouvrir();await screen.findByRole('button',{name:'Consulter les modalités de règlement'});
  fireEvent.click(screen.getByRole('button',{name:'PDF'}));
  expect(mocks.pdf).toHaveBeenCalledWith('commission-cible');sansPaiementDirect();
 });
});
