shell('PLAYER');
const entryEl=id=>document.getElementById(id);
const won=v=>Number(v||0).toLocaleString('en-US')+' KRW';
const categoryName=v=>({MM:'MEN’S',WW:'WOMEN’S',MIXED:'MIXED'}[v]||v);
let entryState=null,playerProfile=null,entryQuote=null,entryBusy=false;
const entryErrors={
AUTH_REQUIRED:'Log in and try again.',ADMIN_ONLY:'Staff access only.',ARC_ACCOUNT_NOT_FOUND:'No ARC account was found for that email. Ask your partner to sign up or check their account email.',
DUPLICATE_PHONE:'This phone number is already linked to a team entry. Try the account you used before (Kakao, Google or email). If the number is incorrect, update your profile.',
GENDER_REQUIRED:'Select your gender.',TEAM_PHOTO_REQUIRED:'Check your player photo or contact us.',
INVALID_DISCOUNT_CODE:'Invalid discount code. Check and try again.',
PROFILE_REQUIRED:'Complete your player profile first.',CONSENT_REQUIRED:'Required consent is missing.',TEAM_NAME_REQUIRED:'Enter a team name.',INVALID_DIVISION:'Choose a division.',INVALID_CATEGORY:'Choose a category.',
CATEGORY_GENDER_MISMATCH:'Player gender does not match this category.',CATEGORY_FULL:'This division and category are full.',REGISTRATION_FULL:'All team places are filled.',REGISTRATION_CLOSED:'Entry or roster updates are currently closed.',
ALREADY_REGISTERED:'This account already has a team entry.',PARTNER_ALREADY_REGISTERED:'This athlete is already on another team.',PRICE_CHANGED:'The price changed. Review the new quote.',
PAYMENT_NOT_CONFIRMED:'Invite your partner after staff confirms the bank transfer.',CAPTAIN_ONLY:'Only the captain can do this.',DISCOUNT_PARTNER_ONLY:'The selected partner is not eligible for this entry. Contact us for help.',
TEAM_FULL:'Your roster is complete.',CANNOT_INVITE_SELF:'You cannot invite your own account.',INVITE_NOT_PENDING:'This invitation is no longer pending.',INVITE_NOT_FOUND:'Invitation not found.',
PAYMENT_HOLD_EXPIRED:'The payment window expired. If you already transferred, contact us before entering again.',PAYMENT_NOT_PENDING:'Payment status changed. Refresh your entry.',
DEPOSITOR_NAME_REQUIRED:'Enter the depositor name (at least 2 characters).',CONTACT_FOR_CANCELLATION:'For cancellation after reporting a transfer, contact us.',INVALID_PHONE:'Check your mobile number.',NAME_REQUIRED:'Enter at least 2 characters for your name.'
};
function entryError(e){const m=String(e?.message||e);return Object.entries(entryErrors).find(([k])=>m.includes(k))?.[1]||'Could not complete your request. Refresh or contact us.'}
async function entryRpc(action,payload={}){const r=await db.rpc('arc_entry_action',{p_action:action,p_payload:payload});if(r.error)throw r.error;return r.data}
function entryMessage(text,error=false){notice('entryMessage',text,error);entryEl('entryMessage').scrollIntoView({behavior:'smooth',block:'center'})}
async function runEntryAction(fn){if(entryBusy)return;entryBusy=true;document.querySelectorAll('main button').forEach(b=>b.disabled=true);try{await fn()}catch(e){entryMessage(entryError(e),true)}finally{entryBusy=false;document.querySelectorAll('main button').forEach(b=>b.disabled=false);entryEl('submitEntry').disabled=!entryQuote;}}
function invalidateQuote(){entryQuote=null;entryEl('submitEntry').disabled=true;entryEl('priceQuote').textContent='Review your team fee with this code.'}
function fillProfile(p){if(!p)return;entryEl('entryName').value=p.full_name||'';entryEl('entryGender').value=p.gender||'';entryEl('entryPhone').value=p.phone||'';entryEl('entryGym').value=p.gym||'';entryEl('entryInstagram').value=p.instagram||'';}
async function refreshEntry(){
 const [s,p]=await Promise.all([entryRpc('state'),db.rpc('arc_player_profile')]);if(p.error)throw p.error;
 entryState=s;playerProfile=p.data?.[0];fillProfile(playerProfile);
 entryEl('entryLoading').hidden=true;entryEl('entryClosed').hidden=s.registration_open;
 entryEl('entryApplication').hidden=!!s.entry||!s.registration_open;

 entryEl('invitePanel').hidden=!s.invites?.length;
 entryEl('inviteCards').innerHTML=(s.invites||[]).map(i=>'<article class="entry-panel"><h2>'+esc(i.team_name)+'</h2><p>'+esc(divisionLabel(i.division))+' / '+esc(categoryName(i.category))+'<br>CAPTAIN: '+esc(i.captain)+'</p><p>The team fee is paid. Accept to join; no extra payment is needed.</p>'+(!playerProfile?.profile_complete?'<p><a href="player-profile.html?next=athlete.html">COMPLETE PLAYER PROFILE →</a></p>':'')+'<label class="entry-consent"><input type="checkbox" id="consent-'+esc(i.id)+'"><span><a href="terms.html" target="_blank" rel="noopener" >TERMS</a>, <a href="privacy.html" target="_blank" rel="noopener">PRIVACY POLICY</a> and <a href="refund.html" target="_blank" rel="noopener">REFUND POLICY</a>. I agree to join this team.</span></label><div class="entry-actions"><button class="btn arcade-primary" data-respond="'+esc(i.id)+'" data-accept="true">ACCEPT</button><button class="btn dark" data-respond="'+esc(i.id)+'" data-accept="false">DECLINE</button></div></article>').join('');
 renderEntryStatus(s.entry);
 setEntryStep(s.entry?3:entryStep===3?1:entryStep,false);
 if(!s.entry&&s.registration_open)await updateEntryQuote();
}
function renderEntryStatus(t){
 const box=entryEl('entryStatus');box.hidden=!t;if(!t)return;
 const paid=t.status==='confirmed',reported=t.payment_status==='payment_check',expired=!paid&&!reported&&new Date(t.deadline)<=new Date();
 let content='<p class="entry-status-label">'+(paid?'ENTRY CONFIRMED':reported?'PAYMENT REVIEW':expired?'PAYMENT WINDOW EXPIRED':'AWAITING TRANSFER')+'</p><h2>'+esc(t.team_name)+'</h2><p>'+esc(divisionLabel(t.division))+' / '+esc(categoryName(t.category))+'</p><div class="entry-total">CAPTAIN '+won(t.captain_fee)+' + PARTNER '+won(t.partner_fee)+'<br>TEAM TOTAL <strong>'+won(t.amount_due)+'</strong></div>';
 if(paid){content+='<div class="arc-roster"><div><span>CAPTAIN</span><strong>'+esc(t.player_1||'CAPTAIN')+'</strong></div><div><span>PARTNER</span><strong>'+esc(t.roster_complete?t.player_2:'INVITE PENDING')+'</strong></div></div>';if(t.roster_complete){content+='<p>Both athletes are on the team.</p>';}else if(t.is_captain){content+='<p>Your partner needs an ARC account. Invite them by their account email; the invitation appears on their entry page.</p>';if(t.pending_invite)content+='<p>INVITE PENDING: '+esc(t.pending_invite.name)+'</p><button class="btn dark" data-entry-action="cancel_invite">CANCEL INVITE</button>';else content+='<form id="inviteForm"><label>PARTNER ARC ACCOUNT EMAIL<input id="inviteEmail" type="email" autocomplete="off" required></label><button class="btn arcade-primary" type="submit">INVITE PARTNER</button></form>';}}
 else{content+='<p>IBK INDUSTRIAL BANK OF KOREA <strong>244-105758-04-010</strong><br>버드컴퍼니 유한회사</p><button class="btn dark" data-copy-bank>COPY ACCOUNT NUMBER</button><p>TRANSFER & REPORT BY: '+esc(new Date(t.deadline).toLocaleString('en-US',{timeZone:'Asia/Seoul'}))+' (KST)</p>';
 if(reported)content+='<p>DEPOSITOR: '+esc(t.depositor_name)+' · Staff is verifying the transfer. Check your confirmation here.</p>';
 else if(expired)content+='<p>If you already transferred, do not re-enter. <a href="mailto:lovesol716@gmail.com">contact us</a>. Otherwise, cancel and enter again.</p>';
 else if(t.is_captain)content+='<form id="paymentForm"><label>NAME ON BANK TRANSFER<input id="depositorName" required minlength="2" maxlength="50" autocomplete="name"></label><label class="entry-consent"><input type="checkbox" required><span>I transferred the team total shown above.</span></label><button class="btn arcade-primary" type="submit">REPORT TRANSFER</button></form>';
 if(t.is_captain&&!reported)content+='<div class="entry-actions"><button class="btn dark" data-entry-action="cancel">CANCEL UNPAID ENTRY</button></div>';}
 content+='<div class="entry-actions"><button class="btn dark" data-refresh-entry>REFRESH STATUS</button></div>';
 box.innerHTML=content;
}
let entryStep=1;
function setEntryStep(step,focus=true){
 entryStep=step;entryEl('entryStep1').hidden=step!==1;entryEl('entryStep2').hidden=step!==2;
 document.querySelectorAll('[data-step]').forEach(item=>{if(Number(item.dataset.step)===step)item.setAttribute('aria-current','step');else item.removeAttribute('aria-current');});
 if(focus&&step<3){const target=entryEl(step===1?'entryName':'discountCode');target.focus();entryEl('entryApplication').scrollIntoView({behavior:'smooth',block:'start'});}
}
function validateEntryInfo(){
 const fields=[...entryEl('entryStep1').querySelectorAll('input,select')];const invalid=fields.find(input=>!input.checkValidity());
 if(invalid){setEntryStep(1,false);invalid.reportValidity();invalid.focus();return false;}return true;
}
function goEntryReview(){
 if(!validateEntryInfo())return;
 entryEl('entryReview').textContent=entryEl('entryTeam').value.trim()+' · '+divisionLabel(entryEl('entryDivision').value)+' · '+categoryName(entryEl('entryCategory').value);
 setEntryStep(2);
}
entryEl('entryNext').onclick=goEntryReview;
entryEl('entryBack').onclick=()=>setEntryStep(1);
let quoteTimer,quoteVersion=0;
async function updateEntryQuote(){
 const version=++quoteVersion,code=entryEl('discountCode').value.trim();
 invalidateQuote();entryEl('priceQuote').textContent='CALCULATING FEE…';
 try{
  const q=await entryRpc('quote',{discount_code:code});
  if(version!==quoteVersion||code!==entryEl('discountCode').value.trim())return;
  entryQuote={...q,code};
  entryEl('priceQuote').innerHTML=esc(q.pricing_tier==='early_bird'?'EARLY BIRD':'REGULAR')+' · '+won(q.captain_fee)+' PER ATHLETE × 2'+(q.discount_percent?'<br>CODE APPLIED · 50% OFF THE TEAM':'')+'<br>TEAM TRANSFER TOTAL <strong>'+won(q.amount_due)+'</strong>';
  entryEl('submitEntry').disabled=entryBusy;
 }catch(e){if(version!==quoteVersion)return;entryQuote=null;entryEl('priceQuote').textContent=entryError(e);entryEl('submitEntry').disabled=true;}
}
entryEl('discountCode').addEventListener('input',()=>{quoteVersion++;invalidateQuote();clearTimeout(quoteTimer);quoteTimer=setTimeout(updateEntryQuote,350);});
entryEl('quoteButton').onclick=()=>{clearTimeout(quoteTimer);updateEntryQuote();};
entryEl('entryForm').onsubmit=e=>{e.preventDefault();if(entryStep!==2){goEntryReview();return;}if(!validateEntryInfo()){return;}if(!entryQuote||entryQuote.code!==entryEl('discountCode').value.trim()||!entryEl('entryConsent').reportValidity())return;runEntryAction(async()=>{
 const p=await db.rpc('arc_save_player_profile',{p_full_name:entryEl('entryName').value.trim(),p_gender:entryEl('entryGender').value,p_phone:entryEl('entryPhone').value,p_instagram:entryEl('entryInstagram').value,p_gym:entryEl('entryGym').value,p_privacy_consent:entryEl('entryConsent').checked});if(p.error)throw p.error;
 await entryRpc('register',{team_name:entryEl('entryTeam').value.trim(),division:entryEl('entryDivision').value,category:entryEl('entryCategory').value,discount_code:entryEl('discountCode').value.trim(),expected_amount:entryQuote.amount_due,consent:entryEl('entryConsent').checked});
 entryQuote=null;await refreshEntry();entryMessage('Entry submitted. Transfer the team total to the bank account below.');
 });};
