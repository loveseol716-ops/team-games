const fp=id=>document.getElementById(id),points=v=>Number(v||0).toLocaleString('ko-KR')+' P';
const pickCategory=v=>({MM:'MEN’S DOUBLES',WW:'WOMEN’S DOUBLES',MIXED:'MIXED DOUBLES'}[v]||v);
const pickStatus=v=>({pending:'PENDING',won:'WIN',lost:'LOSS',refunded:'REFUNDED'}[v]||'PENDING');
let fanUser=null,fanAccount=null,pickRows=[],selectedPick=null,pickBusy=false,refreshBusy=false;
let selectedDivision=null,selectedCategory=null,myEntry=null,rosterTeams=[];
async function pickRpc(name,args){const q=await db.rpc(name,args);if(q.error)throw q.error;return q.data;}
function pickError(e){const m=String(e?.message||e);return Object.entries({AUTH_REQUIRED:'Log in and try again.',INVALID_STAKE:'Enter at least 100 P in 100 P increments.',MARKET_LOCKED:'This market is closed.',BET_ALREADY_PLACED:'You already picked in this market. Check your history.',INSUFFICIENT_POINTS:'Not enough PLAY POINT.',TEAM_NOT_IN_MARKET:'This team is not available. Refresh the board.',FAN_PROFILE_REQUIRED:'Refresh your account and try again.'}).find(([k])=>m.includes(k))?.[1]||'Could not confirm this pick. Refresh your history before trying again.';}
function renderWallet(){
 if(!fanUser){fp('fanWallet').innerHTML='<p class="arc-kicker">PLAYER NOT CONNECTED</p><h2>BE PART OF THE GAME.</h2><p>Log in to see your points and pick stats.</p><a class="arc-button neon-pink" href="account.html?next=fanpick.html">LOG IN / SIGN UP →</a>';return;}
 const a=fanAccount;if(!a){fp('fanWallet').innerHTML='<p>Could not load your points. Refresh the page.</p>';return;}
 fp('fanWallet').innerHTML='<div class="wallet-top"><div><p class="arc-kicker">'+esc(a.display_name)+' / PLAY POINT</p><strong class="wallet-balance">'+points(a.balance)+'</strong><span class="fan-note">AVAILABLE POINTS</span></div><a class="arc-button" href="my.html">MY ACCOUNT ↗</a></div><details class="pick-stats"><summary>MY STATS</summary><div class="fan-stats"><div><span>HIT RATE</span><b>'+(a.settled_bets?Number(a.hit_rate).toFixed(1)+'%':'—')+'</b></div><div><span>WINS / SETTLED</span><b>'+Number(a.wins||0)+' / '+Number(a.settled_bets||0)+'</b></div><div><span>NET POINTS</span><b>'+(a.net_win>0?'+':'')+points(a.net_win)+'</b></div><div><span>TOTAL STAKED</span><b>'+points(a.total_staked)+'</b></div></div><p class="fan-note">Stats cover all picks; hit rate and net points count settled picks only.</p></details>';
}
function renderFilters(){
 const available=pickRows.filter(r=>r.team_id);
 if(!selectedDivision)selectedDivision=myEntry?.division||available[0]?.division||'OPEN';
 if(!selectedCategory)selectedCategory=myEntry?.category||available.find(r=>r.division===selectedDivision)?.category||'MM';
 fp('divisionFilters').innerHTML=['OPEN','PRO'].map(d=>'<button type="button" data-division="'+d+'" aria-pressed="'+(d===selectedDivision)+'">'+esc(divisionLabel(d))+'</button>').join('');
 fp('categoryFilters').innerHTML=['MM','WW','MIXED'].map(c=>{const n=pickRows.filter(r=>r.division===selectedDivision&&r.category===c&&r.team_id).length;return '<button type="button" data-category="'+c+'" aria-pressed="'+(c===selectedCategory)+'">'+({MM:'MEN',WW:'WOMEN',MIXED:'MIXED'}[c])+'<small>'+n+' TEAM'+(n===1?'':'S')+'</small></button>';}).join('');
}
function renderCurrentPicks(){
 const unique=[...new Map(pickRows.filter(r=>r.user_bet_id).map(r=>[r.market_id,r])).values()];
 fp('myCurrentPicks').hidden=!unique.length;
 fp('myCurrentPicks').innerHTML=unique.length?'<p class="arc-kicker">MY PICKS · THIS EVENT</p>'+unique.map(m=>{const t=pickRows.find(r=>r.market_id===m.market_id&&r.team_id===m.user_team_id);const paid=['won','lost','refunded'].includes(m.user_bet_status);return '<article class="neon-panel"><span class="market-badge">'+pickStatus(m.user_bet_status)+'</span><h2>'+esc(t?.team_name||'TEAM UNAVAILABLE')+'</h2><p>'+esc(divisionLabel(m.division))+' / '+esc(pickCategory(m.category))+'</p><p>'+points(m.user_stake)+' USED · '+(paid?'RETURNED '+points(m.user_bet_status==='refunded'?m.user_stake:m.user_payout):'TOTAL IF CORRECT '+points(Math.round(m.user_stake*m.user_odds)))+'</p><small>LOCKED ODDS ×'+Number(m.user_odds).toFixed(2)+'</small></article>';}).join(''):'';
}
function renderBoard(){
 renderFilters();renderCurrentPicks();
 if(!pickRows.length){fp('pickBoard').innerHTML='<section class="neon-panel empty-cabinet"><span class="pixel-icon" aria-hidden="true">◈</span><p class="arc-kicker">NEXT GAME LOADING</p><h2>PICKS ON HOLD</h2><p>We’re finalizing the team lineups.<br>Previous picks have been reset and all points used have been returned. New picks will open after the lineup announcement.</p><div class="arc-actions"><a class="arc-button" href="teams.html">VIEW TEAMS →</a><a class="arc-button" href="event.html">THE GAME →</a></div></section>';return;}
 const groups=Map.groupBy?Map.groupBy(pickRows.filter(r=>r.division===selectedDivision&&r.category===selectedCategory),r=>r.market_id):pickRows.filter(r=>r.division===selectedDivision&&r.category===selectedCategory).reduce((m,r)=>(m.has(r.market_id)?m.get(r.market_id).push(r):m.set(r.market_id,[r]),m),new Map());
 fp('pickBoard').innerHTML=[...groups.values()].map(rows=>{const m=rows[0],open=m.market_status==='open'&&new Date(m.lock_at)>new Date(),hasBet=!!m.user_bet_id;return '<section class="neon-panel market-panel"><div class="fan-section-head"><div><p class="arc-kicker">'+esc(divisionLabel(m.division))+'</p><h2>'+esc(pickCategory(m.category))+'</h2></div><span class="market-badge">'+(hasBet?'PICK LOCKED':open?(rows.some(r=>r.team_id)?'PICK OPEN':'WAITING FOR TEAMS'):m.market_status==='settled'?'SETTLED':'CLOSED')+'</span></div><p class="fan-note">CLOSES '+esc(new Date(m.lock_at).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'}))+' KST · STAKED '+points(m.total_stake)+'</p><div class="pick-teams">'+rows.filter(r=>r.team_id).map(r=>{const names=rosterTeams.find(t=>t.id===r.team_id);return '<button class="pick-team '+(r.user_team_id===r.team_id?'is-picked':'')+'" data-team="'+esc(r.team_id)+'" data-market="'+esc(r.market_id)+'" '+(!open||hasBet?'disabled':'')+'><span>'+esc(r.team_name)+'</span>'+(myEntry?.team_id===r.team_id||myEntry?.id===r.team_id?'<small class="my-team-tag">MY TEAM</small>':'')+'<p class="pick-roster">'+esc(names?.player_1||'PLAYER 1')+'<br>'+esc(names?.player_2||'PARTNER TO BE CONFIRMED')+'</p><small>TOTAL RETURN ×'+Number(r.live_odds).toFixed(2)+'</small><b>'+(r.user_team_id===r.team_id?'✓ MY PICK':open&&!hasBet?'SELECT TEAM →':'CLOSED')+'</b></button>';}).join('')+'</div>'+(!rows.some(r=>r.team_id)?'<p>WAITING FOR CONFIRMED TEAMS.</p>':'')+'</section>';}).join('');
}
async function renderHistory(){
 if(!fanUser)return;
 const q=await db.from('tg_prediction_bets').select('id,team_id,stake,odds_locked,potential_payout,payout,status,created_at').eq('user_id',fanUser.id).order('created_at',{ascending:false}).limit(50);
 if(q.error){fp('historyRows').textContent='Could not load your picks. Refresh.';return;}
 if(!q.data.length){fp('historyRows').innerHTML='<p>No picks yet. Choose a team when the board opens.</p>';return;}
 const ids=[...new Set(q.data.map(b=>b.team_id))];const tq=await db.from('tg_teams').select('id,team_name').in('id',ids);const names=Object.fromEntries((tq.data||[]).map(t=>[t.id,t.team_name]));
 fp('historyRows').innerHTML='<p class="fan-note">LATEST 50 PICKS · ALL GAMES</p>'+q.data.map(b=>'<article class="pick-history '+(b.status==='won'?'history-win':'')+'"><div><span class="market-badge">'+pickStatus(b.status)+'</span><h3>'+esc(names[b.team_id]||'TEAM UNAVAILABLE')+'</h3><small>'+esc(new Date(b.created_at).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'}))+' KST</small></div><div><b>'+points(b.stake)+' · ×'+Number(b.odds_locked).toFixed(2)+'</b><p>'+(['won','lost','refunded'].includes(b.status)?'PAID '+points(b.status==='refunded'?b.stake:b.payout):'POTENTIAL PAYOUT '+points(b.potential_payout))+'</p></div></article>').join('');
}
async function refreshPicks(){
 if(refreshBusy||pickBusy)return;refreshBusy=true;fp('refreshPicks').disabled=true;
 try{
 const results=await Promise.allSettled([pickRpc('tg_prediction_board',{p_event_slug:C.eventSlug}),fanUser?pickRpc('arc_my_account'):Promise.resolve(null),teams(),fanUser?pickRpc('arc_entry_action',{p_action:'state',p_payload:{}}):Promise.resolve(null)]);
 rosterTeams=results[2].status==='fulfilled'?results[2].value||[]:[];
 if(results[3].status==='fulfilled')myEntry=results[3].value?.entry||null;
 if(results[0].status==='fulfilled'){pickRows=results[0].value||[];renderBoard();}else{pickRows=[];fp('pickBoard').innerHTML='<p class="neon-panel">Could not load the board. Refresh.</p>';}
 fanAccount=results[1].status==='fulfilled'?results[1].value?.[0]:null;renderWallet();await renderHistory();
 }finally{refreshBusy=false;fp('refreshPicks').disabled=false;}
}
function estimatePick(){
 const stake=Number(fp('pickStake').value),balance=Number(fanAccount?.balance||0);
 const valid=Number.isInteger(stake)&&stake>=100&&stake%100===0&&stake<=balance;
 fp('pickAvailable').textContent='AVAILABLE · '+points(balance);
 fp('pickEstimate').innerHTML=valid?'<span>ESTIMATED TOTAL IF CORRECT</span><strong>'+points(Math.round(stake*Number(selectedPick?.live_odds||0)))+'</strong><p>'+points(stake)+' USED → '+points(balance-stake)+' LEFT</p>':'<p>'+(balance<100?'You need at least 100 P to make a pick.':'Enter a multiple of 100 within your available balance.')+'</p>';
 fp('confirmPick').disabled=pickBusy||!valid;
 fp('confirmPick').textContent=pickBusy?'SUBMITTING…':'PICK '+(selectedPick?.team_name||'TEAM')+' · USE '+points(valid?stake:0);
 document.querySelectorAll('[data-stake]').forEach(b=>{b.disabled=pickBusy||Number(b.dataset.stake)>balance;b.setAttribute('aria-pressed',String(Number(b.dataset.stake)===stake));});
}
fp('divisionFilters').onclick=e=>{const b=e.target.closest('[data-division]');if(!b)return;selectedDivision=b.dataset.division;selectedCategory=pickRows.find(r=>r.division===selectedDivision&&r.team_id)?.category||'MM';renderBoard();};
fp('categoryFilters').onclick=e=>{const b=e.target.closest('[data-category]');if(!b)return;selectedCategory=b.dataset.category;renderBoard();};
document.querySelector('a[href="#pickHistory"]').onclick=()=>{fp('pickHistory').open=true;};
fp('customStake').onclick=()=>{fp('pickStake').focus();};
fp('pickBoard').addEventListener('click',e=>{const b=e.target.closest('[data-team]');if(!b||b.disabled)return;if(!fanUser){location.href='account.html?next=fanpick.html';return;}if(!fanAccount){fp('pickMessage').textContent='Refresh your balance before picking.';return;}selectedPick=pickRows.find(r=>r.team_id===b.dataset.team&&r.market_id===b.dataset.market);if(!selectedPick)return;fp('pickDialogTitle').textContent=selectedPick.team_name;fp('pickMarketLabel').textContent=divisionLabel(selectedPick.division)+' · '+pickCategory(selectedPick.category);fp('pickStake').value=100;fp('pickStake').max=fanAccount.balance;fp('dialogError').textContent='';estimatePick();fp('pickDialog').showModal();});
fp('pickStake').addEventListener('input',estimatePick);document.querySelectorAll('[data-stake]').forEach(b=>b.onclick=()=>{fp('pickStake').value=b.dataset.stake;estimatePick();});
fp('closePick').onclick=()=>{if(!pickBusy)fp('pickDialog').close();};fp('pickDialog').addEventListener('cancel',e=>{if(pickBusy)e.preventDefault();});fp('refreshPicks').onclick=refreshPicks;
fp('pickForm').onsubmit=async e=>{
 e.preventDefault();if(pickBusy||!selectedPick||!e.target.reportValidity())return;const stake=Number(fp('pickStake').value);if(!Number.isInteger(stake)||stake<100||stake%100||stake>Number(fanAccount?.balance))return;
 pickBusy=true;estimatePick();fp('confirmPick').disabled=true;fp('closePick').disabled=true;fp('pickStake').disabled=true;fp('confirmPick').textContent='SUBMITTING…';fp('dialogError').textContent='';const selected={...selectedPick};const before=fanAccount.balance;
 try{const rows=await pickRpc('tg_place_prediction_bet',{p_market_id:selected.market_id,p_team_id:selected.team_id,p_stake:stake});const result=rows?.[0];if(!result)throw new Error('NO_RECEIPT');fanAccount.balance=result.balance;renderWallet();fp('pickDialog').close();fp('pickMessage').innerHTML='<section class="pick-receipt"><p class="arc-kicker">✓ PICK LOCKED IN</p><h2>'+esc(selected.team_name)+'</h2><p>'+points(before)+' → <strong>'+points(result.balance)+'</strong></p><p>'+points(stake)+' STAKED · LOCKED ODDS ×'+Number(result.odds_locked).toFixed(2)+'<br>POTENTIAL PAYOUT '+points(result.potential_payout)+'</p><a href="#pickHistory">VIEW MY PICKS ↓</a></section>';fp('pickMessage').textContent='Pick confirmed. Your selection is saved above.';
 }catch(err){fp('dialogError').textContent=pickError(err);}
 finally{pickBusy=false;fp('closePick').disabled=false;fp('pickStake').disabled=false;fp('confirmPick').textContent='LOCK IN PICK';await refreshPicks();estimatePick();if(!fp('pickDialog').open)fp('myCurrentPicks').scrollIntoView({behavior:'smooth',block:'start'});}
};
(async()=>{try{fanUser=await currentUser();if(fanUser)await pickRpc('arc_account_bootstrap',{p_display_name:null});await refreshPicks();}catch(e){fp('fanWallet').textContent='Could not load your account. Refresh the page.';fp('pickBoard').textContent='Please try again shortly.';}})();
