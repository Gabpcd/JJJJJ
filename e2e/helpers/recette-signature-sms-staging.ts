import {expect, type BrowserContext, type Route} from '@playwright/test';
import {creerMissionSimulee, ids, now, type RoleRecette} from './recette-complete-mission';

export const STAGING_SMS_SIMULE = 'https://mejpriaetwgtcstbgfid.supabase.co';
/** All Auth/REST/RPC/SMS below are explicit frontend mocks, never provider I/O. */
export function creerSignatureSmsStagingSimulee() {
  const base = creerMissionSimulee();
  const {state} = base;
  state.soignant.est_compte_test = true; state.etablissement.est_compte_test = true;
  state.contratCree = true; state.mission.statut = 'ASSIGNEE'; state.mission.soignant_assigne_id = ids.soignant;
  const admittedHash = state.contrat.hash_document;
  let issuedAt: number | null = null;
  let nextHold: Promise<void> | null = null;
  let nextSmsHold: Promise<void> | null = null;
  const control = {
    enabled: false, revoked: false, time: Date.parse(now), expiresAt: Date.parse(now) + 60 * 60_000,
    admissionReads: 0, pendingAdmissions: 0, pendingSms: 0, smsAttempts: 0, validations: 0,
    retenirProchaineAdmission() {
      expect(nextHold).toBeNull();
      let release!: () => void;
      nextHold = new Promise<void>(resolve => {release = resolve;});
      return release;
    },
    retenirProchainSms() {
      expect(nextSmsHold).toBeNull();
      let release!: () => void;
      nextSmsHold = new Promise<void>(resolve => {release = resolve;});
      return release;
    },
  };
  function scopeActive(role: RoleRecette) {
    const signed = role === 'SOIGNANT' ? state.contrat.signature_soignant : state.contrat.signature_etablissement;
    return control.enabled && !control.revoked && control.time < control.expiresAt
      && state.contrat.hash_document === admittedHash && !signed;
  }
  function receipt(role: RoleRecette) {
    const active = scopeActive(role);
    const canSend = active && control.smsAttempts < 2;
    const canValidate = active && issuedAt !== null && control.time - issuedAt < 10 * 60_000;
    return {admitted:canSend || canValidate,can_send:canSend,can_validate:canValidate,
      remaining:Math.max(0,2-control.smsAttempts),expires_at:new Date(control.expiresAt).toISOString(),
      otp_expires_at:canValidate ? new Date(issuedAt!+10*60_000).toISOString() : null};
  }
  async function installer(context: BrowserContext, role: RoleRecette) {
    await base.installer(context,role,{supabaseOriginSimulee:STAGING_SMS_SIMULE});
    const json = (route:Route,data:unknown,status=200) => route.fulfill({status,json:data,
      headers:{'access-control-allow-origin':'*','access-control-allow-headers':route.request().headers()['access-control-request-headers'] || 'authorization,apikey,content-type,x-client-info,x-supabase-api-version',
        'access-control-allow-methods':'GET,POST,HEAD,OPTIONS'}});
    await context.route('**/rest/v1/rpc/*',async route => {
      const request=route.request(),url=new URL(request.url()),name=url.pathname.split('/').pop()!;
      if (!['fn_admission_otp_signature_recette','fn_envoyer_otp_signature','fn_signer_contrat_otp'].includes(name)) return route.fallback();
      expect(url.origin).toBe(STAGING_SMS_SIMULE);
      if(request.method()==='OPTIONS')return json(route,{});
      expect(request.method()).toBe('POST');expect(request.headers().authorization).toBe(`Bearer simulation-mission-${role}`);
      const body=request.postDataJSON();expect(body.p_contrat_id).toBe(ids.contrat);
      state.calls.push({role,name,method:request.method(),body});
      if(name==='fn_admission_otp_signature_recette'){
        expect(body).toEqual({p_contrat_id:ids.contrat});control.admissionReads++;
        const hold=nextHold;nextHold=null;
        if(hold){control.pendingAdmissions++;await hold;control.pendingAdmissions--;}
        return json(route,receipt(role));
      }
      if(name==='fn_envoyer_otp_signature'){
        if(!receipt(role).can_send)return json(route,{success:false,error_code:'SMS_RECETTE_INDISPONIBLE'});
        control.smsAttempts++;issuedAt=control.time;
        state.sms.push({role,contrat_id:ids.contrat});
        const hold=nextSmsHold;nextSmsHold=null;
        if(hold){control.pendingSms++;await hold;control.pendingSms--;}
        return json(route,{success:true,role:role==='SOIGNANT'?'soignant':'etablissement',telephone_masked:'numéro fictif',sms_restants:Math.max(0,3-control.smsAttempts),expire_dans_minutes:10});
      }
      control.validations++;
      if(!receipt(role).can_validate)return json(route,{success:false,error_code:'NON_AUTORISE'});
      if(body.p_otp_code!=='123456')return json(route,{success:false,error_code:'OTP_INCORRECT',tentatives_restantes:4});
      if(body.p_hash_document!==admittedHash)return json(route,{success:false,error_code:'HASH_DOCUMENT_CHANGE'});
      const signer=role==='SOIGNANT'?'soignant':'etablissement';
      state.contrat['signature_'+signer]=true;state.contrat['signature_'+signer+'_le']=new Date(control.time).toISOString();
      state.contrat.statut=signer==='soignant'?'SIGNE_SOIGNANT':'SIGNE_ETABLISSEMENT';
      state.signatures.push({id:'preuve-sms-simulee-'+signer,contrat_id:ids.contrat,signataire_user_id:role==='SOIGNANT'?ids.soignant:ids.etablissement,
        signataire_role:signer,signe_a:now,otp_valide_a:now,hash_document:admittedHash,statut_signature:'signe',cree_le:now});
      return json(route,{success:true,role:signer,contrat_complet:false});
    });
    await context.route(url=>url.hostname==='fonts.googleapis.com',async route=>{
      if(route.request().method()==='GET'&&route.request().resourceType()==='stylesheet')return route.fulfill({contentType:'text/css',body:''});
      state.external.push(route.request().url());return route.abort('blockedbyclient');
    });
  }
  return {...base,installer,control};
}
