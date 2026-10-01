import { describe, it, expect, vi } from 'vitest';
import { lirePaiementsActifs } from './lire-paiements-actifs';
const row = (id:string,mission_id='mission') => ({id,mission_id,facture_honoraire_id:'facture',statut:'DECLARE'});
describe('historique actif complet et borné aux obligations',()=>{
 it('lit la page suivante contenant le paiement sans pièce et conserve les autres lignes',async()=>{
  const rows=Array.from({length:201},(_,i)=>row(`id-${i}`));rows[200].facture_honoraire_id=null;
  const lire=vi.fn(async(missions:string[],start:number,end:number)=>({data:rows.slice(start,end+1),count:201,error:null}));
  const result=await lirePaiementsActifs([{mission_id:'mission'},{mission_id:'mission'}],lire);
  expect(result).toHaveLength(201);expect(result[200].facture_honoraire_id).toBeNull();
  expect(lire.mock.calls).toEqual([[['mission'],0,199],[['mission'],200,399]]);
 });
 it('accepte un plafond serveur plus petit avec pages exhaustives',async()=>{
  const rows=Array.from({length:5},(_,i)=>row(`id-${i}`));
  const lire=vi.fn(async(_:string[],start:number)=>({data:rows.slice(start,start+2),count:5,error:null}));
  expect(await lirePaiementsActifs([{mission_id:'mission'}],lire)).toEqual(rows);expect(lire).toHaveBeenCalledTimes(3);
 });
 it('ne lit aucun historique lorsqu’aucune obligation n’est affichable',async()=>{
  const lire=vi.fn();expect(await lirePaiementsActifs([],lire)).toEqual([]);expect(lire).not.toHaveBeenCalled();
 });
 it('borne aussi les lots de missions sans lire tout l’historique établissement',async()=>{
  const lire=vi.fn(async(_missions:string[],_debut:number,_fin:number)=>({data:[],count:0,error:null}));
  await lirePaiementsActifs(Array.from({length:101},(_,i)=>({mission_id:`m${i}`})),lire);
  expect(lire.mock.calls).toHaveLength(2);expect(lire.mock.calls[0][0]).toHaveLength(100);expect(lire.mock.calls[1][0]).toEqual(['m100']);
 });
 it.each([
  {data:[],count:null,error:null}, {data:[],count:-1,error:null}, {data:[],count:1.5,error:null},
  {data:[],count:1,error:null}, {data:[row('a')],count:0,error:null},
  {data:[{...row('a'),statut:'INCONNU'}],count:1,error:null},
  {data:[{...row('a'),facture_honoraire_id:undefined}],count:1,error:null},
  {data:[{...row('a'),secret:'non attendu'}],count:1,error:null},
  {data:[row('a','autre')],count:1,error:null}, {data:[row('a'),row('a')],count:2,error:null},
  {data:[],count:10001,error:null}, {data:[],count:0,error:{code:'42501'}},
 ])('refuse compteur/forme/scope non prouvés (%j)',async page=>{
  await expect(lirePaiementsActifs([{mission_id:'mission'}],async()=>page)).rejects.toBeDefined();
 });
 it('refuse une dérive de compteur entre les pages',async()=>{
  const lire=vi.fn().mockResolvedValueOnce({data:[row('a')],count:2,error:null}).mockResolvedValueOnce({data:[row('b')],count:3,error:null});
  await expect(lirePaiementsActifs([{mission_id:'mission'}],lire)).rejects.toThrow();
 });
 it('refuse une ligne répétée lors d’une dérive de pagination',async()=>{
  const lire=vi.fn().mockResolvedValue({data:[row('a')],count:2,error:null});
  await expect(lirePaiementsActifs([{mission_id:'mission'}],lire)).rejects.toThrow();
 });
 it.each([null,[{}],Array.from({length:1001},(_,i)=>({mission_id:`m${i}`}))].map(obligations=>({obligations})))('borne les obligations avant lecture',async ({obligations})=>{
  const lire=vi.fn();await expect(lirePaiementsActifs(obligations,lire)).rejects.toThrow();expect(lire).not.toHaveBeenCalled();
 });
});
