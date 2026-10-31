const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {parseHTML}=require('linkedom');
const initial={server_time:new Date().toISOString(),closes_at:'2099-01-01T00:00:00Z',is_open:false,total:2,mine:null,teams:[],entries:[{ticket:1,name:'One',team:'First'},{ticket:2,name:'Two',team:'Second'}],draws:[{id:'b',ticket:2,status:'pending',created_at:new Date().toISOString()},{id:'a',ticket:1,status:'claimed',created_at:new Date().toISOString()}]};
const clone=x=>JSON.parse(JSON.stringify(x)),flush=()=>new Promise(resolve=>setImmediate(resolve));
function setup(file){
 const {document,window}=parseHTML(fs.readFileSync(file,'utf8')),calls=[],timers=[],storage=new Map([['arc-raffle-request','old-key']]);
 let server=clone(initial),allow=false,fail=null,deferred=null;
 const ctx={document,console,Date,Number,Math,JSON,C:{eventSlug:'fixture'},esc:x=>String(x??'').replaceAll('<','&lt;'),confirm:()=>allow,crypto:{randomUUID:()=> 'new-key'},localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},setInterval:(fn,ms)=>timers.push({fn,ms}),db:{rpc:async(name,args)=>{
  const action=args.p_action;calls.push({action,payload:args.p_payload});
  if(['admin','board'].includes(action)){if(deferred){const callback=deferred;deferred=null;return await callback();}return {data:clone(server)};}
  if(fail)return {error:{message:fail}};
  if(action==='reset')server.draws=[];
  return {data:clone(server)};
 }}};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync('raffle.js','utf8'),ctx);
 return {document,calls,timers,storage,allow:()=>allow=true,fail:value=>fail=value,setServer:value=>server=clone(value),defer:fn=>deferred=fn,click:action=>document.querySelector('[data-action="'+action+'"]').dispatchEvent(new window.Event('click',{bubbles:true}))};
}
(async()=>{
 const a=setup('admin-raffle.html');await flush();
 assert(!a.document.getElementById('adminRaffle').hidden);assert(!a.document.querySelector('[data-action="reset"]').disabled);
 a.click('reset');await flush();assert.equal(a.calls.filter(x=>x.action==='reset').length,0);
 // A pre-reset polling response must not restore old winners after reset.
 let resolveOld;a.defer(()=>new Promise(resolve=>resolveOld=resolve));a.timers.find(x=>x.ms===5000).fn();
 a.allow();a.click('reset');await flush();await flush();
 const reset=a.calls.find(x=>x.action==='reset');assert(reset.payload.confirm_reset);assert.deepEqual(JSON.parse(JSON.stringify(reset.payload.expected_draws)),[{id:'a',status:'claimed'},{id:'b',status:'pending'}]);
 resolveOld({data:clone(initial)});await flush();
 assert.match(a.document.getElementById('drawHistory').textContent,/아직 추첨하지/);assert.match(a.document.getElementById('drawResult').textContent,/기다려/);assert.match(a.document.getElementById('raffleMsg').textContent,/리셋 완료/);
 assert.equal(a.document.querySelectorAll('#entryRows tr').length,2);assert(a.document.querySelector('[data-action="reset"]').disabled);assert(!a.document.querySelector('[data-action="draw"]').disabled);assert(!a.storage.has('arc-raffle-request'));
 a.click('reset');await flush();assert.equal(a.calls.filter(x=>x.action==='reset').length,1);
 // A reset by another operator invalidates the cached draw request.
 a.storage.set('arc-raffle-request','old-key');a.fail('DRAW_RESET');a.click('draw');await flush();await flush();assert(!a.storage.has('arc-raffle-request'));assert.match(a.document.getElementById('raffleMsg').textContent,/다시 추첨/);
 const b=setup('admin-raffle.html');await flush();b.allow();b.fail('RAFFLE_CHANGED');b.click('reset');await flush();await flush();assert.match(b.document.getElementById('raffleMsg').textContent,/다른 관리자/);assert.match(b.document.getElementById('drawResult').textContent,/#002/);assert(!b.document.querySelector('[data-action="reset"]').disabled);
 const live=setup('fanpick-live.html');await flush();assert.match(live.document.getElementById('drawResult').textContent,/#002/);live.setServer({...initial,draws:[]});live.timers.find(x=>x.ms===5000).fn();await flush();assert.match(live.document.getElementById('drawResult').textContent,/기다려/);
 console.log('PASS: confirmation cancel; reset snapshot payload; stale poll suppression; cache clearing; entry retention; disabled empty reset; error recovery; live-screen reset refresh.');
})().catch(e=>{console.error(e);process.exitCode=1;});
