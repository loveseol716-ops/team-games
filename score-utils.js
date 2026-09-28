/* A/B completion times and official rank points. No guessed points schedule. */
window.ArcScore={
 time(value){if(value===null||value===undefined||value==='')return '';const cs=Math.round(Number(value)*100);return Math.floor(cs/6000)+':'+(Math.floor(cs/100)%60).toString().padStart(2,'0')+(cs%100?'.'+(cs%100).toString().padStart(2,'0'):'');},
 parseTime(value){const v=String(value).trim();if(!v)return null;if(!/^\d{1,2}:[0-5]\d(?:\.\d{1,2})?$/.test(v))throw Error('Use M:SS or M:SS.ss for each workout time.');const [m,s]=v.split(':').map(Number),n=m*60+s;if(n>480)throw Error('Completion time must be within the 8:00 cap. Leave unfinished times blank.');return n;},
 number(value,label,integer=false){const v=String(value).trim();if(!v)return null;const n=Number(v);if(!Number.isFinite(n)||n<0||n>=1000000||(integer&&(!Number.isInteger(n)||n<1)))throw Error('Invalid '+label+'.');return n;},
 total(a,b){return a==null||b==null?null:Math.round((Number(a)+Number(b))*100)/100;}
};
