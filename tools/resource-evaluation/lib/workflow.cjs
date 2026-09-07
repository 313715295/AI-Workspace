'use strict';
const fs=require('node:fs'),p=require('node:path'),cp=require('node:child_process');
const {hash,readJson,writeJson,tree,freeze,verify,snapshot,newDirectory,writeReports}=require('./artifacts.cjs');
const {summarize,time}=require('./core.cjs');
const digest=x=>hash(Buffer.from(JSON.stringify(x)));
const slug=s=>{if(typeof s!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(s))throw Error('Use simple case/participant ids');return s;};
function workflow(configFile,out,at=new Date().toISOString()){
  const config=readJson(configFile),home=p.dirname(p.resolve(configFile)),root=p.resolve(out),clock=time(at);
  if(config.schemaVersion!==1||!config.round||!Array.isArray(config.cases)||!Array.isArray(config.participants)||!Number.isSafeInteger(config.stop?.maxJobs)||config.stop.maxJobs<1||config.stop.afterAll!==true)throw Error('Fixed cases/participants and explicit maxJobs/afterAll stop required');
  const deadline=time(config.stop.deadline),caseMap=new Map();for(const c of config.cases){slug(c.id);if(caseMap.has(c.id))throw Error('Duplicate case');caseMap.set(c.id,c);}
  const jobs=[],participantIds=new Set();for(const a of config.participants){slug(a.id);if(participantIds.has(a.id)||!a.model||!a.effort||!Array.isArray(a.cases))throw Error('Unique participant with exact model/effort/cases required');participantIds.add(a.id);if(new Set(a.cases).size!==a.cases.length)throw Error('Duplicate case assignment');for(const id of a.cases){const c=caseMap.get(id);if(!c)throw Error('Unknown case assignment');jobs.push({id:a.id+'--'+id,a,c});}}
  if(jobs.length>config.stop.maxJobs)throw Error('Configured jobs exceed fixed stop.maxJobs');
  if(!fs.existsSync(root))newDirectory(root);if(fs.lstatSync(root).isSymbolicLink())throw Error('Linked workspace is not supported');
  const lock=p.join(root,'.workflow.lock'),fd=fs.openSync(lock,'wx');
  try{
    const statePath=p.join(root,'state.json'),state=fs.existsSync(statePath)?readJson(statePath):{schemaVersion:1,round:config.round,jobs:{},analyses:[]};if(state.round!==config.round)throw Error('Use a new workspace for a different round');
    const summary={newPreparations:[],newResults:[],changedInputs:[],missing:[],acknowledgedExceptions:[],completed:0,stoppedAtDeadline:clock>deadline,dispatch:[],analysis:null};let dirty=false;
    for(const {id,a,c}of jobs){
      const source=p.resolve(home,c.materials),rubric=p.resolve(home,c.rubric),checker=c.checker?p.resolve(home,c.checker):null,files=tree(source),rubricHash=hash(fs.readFileSync(rubric)),checkerHash=checker?hash(fs.readFileSync(checker)):null;
      const messageNames=[c.initial,...(c.followUps??[])];for(const name of messageNames){if(!files.some(f=>f.path===name))throw Error('Message must be a file in public materials');}
      const identity=digest({files,rubricHash,checkerHash,checkerArgs:c.checkerArgs??['{submission}'],model:a.model,effort:a.effort,initial:c.initial,followUps:c.followUps??[],requiresSemantic:c.requiresSemantic===true,stop:config.stop});
      let job=state.jobs[id];
      if(job)verify(p.join(root,job.prepared),job.preparedFreeze);
      if(job?.first){verify(p.join(root,job.first),job.firstFreeze);verify(p.join(root,job.first,'payload'),readJson(p.join(root,job.first,'freeze.json')));if(job.identity!==identity){summary.changedInputs.push({job:id,issue:'completed_definition_changed_use_new_case_or_participant_id'});summary.completed++;continue;}}
      if(!job||job.identity!==identity){if(clock>deadline){summary.missing.push({job:id,need:'preparation_deadline_passed'});continue;}const prepared=p.join('prepared',id,identity.slice(0,16));const dest=p.join(root,prepared);snapshot(source,p.join(dest,'materials'),'materials',id);fs.mkdirSync(p.join(dest,'private'));fs.copyFileSync(rubric,p.join(dest,'private/rubric.json'),fs.constants.COPYFILE_EXCL);if(checker)fs.copyFileSync(checker,p.join(dest,'private/check.cjs'),fs.constants.COPYFILE_EXCL);
        const spec={job:id,round:config.round,case:c.id,participant:a.id,requested:{model:a.model,effort:a.effort},stop:config.stop,rateBasis:config.rateBasis??null,rates:config.rates??{},initial:c.initial,followUps:c.followUps??[],definitionIdentity:identity};writeJson(p.join(dest,'dispatch.json'),spec);
        fs.mkdirSync(p.join(dest,'public-initial'));for(const f of files.filter(f=>!(c.followUps??[]).includes(f.path))){const target=p.join(dest,'public-initial',f.path);fs.mkdirSync(p.dirname(target),{recursive:true});fs.copyFileSync(p.join(source,f.path),target,fs.constants.COPYFILE_EXCL);}
        fs.writeFileSync(p.join(dest,'dispatch.md'),`Case ${c.id}; participant ${a.id}; model ${a.model}; effort ${a.effort}.\nOperator: expose only public-initial/ as the subject input; do not expose this control workspace.\nSubject: read input/${c.initial}. Work only on assigned input and your own result. Do not delegate or read private grading or other participants. Submit once; preserve earlier completed stages.\nStop at ${config.stop.deadline}; no automatic extra cases. Host/operator supplies the result directory.\n${(c.followUps??[]).length?'Operator-only follow-up files; append one at a time, only after freezing the preceding first submission (no ACK/permission loop):\n'+c.followUps.map(f=>'- materials/payload/'+f).join('\n'):'No follow-up messages.'}\n`,{flag:'wx'});
        const previous=job?.history??[];if(job)previous.push(job.prepared);job={identity,prepared,preparedFreeze:freeze(dest,'materials',id),history:previous,first:null};state.jobs[id]=job;dirty=true;summary.newPreparations.push(id);
      }
      const dest=p.join(root,job.prepared);verify(p.join(dest,'materials/payload'),readJson(p.join(dest,'materials/freeze.json')));if(hash(fs.readFileSync(p.join(dest,'private/rubric.json')))!==rubricHash||(checker&&hash(fs.readFileSync(p.join(dest,'private/check.cjs')))!==checkerHash))throw Error('Prepared private grading identity drift');
      const incoming=config.submissions?.[id];
      if(job.first){if(incoming?.path){const current=tree(p.resolve(home,incoming.path)),first=readJson(p.join(root,job.first,'freeze.json')).files;if(digest(current)!==digest(first))summary.changedInputs.push({job:id,issue:'first_submission_changed_not_replaced'});}summary.completed++;}
      else if(incoming?.final===true&&incoming.path&&fs.existsSync(p.resolve(home,incoming.path))){const first=p.join('first',id);snapshot(p.resolve(home,incoming.path),p.join(root,first),'submission',id);job.first=first;dirty=true;
        let result={status:'not_configured',pass:null};if(checker){const args=(c.checkerArgs??['{submission}']).map(s=>s.replaceAll('{submission}',p.join(root,first,'payload')));const run=cp.spawnSync(process.execPath,[p.join(dest,'private/check.cjs'),...args],{shell:false,encoding:'utf8',timeout:10000,maxBuffer:65536});fs.writeFileSync(p.join(root,first,'checker-stdout.txt'),run.stdout??'');fs.writeFileSync(p.join(root,first,'checker-stderr.txt'),run.stderr??'');let parsed;try{parsed=JSON.parse(run.stdout);}catch{}result={status:run.error?'execution_error':parsed&&typeof parsed.pass==='boolean'?'completed':'invalid_checker_output',exitCode:run.status,pass:run.status===0&&parsed?.pass===true,passed:parsed?.passed??null,total:parsed?.total??null};}
        verify(p.join(root,first,'payload'),readJson(p.join(root,first,'freeze.json')));writeJson(p.join(root,first,'mechanical.json'),{...result,mechanicalOnly:true,definitionIdentity:identity});job.firstFreeze=freeze(p.join(root,first),'submission',id);summary.newResults.push(id);summary.completed++;
      }else if(!job.first){summary.missing.push({job:id,need:incoming?.final?'submission_path_missing':'first_submission'});if(clock<=deadline)summary.dispatch.push(p.join(job.prepared,'dispatch.md').split(p.sep).join('/'));}
      if(job.first){const verdict=readJson(p.join(root,job.first,'mechanical.json'));if(verdict.pass===false){const item={job:id,need:'mechanical_failure_explanation',evidence:p.join(job.first,'mechanical.json').split(p.sep).join('/')};if(config.observations?.some(x=>x.participant===a.id&&x.case===c.id&&x.kind==='checker_false_negative'))summary.acknowledgedExceptions.push(item);else summary.missing.push(item);}if(verdict.pass===null)summary.missing.push({job:id,need:'mechanical_checker_not_configured'});if(c.requiresSemantic&&!config.observations?.some(x=>x.participant===a.id&&x.case===c.id&&(x.basis==='semantic'||x.kind==='checker_false_negative')))summary.missing.push({job:id,need:'semantic_judgment'});}
    }
    for(const id of Object.keys(state.jobs))if(!jobs.some(j=>j.id===id))summary.changedInputs.push({job:id,issue:'removed_from_current_plan_first_result_retained'});
    if(config.events){
      const events=readJson(p.resolve(home,config.events)),study={schemaVersion:1,round:config.round,cutoff:config.cutoff,rates:config.rates??{},rateBasis:config.rateBasis??null,tailExcluded:config.tailExcluded===true,trajectoryKind:config.trajectoryKind??'unspecified',turns:config.turns??[],observations:config.observations??[],limitations:config.limitations??[]};const fingerprint=digest({study,events});let analysis=state.analyses.find(x=>x.identity===fingerprint);
      if(!analysis){const r=summarize(study,events),folder=p.join('analysis',fingerprint.slice(0,16));writeReports(p.join(root,folder),r);analysis={identity:fingerprint,folder};state.analyses.push(analysis);dirty=true;}
      summary.analysis=p.join(analysis.folder,'REPORT.md').split(p.sep).join('/');const r=readJson(p.join(root,analysis.folder,'results.json'));
      for(const row of r.rows){if(row.configuration!=='verified')summary.missing.push({turn:row.turnId,need:'actual_configuration_'+row.configuration});if(row.issue)summary.missing.push({turn:row.turnId,need:row.issue});if(row.cumulativeMatches===false)summary.missing.push({turn:row.turnId,need:'cumulative_usage_mismatch'});}
      for(const {id,a,c}of jobs)if(!r.rows.some(t=>t.role==='subject'&&t.participant===a.id&&t.case===c.id))summary.missing.push({job:id,need:'actual_turn_metadata'});
    }else summary.missing.push({need:'usage_events_and_explicit_turn_attribution'});
    summary.allConfiguredFirstResultsCollected=summary.completed===jobs.length;summary.noAutomaticExpansion=true;
    if(dirty){fs.writeFileSync(statePath+'.tmp',JSON.stringify(state,null,2)+'\n');fs.renameSync(statePath+'.tmp',statePath);}
    return summary;
  }finally{fs.closeSync(fd);fs.unlinkSync(lock);}
}
module.exports={workflow};
