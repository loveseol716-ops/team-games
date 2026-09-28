/* Keep each task in its own panel; existing controls and IDs remain intact. */
(()=>{
 const control=document.getElementById('control');
 const section=id=>document.getElementById(id).closest('section');
 const sections={teams:section('adminTeams'),accounts:section('accountControl'),results:section('resultRows'),picks:section('predictionAdminGrid')};
 const add=section('addTeamBtn'),wallet=section('fanWalletSummary'),discount=control.querySelector(':scope > .admin-block');
 const nav=document.createElement('nav');nav.className='admin-tabs';nav.setAttribute('aria-label','Admin sections');
 nav.innerHTML=[['teams','TEAMS'],['accounts','ACCOUNTS'],['results','RESULTS'],['picks','FAN PICK']].map(([id,name])=>`<button type="button" data-admin-tab="${id}" aria-controls="admin-panel-${id}">${name}</button>`).join('')+'<button type="button" class="admin-refresh" id="adminRefresh">REFRESH ↻</button>';
 document.getElementById('summary').after(nav);
 const msg=document.createElement('div');msg.id='adminLoadMsg';msg.className='notice';msg.setAttribute('role','status');nav.after(msg);
 const panels={};Object.entries(sections).forEach(([id,el])=>{const p=document.createElement('div');p.id='admin-panel-'+id;p.className='admin-tab-panel';p.hidden=true;p.append(el);control.append(p);panels[id]=p;});
 function disclosure(el,title){const d=document.createElement('details');d.className='admin-tool';const s=document.createElement('summary');s.textContent=title;d.append(s,el);return d;}
 panels.teams.prepend(disclosure(add,'+ CREATE A TEAM'));
 panels.teams.append(disclosure(discount,'DISCOUNT CODES'));
 panels.picks.append(disclosure(wallet,'FAN WALLETS & POINT ADJUSTMENTS'));
 window.showAdminPanel=id=>{if(!panels[id])id='teams';Object.entries(panels).forEach(([key,p])=>p.hidden=key!==id);nav.querySelectorAll('[data-admin-tab]').forEach(b=>{const active=b.dataset.adminTab===id;b.setAttribute('aria-current',active?'page':'false');});try{sessionStorage.setItem('arc-admin-panel',id);}catch{};};
 nav.addEventListener('click',e=>{const b=e.target.closest('[data-admin-tab]');if(b)showAdminPanel(b.dataset.adminTab);});
 document.getElementById('adminRefresh').onclick=async()=>{const b=document.getElementById('adminRefresh');b.disabled=true;try{await refreshAdmin();}catch(e){notice('adminLoadMsg',adminError(e),true);}finally{b.disabled=false;}};
 let initial='teams';try{initial=sessionStorage.getItem('arc-admin-panel')||initial;}catch{}showAdminPanel(initial);
})();
function adminPhotoUrl(value){try{const u=new URL(value);return ['http:','https:'].includes(u.protocol)&&!/(favicon|default|placeholder)/i.test(u.pathname)?u.href:null;}catch{return null;}}
function adminPartnerOptions(t,query=''){
 const q=query.trim().toLowerCase();
 return '<option value="">SELECT PLAYER</option>'+adminRosterPlayers.filter(a=>a.athlete_id!==t.captain_id&&!a.locked_in&&(!q||[a.display_name,a.email].some(v=>String(v||'').toLowerCase().includes(q)))).map(a=>`<option value="${esc(a.athlete_id)}" ${a.athlete_id===t.pending_player_id?'selected':''}>${esc(a.display_name)} — ${esc(a.email||'')}${a.needs_profile?' · PROFILE NEEDED':''}</option>`).join('');
}
window.filterAdminPartners=id=>{const t=allAdminTeams.find(t=>t.id===id);if(!t)return;const s=document.getElementById('partner-select-'+id),old=s.value;s.innerHTML=adminPartnerOptions(t,document.getElementById('partner-search-'+id).value);if([...s.options].some(o=>o.value===old))s.value=old;adminPartnerHint(id);};
window.adminPartnerHint=id=>{const a=adminRosterPlayers.find(a=>a.athlete_id===document.getElementById('partner-select-'+id).value);document.getElementById('partner-hint-'+id).textContent=a?.needs_profile?'Name, gender and phone are required. Use EDIT PROFILE first.':'';};
window.editAdminPartner=async id=>{
 const a=adminRosterPlayers.find(a=>a.athlete_id===document.getElementById('partner-select-'+id).value);
 if(!a){notice('partner-msg-'+id,'Select a player first.',true);return;}
 try{const d=await accountRpc('accounts',{search:a.email||a.display_name,limit:100}),account=d.accounts.find(x=>x.id===a.athlete_id);if(!account)throw Error('ACCOUNT_NOT_FOUND');if(!accountRows.some(x=>x.id===account.id))accountRows.push(account);openAccount(account.id);}catch(e){notice('partner-msg-'+id,accountError(e),true);}
};
window.addAdminPartner=async id=>{
 const t=allAdminTeams.find(t=>t.id===id),a=adminRosterPlayers.find(a=>a.athlete_id===document.getElementById('partner-select-'+id).value),b=document.getElementById('partner-add-'+id);
 if(!t||!a){notice('partner-msg-'+id,'Select a player first.',true);return;}
 if(a.needs_profile){notice('partner-msg-'+id,'Complete the player profile using EDIT PROFILE first.',true);return;}
 if(!confirm(`Add ${a.display_name} to ${t.team_name}?\nThe player will join immediately, without a separate acceptance step.`))return;
 b.disabled=true;b.textContent='ADDING…';
 try{const r=await db.rpc('arc_admin_add_partner',{p_team_id:id,p_partner_id:a.athlete_id});if(r.error)throw r.error;await refreshAdmin();notice('teamAdminMsg',`${a.display_name} ADDED TO ${t.team_name}.`);}catch(e){notice('partner-msg-'+id,adminError(e),true);}finally{if(b.isConnected){b.disabled=false;b.textContent='ADD TO TEAM';}}
};
