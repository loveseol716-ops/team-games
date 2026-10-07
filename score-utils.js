/* Four-round A and maximum-meter B. Official points are not guessed. */
window.ArcScore={
 time(value){if(value===null||value===undefined||value==='')return '';const cs=Math.round(Number(value)*100);return Math.floor(cs/6000)+':'+(Math.floor(cs/100)%60).toString().padStart(2,'0')+(cs%100?'.'+(cs%100).toString().padStart(2,'0'):'');},
 parseTime(value){const v=String(value).trim();if(!v)return null;if(!/^\d{1,2}:[0-5]\d(?:\.\d{1,2})?$/.test(v))throw Error('Use M:SS or M:SS.ss for each workout time.');const [m,s]=v.split(':').map(Number),n=m*60+s;if(n>480)throw Error('Completion time must be within the 8:00 cap. Leave unfinished times blank.');return n;},
 number(value,label,integer=false){const v=String(value).trim();if(!v)return null;const n=Number(v);if(!Number.isFinite(n)||n<0||n>=1000000||(integer&&(!Number.isInteger(n)||n<1)))throw Error('Invalid '+label+'.');return n;},
 capReps(rounds,reps){if(String(rounds).trim()===''||String(reps).trim()==='')throw Error('Enter rounds and extra reps (use 0 if none).');const r=Number(rounds),n=Number(reps);if(!Number.isInteger(r)||r<0||r>3||!Number.isInteger(n)||n<0||n>41)throw Error('Use 0–3 full rounds and 0–41 extra reps. For 4 rounds, enter finish time.');return r*42+n;},
 meters(v){if(String(v).trim()==='')throw Error('Enter total rowing meters.');const n=Number(v);if(!Number.isInteger(n)||n<0||n>100000)throw Error('Enter whole meters from 0 to 100000.');return n;},
 aLabel(r){return r.workout_a_seconds!=null?this.time(r.workout_a_seconds):r.workout_a_reps!=null?Math.floor(r.workout_a_reps/42)+' R + '+r.workout_a_reps%42+' REPS ('+r.workout_a_reps+'/168)':'—';},
 compareA(a,b){const af=a.workout_a_seconds!=null,bf=b.workout_a_seconds!=null;if(af!==bf)return af?-1:1;return af?Number(a.workout_a_seconds)-Number(b.workout_a_seconds):b.workout_a_reps-a.workout_a_reps;},
 ranks(rows,k){const eligible=rows.filter(r=>k==='a'?r.workout_a_reps!=null:r.workout_b_meters!=null),cmp=k==='a'?this.compareA:(a,b)=>b.workout_b_meters-a.workout_b_meters;eligible.sort(cmp);const map={};let rank=0;eligible.forEach((r,i)=>{if(!i||cmp(r,eligible[i-1])!==0)rank=i+1;map[r.team_id]=rank;});return map;},
 total(a,b){return a==null||b==null?null:Math.round((Number(a)+Number(b))*100)/100;}
};
