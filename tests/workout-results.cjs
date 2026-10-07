const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const ctx={window:{}};vm.createContext(ctx);vm.runInContext(fs.readFileSync('score-utils.js','utf8'),ctx);const s=ctx.window.ArcScore;
assert.equal(s.capReps('3','17'),143);assert.equal(s.capReps('0','0'),0);assert.equal(s.capReps('3','41'),167);
for(const a of [['4','0'],['3','42'],['','0'],['-1','4'],['1.5','0']])assert.throws(()=>s.capReps(...a));
assert.equal(s.parseTime('8:00'),480);assert.throws(()=>s.parseTime('8:00.01'));assert.equal(s.meters('0'),0);assert.throws(()=>s.meters('1.5'));assert.throws(()=>s.meters(''));
const rows=[{team_id:'a',workout_a_seconds:480,workout_a_reps:168,workout_b_meters:1000},{team_id:'b',workout_a_seconds:null,workout_a_reps:167,workout_b_meters:1500},{team_id:'c',workout_a_seconds:450,workout_a_reps:168,workout_b_meters:1500},{team_id:'d',workout_a_seconds:null,workout_a_reps:143,workout_b_meters:0},{team_id:'e',workout_a_reps:null,workout_b_meters:null}];
assert.equal(JSON.stringify(s.ranks(rows,'a')),JSON.stringify({c:1,a:2,b:3,d:4}));assert.equal(JSON.stringify(s.ranks(rows,'b')),JSON.stringify({b:1,c:1,a:3,d:4}));
for(const match of fs.readFileSync('admin.html','utf8').matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g))if(match[1].trim())new vm.Script(match[1]);
console.log('PASS: time-cap boundaries, meters validation, finish-before-cap ranking, ties, missing records, admin script syntax.');
