import React from 'react';
import {act,fireEvent,render,screen,waitFor,within} from '@testing-library/react';
import {MemoryRouter,useLocation} from 'react-router-dom';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
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

const obligations = {
 total_du:80,total_soignants_du:80,total_commissions_du:0,
 missions_non_payees:[{mission_id:'mission',intitule:'Mission répartie sur trois semaines',soignant_nom:'Camille Test',soignant_profession:'IDE',type_contrat_applique:'LIBERAL',facture_honoraires_id:'facture',net_a_payer:80,heures:159,jours_depuis_fin:1}],
 factures_impayees:[],paiements_soignants_en_attente:[],paiements_soignants_confirmes:[],factures_commission_historique:[],missions_non_facturees:[],
};
const missionModele = {...obligations.missions_non_payees[0]};
let facturesComplementaires:Record<string,unknown>[]=[];
let facture:Record<string,unknown>;
const selections:Array<{table:string,colonnes:string}>=[];
describe('Facturation — heures et échéance de la pièce, non intervalle calendaire',()=>{
 afterEach(()=>vi.useRealTimers());
 beforeEach(()=>{
  vi.resetAllMocks();selections.length=0;facturesComplementaires=[];obligations.missions_non_payees=[{...missionModele}];
  Element.prototype.scrollIntoView=vi.fn();
  facture={id:'facture',numero_facture:'FH-TEST',type_document:'FACTURE',quantite_heures_snapshot:4};
  obligations.missions_non_payees[0].type_contrat_applique='LIBERAL';
  mocks.rpc.mockImplementation((name:string)=>{
   if(name==='fn_mon_etablissement_complet')return Promise.resolve({data:{id:'etab'},error:null});
   if(name==='fn_obligations_financieres')return Promise.resolve({data:obligations,error:null});
   if(name==='fn_mes_factures')return Promise.resolve({data:[],error:null});
   if(name==='fn_paiements_etablissement')return Promise.resolve({data:{paiements:[]},error:null});
   throw new Error(`RPC inattendue ${name}`);
  });
  mocks.from.mockImplementation((table:string)=>{
   const q:any={};for(const method of ['eq','in','order','limit','range'])q[method]=()=>q;
   q.select=(colonnes:string)=>{selections.push({table,colonnes});return q;};
   q.then=(resolve:unknown)=>Promise.resolve({data:table==='factures_honoraires'?[facture,...facturesComplementaires]:[],error:null,count:table==='factures_honoraires'?1:0}).then(resolve as never);return q;
  });
 });
 it('affiche les 4 heures facturées malgré un intervalle API de 159 heures, avant et après remontage',async()=>{
  const premier=render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('IDE · 4 h facturées')).toBeInTheDocument();
  expect(screen.queryByText(/159.*pointées/)).not.toBeInTheDocument();
  expect(screen.getByRole('button',{name:'Déclarer un paiement'})).toBeInTheDocument();
  expect(selections.find(x=>x.table==='factures_honoraires')?.colonnes.split(',').map(x=>x.trim())).toContain('quantite_heures_snapshot');
  premier.unmount();render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('IDE · 4 h facturées')).toBeInTheDocument();
  expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it('ne transforme pas les 14 jours depuis la période en retard avant le 3 novembre, même après remontage',async()=>{
  vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(new Date('2026-10-04T12:00:00Z'));
  obligations.missions_non_payees[0].jours_depuis_fin=14;facture.date_echeance='2026-11-03';
  const premier=render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('Échéance : 3 novembre 2026')).toBeInTheDocument();
  expect(screen.queryByText(/retard/)).not.toBeInTheDocument();
  expect(selections.find(x=>x.table==='factures_honoraires')?.colonnes.split(',').map(x=>x.trim())).toContain('date_echeance');
  premier.unmount();render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('Échéance : 3 novembre 2026')).toBeInTheDocument();
  expect(screen.queryByText(/retard/)).not.toBeInTheDocument();expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it.each([
  ['2026-11-03T22:59:59Z','Échéance : 3 novembre 2026'],
  ['2026-11-03T23:00:00Z','En retard de 1 j'],
  ['2026-11-17T12:00:00Z','En retard de 14 j'],
  ['2026-11-18T12:00:00Z','En retard de 15 j'],
 ])('calcule le retard depuis la pièce selon le jour civil Paris à %s',async(instant,libelle)=>{
  vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(new Date(instant));facture.date_echeance='2026-11-03';
  obligations.missions_non_payees[0].jours_depuis_fin=99;
  render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText(libelle)).toBeInTheDocument();expect(screen.queryByText(/99/)).not.toBeInTheDocument();
 });
 it.each([null,undefined,'','illisible','2026-02-30','2026-11-03T00:00:00Z'])('ne remplace pas une échéance invalide (%s) par la fin de période',async(valeur)=>{
  facture.date_echeance=valeur;obligations.missions_non_payees[0].jours_depuis_fin=99;
  render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('Échéance indisponible')).toBeInTheDocument();
  expect(screen.queryByText(/retard/)).not.toBeInTheDocument();
 });
 it('isole deux échéances de la même mission par ID de facture',async()=>{
  vi.useFakeTimers({toFake:['Date']});vi.setSystemTime(new Date('2026-10-04T12:00:00Z'));
  deuxPieces();facture.date_echeance='2026-11-03';facturesComplementaires[0].date_echeance='2026-10-03';
  render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  const premiere=(await screen.findByText('FH-TEST')).closest('.card-base') as HTMLElement;
  const seconde=(await screen.findByText('FH-AUTRE')).closest('.card-base') as HTMLElement;
  expect(within(premiere).getByText('Échéance : 3 novembre 2026')).toBeInTheDocument();
  expect(within(premiere).queryByText(/retard/)).not.toBeInTheDocument();
  expect(within(seconde).getByText('En retard de 1 j')).toBeInTheDocument();
 });
 it('conserve les fractions d’heures de la pièce',async()=>{
  facture.quantite_heures_snapshot='4.25';render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('IDE · 4,25 h facturées')).toBeInTheDocument();
 });
 it.each([null,undefined,0,-1,'','illisible',Infinity])('ne remplace jamais une quantité invalide (%s) par la durée calendaire',async(valeur)=>{
  facture.quantite_heures_snapshot=valeur;render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  expect(await screen.findByText('IDE · Heures facturées indisponibles')).toBeInTheDocument();
  expect(screen.queryByText(/159.*pointées/)).not.toBeInTheDocument();
 });
 it('ne présente pas non plus la durée calendaire salariée comme un pointage',async()=>{
  obligations.missions_non_payees[0].type_contrat_applique='SALARIE';render(<MemoryRouter><FacturationEtablissement/></MemoryRouter>);
  await screen.findByRole('button',{name:'Déclarer un paiement'});
  expect(screen.queryByText(/pointées|4 h facturées|Heures facturées indisponibles/)).not.toBeInTheDocument();
 });
 function deuxPieces() {
  obligations.missions_non_payees=[
   {...missionModele},
   {...missionModele,facture_honoraires_id:'autre-facture',net_a_payer:120},
  ];
  facturesComplementaires=[{id:'autre-facture',numero_facture:'FH-AUTRE',quantite_heures_snapshot:6}];
 }
 function Localisation(){return <output data-testid="recherche">{useLocation().search}</output>;}
 function ouvrirFacture(factureId='facture',missionId='mission') {
  return render(<MemoryRouter initialEntries={[`/etablissement/facturation?tab=missions-a-payer&mission=${missionId}&facture_honoraire=${factureId}`]}><Localisation/><FacturationEtablissement/></MemoryRouter>);
 }
 it('cible une seule facture de la mission et conserve ce ciblage après remontage',async()=>{
  deuxPieces();const premier=ouvrirFacture();
  expect(await screen.findByText('FH-TEST')).toBeInTheDocument();
  expect(screen.queryByText('FH-AUTRE')).not.toBeInTheDocument();
  expect(screen.getAllByRole('button',{name:'Déclarer un paiement'})).toHaveLength(1);
  expect(screen.getByText('Échéance de la facture sélectionnée')).toBeInTheDocument();
  expect(mocks.invoke).not.toHaveBeenCalled();
  premier.unmount();ouvrirFacture();
  expect(await screen.findByText('FH-TEST')).toBeInTheDocument();
  expect(screen.queryByText('FH-AUTRE')).not.toBeInTheDocument();
  expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it.each(['facture-absente','facture-soldee'])('ne substitue aucune autre échéance lorsque %s est absente de la liste payable',async(id)=>{
  deuxPieces();ouvrirFacture(id);
  expect(await screen.findByText('Aucune échéance payable pour cette facture dans cette liste. Consultez son détail ou l’historique des paiements.')).toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Déclarer un paiement'})).not.toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Payer via Stripe'})).not.toBeInTheDocument();
  expect(screen.queryByText('FH-AUTRE')).not.toBeInTheDocument();
  expect(mocks.invoke).not.toHaveBeenCalled();
 });
 it('ne rend pas la facture ciblée si elle appartient à une autre mission',async()=>{
  deuxPieces();obligations.missions_non_payees[0].mission_id='mission-voisine';ouvrirFacture();
  expect(await screen.findByText('Aucune échéance payable pour cette facture dans cette liste. Consultez son détail ou l’historique des paiements.')).toBeInTheDocument();
  expect(screen.queryByRole('button',{name:'Déclarer un paiement'})).not.toBeInTheDocument();
  expect(screen.queryByText('FH-TEST')).not.toBeInTheDocument();
 });
 it('retire les deux filtres avant de retrouver les autres échéances',async()=>{
  deuxPieces();ouvrirFacture();await screen.findByText('FH-TEST');
  fireEvent.click(screen.getByRole('button',{name:'Retirer le filtre facture'}));
  expect(await screen.findByText('FH-AUTRE')).toBeInTheDocument();
  expect(screen.getAllByRole('button',{name:'Déclarer un paiement'})).toHaveLength(2);
  expect(screen.getByTestId('recherche')).toHaveTextContent('?tab=missions-a-payer');
  expect(screen.getByTestId('recherche')).not.toHaveTextContent('mission=');
  expect(screen.getByTestId('recherche')).not.toHaveTextContent('facture_honoraire=');
  expect(mocks.invoke).not.toHaveBeenCalled();
 });

});
