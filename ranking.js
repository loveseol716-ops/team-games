let rankData=[],rankTeams=[],scoreChannel=null,rankLoading=false,rankReload=false;
const re=id=>document.getElementById(id);
function renderRanks(){
 const div=re('rankDivision').value,cat=re('rankCategory').value,view=re('rankView').value;
 const rows=rankData.map(r=>({...r,team:rankTeams.find(t=>t.id===r.team_id)})).filter(r=>r.team?.division===div&&r.team?.category===cat);
 const ar=ArcScore.ranks(rows,'a'),br=ArcScore.ranks(rows,'b');
 rows.sort((a,b)=>((view==='a'?ar[a.team_id]:view==='b'?br[a.team_id]:a.rank)??9999)-((view==='a'?ar[b.team_id]:view==='b'?br[b.team_id]:b.rank)??9999)||a.team.team_name.localeCompare(b.team.team_name));
 const workout=(r,k)=>'<span><b>'+k.toUpperCase()+'</b> · '+esc(k==='a'?ArcScore.aLabel(r):r.workout_b_meters!=null?r.workout_b_meters+' m':'—')+' · PROVISIONAL #'+esc((k==='a'?ar:br)[r.team_id]??'—')+' · '+esc(r['workout_'+k+'_points']??'—')+' PTS</span>';
 re('rankRows').innerHTML=rows.length?'<div class="ranking-list">'+rows.map(r=>'<article class="rank-row"><strong class="rank-number">'+esc((view==='a'?ar[r.team_id]:view==='b'?br[r.team_id]:r.rank)??'—')+'</strong><div><h3>'+esc(r.team.team_name)+'</h3><span>'+esc(r.rank!=null?'OFFICIAL FINAL PLACE':r.workout_a_reps==null||r.workout_b_meters==null?'AWAITING OTHER WORKOUT':'FINAL PLACE PENDING')+'</span><div class="workout-scores">'+workout(r,'a')+workout(r,'b')+'</div></div><b class="rank-total">'+esc(r.total_points??'—')+' PTS</b></article>').join('')+'</div>':'<div class="empty-cabinet"><h2>NO RESULTS YET.</h2><p>Saved records will appear here automatically.</p></div>';
}
async function loadRanks(){
 if(rankLoading){rankReload=true;return;}rankLoading=true;re('refreshRank').disabled=true;
 try{
  const ev=await event();
  if(!scoreChannel){scoreChannel=db.channel('arc-results-'+ev.id).on('postgres_changes',{event:'*',schema:'public',table:'tg_results',filter:'event_id=eq.'+ev.id},()=>loadRanks()).subscribe(status=>{if(status==='SUBSCRIBED')loadRanks();});}
  const [r,t]=await Promise.all([db.from('tg_results').select('team_id,workout_a_seconds,workout_a_reps,workout_b_meters,workout_a_rank,workout_b_rank,workout_a_points,workout_b_points,total_points,status,rank').eq('event_id',ev.id),teams()]);
  if(r.error)throw r.error;rankData=r.data||[];rankTeams=t;renderRanks();
  re('scoreSync').textContent='UPDATED '+new Date().toLocaleTimeString()+' · AUTO REFRESH';
 }catch(e){re('scoreSync').textContent='CONNECTION INTERRUPTED · RETRYING. Displayed scores may be out of date.';}
 finally{rankLoading=false;re('refreshRank').disabled=false;if(rankReload){rankReload=false;loadRanks();}}
}
re('rankDivision').onchange=renderRanks;re('rankCategory').onchange=renderRanks;re('rankView').onchange=renderRanks;re('refreshRank').onclick=loadRanks;
// Fallback when realtime is unavailable; reload after returning to the tab.
setInterval(()=>{if(!document.hidden)loadRanks();},5000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)loadRanks();});
loadRanks();
