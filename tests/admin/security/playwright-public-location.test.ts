// @vitest-environment node
import { describe, it } from 'vitest';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtemp, mkdir, writeFile, realpath, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { projectReport, runPublicPlaywright } from '../../../scripts/ci/run-playwright-public.mjs';

async function fixture(run: (f: any) => Promise<void>) {
 const directory=await realpath(await mkdtemp(path.join(tmpdir(),'jolene-location-unit-')));
 const cwd=path.join(directory,'repo');
 await mkdir(path.join(cwd,'e2e','flows'),{recursive:true});
 const file=path.join(cwd,'e2e','flows','known.spec.ts');
 await writeFile(file,'// declaration\n// context\n  assertSomething();\n');
 const canary=`canary-${randomBytes(24).toString('hex')}`;
 const result: any={status:'failed',duration:10,retry:0,errors:[]};
 const test: any={projectName:'chromium',expectedStatus:'passed',status:'unexpected',results:[result]};
 const report={config:{rootDir:path.join(cwd,'e2e')},suites:[{specs:[{file:'flows/known.spec.ts',line:1,column:1,tests:[test]}]}],errors:[],stats:{duration:10,expected:0,unexpected:1,flaky:0,skipped:0}};
 try {await run({directory,cwd,file,canary,result,test,report});}
 finally{await rm(directory,{recursive:true,force:true});}
}

async function project(f: any) {
 const receipt=await projectReport(f.report,{phase:'chromium',cwd:f.cwd});
 assert.equal(JSON.stringify(receipt).includes(f.canary),false);
 assert.equal(receipt.tests[0].line,1);
 assert.equal(receipt.tests[0].attempts[0].code,'TEST_FAILED');
 return receipt.tests[0].attempts[0];
}

describe('coordonnée publique fermée de l’assertion',()=>{
 it('publie seulement la coordonnée structurée de la spec connue',async()=>fixture(async f=>{
  f.result.errors=[{message:f.canary,snippet:f.canary,location:{file:f.file,line:3,column:3},stack:f.canary}];
  const attempt=await project(f);
  assert.deepEqual(attempt.failureLocation,{file:'e2e/flows/known.spec.ts',line:3,column:3});
  assert.deepEqual(Object.keys(attempt).sort(),['code','durationMs','failureLocation','retry','status']);
 }));
 it('extrait une frame exacte sans jamais publier le message ou le nom de fonction',async()=>fixture(async f=>{
  for(const frame of [`    at ${f.canary} (${f.file}:3:3)`,`    at ${f.file}:3:3`,`    at e2e/flows/known.spec.ts:3:3`]){
   f.result.errors=[{message:f.canary,stack:`Error: ${f.canary}\n${frame}\n    at other (${f.canary}:1:1)`}];
   assert.deepEqual((await project(f)).failureLocation,{file:'e2e/flows/known.spec.ts',line:3,column:3});
  }
 }));
 it('refuse les chemins étrangers et coordonnées hors bornes sans effacer l’échec',async()=>fixture(async f=>{
  await writeFile(path.join(f.cwd,'e2e','flows','other.spec.ts'),'// other\n');
  await symlink(f.file,path.join(f.cwd,'e2e','flows','linked.spec.ts'));
  const invalid=[
   {file:f.file,line:0,column:1},{file:f.file,line:99,column:1},{file:f.file,line:3,column:999},
   {file:f.file,line:3,column:0},{file:f.file,line:1.5,column:1},{file:f.file,line:3,column:1.5},
   {file:f.file,line:'3',column:1},{file:f.file,line:3,column:Number.MAX_SAFE_INTEGER},
   {file:path.join(f.cwd,'e2e','flows','other.spec.ts'),line:1,column:1},
   {file:path.join(f.cwd,'e2e','flows','linked.spec.ts'),line:1,column:1},
   {file:`file://${f.file}`,line:3,column:3},{file:`https://example.invalid/${f.canary}`,line:1,column:1},
   {file:'../e2e/flows/known.spec.ts',line:3,column:3},
  ];
  for(const location of invalid){
   f.result.errors=[{message:f.canary,location,stack:`Error: ${f.canary}`}];
   assert.equal(Object.hasOwn(await project(f),'failureLocation'),false);
  }
  for(const stack of [`${f.file}:3:3`, `Error: ${f.canary} ${f.file}:3:3`, `    at ${f.file}:3:3?${f.canary}`,`    at ${f.file}:3:3\n${'x'.repeat(65536)}`]){
   f.result.errors=[{message:f.canary,stack}];
   assert.equal(Object.hasOwn(await project(f),'failureLocation'),false);
  }
 }));
 it('le retry réussi reste rouge avec les seuls octets fermés publiés',async()=>fixture(async f=>{
  f.result.errors=[{message:f.canary,stack:`Error: ${f.canary}\n    at privateName (${f.file}:3:3)`}];
  f.test.results.push({status:'passed',duration:8,retry:1,errors:[]});
  f.test.status='flaky';f.report.stats.unexpected=0;f.report.stats.flaky=1;
  let output='';
  const exit=await runPublicPlaywright(['--phase','chromium','--','test'],{
   cwd:f.cwd,env:{RUNNER_TEMP:f.directory},getSourceSha:()=> 'a'.repeat(40),emit:(text: string)=>{output+=text;},
   launch:async (context: any)=>{assert.ok(context.args.includes('--fail-on-flaky-tests'));await writeFile(context.env.PLAYWRIGHT_JSON_OUTPUT_FILE,JSON.stringify(f.report));return 1;},
  });
  assert.equal(exit,1);assert.equal(output.includes(f.canary),false);assert.equal(output.includes('privateName'),false);
  const receipt=JSON.parse(output);assert.ok(receipt.codes.includes('FLAKY_TESTS'));assert.equal(receipt.counts.flaky,1);
  assert.deepEqual(receipt.tests[0].attempts[0].failureLocation,{file:'e2e/flows/known.spec.ts',line:3,column:3});
  assert.equal(Object.hasOwn(receipt.tests[0].attempts[1],'failureLocation'),false);
 }));
});
