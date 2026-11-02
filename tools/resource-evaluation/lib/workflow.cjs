'use strict';
const fs=require('node:fs'),p=require('node:path'),cp=require('node:child_process');
const {hash,readJson,writeJson,tree,freeze,verify,snapshot,newDirectory,writeReports,REPORT_FORMAT_VERSION}=require('./artifacts.cjs');
const {summarize,time,CALCULATION_VERSION}=require('./core.cjs');
const digest=x=>hash(Buffer.from(JSON.stringify(x)));
const slug=s=>{if(typeof s!=='string'||!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(s))throw Error('Use simple case/participant ids');return s;};
function stageConfigurations(participant,caseDefinition){
  const groups=participant.stageConfigurations;if(groups===undefined)return {};
  if(!groups||Array.isArray(groups)||typeof groups!=='object'||Object.keys(groups).some(id=>!participant.cases.includes(id)))throw Error('Stage configurations must name assigned cases');
  const stages=groups[caseDefinition.id]??{};
  if(!stages||Array.isArray(stages)||typeof stages!=='object')throw Error('Stage configurations must map follow-up messages');
  for(const [message,requested]of Object.entries(stages))if(!(caseDefinition.followUps??[]).includes(message)||!requested||Object.keys(requested).sort().join('|')!=='effort|model'||typeof requested.model!=='string'||!requested.model.trim()||typeof requested.effort!=='string'||!requested.effort.trim())throw Error('Explicit stage configuration needs a declared follow-up and exact model/effort');
  return stages;
}
function bindFrozenDispatch(result,turns,state,root){
  for(const row of result.rows){
    if(row.role!=='subject')continue;
    const turn=turns.find(t=>t.id===row.turnId),ref=turn.dispatchRef,issues=[];
    let spec=null,expected=null;
    if(!ref)issues.push('missing_dispatch_ref');
    else if(typeof ref!=='object'||Array.isArray(ref)||Object.keys(ref).sort().join('|')!=='definitionIdentity|job|message'||['job','definitionIdentity','message'].some(k=>typeof ref[k]!=='string'||!ref[k]))issues.push('invalid_dispatch_ref');
    else{
      const job=Object.hasOwn(state.jobs,ref.job)?state.jobs[ref.job]:null;
      if(!job)issues.push('unknown_dispatch_job');
      else{
        verify(p.join(root,job.prepared),job.preparedFreeze);
        spec=readJson(p.join(root,job.prepared,'dispatch.json'));
        if(ref.definitionIdentity!==job.identity||spec.definitionIdentity!==job.identity)issues.push('dispatch_definition_mismatch');
        if(spec.job!==ref.job||spec.participant!==turn.participant||spec.case!==turn.case)issues.push('dispatch_attribution_mismatch');
        if(ref.message!==spec.initial&&!(spec.followUps??[]).includes(ref.message))issues.push('dispatch_stage_unknown');
        else expected=spec.stageConfigurations?.[ref.message]??spec.requested;
        if(expected&&(expected.model!==row.requested.model||expected.effort!==row.requested.effort))issues.push('dispatch_requested_mismatch');
        if(expected&&row.configuration==='verified'&&(expected.model!==row.actual.model||expected.effort!==row.actual.effort))issues.push('dispatch_actual_mismatch');
        if(row.configuration!=='verified')issues.push('actual_configuration_'+row.configuration);
      }
    }
    row.dispatchRef=ref??null;row.dispatchRequested=expected;row.dispatchIssues=issues;
    row.dispatchConfiguration=issues.length?(issues.every(x=>x==='missing_dispatch_ref'||x.startsWith('actual_configuration_unverified'))?'unverified':'mismatch'):'verified';
    row.eligibleForComparison=row.eligibleForComparison&&row.dispatchConfiguration==='verified';
  }
  result.totals.subject.comparableTurns=result.rows.filter(r=>r.role==='subject'&&r.eligibleForComparison).length;
  result.limitations.push('Workflow subject comparisons additionally require an explicit message/job/definition reference verified against frozen dispatch; unmatched attempts retain observed costs.');
  return result;
}
function workflow(configFile,out,at=new Date().toISOString()){
  const config=readJson(configFile),home=p.dirname(p.resolve(configFile)),root=p.resolve(out),clock=time(at);
  if(config.schemaVersion!==1||!config.round||!Array.isArray(config.cases)||!Array.isArray(config.participants)||!Number.isSafeInteger(config.stop?.maxJobs)||config.stop.maxJobs<1||config.stop.afterAll!==true)throw Error('Fixed cases/participants and explicit maxJobs/afterAll stop required');
  const deadline=time(config.stop.deadline),caseMap=new Map();for(const c of config.cases){slug(c.id);if(caseMap.has(c.id))throw Error('Duplicate case');if((c.followUps??[]).includes(c.initial))throw Error(`Initial message also listed as follow-up in case ${c.id}: ${c.initial}`);caseMap.set(c.id,c);}
  const jobs=[],participantIds=new Set(),jobIds=new Map();for(const a of config.participants){slug(a.id);if(participantIds.has(a.id)||!a.model||!a.effort||!Array.isArray(a.cases))throw Error('Unique participant with exact model/effort/cases required');participantIds.add(a.id);if(new Set(a.cases).size!==a.cases.length)throw Error('Duplicate case assignment');for(const id of a.cases){const c=caseMap.get(id);if(!c)throw Error('Unknown case assignment');const key=a.id+'--'+id,previous=jobIds.get(key);if(previous)throw Error(`Composite job id collision ${key}: ${previous.participant}/${previous.case} and ${a.id}/${id}`);jobIds.set(key,{participant:a.id,case:id});jobs.push({id:key,a,c});}}
  for(const {a,c}of jobs)stageConfigurations(a,c);
  if(jobs.length>config.stop.maxJobs)throw Error('Configured jobs exceed fixed stop.maxJobs');
  if(!fs.existsSync(root))newDirectory(root);if(fs.lstatSync(root).isSymbolicLink())throw Error('Linked workspace is not supported');
  const lock=p.join(root,'.workflow.lock'),fd=fs.openSync(lock,'wx');
  try{
    const statePath=p.join(root,'state.json'),state=fs.existsSync(statePath)?readJson(statePath):{schemaVersion:1,round:config.round,jobs:{},analyses:[]};if(state.round!==config.round)throw Error('Use a new workspace for a different round');
    const summary={newPreparations:[],newResults:[],changedInputs:[],missing:[],acknowledgedExceptions:[],completed:0,stoppedAtDeadline:clock>deadline,dispatch:[],analysis:null};let dirty=false;
    for(const {id,a,c}of jobs){
      const source=p.resolve(home,c.materials),rubric=p.resolve(home,c.rubric),checker=c.checker?p.resolve(home,c.checker):null,files=tree(source),rubricHash=hash(fs.readFileSync(rubric)),checkerHash=checker?hash(fs.readFileSync(checker)):null;
      const messageNames=[c.initial,...(c.followUps??[])];for(const name of messageNames){if(!files.some(f=>f.path===name))throw Error('Message must be a file in public materials');}
      const stages=stageConfigurations(a,c),identity=digest({files,rubricHash,checkerHash,checkerArgs:c.checkerArgs??['{submission}'],model:a.model,effort:a.effort,initial:c.initial,followUps:c.followUps??[],requiresSemantic:c.requiresSemantic===true,stop:config.stop,...(Object.keys(stages).length?{stageConfigurations:stages}:{})});
      let job=state.jobs[id];
      if(job)verify(p.join(root,job.prepared),job.preparedFreeze);
      if(job?.first){verify(p.join(root,job.first),job.firstFreeze);verify(p.join(root,job.first,'payload'),readJson(p.join(root,job.first,'freeze.json')));if(job.identity!==identity){summary.changedInputs.push({job:id,issue:'completed_definition_changed_use_new_case_or_participant_id'});summary.completed++;continue;}}
      if(!job||job.identity!==identity){if(clock>deadline){summary.missing.push({job:id,need:'preparation_deadline_passed'});continue;}const prepared=p.join('prepared',id,identity.slice(0,16));const dest=p.join(root,prepared);snapshot(source,p.join(dest,'materials'),'materials',id);fs.mkdirSync(p.join(dest,'private'));fs.copyFileSync(rubric,p.join(dest,'private/rubric.json'),fs.constants.COPYFILE_EXCL);if(checker)fs.copyFileSync(checker,p.join(dest,'private/check.cjs'),fs.constants.COPYFILE_EXCL);
        const spec={job:id,round:config.round,case:c.id,participant:a.id,requested:{model:a.model,effort:a.effort},stop:config.stop,rateBasis:config.rateBasis??null,rates:config.rates??{},initial:c.initial,followUps:c.followUps??[],definitionIdentity:identity,...(Object.keys(stages).length?{stageConfigurations:stages}:{})};writeJson(p.join(dest,'dispatch.json'),spec);
        const frozenPayload=p.join(dest,'materials/payload'),frozenManifest=readJson(p.join(dest,'materials/freeze.json'));verify(frozenPayload,frozenManifest);
        fs.mkdirSync(p.join(dest,'public-initial'));const publicFiles=frozenManifest.files.filter(f=>!(c.followUps??[]).includes(f.path));for(const f of publicFiles){const target=p.join(dest,'public-initial',f.path);fs.mkdirSync(p.dirname(target),{recursive:true});fs.copyFileSync(p.join(frozenPayload,f.path),target,fs.constants.COPYFILE_EXCL);}
        if(JSON.stringify(tree(p.join(dest,'public-initial')))!==JSON.stringify(publicFiles))throw Error('Public initial payload differs from verified frozen materials');
        fs.writeFileSync(p.join(dest,'dispatch.md'),`Case ${c.id}; participant ${a.id}; model ${a.model}; effort ${a.effort}.\nOperator: expose only public-initial/ as the subject input; do not expose this control workspace.\nSubject: read input/${c.initial}. Work only on assigned input and your own result. Do not delegate or read private grading or other participants. Submit once; preserve earlier completed stages.\nStop at ${config.stop.deadline}; no automatic extra cases. Host/operator supplies the result directory.\n${(c.followUps??[]).length?'Operator-only follow-up files; append one at a time, only after freezing the preceding first submission (no ACK/permission loop):\n'+c.followUps.map(f=>'- materials/payload/'+f).join('\n'):'No follow-up messages.'}\n`,{flag:'wx'});
        const previous=job?.history??[];if(job)previous.push(job.prepared);job={identity,prepared,preparedFreeze:freeze(dest,'materials',id),history:previous,first:null};state.jobs[id]=job;dirty=true;summary.newPreparations.push(id);
      }
      const dest=p.join(root,job.prepared),materialManifest=readJson(p.join(dest,'materials/freeze.json'));verify(p.join(dest,'materials/payload'),materialManifest);if(JSON.stringify(tree(p.join(dest,'public-initial')))!==JSON.stringify(materialManifest.files.filter(f=>!(c.followUps??[]).includes(f.path))))throw Error('Public initial payload differs from verified frozen materials');if(hash(fs.readFileSync(p.join(dest,'private/rubric.json')))!==rubricHash||(checker&&hash(fs.readFileSync(p.join(dest,'private/check.cjs')))!==checkerHash))throw Error('Prepared private grading identity drift');
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
      const events=readJson(p.resolve(home,config.events)),study={schemaVersion:1,round:config.round,cutoff:config.cutoff,rates:config.rates??{},rateBasis:config.rateBasis??null,rateDate:config.rateDate??null,costUnit:config.costUnit??'codex_credits',comparisonScope:config.comparisonScope??null,clockDomain:config.clockDomain??null,tailExcluded:config.tailExcluded===true,trajectoryKind:config.trajectoryKind??'unspecified',turns:config.turns??[],observations:config.observations??[],limitations:config.limitations??[]};const frozenDispatches=study.turns.filter(t=>t.role==='subject').map(t=>{const key=t.dispatchRef?.job,job=typeof key==='string'&&Object.hasOwn(state.jobs,key)?state.jobs[key]:null;return {turn:t.id,job:key??null,definitionIdentity:job?.identity??null,preparedFreeze:job?.preparedFreeze??null};}),inputIdentity=digest({study,events,frozenDispatches}),calculationIdentity=digest({CALCULATION_VERSION,REPORT_FORMAT_VERSION,core:hash(fs.readFileSync(p.join(__dirname,'core.cjs'))),artifacts:hash(fs.readFileSync(p.join(__dirname,'artifacts.cjs'))),workflow:hash(fs.readFileSync(__filename))}),fingerprint=digest({inputIdentity,calculationIdentity});const outputNames=['results.json','results.csv','REPORT.md'];let analysis=state.analyses.find(x=>x.identity===fingerprint&&x.calculationIdentity===calculationIdentity&&x.outputIdentities&&Object.keys(x.outputIdentities).sort().join('|')===outputNames.slice().sort().join('|')&&outputNames.every(name=>{const file=p.join(root,x.folder,name);return fs.existsSync(file)&&hash(fs.readFileSync(file))===x.outputIdentities[name];}));
      if(!analysis){const {costUnit:_unit,comparisonScope:_scope,rateDate:_date,...legacyStudy}=study,legacyIdentity=digest({study:legacyStudy,events});const prior=state.analyses.find(x=>x.inputIdentity===inputIdentity||x.identity===inputIdentity||x.identity===legacyIdentity||x.identity===fingerprint);if(prior)summary.changedInputs.push({analysis:prior.folder,issue:'analysis_cache_unverified_recomputed'});const r=bindFrozenDispatch(summarize(study,events),study.turns,state,root),base=p.join('analysis',fingerprint.slice(0,16));let folder=base,index=1;while(fs.existsSync(p.join(root,folder)))folder=base+'-r'+index++;const outputIdentities=writeReports(p.join(root,folder),r);analysis={identity:fingerprint,inputIdentity,calculationIdentity,folder,outputIdentities};state.analyses.push(analysis);dirty=true;}
      summary.analysis=p.join(analysis.folder,'REPORT.md').split(p.sep).join('/');const r=readJson(p.join(root,analysis.folder,'results.json'));
      for(const row of r.rows){if(row.role==='subject'&&row.dispatchConfiguration!=='verified')summary.missing.push({turn:row.turnId,need:'dispatch_configuration_'+row.dispatchConfiguration,reasons:row.dispatchIssues});if(row.configuration!=='verified')summary.missing.push({turn:row.turnId,need:'actual_configuration_'+row.configuration});if(!row.measurementComplete)summary.missing.push({turn:row.turnId,need:'measurement_incomplete',reasons:row.measurementIssues});if(!row.eligibleForComparison&&row.role==='subject')summary.missing.push({turn:row.turnId,need:'comparison_ineligible',scope:row.costScope});if(row.issue)summary.missing.push({turn:row.turnId,need:row.issue});if(row.cumulativeMatches===false)summary.missing.push({turn:row.turnId,need:'cumulative_usage_mismatch'});}
      for(const {id,a,c}of jobs)if(!r.rows.some(t=>t.role==='subject'&&t.participant===a.id&&t.case===c.id))summary.missing.push({job:id,need:'actual_turn_metadata'});
    }else summary.missing.push({need:'usage_events_and_explicit_turn_attribution'});
    summary.allConfiguredFirstResultsCollected=summary.completed===jobs.length;summary.noAutomaticExpansion=true;
    if(dirty){fs.writeFileSync(statePath+'.tmp',JSON.stringify(state,null,2)+'\n');fs.renameSync(statePath+'.tmp',statePath);}
    return summary;
  }finally{fs.closeSync(fd);fs.unlinkSync(lock);}
}
module.exports={workflow};
