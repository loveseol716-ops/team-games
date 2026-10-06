
// ARC STATION favicon
(()=> {
  const icon=document.createElement('link');
  icon.rel='icon';icon.type='image/svg+xml';icon.href='station-mark.svg?v=20260922s1';
  document.head.appendChild(icon);
})();

// ARC PARTNERS STRIP
(()=>{
  const style=document.createElement('style');
  style.textContent=`
    .arc-partners-strip{
      width:100%;overflow:visible;
      border-top:1px solid rgba(255,255,255,.07);
      border-bottom:1px solid rgba(255,255,255,.07);
      background:#030405;padding:38px 0 40px
    }
    .arc-partners-inner{display:block}
    .arc-partners-label{display:grid;gap:5px}
    .arc-partners-label span{
      font-family:var(--font-display);font-size:8px;letter-spacing:.12em;color:#666d77
    }
    .arc-partners-label strong{
      font-family:var(--font-display);font-size:15px;font-weight:400;line-height:1.35;
      color:#fff;overflow-wrap:anywhere
    }
    .arc-partners-logos{width:100%;min-width:0;overflow:hidden;margin-top:18px}
    .arc-partners-track{display:flex;width:max-content;animation:arc-partners-right 48s linear infinite;will-change:transform}
    .arc-partners-group{display:flex;flex:none;align-items:center;gap:24px;padding-right:24px}
    .arc-partners-set{display:flex;flex:none;align-items:center;gap:24px}
    .arc-partners-strip .arc-partner-item{display:flex;flex:0 0 112px;width:112px;max-width:112px;min-width:0;min-height:40px;padding:4px 0;align-items:center;justify-content:center;opacity:.94}
    body.station-site .arc-partners-strip .arc-partner-item img,.arc-partners-strip .arc-partner-item img{display:block;width:100%;height:30px;max-height:30px;max-width:112px;object-fit:contain;object-position:center;aspect-ratio:auto}
    .arc-partner-item--arih img,.arc-partner-item--boho img{filter:brightness(0) invert(1)}
    .arc-partners-logos:hover .arc-partners-track,.arc-partners-logos:focus-within .arc-partners-track{animation-play-state:paused}
    .arc-partners-toggle{margin-top:10px;padding:4px 0;border:0;background:none;color:#aaa;font:10px/1.4 Arial,sans-serif;cursor:pointer}
    .arc-partners-logos.is-paused .arc-partners-track{animation-play-state:paused}
    @keyframes arc-partners-right{from{transform:translateX(-50%)}to{transform:translateX(0)}}
    @media(max-width:720px){
      .arc-partners-label strong{font-size:13px;line-height:1.25}
      .arc-partners-group{gap:18px;padding-right:18px}
      .arc-partners-set{gap:18px}
      .arc-partners-strip .arc-partner-item{flex-basis:96px;width:96px;max-width:96px}
      body.station-site .arc-partners-strip .arc-partner-item img,.arc-partners-strip .arc-partner-item img{height:26px;max-height:26px;max-width:96px}
    }
    @media(prefers-reduced-motion:reduce){
      .arc-partners-track{animation:none;transform:none;will-change:auto}
      .arc-partners-group[aria-hidden],.arc-partners-set[aria-hidden],.arc-partners-toggle{display:none}
    }
  `;
  document.head.appendChild(style);
})();

const C=window.TG_CONFIG;
const db=window.supabase.createClient(C.supabaseUrl,C.supabaseAnonKey);

function divisionLabel(v){return v==='OPEN'?'BEGINNER':v==='PRO'?'ATHLETE':v||'—'}

function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}

function nav(active){
  const page=location.pathname.split('/').pop();
  const eventPages=['event.html','athlete.html','rulebook.html','teams.html','fanpick.html','ranking.html','live.html','player.html','player-profile.html'];
  const inEvent=eventPages.includes(page);
  const links=[['GAME','event.html'],['REGISTER','athlete.html'],['RULEBOOK','rulebook.html'],['TEAMS','teams.html'],['FAN PICK','fanpick.html'],['RESULTS','ranking.html'],['LIVE','live.html']];
  const eventNav=inEvent?`<div class="station-event-nav"><div class="container station-event-nav-inner"><a class="station-event-name" href="event.html">#1 NOLTO</a><nav aria-label="#1 NOLTO navigation">${links.map(([label,href])=>`<a href="${href}"${page===href?' aria-current="page"':''}>${label}</a>`).join('')}</nav></div></div>`:'';
  return `<header class="nav station-brand-nav"><div class="container navin"><a class="brand" href="index.html">ARC STATION</a><nav class="station-brand-links" aria-label="Primary navigation"><a href="events.html"${active==='EVENTS'?' aria-current="page"':''}>EVENTS</a></nav><a id="arcAccountNav" class="cta arcade-cta ${active==='ACCOUNT'?'active':''}" href="account.html">LOG IN</a></div></header>${eventNav}`;
}

