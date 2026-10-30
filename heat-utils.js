/* One lane convention for judges and athletes: face the chalkboard. */
(()=>{
 const positive=value=>Number.isInteger(Number(value))&&Number(value)>0?Number(value):null;
 const lane=value=>({1:{code:'A',side:'왼쪽'},2:{code:'B',side:'오른쪽'}})[Number(value)]||{code:'—',side:'미배정'};
 const laneLabel=value=>{const l=lane(value);return l.code+' · '+l.side;};
 function groups(teams){
  const sorted=[...teams].sort((a,b)=>(positive(a.heat_no)??Infinity)-(positive(b.heat_no)??Infinity)||(positive(a.station_no)??Infinity)-(positive(b.station_no)??Infinity)||String(a.team_name||'').localeCompare(String(b.team_name||'')));
  const result=[];
  for(const team of sorted){const heat=positive(team.heat_no);let group=result[result.length-1];if(!group||group.heat!==heat){group={heat,teams:[]};result.push(group);}group.teams.push(team);}
  return result;
 }
 function timeRange(eventDate,heat){
  const base=new Date(eventDate).getTime();if(!eventDate||!Number.isFinite(base)||!positive(heat))return '';
  const start=base+(Number(heat)-1)*13*60000;
  const clock=value=>new Date(value).toLocaleTimeString('en-GB',{timeZone:'Asia/Seoul',hour:'2-digit',minute:'2-digit',hour12:false});
  return clock(start)+'–'+clock(start+8*60000);
 }
 window.ArcHeat={lane,laneLabel,groups,timeRange};
})();
