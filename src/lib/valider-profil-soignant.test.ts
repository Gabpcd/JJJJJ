import {describe,it,expect} from 'vitest';
import {validerProfilSoignant} from './valider-profil-soignant';

const base = {id:'a',prenom:null,nom:null,email:null,profession:null};

describe('données destinées au formulaire profil',()=>{
  it('accepte les champs optionnels absents/null et les spécialités JSON historiques',()=>{
    expect(validerProfilSoignant({...base,prenom:null,specialites:'["Urgences"]'},'a').specialites).toEqual(['Urgences']);
    expect(validerProfilSoignant({...base,specialites:''},'a').specialites).toEqual([]);
    expect(validerProfilSoignant({...base,specialites:null},'a').specialites).toEqual([]);
  });
  it.each([{prenom:{}},{heures_cumulees:'4'},{adresse_lat:Infinity},{rpps_verifie:'true'},{specialites:[{}]},{specialites:false},{specialites:'null'},{specialites:'{}'}])('refuse un type incompatible %j',delta=>{
    expect(()=>validerProfilSoignant({...base,...delta},'a')).toThrow();
  });
});
