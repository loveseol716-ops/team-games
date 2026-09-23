// Display uses server time when available. Checkout and deadlines are enforced by SQL.
(() => {
 let terms=null,anchor=Date.now(),tick=performance.now();
 function render(){
  const now=anchor+(performance.now()-tick);
  const early=now<Date.parse(terms?.early_bird_ends_at||'2026-10-11T00:00:00+09:00');
  const closed=now>=Date.parse(terms?.registration_closes_at||'2026-10-25T00:00:00+09:00')||terms?.registration_open===false;
  const full=terms&&terms.filled>=terms.max_teams;
  document.querySelectorAll('[data-event-sale]').forEach(el=>{
   el.hidden=!early&&!closed&&!full;
   el.classList.toggle('is-closed',!!(closed||full));
   el.innerHTML=closed?'ENTRIES CLOSED':full?'24 TEAMS · FULL':early?'<span>EARLY BIRD OPEN</span><small>UNTIL OCT 10 · ₩20,000 / ATHLETE</small>':'';
  });
  document.querySelectorAll('[data-event-price]').forEach(el=>el.textContent=closed?'ENTRIES CLOSED':(early?'EARLY BIRD · ₩20,000':'REGULAR · ₩25,000')+' PER ATHLETE');
  document.querySelectorAll('[data-event-price-note]').forEach(el=>el.textContent=closed?'ENTRY DEADLINE: OCT 24, 23:59 KST':early?'THROUGH OCT 10 · ENTRY CLOSES OCT 24 (KST)':'EARLY BIRD ENDED · ENTRY CLOSES OCT 24 (KST)');
  if(closed){const form=document.getElementById('entryApplication');if(form&&!form.hidden){form.hidden=true;const message=document.getElementById('entryClosed');if(message)message.hidden=false;}}
 }
 async function sync(){
  try{const r=await db.rpc('arc_event_status',{p_event_slug:C.eventSlug});if(!r.error&&r.data){terms=r.data;anchor=Date.parse(terms.server_now);tick=performance.now();}}catch{}
  render();
 }
 render();sync();setInterval(render,1000);setInterval(sync,60000);
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)sync();});
})();
