import {test,expect,type Page,type TestInfo,type Browser} from '@playwright/test';
import {creerSignatureSmsStagingSimulee} from './helpers/recette-signature-sms-staging';
import {ids,now,preuveMission,type RoleRecette} from './helpers/recette-complete-mission';

// Dedicated Vite build with exact staging URL and a dummy public key.
// Every API request is intercepted: no account, SMS, SQL or provider is real.
const otpOption=(page:Page)=>page.getByRole('radio',{name:/Signature électronique OTP SMS/});
const codeInput=(page:Page)=>page.getByRole('textbox',{name:'Code SMS à 6 chiffres'});
const send=(page:Page)=>page.getByRole('button',{name:'Recevoir le code SMS pour signer',exact:true});
const resend=(page:Page)=>page.getByRole('button',{name:'Renvoyer le code',exact:true});
const sign=(page:Page)=>page.getByRole('button',{name:'Signer',exact:true});
async function scene(browser:Browser,info:TestInfo,role:RoleRecette){
  const context=await browser.newContext({...info.project.use});
  const harness=creerSignatureSmsStagingSimulee();
  await harness.installer(context,role);
  const page=await context.newPage();page.setDefaultTimeout(12_000);
  await page.clock.install({time:new Date(now)});
  return {context,page,...harness};
}
async function openOtp(page:Page){
  await expect(otpOption(page)).toBeVisible();await otpOption(page).check();
  await page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
  await send(page).click();await expect(codeInput(page)).toBeEnabled();
  await codeInput(page).fill('123456');
}
async function secondSms(page:Page){
  await resend(page).click();await expect(codeInput(page)).toHaveValue('');
  await codeInput(page).fill('123456');
}
async function simulatedSmsReturn(page:Page){
  // Simulates the native/browser focus event on return from reading Messages.
  // No SMS app or physical handset is represented by this event.
  await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
}
function assertNoProvider(harness:ReturnType<typeof creerSignatureSmsStagingSimulee>){
  expect(harness.state.external).toEqual([]);expect(harness.state.unknown).toEqual([]);expect(harness.state.errors).toEqual([]);
  expect(harness.state.calls.some(call=>['send-sms','stripe-connect-pay-mission','process-stripe-refunds'].includes(call.name))).toBe(false);
}
async function attachSummary(info:TestInfo,label:string,h:ReturnType<typeof creerSignatureSmsStagingSimulee>){
  await info.attach(label,{body:JSON.stringify({boundary:'Frontend API mocks only; no SMS, SQL or supplier integration',
    admissionReads:h.control.admissionReads,simulatedSms:h.control.smsAttempts,validations:h.control.validations,
    calls:h.state.calls.map(call=>({name:call.name,method:call.method,role:call.role})),
    external:h.state.external,unknown:h.state.unknown,errors:h.state.errors}),contentType:'application/json'});
}

