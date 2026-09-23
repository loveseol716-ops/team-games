// Account administration. All privileges are checked again by the database/API.
let accountRows=[],accountOffset=0,accountTotal=0,accountEditing=null,accountBusy=false;
const accountErrors={
 ADMIN_ACCOUNT_PROTECTED:'Administrator accounts cannot be deleted here.',
 CANNOT_DELETE_SELF:'You cannot delete your own account.',
 ACCOUNT_HAS_TEAM_HISTORY:'This account has team history. Deletion is blocked to preserve event records.',
 ACCOUNT_HAS_POINT_HISTORY:'This account has prediction or point history. Deletion is blocked to preserve those records.',
 ACCOUNT_HAS_ADMIN_HISTORY:'This account has staff history and cannot be deleted here.',
 EMAIL_CONFIRMATION_MISMATCH:'The confirmation email does not match this account.',
 REASON_REQUIRED:'Enter a reason (3–300 characters).',
 NICKNAME_REQUIRED:'Enter a nickname (1–30 characters).',
 NAME_REQUIRED:'Enter a player name (2–50 characters).',
 GENDER_REQUIRED:'Select the player’s category gender.',
 INVALID_PHONE:'Enter a phone number with 10 or 11 digits.',
 PROFILE_FIELDS_REQUIRED:'Complete the player name, gender and phone in Account Control first.',
 CATEGORY_GENDER_MISMATCH:'The player genders do not match the team category.',
 ACCOUNT_NOT_FOUND:'This account no longer exists.',
 DELETE_FAILED:'Deletion could not be completed. Linked records or owned uploads may need review.'
};
function accountError(e){const m=String(e?.message||e);return Object.keys(accountErrors).find(k=>m.includes(k))?accountErrors[Object.keys(accountErrors).find(k=>m.includes(k))]:adminError(e);}
async function accountRpc(action,payload={}){const r=await db.rpc('arc_admin_action',{p_action:action,p_payload:payload});if(r.error)throw r.error;return r.data;}
async function loadAccountControls(){
 const [events]=await Promise.all([accountRpc('events'),loadAccounts(),loadAccountAudit()]);
 const select=document.getElementById('newEvent'),old=select.value||C.eventSlug;
 select.innerHTML=events.map(e=>`<option value="${esc(e.slug)}">${esc(e.slug)} · ${new Date(e.date).toLocaleDateString('en-GB')}</option>`).join('');
 select.value=old;if(!select.value&&events.length)select.value=events[0].slug;
}
async function loadAccounts(){
 const data=await accountRpc('accounts',{search:document.getElementById('accountSearch').value.trim(),offset:accountOffset,limit:25});
 accountRows=data.accounts;accountTotal=data.total;
 if(!accountRows.length&&accountOffset>0){accountOffset=Math.max(0,accountOffset-25);return loadAccounts();}
 document.getElementById('accountCount').textContent=`${accountTotal} ACCOUNTS · ${accountTotal?accountOffset+1:0}–${Math.min(accountOffset+25,accountTotal)}`;
 document.getElementById('accountPrev').disabled=accountOffset===0;
 document.getElementById('accountNext').disabled=accountOffset+25>=accountTotal;
 document.getElementById('accountList').innerHTML=accountRows.length?accountRows.map(a=>`<article class="account-row"><div><strong>${esc(a.full_name||a.nickname||'ARC ACCOUNT')}</strong><small>${esc(a.email||'—')}${a.is_admin?' · ADMIN':''}</small><small>${a.teams.length?a.teams.map(t=>`${esc(t.name)} · ${esc(t.event)}${t.active?'':' (inactive)'}`).join('<br>'):'NO TEAM'}</small></div><button type="button" class="btn dark" data-edit-account="${a.id}">MANAGE</button></article>`).join(''):'<p class="muted">NO ACCOUNTS FOUND.</p>';
}
async function loadAccountAudit(){
 const rows=await accountRpc('audit');
 document.getElementById('accountAudit').innerHTML=rows.length?rows.map(r=>`<div class="account-audit-row"><strong>${esc(r.action.replaceAll('_',' ').toUpperCase())}</strong><small>${new Date(r.created_at).toLocaleString('en-GB')}</small>${r.reason?`<p>${esc(r.reason)}</p>`:''}<small>ACTOR ${esc(r.actor_id||'SYSTEM')}<br>TARGET ${esc(r.target_id||'—')}</small></div>`).join(''):'<p class="muted">NO CHANGES YET.</p>';
}
function openAccount(id){
 if(accountBusy)return;
 accountEditing=accountRows.find(a=>a.id===id);if(!accountEditing)return;
 const a=accountEditing;
 for(const key of ['nickname','full_name','gender','phone','gym','instagram'])document.getElementById(`acct_${key}`).value=a[key]||'';
 document.getElementById('acct_reason').value='';document.getElementById('acct_delete_email').value='';
 document.getElementById('accountEditorTitle').textContent=a.email||'ACCOUNT';
 document.getElementById('accountEditor').hidden=false;
 document.getElementById('accountDelete').disabled=!!a.delete_blocker;
 document.getElementById('accountDeleteHint').textContent=a.delete_blocker?accountError(a.delete_blocker):'Permanently deletes this account and its profile. This cannot be undone.';
 document.getElementById('accountEditMsg').style.display='none';
 document.getElementById('accountEditor').scrollIntoView({behavior:'smooth',block:'start'});
}
async function runAccountChange(button,fn){
 if(accountBusy)return;accountBusy=true;button.disabled=true;
 try{await fn();}catch(e){notice('accountEditMsg',accountError(e),true);}finally{accountBusy=false;button.disabled=button.id==='accountDelete'&&!!accountEditing?.delete_blocker;}
}
document.getElementById('accountSearchForm').onsubmit=async e=>{e.preventDefault();accountOffset=0;try{await loadAccounts();}catch(err){notice('accountMsg',accountError(err),true);}};
document.getElementById('accountPrev').onclick=async()=>{accountOffset=Math.max(0,accountOffset-25);try{await loadAccounts();}catch(e){notice('accountMsg',accountError(e),true);}};
document.getElementById('accountNext').onclick=async()=>{accountOffset+=25;try{await loadAccounts();}catch(e){notice('accountMsg',accountError(e),true);}};
document.getElementById('accountList').onclick=e=>{const b=e.target.closest('[data-edit-account]');if(b)openAccount(b.dataset.editAccount);};
document.getElementById('accountClose').onclick=()=>{if(!accountBusy)document.getElementById('accountEditor').hidden=true;};
document.getElementById('accountProfileForm').onsubmit=e=>{
 e.preventDefault();if(!accountEditing)return;
 const payload={user_id:accountEditing.id};for(const key of ['nickname','full_name','gender','phone','gym','instagram','reason'])payload[key]=document.getElementById(`acct_${key}`).value.trim();
 runAccountChange(document.getElementById('accountSave'),async()=>{
  await accountRpc('save_profile',payload);await refreshAdmin();
  notice('accountEditMsg','PROFILE SAVED. Team names and captain contact were updated.');
 });
};
document.getElementById('accountDelete').onclick=()=>{
 if(!accountEditing)return;
 const target=accountEditing.id,email=document.getElementById('acct_delete_email').value.trim(),reason=document.getElementById('acct_reason').value.trim();
 if(email.toLowerCase()!==(accountEditing.email||'').toLowerCase()){notice('accountEditMsg',accountErrors.EMAIL_CONFIRMATION_MISMATCH,true);return;}
 if(reason.length<3){notice('accountEditMsg',accountErrors.REASON_REQUIRED,true);return;}
 if(!confirm(`Permanently delete ${email}? This cannot be undone.`))return;
 runAccountChange(document.getElementById('accountDelete'),async()=>{
  const {data,error}=await db.functions.invoke('arc-admin-accounts',{body:{action:'delete',user_id:target,email,reason}});
  if(error){let body;try{body=await error.context?.json();}catch{}throw new Error(body?.error||error.message);}
  if(data?.error)throw new Error(data.error);
  accountEditing=null;document.getElementById('accountEditor').hidden=true;await refreshAdmin();notice('accountMsg','ACCOUNT DELETED.');
 });
};