document.addEventListener('submit',ev=>{
 if(ev.target.id==='inviteForm'){ev.preventDefault();runEntryAction(async()=>{await entryRpc('invite',{team_id:entryState.entry.id,email:entryEl('inviteEmail').value.trim()});await refreshEntry();entryMessage('Invitation sent. Ask your partner to accept it on the entry page.');});}
 if(ev.target.id==='paymentForm'){ev.preventDefault();runEntryAction(async()=>{await entryRpc('report_payment',{team_id:entryState.entry.id,depositor_name:entryEl('depositorName').value.trim()});await refreshEntry();entryMessage('Transfer reported. Your team is confirmed after staff verification.');});}
});
document.addEventListener('click',ev=>{
 const b=ev.target.closest('button');if(!b)return;
 if(b.hasAttribute('data-refresh-entry'))runEntryAction(refreshEntry);
 if(b.hasAttribute('data-copy-bank')){navigator.clipboard?.writeText('244-105758-04-010').then(()=>entryMessage('Account number copied.')).catch(()=>entryMessage('Account number: 244-105758-04-010'));if(!navigator.clipboard)entryMessage('Account number: 244-105758-04-010');}
 if(b.dataset.entryAction){const action=b.dataset.entryAction;if(action==='cancel'&&!confirm('Cancel this unpaid entry? If you have transferred, contact us instead.'))return;runEntryAction(async()=>{await entryRpc(action,{team_id:entryState.entry.id});await refreshEntry();entryMessage(action==='cancel'?'Entry cancelled.':'Invitation cancelled.');});}
 if(b.dataset.respond){const accept=b.dataset.accept==='true';if(accept&&!playerProfile?.profile_complete){location.href='player-profile.html?next=athlete.html';return;}const consent=entryEl('consent-'+b.dataset.respond)?.checked;if(accept&&!consent){entryMessage('Accept the team consent to continue.',true);return;}runEntryAction(async()=>{await entryRpc('respond',{invite_id:b.dataset.respond,accept,consent});await refreshEntry();entryMessage(accept?'You have joined the team.':'Invitation declined.');});}
});
(async()=>{try{const user=await currentUser();if(!user){entryEl('entryLoading').hidden=true;entryEl('entryLogin').hidden=false;return;}const boot=await db.rpc('arc_account_bootstrap',{p_display_name:null});if(boot.error)throw boot.error;await refreshEntry();}catch(e){entryEl('entryLoading').hidden=true;entryMessage(entryError(e),true);}})();
