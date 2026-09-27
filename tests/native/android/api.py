"""In-memory API for native UI simulations only. Unknown operations fail with 501.
No database, credentials, outbound requests, professional verification or provider delivery.
"""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs
from pathlib import Path
import json,uuid,time,datetime,hashlib,base64,threading,os
LOG=Path(os.environ.get('NATIVE_API_LOG', 'test-results/android-native/api.jsonl'))
LOG.parent.mkdir(parents=True, exist_ok=True)
LOCK=threading.RLock(); USERS={}; PARCOURS={}; UNKNOWN=[]; ERRORS=[]; CALLS=[]
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def log(item):
 with LOCK:
  CALLS.append(item)
  with LOG.open('a') as f:f.write(json.dumps(item,ensure_ascii=False)+'\n')
def user_for(email):
 uid=str(uuid.uuid5(uuid.NAMESPACE_DNS,email))
 if uid not in USERS:USERS[uid]={'id':uid,'email':email,'aud':'authenticated','role':'authenticated','email_confirmed_at':now(),'app_metadata':{},'user_metadata':{},'identities':[]}
 return USERS[uid]
def session(user):return {'user':user,'token_type':'bearer','access_token':'fixture-'+user['id'],'refresh_token':'fixture-'+user['id'],'expires_in':3600,'expires_at':int(time.time())+3600}
def mission():
 debut=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=7)).replace(hour=8,minute=0,second=0,microsecond=0);fin=debut+datetime.timedelta(hours=8)
 return {'id':'69000000-0000-4000-8000-000000000072','cree_le':now(),'intitule':'Remplacement infirmier de jour — simulation','profession_requise':'IDE','description':'Donnée fictive de recette native. Aucun établissement réel.','debut_le':debut.isoformat(),'fin_le':fin.isoformat(),'duree_heures':8,'nb_creneaux':1,'taux_horaire_base':30,'total_brut':240,'net_estime':240,'net_a_payer':240,'mode_remuneration':'TAUX_HORAIRE','statut':'OUVERTE','mode_attribution':'CANDIDATURE','type_contrat_recherche':'SALARIE','type_contrat_applique':'SALARIE','soignant_assigne_id':None,'etablissement_id':'69000000-0000-4000-8000-000000000073','etablissements':{'id':'69000000-0000-4000-8000-000000000073','nom':'Résidence Camille — simulation','type':'EHPAD','adresse_ville':'Paris','adresse_code_postal':'75001'},'creneaux':[{'id':'69000000-0000-4000-8000-000000000075','mission_id':'69000000-0000-4000-8000-000000000072','debut':debut.isoformat(),'fin':fin.isoformat(),'est_pause':False,'type_creneau':'PREVISIONNEL'}]}
