"""Loopback diagnostics only; never forwards an API or holds credentials."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json,os,re
from pathlib import Path
calls=[];errors=[]
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_OPTIONS(self): self.reply({})
 def reply(self,value,status=200):
  payload=json.dumps(value).encode();self.send_response(status)
  for k,v in {'Content-Type':'application/json','Content-Length':str(len(payload)),'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type','Access-Control-Allow-Methods':'GET,POST,OPTIONS'}.items():self.send_header(k,v)
  self.end_headers();self.wfile.write(payload)
 def do_GET(self):
  if self.path=='/__recette/bilan':self.reply({'calls':calls,'errors':errors})
  else:self.reply({},404)
 def do_POST(self):
  if self.path!='/__recette/erreur':return self.reply({},404)
  size=int(self.headers.get('Content-Length','0'))
  if size>4096:return self.reply({},413)
  value=json.loads(self.rfile.read(size));safe={}
  for k in ['type','message','path','status','duration','directive']:
   if k in value:
    safe[k]=re.sub(r'eyJ[A-Za-z0-9_\-.]+','[REDACTED]',str(value[k]))[:500]
  (calls if safe.get('type')=='request' else errors).append(safe)
  self.reply({})
ThreadingHTTPServer(('127.0.0.1',8904),Handler).serve_forever()
