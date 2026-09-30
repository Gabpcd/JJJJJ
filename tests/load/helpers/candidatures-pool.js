const uuidServeur=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-a[a-f0-9]{3}-[a-f0-9]{12}$/;
export function lireCandidaturesD(brut,runId) {
  let m;try{m=JSON.parse(brut);}catch{throw new Error('Banc D2 non préparé : aucune requête.');}
  if(!m||m.version!==1||m.projectRef!=='mejpriaetwgtcstbgfid'||m.runId!==runId||!runId||m.marker!==`RECETTE D ${runId}`
    ||!uuid.test(m.missionId)||!uuid.test(m.creneauId)||!Array.isArray(m.identites)||m.identites.length!==3
    ||m.identites.some((a,i)=>a.slot!==i||!uuid.test(a.userId)||a.email!==`recette-d-${a.userId}@example.invalid`||a.role!==(i===2?'ADMIN_ETABLISSEMENT':'SOIGNANT')||typeof a.password!=='string'||a.password.length<32||/[\r\n]/.test(a.password))
    ||new Set(m.identites.map(a=>a.userId)).size!==3||new Set(m.identites.map(a=>a.password)).size!==3
    ||!/^\d{4}-\d{2}-\d{2}$/.test(m.jour)||m.debut!==`${m.jour}T09:00:00.000Z`||m.fin!==`${m.jour}T13:00:00.000Z`) throw new Error('Lot D2 invalide : aucune requête.');
  return m;
}
export function utilisateurD(u,a,runId) {return u?.id===a.userId&&u.email===a.email&&u.app_metadata?.role===a.role&&u.app_metadata.est_compte_test===true&&u.app_metadata.is_test_playwright===true&&u.app_metadata.load_fixture_kind==='CANDIDATURES_D2'&&u.app_metadata.load_fixture_run===runId&&(a.role!=='ADMIN_ETABLISSEMENT'||u.app_metadata.etablissement_id===a.userId);}
export function corpsPostulerD(m) {return {p_mission_id:m.missionId,p_action:'POSTULER',p_creneaux_confirmes:[{debut:m.debut,fin:m.fin}],p_message:m.marker,p_choix_contrat:null,p_candidature_id:null};}
export function candidatureDValide(c,m,a,id) {return c?.id===id&&uuidServeur.test(id)&&c.mission_id===m.missionId&&c.soignant_id===a.userId&&c.statut==='EN_ATTENTE'&&c.type_contrat_choisi==='SALARIE'&&c.message===m.marker;}