for(const role of ['SOIGNANT','ADMIN_ETABLISSEMENT'] as RoleRecette[]){
  test(`SMS STAGING SIMULÉ — ${role} : CANVAS pendant SMS2 puis OTP après réponse sans reload ni focus`,async({browser},info)=>{
    const h=await scene(browser,info,role);h.control.enabled=true;
    try{
      await h.page.goto(`/contrat/${ids.contrat}`);await openOtp(h.page);
      const releaseSms=h.control.retenirProchainSms();await resend(h.page).click();
      await expect.poll(()=>h.control.pendingSms).toBe(1);expect(h.control.smsAttempts).toBe(2);
      const readsBeforeCanvas=h.control.admissionReads;
      await h.page.getByRole('radio',{name:/Signature manuscrite/}).check();await expect(codeInput(h.page)).toHaveCount(0);
      releaseSms();await expect.poll(()=>h.control.pendingSms).toBe(0);
      expect(h.control.admissionReads).toBe(readsBeforeCanvas);
      // The radio is hidden while this admission is held; check() would wait
      // for a control that can return only after the release below.
      const releaseAdmission=h.control.retenirProchaineAdmission();await otpOption(h.page).click();
      await expect.poll(()=>h.control.pendingAdmissions).toBe(1);
      expect(h.control.admissionReads).toBe(readsBeforeCanvas+1);
      await expect(send(h.page)).toBeDisabled();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(0);
      releaseAdmission();await expect(codeInput(h.page)).toBeEnabled();await expect(codeInput(h.page)).toHaveValue('');
      await expect(otpOption(h.page)).toBeChecked();
      await expect(h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/})).not.toBeChecked();
      await expect(resend(h.page)).toBeDisabled();await expect(send(h.page)).toHaveCount(0);
      await codeInput(h.page).fill('123456');await h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
      await preuveMission(h.page,info,role+'-sms-canvas-pendant-envoi');await sign(h.page).click();
      await expect(h.page.getByText('✅ Vous avez déjà signé ce contrat',{exact:true})).toBeVisible();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(1);assertNoProvider(h);
    }finally{await attachSummary(info,'sms-canvas-pending-send-'+role,h);await h.context.close();}
  });

  test(`SMS STAGING SIMULÉ — ${role} : CANVAS→OTP directement après SMS2 sans reload ni focus`,async({browser},info)=>{
    const h=await scene(browser,info,role);h.control.enabled=true;
    try{
      await h.page.goto(`/contrat/${ids.contrat}`);await openOtp(h.page);await secondSms(h.page);
      await expect.poll(()=>h.control.admissionReads).toBeGreaterThanOrEqual(4);
      await expect.poll(()=>h.control.pendingAdmissions).toBe(0);
      await expect(resend(h.page)).toBeDisabled();
      await h.page.getByRole('radio',{name:/Signature manuscrite/}).check();await otpOption(h.page).check();
      await expect(codeInput(h.page)).toBeEnabled();await expect(codeInput(h.page)).toHaveValue('');
      await expect(h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/})).not.toBeChecked();
      await expect(resend(h.page)).toBeDisabled();await expect(send(h.page)).toHaveCount(0);
      await codeInput(h.page).fill('123456');
      await h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(0);
      await preuveMission(h.page,info,role+'-sms-canvas-direct-apres-envoi');
      await sign(h.page).click();
      await expect(h.page.getByText('✅ Vous avez déjà signé ce contrat',{exact:true})).toBeVisible();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(1);assertNoProvider(h);
    }finally{await attachSummary(info,'sms-canvas-direct-'+role,h);await h.context.close();}
  });

  test(`SMS STAGING SIMULÉ — ${role} : OTP2 après reload puis CANVAS→OTP sans troisième SMS`,async({browser},info)=>{
    const h=await scene(browser,info,role);h.control.enabled=true;
    try{
      await h.page.goto(`/contrat/${ids.contrat}`);await openOtp(h.page);await secondSms(h.page);
      expect(h.control.smsAttempts).toBe(2);
      await h.page.reload();await expect(otpOption(h.page)).toBeVisible();await otpOption(h.page).check();
      await expect(codeInput(h.page)).toBeEnabled();await expect(codeInput(h.page)).toHaveValue('');
      await expect(h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/})).not.toBeChecked();
      await expect(resend(h.page)).toBeDisabled();await expect(send(h.page)).toHaveCount(0);
      await codeInput(h.page).fill('123456');
      await h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
      await h.page.getByRole('radio',{name:/Signature manuscrite/}).check();
      await expect(codeInput(h.page)).toHaveCount(0);await otpOption(h.page).check();
      await expect(codeInput(h.page)).toBeEnabled();await expect(codeInput(h.page)).toHaveValue('');
      await expect(h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/})).not.toBeChecked();
      await codeInput(h.page).fill('123456');
      await h.page.getByRole('checkbox',{name:/J'ai lu l'intégralité du contrat/}).check();
      const release=h.control.retenirProchaineAdmission();await simulatedSmsReturn(h.page);
      await expect.poll(()=>h.control.pendingAdmissions).toBe(1);
      await expect(codeInput(h.page)).toBeDisabled();await expect(sign(h.page)).toBeDisabled();await expect(resend(h.page)).toBeDisabled();
      release();await expect(codeInput(h.page)).toBeEnabled();await expect(codeInput(h.page)).toHaveValue('123456');
      await expect(resend(h.page)).toBeDisabled();await expect(sign(h.page)).toBeEnabled();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(0);
      await preuveMission(h.page,info,role+'-sms-continuation-remontee');
      await sign(h.page).click();
      await expect(h.page.getByText('✅ Vous avez déjà signé ce contrat',{exact:true})).toBeVisible();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(1);assertNoProvider(h);
    }finally{await attachSummary(info,'sms-otp2-remount-'+role,h);await h.context.close();}
  });

  test(`SMS STAGING SIMULÉ — ${role} : remount OTP2 conserve l’échéance originale du code`,async({browser},info)=>{
    const h=await scene(browser,info,role);h.control.enabled=true;
    try{
      await h.page.goto(`/contrat/${ids.contrat}`);await openOtp(h.page);await secondSms(h.page);
      h.control.time=Date.parse(now)+9*60_000;
      await h.page.clock.fastForward(9*60_000);
      await h.page.reload();await expect(otpOption(h.page)).toBeVisible();await otpOption(h.page).check();
      await expect(codeInput(h.page)).toBeEnabled();await expect(codeInput(h.page)).toHaveValue('');
      await h.page.getByRole('radio',{name:/Signature manuscrite/}).check();await otpOption(h.page).check();
      await expect(codeInput(h.page)).toBeEnabled();await expect(resend(h.page)).toBeDisabled();
      const release=h.control.retenirProchaineAdmission();await simulatedSmsReturn(h.page);
      await expect.poll(()=>h.control.pendingAdmissions).toBe(1);await expect(codeInput(h.page)).toBeDisabled();
      h.control.time=Date.parse(now)+10*60_000;
      await h.page.clock.fastForward(60_000+1);
      await expect(codeInput(h.page)).toHaveCount(0);await expect(otpOption(h.page)).toHaveCount(0);
      await expect(h.page.getByRole('radio',{name:/Signature manuscrite/})).toBeChecked();
      release();await expect.poll(()=>h.control.pendingAdmissions).toBe(0);
      await h.page.reload();await expect(otpOption(h.page)).toHaveCount(0);
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(0);
      await preuveMission(h.page,info,role+'-sms-remount-code-expire');assertNoProvider(h);
    }finally{await attachSummary(info,'sms-remount-expiry-'+role,h);await h.context.close();}
  });

  test(`SMS STAGING SIMULÉ — ${role} : TEST canvas, retour Messages et deuxième OTP sans troisième SMS`,async({browser},info)=>{
    const h=await scene(browser,info,role);
    try{
      await h.page.goto(`/contrat/${ids.contrat}`);
      await expect(h.page.getByRole('heading',{name:'Document fictif de recette',exact:true})).toBeVisible();
      await expect(h.page.getByRole('radio',{name:/Signature manuscrite/})).toBeChecked();
      await expect(otpOption(h.page)).toHaveCount(0);
      await expect.poll(()=>h.control.admissionReads).toBeGreaterThan(0);
      expect(h.control.smsAttempts).toBe(0);
      await preuveMission(h.page,info,role+'-sms-admission-fermee');
      h.control.enabled=true;
      await h.page.reload();await openOtp(h.page);await secondSms(h.page);
      expect(h.control.smsAttempts).toBe(2);
      const release=h.control.retenirProchaineAdmission();
      await simulatedSmsReturn(h.page);
      await expect.poll(()=>h.control.pendingAdmissions).toBe(1);
      await expect(codeInput(h.page)).toHaveValue('123456');await expect(codeInput(h.page)).toBeDisabled();
      await expect(sign(h.page)).toBeDisabled();await expect(resend(h.page)).toBeDisabled();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(0);
      await preuveMission(h.page,info,role+'-sms-retour-pendant');
      release();
      await expect(codeInput(h.page)).toBeEnabled();await expect(codeInput(h.page)).toHaveValue('123456');
      await expect(sign(h.page)).toBeEnabled();await expect(resend(h.page)).toBeDisabled();
      expect(h.control.smsAttempts).toBe(2);expect(h.control.validations).toBe(0);
      await sign(h.page).click();
      await expect(h.page.getByText('✅ Vous avez déjà signé ce contrat',{exact:true})).toBeVisible();
      expect(h.control.validations).toBe(1);expect(h.control.smsAttempts).toBe(2);
      await h.page.reload();
      await expect(h.page.getByText('✅ Vous avez déjà signé ce contrat',{exact:true})).toBeVisible();
      await preuveMission(h.page,info,role+'-sms-signature-recharge');
      assertNoProvider(h);
    }finally{await attachSummary(info,'sms-deuxieme-otp-'+role,h);await h.context.close();}
  });

  for(const refusal of ['revocation','expiration'] as const){
    test(`SMS STAGING SIMULÉ — ${role} : ${refusal} pendant retour du deuxième SMS ferme la saisie`,async({browser},info)=>{
      const h=await scene(browser,info,role);h.control.enabled=true;
      try{
        await h.page.goto(`/contrat/${ids.contrat}`);await openOtp(h.page);await secondSms(h.page);
        const release=h.control.retenirProchaineAdmission();await simulatedSmsReturn(h.page);
        await expect.poll(()=>h.control.pendingAdmissions).toBe(1);
        await expect(sign(h.page)).toBeDisabled();await expect(codeInput(h.page)).toHaveValue('123456');
        if(refusal==='revocation')h.control.revoked=true;
        else{
          h.control.time=h.control.expiresAt;
          await h.page.clock.fastForward(60*60_000+1);
          await expect(codeInput(h.page)).toHaveCount(0);
        }
        release();
        await expect(codeInput(h.page)).toHaveCount(0);await expect(otpOption(h.page)).toHaveCount(0);
        await expect(h.page.getByRole('radio',{name:/Signature manuscrite/})).toBeChecked();
        expect(h.control.validations).toBe(0);expect(h.control.smsAttempts).toBe(2);
        await h.page.reload();await expect(otpOption(h.page)).toHaveCount(0);
        await expect.poll(()=>h.control.pendingAdmissions).toBe(0);
        await preuveMission(h.page,info,role+'-sms-'+refusal+'-recharge');assertNoProvider(h);
      }finally{await attachSummary(info,'sms-'+refusal+'-'+role,h);await h.context.close();}
    });
  }

  test(`SMS STAGING SIMULÉ — ${role} : changement de document puis reload exige une nouvelle admission`,async({browser},info)=>{
    const h=await scene(browser,info,role);h.control.enabled=true;
    try{
      await h.page.goto(`/contrat/${ids.contrat}`);await openOtp(h.page);
      h.state.contrat.hash_document='b'.repeat(64);
      h.state.contrat.contenu_html='<article><h2>Document fictif modifié de recette</h2><p>Nouvelle version synthétique.</p></article>';
      await h.page.reload();
      await expect(h.page.getByRole('heading',{name:'Document fictif modifié de recette',exact:true})).toBeVisible();
      await expect(otpOption(h.page)).toHaveCount(0);await expect(codeInput(h.page)).toHaveCount(0);
      await expect(h.page.getByRole('radio',{name:/Signature manuscrite/})).toBeChecked();
      expect(h.control.smsAttempts).toBe(1);expect(h.control.validations).toBe(0);
      await preuveMission(h.page,info,role+'-sms-document-change');assertNoProvider(h);
    }finally{await attachSummary(info,'sms-scope-change-'+role,h);await h.context.close();}
  });
}
