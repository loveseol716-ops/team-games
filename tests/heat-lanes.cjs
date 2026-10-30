const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {parseHTML}=require('linkedom');
const html=fs.readFileSync('admin.html','utf8');
const {document,window}=parseHTML(html);
// linkedom lacks the browser's writable HTMLSelectElement.value.
Object.defineProperty(window.HTMLSelectElement.prototype,'value',{configurable:true,get(){return this.querySelector('option[selected]')?.value??this.querySelector('option')?.value??'';},set(value){for(const o of this.querySelectorAll('option'))o.toggleAttribute('selected',o.value===String(value));}});
const team=(id,heat,lane,extra={})=>({id,event_id:'event',team_name:'Team '+id,player_1:'Captain '+id,player_2:'Partner '+id,status:'confirmed',division:'OPEN',category:'WW',heat_no:heat,station_no:lane,...extra});
const fixture=[team('ten-b',10,2),team('one-b',1,2),team('two-b',2,2),team('one-a',1,1,{team_name:'Team <A>'}),team('ten-a',10,1),team('two-a',2,1),team('pending',null,null),team('cancelled',1,1,{status:'cancelled'}),team('other-event',1,1,{event_id:'other'})];
const saved=[];
const ctx={document,console,allAdminTeams:fixture,currentEvent:{id:'event',event_date:'2026-10-31T10:00:00+09:00'},$:id=>document.getElementById(id),esc:x=>String(x??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;'),divisionLabel:x=>x,adminError:e=>e.message,
 db:{from:()=>({select:()=>({eq:async()=>({data:[{team_id:'one-a',workout_a_reps:168,workout_a_seconds:432,workout_b_meters:1800}],error:null})})}),rpc:async(name,args)=>{saved.push({name,args});return {data:{},error:null};}}};
ctx.window=ctx;vm.createContext(ctx);
for(const file of ['heat-utils.js','score-utils.js'])vm.runInContext(fs.readFileSync(file,'utf8'),ctx);
vm.runInContext(html.slice(html.indexOf('async function loadResults(){'),html.indexOf('window.resetResults=')),ctx);
const visible=()=>[...document.querySelectorAll('.result-heat-group')].filter(g=>!g.hidden).flatMap(g=>[...g.querySelectorAll('.result-card')].filter(c=>!c.hidden).map(c=>c.dataset.teamId));
const $=ctx.$;
(async()=>{
 assert.equal(ctx.ArcHeat.laneLabel('1'),'A · 왼쪽');assert.equal(ctx.ArcHeat.laneLabel(2),'B · 오른쪽');assert.equal(ctx.ArcHeat.lane(null).code,'—');
 assert.equal(ctx.ArcHeat.timeRange(ctx.currentEvent.event_date,12),'12:23–12:31');
 assert.equal(ctx.ArcHeat.timeRange('bad',1),'');
 const before=fixture.map(t=>t.id).join();await ctx.loadResults();assert.equal(fixture.map(t=>t.id).join(),before);
 assert.deepEqual(visible(),['one-a','one-b','two-a','two-b','ten-a','ten-b','pending']);
 assert.equal(document.querySelector('[data-team-id="one-a"] h4').textContent,'Team <A>');
 assert.equal(document.querySelector('[data-team-id="one-a"] .result-lane-badge').textContent,'레인 A · 왼쪽');
 assert.equal($('b-meters-one-a').value,'1800');
 $('b-meters-one-b').value='1999';$('a-time-one-a').value='7:12';
 $('resultHeatFilter').value='1';ctx.filterResultCards();assert.deepEqual(visible(),['one-a','one-b']);assert($('resultPrevHeat').disabled);
 ctx.stepResultHeat(1);assert.equal($('resultHeatFilter').value,'2');assert.deepEqual(visible(),['two-a','two-b']);
 ctx.stepResultHeat(-1);assert.equal($('b-meters-one-b').value,'1999');
 $('resultSearch').value='partner one-b';ctx.filterResultCards();assert.deepEqual(visible(),['one-b']);
 $('resultSearch').value='does not exist';ctx.filterResultCards();assert.equal(visible().length,0);assert.match($('resultFilterStatus').textContent,/없습니다/);
 $('resultSearch').value='';$('resultHeatFilter').value='all';ctx.filterResultCards();
 const button=document.querySelector('[data-team-id="one-b"] button[onclick*="saveWorkout"][onclick*="\'b\'"]');
 await ctx.saveWorkout('one-b','b',button);assert.equal(saved.length,1);assert.equal(saved[0].name,'arc_save_workout');assert.equal(saved[0].args.p_team,'one-b');assert.equal(saved[0].args.p_meters,1999);assert.equal($('a-time-one-a').value,'7:12');
 $('resultHeatFilter').value='10';await ctx.loadResults();assert.equal($('resultHeatFilter').value,'10');assert.deepEqual(visible(),['ten-a','ten-b']);
 // Athlete lane uses the exact same mapping, without disclosing other teams.
 for(const lane of [1,2]){
  const d=parseHTML('<div id="arcMyHeat"></div>').document;
  const athlete={document:d,console,esc:ctx.esc,ArcHeat:ctx.ArcHeat,C:{eventSlug:'fixture'},currentUser:async()=>({id:'fixture'}),setTimeout,location:{replace:()=>{throw Error('Unexpected redirect');}},db:{rpc:async()=>({data:{status:'ready',team_name:'My <team>',heat:2,lane,starts_at:'2026-10-31T10:13:00+09:00',ends_at:'2026-10-31T10:21:00+09:00'}}),auth:{onAuthStateChange:()=>{}}}};
  vm.createContext(athlete);vm.runInContext(fs.readFileSync('my-heat.js','utf8'),athlete);await new Promise(resolve=>setImmediate(resolve));
  assert.equal(d.querySelectorAll('.is-yours').length,1);assert.equal(d.querySelector('.is-yours b').textContent,ctx.ArcHeat.laneLabel(lane));assert.equal(d.querySelector('h2').textContent,'My <team>');
 }
 for(const file of ['admin.html','admin-heats.html','my-heat.html'])for(const match of fs.readFileSync(file,'utf8').matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g))if(match[1].trim())new vm.Script(match[1]);
 console.log('PASS: numeric heat order, A/B order, unassigned teams, event/status isolation, exact heat and player filters, navigation, unsaved input retention, correct-team save, selected heat after reload, both athlete lane diagrams, and script syntax.');
})().catch(e=>{console.error(e);process.exitCode=1;});
