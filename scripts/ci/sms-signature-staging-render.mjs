import {createHash} from 'node:crypto';

// Exact definition read from staging on 2026-10-14, not an old migration.
export const OTP_SOURCE_SHA256='5d6ad83f50b15b633841ed853961f48dc9a54575b8abffb6b68f574360e1e052';
function replaceOnce(source,anchor,replacement){
 if(source.split(anchor).length!==2)throw new Error('SIGNATURE_SMS_STAGING_PATCH_ANCHOR');
 return source.replace(anchor,replacement);
}
export function renderSignatureSmsStaging(source,helpers){
 if(createHash('sha256').update(source).digest('hex')!==OTP_SOURCE_SHA256)throw new Error('SIGNATURE_SMS_STAGING_SOURCE_DRIFT');
 let patched=replaceOnce(source,"  -- Le bootstrap staging aligne ces deux valeurs sur son propre projet.",`  -- Only the pinned TEST capability can request an external signature OTP.
  IF EXISTS(SELECT 1 FROM public.soignants WHERE id=v_uid AND est_compte_test IS TRUE)
     OR EXISTS(SELECT 1 FROM public.etablissements WHERE id=v_uid AND est_compte_test IS TRUE) THEN
    BEGIN
      PERFORM private.fn_signature_sms_test_scope(p_contrat_id,v_uid);
      IF public.fn_admission_otp_signature_recette(p_contrat_id)->'can_send' IS DISTINCT FROM 'true'::jsonb THEN
        RAISE EXCEPTION 'SIGNATURE_SMS_TEST_BUDGET_EXHAUSTED';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object('success',false,'error_code','SMS_RECETTE_INDISPONIBLE',
        'error','Envoi du code indisponible pour cette recette.');
    END;
  END IF;

  -- Le bootstrap staging aligne ces deux valeurs sur son propre projet.`);
 patched=replaceOnce(patched,"'data', jsonb_build_object('contrat_id', p_contrat_id)","'data', jsonb_build_object('contrat_id', p_contrat_id, 'mission_id', (SELECT mission_id FROM public.contrats_mission WHERE id=p_contrat_id))");
 return `${helpers.trim()}\n\n${patched.trim()};
DO $sms_inventory$
DECLARE x record;
BEGIN
 FOR x IN SELECT * FROM (VALUES
   ('public.fn_envoyer_otp_signature(uuid)','RPC_UTILISATEUR_AUTH_INTERNE'),
   ('public.fn_admission_otp_signature_recette(uuid)','RPC_UTILISATEUR_AUTH_INTERNE'),
   ('public.fn_reserver_sms_signature_recette(text,text,text,uuid,uuid,uuid,text,text,text,text,text,text)','SERVICE_ONLY_REVOQUE')
 ) AS expected(signature,categorie) LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=x.signature::regprocedure AND prosecdef) THEN
     RAISE EXCEPTION 'SIGNATURE_SMS_TEST_INVENTORY';
   END IF;
   INSERT INTO private.security_definer_inventory(signature,categorie,definition_md5,justification,recense_le)
   SELECT regexp_replace(x.signature,'^public[.]',''),x.categorie,md5(prosrc),
     'Admission signature OTP staging bornee ; compte TEST preserve, allocation fermee.',clock_timestamp()
   FROM pg_proc WHERE oid=x.signature::regprocedure
   ON CONFLICT(signature) DO UPDATE SET definition_md5=excluded.definition_md5,
     justification=excluded.justification,recense_le=excluded.recense_le
   WHERE private.security_definer_inventory.categorie=excluded.categorie;
   IF NOT FOUND THEN RAISE EXCEPTION 'SIGNATURE_SMS_TEST_INVENTORY'; END IF;
 END LOOP;
END; $sms_inventory$;
`;
}
