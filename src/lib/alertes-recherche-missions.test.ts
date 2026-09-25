import { describe, expect, it } from 'vitest';
import { preparerAlerteMissions } from './alertes-recherche-missions';
const criteres = { profession:'',rayonKm:25,tauxMin:30,typeContrat:'CDD',urgentesOnly:true,horaire:'NUIT',villeRecherche:'Paris' };
describe('alerte depuis les critères réels d’Explorer',()=>{
 it('préserve les sept filtres et la profession vide qui inclut la hiérarchie du profil',()=>{
  expect(preparerAlerteMissions(criteres,[],'Alerte missions IADE')).toEqual({deja:undefined,nom:'Alerte missions IADE',filtres:criteres});
 });
 it('ne réactive pas une ancienne alerte portant le même nom et un autre rayon',()=>{
  const ancien={id:'a',nom:'Alerte missions',alerte_active:false,filtres:{profession:'IDE',rayonKm:100}};
  const r=preparerAlerteMissions(criteres,[ancien,{...ancien,id:'b',nom:'Alerte missions (2)'}],'Alerte missions');
  expect(r.deja).toBeUndefined();expect(r.nom).toBe('Alerte missions (3)');expect(r.filtres).toEqual(criteres);
 });
 it('réutilise uniquement la recherche exactement équivalente même avec un ordre JSON différent',()=>{
  const meme={id:'exacte',nom:'Ma recherche',alerte_active:false,filtres:{villeRecherche:'Paris',horaire:'NUIT',urgentesOnly:true,typeContrat:'CDD',tauxMin:30,rayonKm:25,profession:''}};
  expect(preparerAlerteMissions(criteres,[meme],'Alerte missions').deja?.id).toBe('exacte');
 });
});
