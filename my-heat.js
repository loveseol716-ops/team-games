(()=>{
const root=document.getElementById('arcHomeHeat')||document.getElementById('arcMyHeat');if(!root)return;
const home=root.id==='arcHomeHeat';let version=0;
const time=v=>new Date(v).toLocaleTimeString('en-GB',{timeZone:'Asia/Seoul',hour:'2-digit',minute:'2-digit',hour12:false});
const date=v=>new Date(v).toLocaleDateString('en-GB',{timeZone:'Asia/Seoul',day:'2-digit',month:'short',year:'numeric'}).toUpperCase();
function card(h){
 let body='';
 if(h.status==='ready')body='<div class="arc-heat-kicker">YOUR RACE · '+date(h.starts_at)+' · KST</div><h2>'+esc(h.team_name)+'</h2><div class="arc-heat-stats"><div><span>HEAT</span><strong>'+esc(String(h.heat).padStart(2,'0'))+'</strong></div><div><span>LANE</span><strong>'+esc(h.lane)+'</strong></div><div><span>START TIME</span><strong>'+time(h.starts_at)+'</strong></div></div><p>FINISH '+time(h.ends_at)+' · 8 MIN RACE · NOLTO GYM</p>';
 else if(h.status==='partner_needed')body='<div class="arc-heat-kicker">YOUR HEAT IS LOCKED</div><h2>COMPLETE YOUR TEAM.</h2><p>Add your partner to unlock your heat, lane and start time. Your partner needs an ARC account. No separate acceptance is required.</p><div class="arc-heat-actions"><a href="athlete.html">ADD PARTNER →</a></div>';
 else if(h.status==='unassigned')body='<div class="arc-heat-kicker">TEAM COMPLETE</div><h2>HEAT COMING SOON.</h2><p>Your team is ready. Your assignment will appear here once it is set.</p>';
 else if(h.status==='no_team')body='<h2>NO CONFIRMED TEAM YET.</h2><p>Check your team entry or ask your captain to add your ARC account.</p><div class="arc-heat-actions"><a href="athlete.html">MY TEAM →</a></div>';
 else body='<h2>COULD NOT LOAD YOUR HEAT.</h2><p>Please refresh to try again.</p>';
 return '<article class="arc-heat-card">'+body+'<div class="arc-heat-actions">'+(home?'<a href="my-heat.html">MY HEAT ↗</a>':'<a href="athlete.html">MANAGE TEAM →</a>')+'<button type="button" data-refresh-heat>REFRESH ↻</button></div></article>';
}
async function refresh(){const v=++version;root.hidden=home;root.innerHTML=home?'':'<p role="status">Loading your heat…</p>';
 try{const user=await currentUser();if(v!==version)return;if(!user){if(!home)location.replace('account.html?mode=login&next=my-heat.html');return}
 const r=await db.rpc('arc_my_heat',{p_event_slug:C.eventSlug});if(v!==version)return;if(r.error)throw r.error;
 if(home&&r.data?.status==='no_team'){root.hidden=true;root.innerHTML='';return}
 root.innerHTML=card(r.data||{status:'error'});root.hidden=false;
 }catch(e){if(v!==version)return;root.innerHTML=card({status:'error'});root.hidden=false;}}
root.addEventListener('click',e=>{if(e.target.closest('[data-refresh-heat]'))refresh()});
db.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){++version;root.innerHTML='';root.hidden=home;if(!home)location.replace('account.html?mode=login&next=my-heat.html')}else if(event==='SIGNED_IN')setTimeout(refresh,0)});
refresh();
})();