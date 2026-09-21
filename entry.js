shell('PLAYER');
const entryEl=id=>document.getElementById(id);
const won=v=>Number(v||0).toLocaleString('ko-KR')+'원';
const categoryName=v=>({MM:'MEN’S · 남남',WW:'WOMEN’S · 여여',MIXED:'MIXED · 남녀'}[v]||v);
let entryState=null,playerProfile=null,entryQuote=null,entryBusy=false;
const entryErrors={
AUTH_REQUIRED:'로그인 후 다시 시도해 주세요.',ADMIN_ONLY:'운영자만 사용할 수 있습니다.',ARC_ACCOUNT_NOT_FOUND:'해당 이메일의 ARC 계정이 없습니다. 팀원에게 회원가입 또는 계정 이메일 확인을 요청해 주세요.',
INVALID_DISCOUNT_CODE:'유효하지 않은 할인 코드입니다. 다시 확인해 주세요.',
PROFILE_REQUIRED:'선수 정보를 먼저 완성해 주세요.',CONSENT_REQUIRED:'필수 동의 항목을 확인해 주세요.',TEAM_NAME_REQUIRED:'팀 이름을 입력해 주세요.',INVALID_DIVISION:'디비전을 선택해 주세요.',INVALID_CATEGORY:'카테고리를 선택해 주세요.',
CATEGORY_GENDER_MISMATCH:'선수 성별이 선택한 팀 카테고리와 맞지 않습니다.',CATEGORY_FULL:'해당 디비전·카테고리 정원이 마감되었습니다.',REGISTRATION_FULL:'전체 참가 정원이 마감되었습니다.',REGISTRATION_CLOSED:'현재 신규 참가신청 또는 팀원 추가 기간이 아닙니다.',
ALREADY_REGISTERED:'이미 참가신청한 팀이 있습니다.',PARTNER_ALREADY_REGISTERED:'해당 팀원은 이미 다른 팀에 신청했습니다.',PRICE_CHANGED:'참가비가 변경되었습니다. 참가비를 다시 확인해 주세요.',
PAYMENT_NOT_CONFIRMED:'운영자의 입금 확인 후 팀원을 초대할 수 있습니다.',CAPTAIN_ONLY:'대표 선수만 진행할 수 있습니다.',DISCOUNT_PARTNER_ONLY:'신청 시 팀원 할인을 적용한 코드의 회원만 초대·합류할 수 있습니다.',
TEAM_FULL:'이미 2인 팀 구성이 완료되었습니다.',CANNOT_INVITE_SELF:'본인 계정은 초대할 수 없습니다.',INVITE_NOT_PENDING:'이미 처리되었거나 취소된 초대입니다.',INVITE_NOT_FOUND:'초대를 찾을 수 없습니다.',
PAYMENT_HOLD_EXPIRED:'입금 안내 기한이 지났습니다. 이미 입금했다면 재신청하지 말고 운영자에게 문의해 주세요.',PAYMENT_NOT_PENDING:'입금 확인 상태가 변경되었습니다. 신청 상태를 새로고침해 주세요.',
DEPOSITOR_NAME_REQUIRED:'입금자명을 두 글자 이상 입력해 주세요.',CONTACT_FOR_CANCELLATION:'입금 신고 이후 취소·환불은 운영자에게 문의해 주세요.',INVALID_PHONE:'휴대전화번호를 확인해 주세요.',NAME_REQUIRED:'이름을 두 글자 이상 입력해 주세요.'
};
function entryError(e){const m=String(e?.message||e);return Object.entries(entryErrors).find(([k])=>m.includes(k))?.[1]||'처리하지 못했습니다. 새로고침 후에도 계속되면 운영자에게 문의해 주세요.'}
async function entryRpc(action,payload={}){const r=await db.rpc('arc_entry_action',{p_action:action,p_payload:payload});if(r.error)throw r.error;return r.data}
function entryMessage(text,error=false){notice('entryMessage',text,error);entryEl('entryMessage').scrollIntoView({behavior:'smooth',block:'center'})}
async function runEntryAction(fn){if(entryBusy)return;entryBusy=true;document.querySelectorAll('main button').forEach(b=>b.disabled=true);try{await fn()}catch(e){entryMessage(entryError(e),true)}finally{entryBusy=false;document.querySelectorAll('main button').forEach(b=>b.disabled=false);entryEl('submitEntry').disabled=!entryQuote;}}
function invalidateQuote(){entryQuote=null;entryEl('submitEntry').disabled=true;entryEl('priceQuote').textContent='입력한 코드로 참가비를 다시 확인해 주세요.'}
function fillProfile(p){if(!p)return;entryEl('entryName').value=p.full_name||'';entryEl('entryGender').value=p.gender||'';entryEl('entryPhone').value=p.phone||'';entryEl('entryGym').value=p.gym||'';entryEl('entryInstagram').value=p.instagram||'';}
async function refreshEntry(){
 const [s,p]=await Promise.all([entryRpc('state'),db.rpc('arc_player_profile')]);if(p.error)throw p.error;
 entryState=s;playerProfile=p.data?.[0];fillProfile(playerProfile);
 entryEl('entryLoading').hidden=true;entryEl('entryClosed').hidden=s.registration_open;
 entryEl('entryApplication').hidden=!!s.entry||!s.registration_open;

 entryEl('invitePanel').hidden=!s.invites?.length;
 entryEl('inviteCards').innerHTML=(s.invites||[]).map(i=>'<article class="entry-panel"><h2>'+esc(i.team_name)+'</h2><p>'+esc(divisionLabel(i.division))+' / '+esc(categoryName(i.category))+'<br>대표: '+esc(i.captain)+'</p><p>팀 참가비는 입금 확인되었습니다. 추가 입금 없이 초대를 수락해 합류하세요.</p>'+(!playerProfile?.profile_complete?'<p><a href="player-profile.html?next=athlete.html">먼저 선수 정보 작성 →</a></p>':'')+'<label class="entry-consent"><input type="checkbox" id="consent-'+esc(i.id)+'"><span><a href="terms.html" target="_blank" rel="noopener">이용약관</a>·<a href="privacy.html" target="_blank" rel="noopener">개인정보처리방침</a>·<a href="refund.html" target="_blank" rel="noopener">환불·취소정책</a>을 확인하고 팀 참가에 동의합니다.</span></label><div class="entry-actions"><button class="btn arcade-primary" data-respond="'+esc(i.id)+'" data-accept="true">초대 수락</button><button class="btn dark" data-respond="'+esc(i.id)+'" data-accept="false">거절</button></div></article>').join('');
 renderEntryStatus(s.entry);
 if(!s.entry&&s.registration_open)await updateEntryQuote();
}
function renderEntryStatus(t){
 const box=entryEl('entryStatus');box.hidden=!t;if(!t)return;
 const paid=t.status==='confirmed',reported=t.payment_status==='payment_check',expired=!paid&&!reported&&new Date(t.deadline)<=new Date();
 let content='<p class="entry-status-label">'+(paid?'참가 확정':reported?'입금 확인 대기':expired?'입금 안내 기한 만료':'입금 대기')+'</p><h2>'+esc(t.team_name)+'</h2><p>'+esc(divisionLabel(t.division))+' / '+esc(categoryName(t.category))+'</p><div class="entry-total">대표 '+won(t.captain_fee)+' + 팀원 '+won(t.partner_fee)+'<br>팀 합계 <strong>'+won(t.amount_due)+'</strong></div>';
 if(paid){content+='<p>대표: '+esc(t.player_1)+'<br>팀원: '+esc(t.player_2)+'</p>';if(t.roster_complete){content+='<p>2인 팀 구성이 완료되었습니다.</p>';}else if(t.is_captain){content+='<p>팀원은 먼저 ARC 계정을 만들어야 합니다. 아래에 팀원의 ARC 계정 이메일을 입력하세요. 초대는 팀원의 참가신청 화면에 표시됩니다.</p>';if(t.pending_invite)content+='<p>초대 수락 대기: '+esc(t.pending_invite.name)+'</p><button class="btn dark" data-entry-action="cancel_invite">현재 초대 취소</button>';else content+='<form id="inviteForm"><label>팀원의 ARC 계정 이메일<input id="inviteEmail" type="email" autocomplete="off" required></label><button class="btn arcade-primary" type="submit">팀원 초대</button></form>';}}
 else{content+='<p>기업은행 <strong>244-105758-04-010</strong><br>버드컴퍼니 유한회사</p><button class="btn dark" data-copy-bank>계좌번호 복사</button><p>입금 및 신고 기한: '+esc(new Date(t.deadline).toLocaleString('ko-KR',{timeZone:'Asia/Seoul'}))+' (한국시간)</p>';
 if(reported)content+='<p>입금자 '+esc(t.depositor_name)+' · 운영자가 실제 입금을 확인 중입니다. 이 화면에서 참가 확정 여부를 확인할 수 있습니다.</p>';
 else if(expired)content+='<p>이미 입금했다면 재신청하지 말고 <a href="mailto:lovesol716@gmail.com">운영자에게 문의</a>해 주세요. 아직 입금하지 않았다면 신청을 취소한 뒤 다시 신청할 수 있습니다.</p>';
 else if(t.is_captain)content+='<form id="paymentForm"><label>실제 입금자명<input id="depositorName" required minlength="2" maxlength="50" autocomplete="name"></label><label class="entry-consent"><input type="checkbox" required><span>위 팀 합계 금액을 입금했습니다.</span></label><button class="btn arcade-primary" type="submit">입금 완료 알리기</button></form>';
 if(t.is_captain&&!reported)content+='<div class="entry-actions"><button class="btn dark" data-entry-action="cancel">미입금 신청 취소</button></div>';}
 content+='<div class="entry-actions"><button class="btn dark" data-refresh-entry>상태 새로고침</button></div>';
 box.innerHTML=content;
}
let quoteTimer,quoteVersion=0;
async function updateEntryQuote(){
 const version=++quoteVersion,code=entryEl('discountCode').value.trim();
 invalidateQuote();entryEl('priceQuote').textContent='참가비를 확인하고 있습니다…';
 try{
  const q=await entryRpc('quote',{discount_code:code});
  if(version!==quoteVersion||code!==entryEl('discountCode').value.trim())return;
  entryQuote={...q,code};
  entryEl('priceQuote').innerHTML=esc(q.pricing_tier==='early_bird'?'EARLY BIRD':'REGULAR')+' · 1인 '+won(q.captain_fee)+' × 2명'+(q.discount_percent?'<br>할인 코드 적용 · 팀 전체 50% 할인':'')+'<br>입금할 팀 합계 <strong>'+won(q.amount_due)+'</strong>';
  entryEl('submitEntry').disabled=entryBusy;
 }catch(e){if(version!==quoteVersion)return;entryQuote=null;entryEl('priceQuote').textContent=entryError(e);entryEl('submitEntry').disabled=true;}
}
entryEl('discountCode').addEventListener('input',()=>{quoteVersion++;invalidateQuote();clearTimeout(quoteTimer);quoteTimer=setTimeout(updateEntryQuote,350);});
entryEl('quoteButton').onclick=()=>{clearTimeout(quoteTimer);updateEntryQuote();};
entryEl('entryForm').onsubmit=e=>{e.preventDefault();if(!entryQuote||entryQuote.code!==entryEl('discountCode').value.trim()||!e.target.reportValidity())return;runEntryAction(async()=>{
 const p=await db.rpc('arc_save_player_profile',{p_full_name:entryEl('entryName').value.trim(),p_gender:entryEl('entryGender').value,p_phone:entryEl('entryPhone').value,p_instagram:entryEl('entryInstagram').value,p_gym:entryEl('entryGym').value,p_privacy_consent:entryEl('entryConsent').checked});if(p.error)throw p.error;
 await entryRpc('register',{team_name:entryEl('entryTeam').value.trim(),division:entryEl('entryDivision').value,category:entryEl('entryCategory').value,discount_code:entryEl('discountCode').value.trim(),expected_amount:entryQuote.amount_due,consent:entryEl('entryConsent').checked});
 entryQuote=null;await refreshEntry();entryMessage('참가신청이 접수되었습니다. 아래 계좌와 팀 합계 금액을 확인한 뒤 입금해 주세요.');
 });};
