import { expect, type BrowserContext, type Page, type TestInfo } from '@playwright/test';

/** Contrat frontend uniquement : ni SQL/RLS, ni SMS/paiement réels ne sont exercés. */
export const ids = {
  soignant: '71000000-0000-4000-8000-000000000001',
  etablissement: '71000000-0000-4000-8000-000000000002',
  mission: '71000000-0000-4000-8000-000000000003',
  candidature: '71000000-0000-4000-8000-000000000004',
  contrat: '71000000-0000-4000-8000-000000000005',
  presence: '71000000-0000-4000-8000-000000000006',
};
export type RoleRecette = 'SOIGNANT' | 'ADMIN_ETABLISSEMENT';
export const now = '2026-09-24T06:55:00.000Z';
export const hash = 'a'.repeat(64);

export function creerMissionSimulee() {
  const soignant = { id: ids.soignant, prenom: 'Camille', nom: 'Recette', profession: 'MEDECIN',
    date_naissance: '1985-06-15', telephone: '+33600000001', telephone_verifie: true,
    numero_rpps: '10000000001', rpps_verifie: true, type_exercice: 'LIBERAL', statut_liberal: 'ACTIF',
    tous_documents_valides: true, adresse_rue: '1 rue de la Simulation', adresse_ville: 'Paris',
    adresse_code_postal: '75001', adresse_lat: 48.86, adresse_lng: 2.35, est_compte_test: false,
    consentement_gps: false, email: 'soignant-mission@example.invalid', score_fiabilite: 85,
    regime_fiscal: 'BNC', regime_fiscal_confirme: true, mandat_facturation_signe:true,
    mandat_facturation_version:'simulation-v1', premiere_mission_le: null };
  const etablissement = { id: ids.etablissement, nom: 'Clinique Simulation', type: 'CLINIQUE',
    adresse_rue: '2 rue de la Simulation', adresse_ville: 'Paris', adresse_code_postal: '75001',
    adresse_lat: 48.86, adresse_lng: 2.35, email_contact: 'etablissement-mission@example.invalid',
    telephone_contact: '+33600000002', siret: '00000000000000', finess: '000000000',
    est_compte_test: false, paiement_rapide: false, statut_verification: 'VERIFIE',contrat_service_signe:true };
  const mission = { id: ids.mission, intitule: 'Mission médecin — recette intégrale', description: 'Mission fictive de simulation UI.',
    service: 'Consultations', profession_requise: 'MEDECIN', debut_le: '2026-09-24T07:00:00.000Z',
    fin_le: '2026-09-24T15:00:00.000Z', duree_heures: 8, nb_creneaux: 1, taux_horaire_base: 80,
    total_brut: 640, net_a_payer: 640, net_estime: 640, type_contrat_recherche: 'LIBERAL',
    type_contrat_applique: null as string | null, type_paiement_soignant: 'NOTE_HONORAIRES', mode_paiement_soignant: 'DIRECT',
    choix_contrat_soignant: null, mode_remuneration: 'TAUX_HORAIRE', mode_attribution: 'CANDIDATURE',
    statut: 'OUVERTE', soignant_assigne_id: null as string | null, etablissement_id: ids.etablissement,
    cree_le: now, modifie_le: now, taux_ifm: 0, taux_icp: 0, montant_ifm: 0, montant_icp: 0,
    heures_nuit: 0, heures_dimanche: 0, heures_ferie: 0, montant_majoration_nuit: 0,
    montant_majoration_dimanche: 0, montant_majoration_ferie: 0, nature_tva_prestation: 'SOIN_THERAPEUTIQUE_EXONERE',
    nature_tva_confirmee_soignant: 'SOIN_THERAPEUTIQUE_EXONERE', statut_validation_tva: 'CONFIRMEE',
    etablissements: etablissement, presences: [] as any[] };
  const creneaux: any[] = [{id: '71000000-0000-4000-8000-000000000010', mission_id: ids.mission,
    debut: mission.debut_le, fin: mission.fin_le, est_pause: false, type_creneau: 'PREVISIONNEL'}];
  const contrat: any = { id: ids.contrat, mission_id: ids.mission, soignant_id: ids.soignant,
    etablissement_id: ids.etablissement, numero_contrat: 'SIM-2026-0001', type_contrat: 'LIBERAL',
    statut: 'EN_ATTENTE_SIGNATURES', cree_le: now, signature_soignant: false, signature_etablissement: false,
    hash_document: hash, storage_path: 'simulation/contrat.pdf', contenu_html_rendu_le: now,
    contenu_html: '<article><h2>Document fictif de recette</h2><p>Camille Recette — Clinique Simulation</p><p>24 septembre 2026 : 09:00 à 17:00 — 8 heures à 80,00 €, soit 640,00 €.</p></article>' };
  const state = {
    soignant, etablissement, mission, creneaux, contrat, candidature: null as any, signatures: [] as any[],
    segments: [] as any[], presence: null as any, facture: null as any,
    calls: [] as { role: RoleRecette; name: string; method: string; body: any }[],
    unknown: [] as string[], external: [] as string[], errors: [] as string[],
    otpError: null as string | null, failOnce: null as string | null, scanTimes: [] as string[],
    sms: [] as {role: RoleRecette; contrat_id: string}[], emails: [] as any[], notes: [] as any[],
    contratCree: false,
  };
  function filter(rows: any[], url: URL) {
    return rows.filter(row => [...url.searchParams.entries()].every(([key, val]) => {
      if (['select', 'order', 'limit', 'offset'].includes(key)) return true;
      const value = key.split('.').reduce((a, k) => a?.[k], row);
      if (val.startsWith('eq.')) return String(value) === val.slice(3);
      if (val.startsWith('neq.')) return String(value) !== val.slice(4);
      if (val.startsWith('in.(')) return val.slice(4, -1).split(',').map(x => x.replaceAll('"', '')).includes(String(value));
      if (val === 'not.is.null') return value != null;
      if (val === 'is.null') return value == null;
      if (val.startsWith('gte.')) return String(value) >= val.slice(4);
      if (val.startsWith('lte.')) return String(value) <= val.slice(4);
      return true;
    }));
  }
  async function installer(context: BrowserContext, role: RoleRecette) {
    const user = {id: role === 'SOIGNANT' ? ids.soignant : ids.etablissement,
      email: role === 'SOIGNANT' ? soignant.email : etablissement.email_contact, aud:'authenticated',role:'authenticated',
      email_confirmed_at: now, app_metadata:{role, etablissement_id: role === 'ADMIN_ETABLISSEMENT' ? ids.etablissement : null},
      user_metadata:{prenom: role === 'SOIGNANT' ? soignant.prenom : 'Clinique', nom:'Recette'}, identities:[]};
    const session = {user, token_type:'bearer',access_token:'simulation-mission-'+role,refresh_token:'simulation-refresh',
      expires_in:86400,expires_at:1799999999};
    await context.addInitScript(({session}) => {
      if (!['127.0.0.1','localhost'].includes(location.hostname)) return;
      sessionStorage.setItem('sb-127-auth-token', JSON.stringify(session));
      localStorage.setItem('cookie-consent','refused');
    }, {session});
    await context.routeWebSocket('**/*', socket => socket.close());
    const suivreErreurs=(page:Page)=>page.on('pageerror',error=>state.errors.push(error.message));
    context.pages().forEach(suivreErreurs);context.on('page',suivreErreurs);
    await context.route('**/*', async route => {
      const req=route.request(), url=new URL(req.url()), name=url.pathname.split('/').pop()!;
      const json = (data: any, status=200, extraHeaders:Record<string,string>={}) => route.fulfill({status, json:data,
        headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*',...extraHeaders}});
      if (!['127.0.0.1','localhost'].includes(url.hostname)) {
        state.external.push(url.origin); return route.abort('blockedbyclient');
      }
      if (url.pathname.startsWith('/auth/v1/')) {
        if (['user','token','logout'].includes(name)) return json(name==='user'?user:name==='logout'?{}:session);
        state.unknown.push(`${req.method()} ${url.pathname}`); return json({message:'Auth simulée non prévue'},501);
      }
      if (!url.pathname.startsWith('/rest/v1/') && !url.pathname.startsWith('/functions/v1/') && !url.pathname.startsWith('/storage/v1/')) {
        if(req.isNavigationRequest()&&req.resourceType()==='document') {
          // Les préconnexions DNS/TLS ne passent pas par l'interception HTTP.
          // Retirer uniquement ces hints évite aussi toute connexion anticipée externe.
          const response=await route.fetch();
          const html=(await response.text()).replace(/<link\b(?=[^>]*\brel=["'](?:preconnect|dns-prefetch)["'])[^>]*>/gi,'');
          return route.fulfill({response,body:html});
        }
        return route.continue();
      }
      const body = req.postData() ? JSON.parse(req.postData()!) : null;
      state.calls.push({role,name,method:req.method(),body});
      if (req.method()==='OPTIONS') return json({});
      if (state.failOnce===name) {state.failOnce=null; return json({message:'Interruption réseau simulée'},503);}
      if (url.pathname.startsWith('/functions/v1/')) {
        if (name==='send-email') {state.emails.push(body);return json({success:true,simulated:true});}
      }
      if (url.pathname.includes('/rpc/')) {
        switch(name) {
          case 'fn_get_my_role': return json({role,etablissement_id:role==='ADMIN_ETABLISSEMENT'?ids.etablissement:null});
          case 'fn_compte_auth_actif': return json(true);
          case 'fn_mon_profil_soignant_complet': return json(soignant);
          case 'fn_mon_etablissement_complet': return json(etablissement);
          case 'fn_etablissement_public': case 'fn_etablissement_pour_mission': return json(etablissement);
          case 'fn_etablissements_safe': return json([etablissement]);
          case 'fn_soignant_pour_etablissement': return json(soignant);
          case 'fn_mes_soignants_etablissement': return json([soignant]);
          case 'fn_messages_non_lus': return json(0);
          case 'fn_update_presence': return json(null);
          case 'fn_obtenir_conversation': return json('71000000-0000-4000-8000-000000000007');
          case 'fn_est_bloque': return json(false);
          case 'fn_marquer_messages_lus': return json(null);
          case 'fn_interlocuteurs_conversations': return json([{conversation_id:'71000000-0000-4000-8000-000000000007',
            user_id:ids.soignant,prenom:soignant.prenom,nom:soignant.nom,avatar_url:null}]);
          case 'fn_note_moyenne': return json({moyenne:null,total:0});
          case 'fn_mode_exercice': return json({niveau:'AUTORISE',categorie:'prive',source_libelle:'Matrice simulée pour médecin en clinique',source_force:'CONFORMITE_JOLENE',source_url:null});
          case 'fn_param_bool': return json(false);
          case 'fn_ecrire_audit_safe': return json(null);
          case 'fn_onboarding_soignant_statut': return json(null);
          case 'fn_litige_pour_mission': return json({exists:false});
          case 'fn_alerte_cddu_repetitif': return json({alerte:false});
          case 'fn_generer_donnees_dpae': return json({success:true,contrat_id:ids.contrat,type_contrat:contrat.type_contrat,
            etablissement:{nom:etablissement.nom,siret:etablissement.siret,adresse_rue:etablissement.adresse_rue,
              adresse_ville:'Paris',adresse_code_postal:'75001',organisme_protection_sociale:'URSSAF'},
            salarie:{nom:soignant.nom,prenom:soignant.prenom,date_naissance:soignant.date_naissance,
              profession:soignant.profession,champs_a_completer_sur_net_entreprises:['numero_securite_sociale']},
            embauche:{date_prevue:mission.debut_le,heure_prevue:'09:00',date_fin:mission.fin_le,
              type_contrat:contrat.type_contrat,duree_heures_prevues:mission.duree_heures},
            urssaf_url:'https://www.net-entreprises.fr/declaration-prealable-embauche/',note:'Données de recette fictives.'});
          case 'fn_enregistrer_numero_dpae':
            if(!/^[A-Za-z0-9]{8,30}$/.test(body.p_dpae_numero)) return json({success:false,
              error:'Format invalide : 8 à 30 caractères alphanumériques (lettres et chiffres) requis. Aucun espace ni ponctuation.'});
            contrat.dpae_numero=body.p_dpae_numero;contrat.dpae_effectuee=true;contrat.dpae_effectuee_le=now;
            state.emails.push({simulated:true,type:'DPAE_DECLAREE_SOIGNANT',destinataire_id:ids.soignant});
            return json({success:true,dpae_numero:contrat.dpae_numero});
          case 'fn_mes_permissions_etab': return json({success:true,role:'PROPRIETAIRE',etablissement_id:ids.etablissement,
            permissions:Object.fromEntries(['gerer_equipe','supprimer_compte','profil_etab','paiement','lecture_paiement','missions','candidatures','contrats','pointage','rh','lecture'].map(p=>[p,true]))});
          case 'fn_confirmer_action_planning_v1':
            if (body.p_action==='POSTULER' && !state.candidature) {
              state.candidature={id:ids.candidature,mission_id:ids.mission,soignant_id:ids.soignant,
                message:body.p_message,statut:'EN_ATTENTE',cree_le:now};
              return json({success:true,candidature_id:ids.candidature});
            } break;
          case 'fn_traiter_candidature_planning_v1':
            if (body.p_decision==='ACCEPTEE' && state.candidature?.statut==='EN_ATTENTE') {
              state.candidature.statut='ACCEPTEE';state.candidature.acceptee_a=now;
              mission.statut='ASSIGNEE';mission.soignant_assigne_id=ids.soignant;mission.type_contrat_applique='LIBERAL';
              state.contratCree=true;return json({success:true,contrat_id:ids.contrat});
            } break;
          case 'fn_envoyer_otp_signature':
            if(state.otpError==='NON_AUTHENTIFIE') {state.otpError=null;return json({success:false,error_code:'NON_AUTHENTIFIE'});}
            state.sms.push({role,contrat_id:body.p_contrat_id});
            return json({success:true,telephone_masked:'+33 6 ** ** ** 01',sms_restants:2,expire_dans_minutes:10});
          case 'fn_signer_contrat_otp': {
            if(state.otpError) {const code=state.otpError;state.otpError=null;return json({success:false,error_code:code});}
            if(body.p_otp_code!=='123456') return json({success:false,error_code:'OTP_INCORRECT',tentatives_restantes:4});
            if(body.p_hash_document!==hash) return json({success:false,error_code:'HASH_DOCUMENT_CHANGE'});
            const signataire=role==='SOIGNANT'?'soignant':'etablissement';
            if(contrat['signature_'+signataire]) return json({success:false,error_code:'DEJA_SIGNE'});
            contrat['signature_'+signataire]=true;contrat['signature_'+signataire+'_le']=now;
            state.signatures.push({id:'signature-'+signataire,contrat_id:ids.contrat,signataire_user_id:user.id,
              signataire_role:signataire,signe_a:now,otp_valide_a:now,hash_document:hash,statut_signature:'signe',
              cree_le:now,ip_signature:'127.0.0.1',user_agent:'Recette Playwright',rpps_verifie:true,psc_session_active:false});
            const complet=contrat.signature_soignant&&contrat.signature_etablissement;
            contrat.statut=complet?'SIGNE_COMPLET':signataire==='soignant'?'SIGNE_SOIGNANT':'SIGNE_ETABLISSEMENT';
            return json({success:true,role:signataire,contrat_complet:complet});
          }
          case 'fn_etat_pointage_mission': return json({statut:mission.statut,segment_ouvert:state.segments.some(s=>!s.fin),
            prochain_type_scan:state.segments.some(s=>!s.fin)?'FERMETURE':'OUVERTURE',segments:state.segments});
          case 'fn_scanner_code_pointage': {
            if(body.p_code!=='654321') return json({code:'P0002',message:'Code de pointage invalide ou expiré.',details:null,hint:null},400);
            const timestamp=state.scanTimes.shift();
            if(!timestamp) throw new Error('Horodatage de scan non préparé');
            const segment=state.segments.find(s=>!s.fin);
            if(segment) segment.fin=timestamp;
            else {const s={id:'segment-'+state.segments.length,mission_id:ids.mission,debut:timestamp,fin:null,
              type_creneau:'EFFECTIF',est_pause:false};state.segments.push(s);creneaux.push(s);}
            mission.statut='EN_COURS';
            state.presence={id:ids.presence,mission_id:ids.mission,soignant_id:ids.soignant,
              pointage_arrivee_le:state.segments[0].debut,pointage_depart_le:segment?timestamp:null,
              valide_par_etablissement:false,cree_le:now,methode_pointage_arrivee:'CODE_ROTATIF',
              methode_pointage_depart:segment?'CODE_ROTATIF':null,missions:{...mission,presences:undefined}};
            mission.presences=[{...state.presence,missions:undefined}];
            return json({success:true,type_scan_effectue:segment?'FERMETURE':'OUVERTURE',presence_id:ids.presence});
          }
          case 'fn_valider_presence':
            state.presence.valide_par_etablissement=true;state.presence.valide_le='2026-09-24T15:15:00Z';
            mission.presences=[{...state.presence,missions:undefined}];
            return json({success:true});
          case 'fn_creer_notation_mission': state.notes.push(body);return json({success:true});
          case 'fn_terminer_mission':
            if(state.segments.some(s=>!s.fin)) return json({success:false,error:'Un segment de pointage est encore ouvert'});
            mission.statut='TERMINEE';return json({success:true});
          case 'fn_mes_factures_honoraires': return json(state.facture?[state.facture]:[]);
          case 'fn_mes_bulletins_paie': return json([]);
          case 'fn_mes_paiements_escrow': return json([]);
          case 'fn_mes_factures': return json([]);
          case 'fn_paiements_etablissement': return json({paiements:[]});
          case 'fn_mode_paiement_mission': return json({mode_recommande:'VIREMENT_NOTE_HONORAIRES',
            type_contrat_applique:'LIBERAL',type_exercice:soignant.type_exercice,stripe_connect_actif:false,
            rib_partage:false,iban_last4:null,montant_soignant:640,montant_soignant_estime:false,
            total_brut:640,net_estime:640,commission_ht:0,commission_ttc:0,total:640});
          case 'fn_obligations_financieres': return json({total_du:state.facture?640:0,total_soignants_du:state.facture?640:0,
            total_commissions_du:0,nb_missions_non_payees:state.facture?1:0,factures_impayees:[],
            paiements_soignants_en_attente:[],paiements_soignants_confirmes:[],factures_commission_historique:[],
            missions_non_facturees:[],missions_non_payees:state.facture?[{mission_id:ids.mission,intitule:mission.intitule,
              soignant_id:ids.soignant,soignant_nom:'Camille Recette',soignant_profession:'MEDECIN',type_contrat_applique:'LIBERAL',
              // La RPC expose ici la durée bornée par la période facturée (8 h), pas les segments effectifs (7 h 30).
              net_a_payer:640,heures:8,jours_depuis_fin:0,fin_le:mission.fin_le,debut_le:mission.debut_le,
              facture_honoraires_id:state.facture.id,est_facture_finale_mission:true,soignant_stripe_connect:false}]:[]});
        }
      } else if (url.pathname.startsWith('/rest/v1/')) {
        const tableData: Record<string, any[]> = {
          soignants:[soignant],etablissements:[etablissement],missions:[mission],mission_creneaux:creneaux,
          contrats_mission:state.contratCree?[contrat]:[],candidatures:state.candidature?[state.candidature]:[],
          signatures_contrats:state.signatures,presences:state.presence?[state.presence]:[],
          templates_contrat:[],parcours_inscription:[],notifications:[],documents_soignants:[],litiges:[],
          contrats_travail_missions:[],messages:[],messages_chat:[],typing_status:[],presence_status:[],
          conversations:[{id:'71000000-0000-4000-8000-000000000007',archived_at:null,soignant_id:ids.soignant}],
          notations_missions:[],evaluations:[],
          stripe_transfers:[],stripe_connect_onboarding:[],bulletins_paie:[],favoris:[],favoris_etab_soignant:[],
          paiements_soignant:[],factures_honoraires:state.facture?[state.facture]:[],paiements_mission:[],
        };
        if(name in tableData && ['GET','HEAD'].includes(req.method())) {
          const rows=filter(tableData[name],url);
          return json(req.headers().accept?.includes('object')?(rows[0]??null):rows,200,{'content-range':`0-${Math.max(rows.length-1,0)}/${rows.length}`});
        }
      }
      state.unknown.push(`${role} ${req.method()} ${url.pathname} ${url.search}`);
      return json({message:`Endpoint absent de la simulation stricte : ${name}`},501);
    });
  }
  function simulerEmissionFacture() {
    // Frontière explicite : l'émission serveur/asynchrone n'est PAS exécutée par Playwright.
    // Cette réponse ne devient disponible qu'après les actions UI de clôture et validation.
    expect(mission.statut).toBe('TERMINEE');expect(state.presence?.valide_par_etablissement).toBe(true);
    // Prévisionnel 8 h sans pause, effectif 7 h 30 : plancher prévu conservé (640 €).
    // Le calcul/régularisation SQL n'est pas exécuté ni prétendu validé ici.
    state.facture={id:'71000000-0000-4000-8000-000000000008',mission_id:ids.mission,soignant_id:ids.soignant,
      etablissement_id:ids.etablissement,numero_facture:'SIM-HON-2026-0001',statut:'EMISE',type_document:'FACTURE',
      montant_ht:640,montant_ttc:640,montant_signe:640,taux_tva:0,exoneration_tva:true,date_emission:'2026-09-24',
      date_echeance:'2026-10-24',date_paiement:null,cree_le:'2026-09-24T15:20:00Z',template_version:2,
      periode_debut:'2026-09-24',periode_fin:'2026-09-24',numero_semaine_iso:39,annee_iso:2026,
      est_facture_finale_mission:true,mission_intitule:mission.intitule,etablissement_nom:etablissement.nom,
      missions:mission,etablissements:etablissement};
  }
  return {state,installer,simulerEmissionFacture};
}

export async function preuveMission(page: Page, testInfo: TestInfo, label: string) {
  await testInfo.attach(label+'-aria',{body:await page.locator('body').ariaSnapshot(),contentType:'text/plain'});
  const screenshot=testInfo.outputPath(label+'.png');
  await page.screenshot({path:screenshot,fullPage:true,animations:'disabled'});
  await testInfo.attach(label+'-image',{path:screenshot,contentType:'image/png'});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth)).toBe(true);
}
