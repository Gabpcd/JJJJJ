// Pure admission helper. No network, secrets, mutation or logging.
const STAGING_URL='https://mejpriaetwgtcstbgfid.supabase.co';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const E164=/^\+[1-9][0-9]{7,14}$/;
type Config={runId:string;sourceSha:string;manifestSha256:string;accountSid:string;senderPhone:string};
export function signatureSmsStagingConfig(get:(key:string)=>string|undefined):Config|null{
 const raw=get('SIGNATURE_SMS_STAGING_TEST_RUN');
 if(raw===undefined)return null;
 try{
  const c=JSON.parse(raw);
  if(!c||Array.isArray(c)||Object.keys(c).sort().join(',')!=='accountSid,manifestSha256,runId,senderPhone,sourceSha'
    ||get('SUPABASE_URL')!==STAGING_URL
    ||(get('SUPABASE_ENV')!==undefined&&!['staging','test'].includes(get('SUPABASE_ENV')!))
    ||typeof c.runId!=='string'||!/^sms-signature-[a-z0-9-]{8,64}$/.test(c.runId)
    ||typeof c.sourceSha!=='string'||!/^[a-f0-9]{40}$/.test(c.sourceSha)
    ||typeof c.manifestSha256!=='string'||!/^[a-f0-9]{64}$/.test(c.manifestSha256)
    ||typeof c.accountSid!=='string'||!/^AC[0-9a-fA-F]{32}$/.test(c.accountSid)
    ||typeof c.senderPhone!=='string'||!E164.test(c.senderPhone)
    ||get('TWILIO_ACCOUNT_SID')!==c.accountSid
    ||(get('TWILIO_FROM_NUMBER')||get('TWILIO_PHONE_NUMBER'))!==c.senderPhone
    ||!get('TWILIO_AUTH_TOKEN'))throw new Error();
  return c;
 }catch{throw new Error('SIGNATURE_SMS_STAGING_CONFIG_REFUSED');}
}
export async function signatureSmsStagingRequest(config:Config|null,isServiceRole:boolean,body:Record<string,unknown>,phone:string|null){
 if(!config||!isServiceRole||body.type!=='OTP_SIGNATURE'||body.prefix_type!=='SIGNATURE'
   ||typeof body.destinataire_id!=='string'||!UUID.test(body.destinataire_id)
   ||!phone||!E164.test(phone)||!body.data||typeof body.data!=='object'||Array.isArray(body.data))return null;
 const data=body.data as Record<string,unknown>;
 if(Object.keys(data).sort().join(',')!=='contrat_id,mission_id'
   ||typeof data.contrat_id!=='string'||!UUID.test(data.contrat_id)
   ||typeof data.mission_id!=='string'||!UUID.test(data.mission_id)
   ||typeof body.idempotency_key!=='string'||!body.idempotency_key.startsWith(`otp-signature.${data.contrat_id}.${body.destinataire_id}.`)
   ||typeof body.contenu!=='string')return null;
 const match=/^Code de signature Jolene : ([0-9]{6}) \(valide 10 min\)\. Ne le partagez avec personne\.$/.exec(body.contenu);
 if(!match)return null;
 const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(`${match[1]}|${data.contrat_id}|${body.destinataire_id}`));
 const otpHash=Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,'0')).join('');
 return {p_run_id:config.runId,p_source_sha:config.sourceSha,p_manifest_sha256:config.manifestSha256,
  p_contrat_id:data.contrat_id,p_mission_id:data.mission_id,p_actor_id:body.destinataire_id,p_telephone:phone,p_otp_hash:otpHash,
  p_idempotency_key:body.idempotency_key,p_twilio_account_sid:config.accountSid,p_sender_phone:config.senderPhone};
}
