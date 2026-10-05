import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const source = await readFile(new URL('./navigation.mjs', import.meta.url), 'utf8');
const start = source.indexOf('  const accessibilityStarted = performance.now();');
const end = source.indexOf("  assert.equal(await page.evaluate(() => window.Capacitor?.getPlatform())", start);
assert(start > 0 && end > start);
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
const run = new AsyncFunction('assert','device','pkg','nativeShell','originalAppPid','requireAppWindow','metric','performance','setTimeout','clearTimeout',source.slice(start,end));
function fixture({waitError,changedPid,windowError,pending=false,fireDeadline=false,late=false}={}) {
  const order=[],metrics=[],timers=[],cleared=[];
  const device={wait:async(selector,options)=>{
    order.push('wait');assert.deepEqual(selector,{pkg:'app.jolene.recette'});assert.deepEqual(options,{timeout:60000});
    if(waitError)throw waitError;if(pending)await new Promise(()=>{});
  }};
  const nativeShell=async command=>{
    order.push(command.startsWith('pidof')?'pid':'window');
    return command.startsWith('pidof')?(changedPid?'99':'42'):'SYNTHETIC_WINDOW';
  };
  const windowCheck=value=>{assert.equal(value,'SYNTHETIC_WINDOW');order.push('window-check');if(windowError)throw windowError;};
  let clock=10;
  const setTimer=(callback,ms)=>{timers.push(ms);if(fireDeadline)queueMicrotask(callback);return 'timer';};
  const clearTimer=handle=>cleared.push(handle);
  const execute=()=>run(assert,device,'app.jolene.recette',nativeShell,'42',windowCheck,(kind,data)=>metrics.push({kind,...data}),{now:()=>late && clock>10 ? 61011 : clock++},setTimer,clearTimer);
  return {execute,order,metrics,timers,cleared};
}

test('driver starts once before PID and window checks; success recorded only after both, with fixed total deadline',async()=>{
  const f=fixture();await f.execute();
  assert.deepEqual(f.order,['wait','pid','window','window-check']);assert.deepEqual(f.timers,[60000]);assert.deepEqual(f.cleared,['timer']);
  assert.deepEqual(f.metrics,[{kind:'native-accessibility-driver-ready',sameProcess:true,appWindow:true,elapsedMs:1}]);
});
test('driver rejection propagates without recording readiness or running later checks',async()=>{
  const original=new Error('SYNTHETIC_DRIVER_FAILURE'),f=fixture({waitError:original});
  await assert.rejects(f.execute(),error=>error===original);assert.deepEqual(f.order,['wait']);assert.deepEqual(f.metrics,[]);assert.deepEqual(f.cleared,['timer']);
});
test('PID change refuses readiness before window check',async()=>{
  const f=fixture({changedPid:true});await assert.rejects(f.execute(),/preserve the original app process/);
  assert.deepEqual(f.order,['wait','pid']);assert.deepEqual(f.metrics,[]);assert.deepEqual(f.cleared,['timer']);
});
test('obstructed app window refuses readiness',async()=>{
  const original=new Error('SYNTHETIC_ANR'),f=fixture({windowError:original});
  await assert.rejects(f.execute(),error=>error===original);assert.deepEqual(f.metrics,[]);assert.deepEqual(f.cleared,['timer']);
});
test('a hung driver cannot proceed past the fixed deadline and never records readiness',async()=>{
  const f=fixture({pending:true,fireDeadline:true});await assert.rejects(f.execute(),/ANDROID_ACCESSIBILITY_DRIVER_TIMEOUT/);
  assert.deepEqual(f.timers,[60000]);assert.deepEqual(f.order,['wait']);assert.deepEqual(f.metrics,[]);assert.deepEqual(f.cleared,['timer']);
});
test('setup is before authentication and exact reload predicate retains its separate ten-second budget',()=>{
  assert(start>source.indexOf('  requireAppWindow(nativeWindow);'));
  assert(end<source.indexOf("  for (const role of ['soignant', 'etab'])"));
  assert.match(source,/await device\.wait\(\{ pkg, text: role === 'etab' \? 'Préparer une mission' : \/\^\(Bonjour\|Bonsoir\), bienvenue\$\/ \}, \{ timeout: 10000 \}\);/);
});


test('a late completion cannot win a delayed timer and claim readiness',async()=>{
  const f=fixture({late:true});await assert.rejects(f.execute(),/exceeded its fixed deadline/);
  assert.deepEqual(f.metrics,[]);assert.deepEqual(f.cleared,['timer']);
});
