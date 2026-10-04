// @vitest-environment node
import { webcrypto } from 'node:crypto';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import { retourMissionPsc, signerEtatPsc, verifierEtatPsc } from '../../../supabase/functions/_shared/psc-return';
import { retourMissionNotification } from '@/lib/navigationNotification';
const M='/etablissement/missions/11111111-1111-4111-8111-111111111111';
const R='A'.repeat(43);const KEY='cle-synthetique-pour-tests-locaux';const NOW=1790920800;
beforeEach(()=>{vi.stubGlobal('crypto',webcrypto);});afterEach(()=>vi.unstubAllGlobals());
it('signe et vérifie la destination canonique sans changer le state de recherche complet',async()=>{
 const state=await signerEtatPsc(R,M,KEY,NOW);expect(state.length).toBeLessThan(180);expect(state).not.toContain(KEY);
 expect(await verifierEtatPsc(state,KEY,NOW+1)).toEqual({state,retour:M});
});
it('admet le state historique sans destination pour les sessions déjà ouvertes',async()=>{
 expect(await verifierEtatPsc(R,undefined,NOW)).toEqual({state:R,retour:null});
});
it.each(['https://evil.invalid'+M,'//evil.invalid',M+'?retour=ailleurs',M+'#section',M+'/',M+'\n',' '+M,'/etablissement/missions/../../admin','/etablissement/missions/creer','/admin','javascript:alert(1)'])('refuse le retour non canonique %s',async destination=>{
 expect(retourMissionPsc(destination)).toBeNull();expect(retourMissionNotification(destination)).toBeNull();
 await expect(signerEtatPsc(R,destination,KEY,NOW)).rejects.toThrow();
});
it('échoue fermé si mission, aléa, expiration ou signature changent',async()=>{
 const state=await signerEtatPsc(R,M,KEY,NOW);const fields=state.split('.');
 for(const index of [1,2,3,4]){const copy=[...fields];copy[index]=(index===3?'8':copy[index][0]==='A'?'B':'A')+copy[index].slice(1);expect(await verifierEtatPsc(copy.join('.'),KEY,NOW)).toBeNull();}
 expect(await verifierEtatPsc(state,'autre-cle',NOW)).toBeNull();expect(await verifierEtatPsc(state,undefined,NOW)).toBeNull();
});
it('refuse le state expiré et la signature encodée de façon non canonique',async()=>{
 const state=await signerEtatPsc(R,M,KEY,NOW);expect(await verifierEtatPsc(state,KEY,NOW+900)).toBeNull();
 const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';const last=chars.indexOf(state.at(-1)!);const alias=state.slice(0,-1)+chars[last|1];
 expect(alias).not.toBe(state);expect(await verifierEtatPsc(alias,KEY,NOW)).toBeNull();
});
it('refuse les formats arbitraires ou trop longs sans les traiter comme anciens states',async()=>{
 for(const state of [null,'','v1.'+R,'A'.repeat(181),R+'.'+M,' '+R])expect(await verifierEtatPsc(state,KEY,NOW)).toBeNull();
});