function initMobileNav(){
  const header=document.querySelector('.nav');
  const toggle=document.querySelector('.nav-toggle');
  const links=document.querySelector('.links');
  if(!header||!toggle||!links)return;
  const label=toggle.querySelector('.nav-toggle-label');
  const close=()=>{
    header.classList.remove('is-menu-open');
    toggle.setAttribute('aria-expanded','false');
    label.textContent='MENU';
  };
  toggle.addEventListener('click',()=>{
    const open=!header.classList.contains('is-menu-open');
    header.classList.toggle('is-menu-open',open);
    toggle.setAttribute('aria-expanded',String(open));
    label.textContent=open?'CLOSE':'MENU';
  });
  links.addEventListener('click',event=>{if(event.target.closest('a'))close()});
  document.addEventListener('keydown',event=>{if(event.key==='Escape')close()});
  window.matchMedia('(min-width: 901px)').addEventListener?.('change',event=>{if(event.matches)close()});
}

function adminNav(){
  return `<header class="nav admin-only-nav"><div class="container navin admin-only-navin"><div class="brand admin-only-brand">GAME MASTER</div><div class="admin-only-badge">PRIVATE CONTROL ROOM</div></div></header>`;
}

function shell(active){
  if(active==='ADMIN'){
    document.querySelector('#nav').innerHTML=adminNav();
    document.querySelector('#footer').innerHTML=`<footer class="footer admin-only-footer"><div class="container arcade-footer"><span>ARC STATION // GAME MASTER</span><span>PRIVATE CONTROL ROOM</span></div></footer>`;
    return;
  }
  document.querySelector('#nav').innerHTML=nav(active);
  initMobileNav();
  document.querySelector('#footer').innerHTML=`
    <section class="arc-partners-strip" aria-label="official partners">
      <div class="container arc-partners-inner">
        <div class="arc-partners-label">
          <span>ARC STATION</span>
          <strong>OFFICIAL PARTNERS</strong>
        </div>
        <div class="arc-partners-logos" id="arcPartnersLogos">
          <div class="arc-partners-track">
            <div class="arc-partners-group"><div class="arc-partners-set">          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div><div class="arc-partners-set" aria-hidden="true" inert>          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div><div class="arc-partners-set" aria-hidden="true" inert>          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div><div class="arc-partners-set" aria-hidden="true" inert>          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div></div>
            <div class="arc-partners-group" aria-hidden="true" inert><div class="arc-partners-set">          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div><div class="arc-partners-set" aria-hidden="true" inert>          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div><div class="arc-partners-set" aria-hidden="true" inert>          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div><div class="arc-partners-set" aria-hidden="true" inert>          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg?v=20260919-account1" alt="WEL">
          </a>
          <span class="arc-partner-item arc-partner-item--arih">
            <img src="arih-logo.svg?v=20261006" alt="ARIH" width="573" height="254" loading="lazy">
          </span>
          <span class="arc-partner-item arc-partner-item--boho">
            <img src="boho-logo.png?v=20261006" alt="BOHO" width="2047" height="355" loading="lazy">
          </span></div></div>
          </div>
        </div>
        <button class="arc-partners-toggle" type="button" aria-controls="arcPartnersLogos" aria-pressed="false">PAUSE LOGOS</button>
      </div>
    </section>
    <footer class="footer arc-legal-footer">
      <div class="container">
        <div class="arc-footer-top">
          <div class="arc-footer-brand">
            <b>ARC STATION</b>
            <span>OPERATED BY BIRD COMPANY LLC</span>
          </div>
          <nav class="arc-footer-links" aria-label="legal">
            <a href="terms.html">TERMS</a>
            <a href="privacy.html">PRIVACY</a>
            <a href="refund.html">REFUNDS</a>
          </nav>
        </div>
        <div class="arc-business-info">
          <span>OPERATOR: BIRD COMPANY LLC (버드컴퍼니 유한회사)</span>
          <span>REPRESENTATIVE: SEOL JAEHYUN</span>
          <span>BUSINESS NO. 539-81-03765</span>          <span>ADDRESS: B1, 9 Eonju-ro 146-gil, Gangnam-gu, Seoul, South Korea</span>          <span>CONTACT: lovesol716@gmail.com</span>
        </div>
        <div class="arc-footer-bottom">
          <span>© 2026 ARC STATION. ALL RIGHTS RESERVED.</span>
          <span>PLAY POINT HAS NO CASH VALUE.</span>
        </div>
      </div>
    </footer>`;
  const partnerToggle=document.querySelector('.arc-partners-toggle');
  partnerToggle?.addEventListener('click',()=>{
    const paused=document.querySelector('#arcPartnersLogos').classList.toggle('is-paused');
    partnerToggle.setAttribute('aria-pressed',String(paused));
    partnerToggle.textContent=paused?'PLAY LOGOS':'PAUSE LOGOS';
  });
  syncArcAccountNav();
  enforceAccountSetup().catch(()=>{location.replace('account.html?mode=login&next='+encodeURIComponent(safeNextUrl(location.pathname.split('/').pop()+location.search,'my.html')));});
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

async function syncArcAccountNav(){
  const el=document.getElementById('arcAccountNav');
  if(!el)return;
  try{
    const user=await currentUser();
    if(user){
      el.textContent='ACCOUNT';
      el.href='my.html';
      el.dataset.auth='in';
    }else{
      el.textContent='LOG IN';
      el.href='account.html';
      el.dataset.auth='out';
    }
  }catch(_){
    el.textContent='LOG IN';
    el.href='account.html';
  }
}

function safeNextUrl(raw,fallback='my.html'){
  const v=String(raw||'').trim();
  if(!v)return fallback;
  if(!/^[a-z0-9-]+\.html(?:[?#].*)?$/i.test(v)||v.includes('..')||/[\\\r\n]/.test(v))return fallback;
  return v;
}

async function arcRequireLogin(target){
  const user=await currentUser();
  if(user)return true;
  location.href='account.html?next='+encodeURIComponent(safeNextUrl(target||location.pathname.split('/').pop()||'index.html'));
  return false;
}

window.arcRequireLogin=arcRequireLogin;
window.safeNextUrl=safeNextUrl;

async function arcBeginGameEntry(next='athlete.html'){
  const target=safeNextUrl(next,'athlete.html');
  const user=await currentUser();
  if(!user){
    location.href='account.html?mode=login&next='+encodeURIComponent('player-profile.html?next='+encodeURIComponent(target));
    return false;
  }
  const boot=await db.rpc('arc_account_bootstrap',{p_display_name:null});
  if(boot.error)throw boot.error;
  const profile=await db.rpc('arc_player_profile');
  if(profile.error)throw profile.error;
  const row=profile.data?.[0];
  if(!row?.profile_complete){
    location.href='player-profile.html?next='+encodeURIComponent(target);
    return false;
  }
  location.href=target;
  return true;
}
window.arcBeginGameEntry=arcBeginGameEntry;

function countdown(){
  const el=document.getElementById('countdown');if(!el)return;
  const target=new Date(C.eventDateISO);
  const tick=()=>{let d=Math.max(0,target-new Date()),days=Math.floor(d/864e5);d%=864e5;let h=Math.floor(d/36e5);d%=36e5;let m=Math.floor(d/6e4),s=Math.floor((d%6e4)/1e3);el.innerHTML=[['DAYS',days],['HOURS',h],['MIN',m],['SEC',s]].map(([l,v])=>`<div class="card"><b>${String(v).padStart(2,'0')}</b><span>${l}</span></div>`).join('')};tick();setInterval(tick,1000);
}

// Existing sessions must complete the same required account details as new sign-ins.
async function enforceAccountSetup(){
  const page=location.pathname.split('/').pop()||'index.html';
  if(['account.html','player-profile.html','admin.html','privacy.html','terms.html','reset-password.html'].includes(page))return true;
  const user=await currentUser();if(!user)return true;
  const q=await db.rpc('arc_account_setup_state');if(q.error)throw q.error;
  if(q.data?.complete)return true;
  location.replace('player-profile.html?next='+encodeURIComponent(safeNextUrl(page+location.search,'my.html')));
  return false;
}
