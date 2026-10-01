import { createServer } from 'node:http';
import { once } from 'node:events';
import { readFile, readdir, lstat, mkdir, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { resolve, relative, join } from 'node:path';
import { createRequire } from 'node:module';
import { refuse, sha256, requireReady } from './f1-cloud-core.mjs';
import { createAdapterF1 } from './f1-cloud-adapter.mjs';
import { createPdfAnalyzerF1 } from './f1-cloud-documents.mjs';
import { installNetworkF1, UI_ORIGIN } from './f1-cloud-network.mjs';
import { uiMatrixF1, openDocumentScreenF1, captureDocumentPortionsF1 } from './f1-cloud-ui.mjs';
const require = createRequire(import.meta.url);
// Same isolated HTML policy as the reviewed E10 preview, no product source edit.
export function preparerHtmlPreview(html) {
  return html.replace(/<link\b[^>]*>/gi,tag=>{
    const attribute=name=>{const value=tag.match(new RegExp(`\\b${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`,'i'));return value?.[1]??value?.[2]??value?.[3]??'';};
    const relations=attribute('rel').toLowerCase().split(/\s+/);
    if(relations.some(x=>['preconnect','dns-prefetch'].includes(x)))return '';
    if(relations.includes('stylesheet')&&new URL(attribute('href'),UI_ORIGIN).origin==='https://fonts.googleapis.com')return '';
    return tag;
  });
}
const SOURCE_PATHS = ['src/pages/DetailMission.tsx','src/pages/DetailMissionSoignant.tsx','src/pages/FacturationEtablissement.tsx',
  'src/components/FactureHonorairesCard.tsx','supabase/functions/generate-invoice/index.ts'];

/** Avoid a circular commit hash in a committed JSON file: reviewed blob hashes
 * pin the product inputs, then the dispatch's approved main SHA binds the run. */
export async function loadContractF1(ctx, cwd = process.cwd()) {
  const contract = JSON.parse(await readFile(new URL('./f1-cloud-readiness.json', import.meta.url)));
  if (contract.ready !== true) refuse('F1_CONTRACT_PENDING');
  const git = args => execFileSync('git',args,{cwd,encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();
  if (git(['rev-parse','HEAD']) !== ctx.sha || git(['status','--porcelain','--untracked-files=all']) !== '') refuse('F1_LOCAL_SHA');
  if (!contract.sourceFiles || !SOURCE_PATHS.every(path=>/^[a-f0-9]{64}$/.test(contract.sourceFiles[path]??''))) refuse('F1_SOURCE_CONTRACT');
  for (const path of SOURCE_PATHS) if (sha256(await readFile(join(cwd,path))) !== contract.sourceFiles[path]) refuse('F1_SOURCE_DRIFT');
  const bound = {...contract,sourceSha:ctx.sha}; requireReady(bound,ctx); return bound;
}

/** Serve only built static files; browser processes never inherit credentials.
 * The isolated HTML uses the already reviewed E10 system-font fallback. */
export async function previewF1(cwd = process.cwd()) {
  const root=resolve(cwd,'dist'),files=new Map();
  async function visit(directory) {
    for(const entry of await readdir(directory,{withFileTypes:true})) {
      const path=join(directory,entry.name);if((await lstat(path)).isSymbolicLink())refuse('F1_PREVIEW_SYMLINK');
      if(entry.isDirectory())await visit(path);else if(entry.isFile())files.set('/'+relative(root,path).replaceAll('\\','/'),path);
      if(files.size>2000)refuse('F1_PREVIEW_SIZE');
    }
  }
  await visit(root);if(!files.has('/index.html'))refuse('F1_PREVIEW_BUILD');
  const html=preparerHtmlPreview(await readFile(files.get('/index.html'),'utf8'));
  const scripts=[...html.matchAll(/<script\b[^>]*\bsrc="([^"]+)"[^>]*>/g)].map(m=>m[1]);
  if(scripts.length!==1||!files.has(scripts[0]))refuse('F1_PREVIEW_ENTRY');
  const entry=await readFile(files.get(scripts[0]),'utf8');
  if(!entry.includes('https://mejpriaetwgtcstbgfid.supabase.co')||/https:\/\/(?:flripxtsyegjshnhzjkz|wnepopwygokbhlqghydb)\.supabase\.co/.test(entry))refuse('F1_PREVIEW_DESTINATION');
  const mime={js:'text/javascript',css:'text/css',svg:'image/svg+xml',png:'image/png',woff2:'font/woff2',ico:'image/x-icon',webp:'image/webp',json:'application/json'};
  const server=createServer(async(req,res)=>{
    try {
      const u=new URL(req.url,UI_ORIGIN);
      if(req.method!=='GET'||u.search||u.hash||u.origin!==UI_ORIGIN){res.writeHead(404).end();return;}
      const path=files.get(u.pathname),spa=/^\/(?:connexion|(?:soignant|etablissement)\/(?:tableau-de-bord|missions\/[a-f0-9-]{36}))$/.test(u.pathname);
      if(path&&u.pathname!=='/index.html'){res.writeHead(200,{'Content-Type':mime[path.split('.').pop()]??'application/octet-stream','Cache-Control':'no-store'}).end(await readFile(path));}
      else if(spa||u.pathname==='/index.html'){res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-store'}).end(html);}
      else res.writeHead(404).end();
    }catch{res.writeHead(500).end();}
  });
  server.listen(8904,'127.0.0.1');await once(server,'listening');
  return {assetPaths:new Set(files.keys()),entry_sha256:sha256(Buffer.from(entry)),async close(){server.closeAllConnections();await new Promise((r,j)=>server.close(e=>e?j(e):r()));}};
}

export async function connectedDependenciesF1({ctx,env,contract,cwd=process.cwd()}) {
  requireReady(contract,ctx);
  const preview=await previewF1(cwd),proof=join(ctx.privateRoot,'f1-cloud-proof');await mkdir(proof,{recursive:true,mode:0o700});
  let analysisBrowser,analyzer;const networkDiagnostics=[],uiDiagnostics=[];let contextIndex=0;
  const closePdf=async()=>{try{if(analyzer)await analyzer.close();}finally{analyzer=null;if(analysisBrowser)await analysisBrowser.close();analysisBrowser=null;}};
  const analyzePdf=async(bytes,document,parties)=>{
    if(!analyzer){const {chromium}=require('@playwright/test');analysisBrowser=await chromium.launch({env:Object.fromEntries(['PATH','HOME','TMPDIR'].filter(k=>env[k]).map(k=>[k,env[k]]))});analyzer=await createPdfAnalyzerF1(analysisBrowser);}
    return analyzer.analyze(bytes,document,parties);
  };
  const adapter=createAdapterF1({env,contract,analyzePdf});
  const verifyDownloads=adapter.verifyDownloads;
  adapter.verifyDownloads=async(...args)=>{try{return await verifyDownloads(...args);}finally{await closePdf();}};
  const ui=async({manifest,documents})=>uiMatrixF1({ctx,preflight:contract,manifest,documents,env,
    observe:async value=>{if(uiDiagnostics.length<128)uiDiagnostics.push(value);await writeFile(join(ctx.privateRoot,ctx.run,'ui.private.json'),JSON.stringify(uiDiagnostics),{mode:0o600});},
    installNetwork:(context,actor,m,docs,location)=>{const index=contextIndex++;return installNetworkF1(context,actor,m,docs,{recordAuth:(a,r)=>adapter.recordUiAuth(a,r),assetPaths:preview.assetPaths,diagnostic:async value=>{networkDiagnostics[index]={context:index,format:location.format,...value};await writeFile(join(ctx.privateRoot,ctx.run,'network.private.json'),JSON.stringify(networkDiagnostics),{mode:0o600});}});},
    openScreen:openDocumentScreenF1,
    capture:async(page,{format,role,phase})=>{
      if(!['iphone','android','ipad-portrait','ipad-paysage','ordinateur'].includes(format)||!['SOIGNANT','ETABLISSEMENT'].includes(role)||!['documents','reload'].includes(phase))refuse('F1_CAPTURE_SHAPE');
      const {expect}=require('@playwright/test');
      await captureDocumentPortionsF1(page,role,expect,(locator,part)=>locator.screenshot({path:join(proof,`${format}-${role.toLowerCase()}-${phase}-${part}.png`),scale:'css',animations:'disabled'}));
    },
  });
  return {adapter,ui,proof,async close(){try{await closePdf();}finally{await preview.close();}},
    async report(value){await writeFile(join(proof,'result.json'),JSON.stringify({...value,network:networkDiagnostics,uiDiagnostic:uiDiagnostics},null,2)+'\n',{mode:0o600});}};
}