EMPTY_TABLES=set('admins_groupe_sante attestations_heures_externes bulletins_paie candidatures conformite_travail contrats_mission contrats_travail_missions conversations cotisations_sociales disponibilites_soignant documents_requis_par_profession documents_soignants evaluations exclusions factures_honoraires heures_externes_soignants justificatifs liste_attente_premium litiges mandats_facturation_signatures messages_chat messages_litige missions_sauvegardees notations_missions notifications paiements_soignant presence_status presences prevoyance_liste_attente reclamations specialites_medicales stripe_connect_onboarding swipes typing_status paliers_commission stripe_transfers paiements_mission parrainages_etablissements chorus_pro_config favoris_etab_soignant documents_etablissements'.split())
EMPTY_RPCS=set('fn_evolution_score_soignant fn_mes_evaluations_recues fn_lister_notations_recues fn_mes_exclusions_recues fn_mes_favoris_etablissements fn_mes_avances_factor fn_mes_bulletins_paie fn_mes_dpae fn_mes_factures_honoraires fn_mes_paiements_escrow fn_interlocuteurs_conversations fn_lister_conversations_messagerie fn_lister_mes_filtres_sauvegardes fn_top_soignants fn_mes_reclamations fn_mes_litiges fn_presences_detail_mission fn_mes_soignants_etablissement fn_mes_filleuls_etab fn_litiges_etablissement fn_lister_missions_a_noter_etab fn_mes_favoris_soignants fn_pool_urgence_etablissement fn_mes_factures'.split())
NULL_RPCS=set('fn_onboarding_soignant_statut fn_mon_token_calendrier fn_litige_pour_mission fn_mon_breakdown_actuel fn_consulter_mon_iban fn_audit_connexion fn_maj_activite_soignant fn_ecrire_audit_safe fn_update_presence'.split())
class Mock(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def reply(self,data,status=200,extra={}):
  payload=json.dumps(data,ensure_ascii=False).encode();self.send_response(status)
  for k,v in {'Content-Type':'application/json','Content-Length':str(len(payload)),'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info,prefer,range,range-unit,accept-profile,content-profile,x-supabase-api-version','Access-Control-Allow-Methods':'GET,HEAD,POST,OPTIONS','Access-Control-Expose-Headers':'content-range','Cache-Control':'no-store',**extra}.items():self.send_header(k,v)
  self.end_headers()
  if self.command!='HEAD':self.wfile.write(payload)
 def unknown(self,path):
  item={'method':self.command,'path':path,'unknown':True};UNKNOWN.append(item);log(item);return self.reply({'code':'RECETTE_INCONNU','message':'Endpoint non simulé'},501)
 def run_api(self):
  path=urlparse(self.path).path;name=path.split('/')[-1]
  try:body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))) or b'{}')
  except: return self.reply({'message':'JSON invalide'},400)
  if path=='/__recette/bilan' and self.command=='GET':return self.reply({'unknown':UNKNOWN,'errors':ERRORS,'calls':CALLS,'users':list(USERS),'parcours':PARCOURS})
  if path=='/__recette/erreur' and self.command=='POST':ERRORS.append(body);log({'error':body});return self.reply({})
  if path.startswith('/mobile-updates/') and self.command=='GET':log({'method':'GET','path':path,'ota':'disabled-local-fixture'});return self.reply({'message':'Aucune mise à jour de recette'},404)
  if path=='/realtime/v1/websocket' and self.command=='GET':
   key=self.headers.get('Sec-WebSocket-Key')
   if not key:return self.reply({'message':'WebSocket recette fermé'},400)
   self.send_response(101);self.send_header('Upgrade','websocket');self.send_header('Connection','Upgrade');self.send_header('Sec-WebSocket-Accept',base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode());self.end_headers();self.wfile.write(b'\x88\x02\x03\xe8');self.close_connection=True;return
  uid=self.headers.get('Authorization','').removeprefix('Bearer fixture-')
  log({'method':self.command,'path':path,'query':urlparse(self.path).query,'user':uid if uid in USERS else None})
  if path=='/auth/v1/signup' and self.command=='POST':
   email=body.get('email','')
   if not email.endswith('@example.invalid') or body.get('password')!='Recette-Native!2026':return self.reply({'message':'Compte hors recette'},400)
   return self.reply(session(user_for(email)))
  if path=='/auth/v1/token' and self.command=='POST':
   user=USERS.get(body.get('refresh_token','').removeprefix('fixture-')) if body.get('refresh_token') else next((u for u in USERS.values() if u['email']==body.get('email') and body.get('password')=='Recette-Native!2026'),None)
   return self.reply(session(user)) if user else self.reply({'message':'Invalid login credentials','code':'invalid_credentials'},400)
  if path=='/auth/v1/user' and self.command=='GET':return self.reply(USERS[uid]) if uid in USERS else self.reply({'message':'Session expirée','code':'bad_jwt'},401)
  if path=='/auth/v1/logout' and self.command=='POST':return self.reply({})
  if not path.startswith('/rest/v1/'):return self.unknown(path)
  if uid not in USERS:return self.reply({'message':'Session expirée','code':'PGRST301'},401)
  p=PARCOURS.get(uid)
  if path.startswith('/rest/v1/rpc/') and self.command=='POST':
   if name=='fn_get_my_role':data={'role':'INCONNU','etablissement_id':None}
   elif name=='fn_demarrer_inscription':
    typ=body.get('p_type_compte')
    if typ not in ('SOIGNANT','ETABLISSEMENT'):return self.reply({'message':'Type invalide'},400)
    p={'user_id':uid,'type_compte':typ,'donnees':{'profession':body.get('p_profession')} if typ=='SOIGNANT' else {'nom':body.get('p_nom')},'modifie_le':now()};PARCOURS[uid]=p;data=p
   elif name=='fn_enregistrer_parcours_inscription':
    if not p:return self.reply({'message':'Aucun brouillon'},400)
    p['donnees'].update(body.get('p_donnees',{}));data=p
   elif name=='fn_compte_auth_actif':data=True
   elif name in ('fn_mon_profil_soignant_complet','fn_mon_etablissement_complet'):data={'error':'Profil introuvable'}
   elif name=='fn_explorer_missions_inscription':data=[mission()] if p and p['type_compte']=='SOIGNANT' else []
   elif name=='fn_obtenir_missions_swipe':data={'missions':[]}
   elif name=='fn_dashboard_soignant_complet':data=None
   elif name=='fn_messages_non_lus':data=0
   elif name in ('fn_param_bool','fn_est_bloque','fn_capacite_alertes_recherches'):data=False
   elif name=='fn_obtenir_mes_parrainages':data={'filleuls':[]}
   elif name=='fn_note_moyenne':data={'moyenne':None,'total':0}
   elif name=='fn_types_exercice_autorises':data=['SALARIE','LIBERAL','MIXTE']
   elif name=='fn_verifier_coherence_documents':data={'coherent':True}
   elif name=='fn_obtenir_mes_preferences_notifications':data={'global':{'canal_email':True,'canal_push':True,'canal_sms':False,'canal_in_app':True},'par_evenement':[]}
   elif name=='fn_mes_permissions_etab':data={'success':False,'role':None,'permissions':{}}
   elif name=='fn_apercu_marche_profession':data={'nb_missions':1,'taux_max':30,'zone':'France'}
   elif name=='fn_stats_dashboard_etablissement':data={**dict.fromkeys('missions_ouvertes missions_assignees missions_en_cours missions_terminees candidatures_en_attente pool_urgence_count messages_non_lus missions_a_payer missions_terminees_ce_mois soignants_ce_mois commissions_impayees nb_factures_impayees litiges_ouverts'.split(),0),'candidatures_recentes':[],'missions_assignees_detail':[]}
   elif name in NULL_RPCS:data=None
   elif name in EMPTY_RPCS:data=[]
   else:return self.unknown(path)
   return self.reply(data)
  if self.command not in ('GET','HEAD'):return self.unknown(path)
  if name=='parcours_inscription':rows=[p] if p else []
  elif name in ('soignants','etablissements'):rows=[]
  elif name=='missions':rows=[mission()] if p and p['type_compte']=='SOIGNANT' else []
  elif name=='mission_creneaux':rows=mission()['creneaux']
  elif name in EMPTY_TABLES:rows=[]
  else:return self.unknown(path)
  for key,values in parse_qs(urlparse(self.path).query).items():
   if key in ('select','order','limit','offset','or','and') or '.' in key:continue
   value=values[0]
   if value.startswith('eq.'):rows=[r for r in rows if str(r.get(key))==value[3:]]
   elif value.startswith('is.null'):rows=[r for r in rows if r.get(key) is None]
  return self.reply((rows[0] if rows else None) if 'object' in self.headers.get('Accept','') else rows,extra={'Content-Range':f'0-{len(rows)-1}/{len(rows)}' if rows else '*/0'})
 def do_GET(self):self.run_api()
 def do_HEAD(self):self.run_api()
 def do_POST(self):self.run_api()
 def do_PATCH(self):self.run_api()
 def do_DELETE(self):self.run_api()
 def do_PUT(self):self.run_api()
 def do_OPTIONS(self):self.reply(None,204)
if __name__ == '__main__':
 ThreadingHTTPServer(('127.0.0.1',8904),Mock).serve_forever()
