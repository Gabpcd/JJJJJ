import { describe, expect, it, vi } from 'vitest';
import { verifierPreferencesEvenementsEmail } from '../../../supabase/functions/_shared/preferences-alertes-email';
const type='NOUVEAUX_SOIGNANTS_FILTRE',evenement='NOUVEAU_SOIGNANT_MATCHANT_FILTRE';
describe('opt-out alertes établissement : compatibilité des deux clés',()=>{
 it.each([[true,false,false],[false,true,false],[false,false,false],[true,true,true]])('canonique %s, historique %s ⇒ autorisation %s',async(canonique,historique,attendu)=>{
  const rpc=vi.fn().mockImplementation((_nom,params)=>Promise.resolve({data:params.p_type_evenement===evenement?canonique:historique,error:null}));
  expect(await verifierPreferencesEvenementsEmail({rpc},'etab',type,evenement)).toBe(attendu);
  if(canonique)expect(rpc).toHaveBeenCalledWith('fn_doit_notifier',{p_utilisateur_id:'etab',p_type_evenement:'NOUVELLE_MISSION_MATCHANT_FILTRE',p_canal:'EMAIL'});
 });
 it('une panne de vérification ne peut pas devenir un consentement',async()=>{
  const rpc=vi.fn().mockResolvedValueOnce({data:true,error:null}).mockResolvedValueOnce({data:null,error:{message:'503'}});
  await expect(verifierPreferencesEvenementsEmail({rpc},'etab',type,evenement)).rejects.toThrow('indisponible');
 });
 it('les autres emails conservent leur unique préférence',async()=>{
  const rpc=vi.fn().mockResolvedValue({data:true,error:null});
  expect(await verifierPreferencesEvenementsEmail({rpc},'soignant','NOUVELLES_MISSIONS_FILTRE','NOUVELLE_MISSION_MATCHANT_FILTRE')).toBe(true);
  expect(rpc).toHaveBeenCalledTimes(1);
 });
});
