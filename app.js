const C=window.TG_CONFIG;
const db=window.supabase.createClient(C.supabaseUrl,C.supabaseAnonKey);

function divisionLabel(v){return v==='OPEN'?'BEGINNER':v==='PRO'?'ATHLETE':v||'—'}

function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}

function nav(active){
  const p=[
    ['HOME','index.html'],['GAME','event.html'],['TEAMS','teams.html'],
    ['FAN PICK','fanpick.html'],['LIVE','live.html'],['PLAYER','athlete.html']
  ];
  return `<header class="nav"><div class="container navin"><a class="brand" href="index.html">ARC GAMES</a><nav class="links">${p.map(([n,h])=>`<a class="${active===n?'active':''}" href="${h}">${n}</a>`).join('')}</nav><a class="cta arcade-cta" href="athlete.html?join=1">ENTER GAME #01</a></div></header>`;
}

function adminNav(){
  return `<header class="nav admin-only-nav"><div class="container navin admin-only-navin"><div class="brand admin-only-brand">GAME MASTER</div><div class="admin-only-badge">PRIVATE CONTROL ROOM</div></div></header>`;
}

function shell(active){
  if(active==='ADMIN'){
    document.querySelector('#nav').innerHTML=adminNav();
    document.querySelector('#footer').innerHTML=`<footer class="footer admin-only-footer"><div class="container arcade-footer"><span>ARC GAMES // GAME MASTER</span><span>PRIVATE CONTROL ROOM</span></div></footer>`;
    return;
  }
  document.querySelector('#nav').innerHTML=nav(active);
  document.querySelector('#footer').innerHTML=`<footer class="footer"><div class="container arcade-footer"><span>ARC GAMES // STAGE 01</span><span>OCT 31, 2026 · NOLTO GYM</span><span>PLAY · PICK · WATCH</span></div></footer>`;
}

function revealGameMaster(){/* admin is intentionally isolated from participant navigation */}

function notice(id,msg,err=false){const e=document.getElementById(id);if(!e)return;e.textContent=msg;e.style.display='block';e.classList.toggle('err',err)}
function token(){let t=localStorage.getItem('tg_device_token');if(!t){t=crypto.randomUUID();localStorage.setItem('tg_device_token',t)}return t}

async function event(){const {data,error}=await db.from('tg_events').select('*').eq('slug',C.eventSlug).single();if(error)throw error;return data}
async function teams(){const e=await event();const {data,error}=await db.from('tg_teams').select('id,event_id,team_name,player_1,player_2,photo_url,heat_no,station_no,status,division,category,pricing_tier,amount_due,created_at').eq('event_id',e.id).eq('status','confirmed').order('created_at');if(error)throw error;return data||[]}

async function rosterMap(teamIds){
  const out={};
  if(!teamIds?.length)return out;
  const {data:members,error}=await db.from('tg_team_members').select('team_id,athlete_id,member_role').in('team_id',teamIds);
  if(error)throw error;
  const ids=[...new Set((members||[]).map(x=>x.athlete_id))];
  if(!ids.length)return out;
  const {data:athletes,error:aerr}=await db.from('tg_athletes').select('id,display_name,handle,photo_url,gym,instagram,gender,division').in('id',ids);
  if(aerr)throw aerr;
  const am=Object.fromEntries((athletes||[]).map(a=>[a.id,a]));
  (members||[]).forEach(m=>{(out[m.team_id]??=[]).push({...am[m.athlete_id],member_role:m.member_role})});
  Object.values(out).forEach(arr=>arr.sort((a,b)=>a.member_role==='captain'?-1:b.member_role==='captain'?1:0));
  return out;
}

async function currentUser(){const {data:{user}}=await db.auth.getUser();return user||null}

function countdown(){
  const el=document.getElementById('countdown');if(!el)return;
  const target=new Date(C.eventDateISO);
  const tick=()=>{let d=Math.max(0,target-new Date()),days=Math.floor(d/864e5);d%=864e5;let h=Math.floor(d/36e5);d%=36e5;let m=Math.floor(d/6e4),s=Math.floor((d%6e4)/1e3);el.innerHTML=[['DAYS',days],['HOURS',h],['MIN',m],['SEC',s]].map(([l,v])=>`<div class="card"><b>${String(v).padStart(2,'0')}</b><span>${l}</span></div>`).join('')};tick();setInterval(tick,1000);
}
