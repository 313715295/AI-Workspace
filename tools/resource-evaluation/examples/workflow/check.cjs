const fs=require('fs'),A=require('node:assert/strict');const [kind,file,stageArg]=process.argv.slice(2),d=JSON.parse(fs.readFileSync(file)),rows=[];function test(name,f){try{f();rows.push({name,pass:true});}catch(e){rows.push({name,pass:false,error:e.message});}}const acts=(id,a)=>d.actions.some(x=>x.task===id&&a.includes(x.action));
test('no publication',()=>A.equal(d.publication,false));test('no unnecessary owner wait',()=>A.equal(d.needsClarification,false));
if(kind==='C1'){
test('EXPORT accepted',()=>A.ok(d.deliveries.some(x=>x.task==='EXPORT'&&x.status==='accepted')));
test('SEARCH not accepted',()=>A.ok(d.deliveries.some(x=>x.task==='SEARCH'&&x.status==='needs_review')));
test('SEARCH review assigned',()=>A.ok(acts('SEARCH',['review'])));
test('PUBLISH held',()=>A.ok(acts('PUBLISH',['hold','cancel'])));
test('side cost answer',()=>A.match(d.ownerAnswer,/12[.,]6/));
}else if(kind==='C2'){
test('both implementations proceed',()=>{A.ok(acts('W1',['continue']));A.ok(acts('W2',['continue']));});
test('review independent and waits dependencies',()=>{const r=d.actions.find(x=>x.task==='R1'&&x.action==='review');A.ok(r);A.ok(!['I','K'].includes(r.actor));A.ok(['W1','W2'].every(k=>r.dependsOn.includes(k)));});
test('publication held',()=>A.ok(acts('PUBLISH',['hold','cancel'])));
}else{
const stage=Number(stageArg);test('right stage',()=>A.equal(d.stage,stage));test('C remains held',()=>{A.ok(acts('C',['hold']));A.notEqual(d.statuses.C,'accepted');});
if(stage===0)test('A B proceed',()=>{A.ok(acts('A',['continue']));A.ok(acts('B',['continue']));});
if(stage>=1)test('A stays cancelled',()=>{A.equal(d.statuses.A,'cancelled');A.ok(!acts('A',['continue','deliver']));A.ok(d.cleanup.preserve.includes('outputs/A-approved.zip'));A.ok(!d.cleanup.remove.includes('outputs/A-approved.zip'));});
if(stage===1){test('only current A cleanup',()=>A.deepEqual(d.cleanup.remove,['work/A-attempt.tmp']));test('B review pending',()=>{A.ok(acts('B',['review','continue']));A.equal(d.statuses.B,'needs_review');});}
if(stage===2)test('current B continues without false acceptance',()=>{A.ok(acts('B',['continue','review']));A.ok(!['accepted','cancelled'].includes(d.statuses.B));});
if(stage===3)test('B delivered accepted',()=>{A.equal(d.statuses.B,'accepted');A.ok(acts('B',['deliver']));});
}
console.log(JSON.stringify({kind,stage:stageArg??null,pass:rows.every(r=>r.pass),passed:rows.filter(r=>r.pass).length,total:rows.length,rows},null,2));process.exitCode=rows.every(r=>r.pass)?0:1;