document.addEventListener('submit',ev=>{
 if(ev.target.id==='inviteForm'){ev.preventDefault();runEntryAction(async()=>{await entryRpc('invite',{team_id:entryState.entry.id,email:entryEl('inviteEmail').value.trim()});await refreshEntry();entryMessage('팀원 계정에 초대를 등록했습니다. 팀원에게 참가신청 페이지에서 수락하도록 안내해 주세요.');});}
 if(ev.target.id==='paymentForm'){ev.preventDefault();runEntryAction(async()=>{await entryRpc('report_payment',{team_id:entryState.entry.id,depositor_name:entryEl('depositorName').value.trim()});await refreshEntry();entryMessage('입금 확인을 요청했습니다. 운영자 확인 후 참가가 확정됩니다.');});}
});
document.addEventListener('click',ev=>{
 const b=ev.target.closest('button');if(!b)return;
 if(b.hasAttribute('data-refresh-entry'))runEntryAction(refreshEntry);
 if(b.hasAttribute('data-copy-bank')){navigator.clipboard?.writeText('244-105758-04-010').then(()=>entryMessage('계좌번호를 복사했습니다.')).catch(()=>entryMessage('계좌번호: 244-105758-04-010'));if(!navigator.clipboard)entryMessage('계좌번호: 244-105758-04-010');}
 if(b.dataset.entryAction){const action=b.dataset.entryAction;if(action==='cancel'&&!confirm('아직 입금하지 않은 신청을 취소할까요? 이미 입금했다면 운영자에게 문의해 주세요.'))return;runEntryAction(async()=>{await entryRpc(action,{team_id:entryState.entry.id});await refreshEntry();entryMessage(action==='cancel'?'신청이 취소되었습니다.':'초대가 취소되었습니다.');});}
 if(b.dataset.respond){const accept=b.dataset.accept==='true';if(accept&&!playerProfile?.profile_complete){location.href='player-profile.html?next=athlete.html';return;}const consent=entryEl('consent-'+b.dataset.respond)?.checked;if(accept&&!consent){entryMessage('참가 동의 항목을 확인해 주세요.',true);return;}runEntryAction(async()=>{await entryRpc('respond',{invite_id:b.dataset.respond,accept,consent});await refreshEntry();entryMessage(accept?'팀 합류가 완료되었습니다.':'초대를 거절했습니다.');});}
});
(async()=>{try{const user=await currentUser();if(!user){entryEl('entryLoading').hidden=true;entryEl('entryLogin').hidden=false;return;}const boot=await db.rpc('arc_account_bootstrap',{p_display_name:null});if(boot.error)throw boot.error;await refreshEntry();}catch(e){entryEl('entryLoading').hidden=true;entryMessage(entryError(e),true);}})();
