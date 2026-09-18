
// ARC GAMES favicon
(()=> {
  const head=document.head;
  if(!head)return;
  const icon=document.createElement('link');
  icon.rel='icon';
  icon.type='image/x-icon';
  icon.href='favicon.ico?v=arcgames-20260918';
  head.appendChild(icon);
  const png=document.createElement('link');
  png.rel='icon';
  png.type='image/png';
  png.sizes='64x64';
  png.href='favicon.png?v=arcgames-20260918';
  head.appendChild(png);
})();

// ARC PARTNERS STRIP
(()=>{
  const style=document.createElement('style');
  style.textContent=`
    .arc-partners-strip{border-top:1px solid rgba(255,255,255,.07);border-bottom:1px solid rgba(255,255,255,.07);background:#030405;padding:34px 0}
    .arc-partners-inner{display:grid;grid-template-columns:190px 1fr;gap:34px;align-items:center}
    .arc-partners-label{display:grid;gap:5px}
    .arc-partners-label span{font-family:var(--font-display);font-size:8px;letter-spacing:.12em;color:#666d77}
    .arc-partners-label strong{font-family:var(--font-display);font-size:15px;font-weight:400;color:#fff}
    .arc-partners-logos{display:flex;align-items:center;gap:46px;flex-wrap:wrap;min-height:72px}
    .arc-partner-item{display:grid;place-items:center;min-width:150px;min-height:66px;padding:10px 16px;opacity:.92;transition:opacity .15s ease,transform .15s ease}
    .arc-partner-item:hover{opacity:1;transform:translateY(-2px)}
    .arc-partner-item img{display:block;max-width:180px;max-height:52px;width:auto;height:auto;object-fit:contain}
    @media(max-width:720px){
      .arc-partners-strip{padding:28px 0}
      .arc-partners-inner{grid-template-columns:1fr;gap:18px}
      .arc-partners-logos{gap:20px}
      .arc-partner-item{min-width:120px;justify-content:start;padding-left:0}
      .arc-partner-item img{max-width:160px}
    }
  `;
  document.head.appendChild(style);
})();

const C=window.TG_CONFIG;
const db=window.supabase.createClient(C.supabaseUrl,C.supabaseAnonKey);

function divisionLabel(v){return v==='OPEN'?'BEGINNER':v==='PRO'?'ATHLETE':v||'—'}

function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}

function nav(active){
  const p=[
    ['HOME','index.html'],['GAME','event.html'],['TEAMS','teams.html'],
    ['FAN PICK','fanpick.html'],['LIVE','live.html'],['PLAYER','athlete.html']
  ];
  return `<header class="nav"><div class="container navin"><a class="brand" href="index.html">ARC GAMES</a><nav class="links">${p.map(([n,h])=>`<a class="${active===n?'active':''}" href="${h}">${n}</a>`).join('')}</nav><a id="arcAccountNav" class="cta arcade-cta ${active==='ACCOUNT'?'active':''}" href="account.html">LOGIN</a></div></header>`;
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
  document.querySelector('#footer').innerHTML=`
    <section class="arc-partners-strip" aria-label="official partners">
      <div class="container arc-partners-inner">
        <div class="arc-partners-label">
          <span>ARC GAMES</span>
          <strong>OFFICIAL PARTNERS</strong>
        </div>
        <div class="arc-partners-logos">
          <a class="arc-partner-item" href="https://www.instagram.com/welwelwel.official/" target="_blank" rel="noopener noreferrer" aria-label="WELWELWEL Instagram">
            <img src="wel-logo.svg" alt="WEL">
          </a>
        </div>
      </div>
    </section>
    <footer class="footer arc-legal-footer">
      <div class="container">
        <div class="arc-footer-top">
          <div class="arc-footer-brand">
            <b>ARC GAMES</b>
            <span>OPERATED BY BIRD COMPANY LLC</span>
          </div>
          <nav class="arc-footer-links" aria-label="legal">
            <a href="terms.html">이용약관</a>
            <a href="privacy.html">개인정보처리방침</a>
            <a href="refund.html">환불·취소정책</a>
          </nav>
        </div>
        <div class="arc-business-info">
          <span>상호명: 버드컴퍼니 유한회사</span>
          <span>대표자: 설재현</span>
          <span>사업자등록번호: 539-81-03765</span>
          <span>통신판매업신고번호: 2025-서울구로-1975</span>
          <span>사업자 주소: 서울특별시 강남구 언주로146길 9 (논현동 98-10), 지하1층</span>
          <span>대표전화: 010-9206-4927</span>
          <span>문의: lovesol716@gmail.com</span>
        </div>
        <div class="arc-footer-bottom">
          <span>© 2026 ARC GAMES. ALL RIGHTS RESERVED.</span>
          <span>PLAY POINT HAS NO CASH VALUE.</span>
        </div>
      </div>
    </footer>`;
  syncArcAccountNav();
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
      el.textContent='MY PAGE';
      el.href='my.html';
      el.dataset.auth='in';
    }else{
      el.textContent='LOGIN';
      el.href='account.html';
      el.dataset.auth='out';
    }
  }catch(_){
    el.textContent='LOGIN';
    el.href='account.html';
  }
}

function safeNextUrl(raw,fallback='my.html'){
  const v=String(raw||'').trim();
  if(!v)return fallback;
  if(/^https?:/i.test(v)||v.startsWith('//')||v.includes('..'))return fallback;
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
