'use strict';
const counters=['input_tokens','cached_input_tokens','cache_write_input_tokens','output_tokens','reasoning_output_tokens','total_tokens'];
const kinds=['preregistered','checker_false_negative','post_hoc_unscored'];
const fail=m=>{throw Error(m);};
function time(s){if(typeof s!=='string'||!/(Z|[+-]\d\d:\d\d)$/.test(s)||!Number.isFinite(Date.parse(s)))fail('Expected timestamp with timezone');return Date.parse(s);}
function count(v,k){if(v!==undefined&&v!==null&&(!Number.isSafeInteger(v)||v<0))fail('Invalid token counter: '+k);return v??null;}
function usage(v={}){const u=Object.fromEntries(counters.map(k=>[k,count(v[k],k)]));if(u.cached_input_tokens!==null&&u.input_tokens!==null&&u.cached_input_tokens>u.input_tokens)fail('Cached input exceeds input');if(u.reasoning_output_tokens!==null&&u.output_tokens!==null&&u.reasoning_output_tokens>u.output_tokens)fail('Reasoning exceeds output');return u;}
function sumUsage(rows){return Object.fromEntries(counters.map(k=>[k,rows.some(r=>r[k]===null)?null:rows.reduce((n,r)=>n+r[k],0)]));}
function price(u,rate){
  if(!rate)return {credits:null,issue:'missing_rate'};
  for(const k of ['input','cachedInput','output'])if(typeof rate[k]!=='number'||!Number.isFinite(rate[k])||rate[k]<0)return {credits:null,issue:'invalid_rate'};
  if(['input_tokens','cached_input_tokens','output_tokens','cache_write_input_tokens'].some(k=>u[k]===null))return {credits:null,issue:'missing_billable_counter'};
  if(u.cache_write_input_tokens!==0)return {credits:null,issue:'nonzero_cache_write_semantics_not_supported'};
  return {credits:((u.input_tokens-u.cached_input_tokens)*rate.input+u.cached_input_tokens*rate.cachedInput+u.output_tokens*rate.output)/1e6,issue:null};
}
const pick=(v,keys)=>Object.fromEntries(keys.filter(k=>v[k]!==undefined).map(k=>[k,v[k]]));
function observations(xs=[]){return xs.map(x=>{if(!kinds.includes(x.kind))fail('Unknown observation kind');return pick(x,['kind','basis','case','participant','stage','rawPass','resolvedPass','score','expected','actual','noWrites','count','label','sourceRef']);});}
function summarize(study,events,overrideCutoff){
  if(study.schemaVersion!==1||!Array.isArray(study.turns)||!Array.isArray(events))fail('Expected schemaVersion 1 study and events array');
  const cutoff=overrideCutoff??study.cutoff,cut=time(cutoff),turns=new Map();
  for(const t of study.turns){if(!t.id||!t.threadId||!['subject','coordinator'].includes(t.role)||turns.has(t.id))fail('Turn ids must be unique and explicitly assigned a role/thread');if(t.sentAt)time(t.sentAt);turns.set(t.id,t);}
  const buckets=new Map([...turns.keys()].map(k=>[k,[]])),seen=new Map();let duplicates=0,afterCutoff=0;
  for(const raw of events){
    if(!['context','usage','timing'].includes(raw.type))fail('Unknown event type');
    const at=time(raw.timestamp);if(at>cut){afterCutoff++;continue;}
    const t=turns.get(raw.turnId);if(!t)fail('Unassigned turn: '+raw.turnId);if(t.threadId!==raw.threadId)fail('Thread/turn attribution mismatch');
    const e={...raw};
    if(e.type==='usage'){
      if(!e.responseId)fail('Usage requires responseId');e.usage=usage(e.usage);
      const fingerprint=JSON.stringify([e.threadId,e.turnId,e.usage]);
      if(seen.has(e.responseId)){if(seen.get(e.responseId)!==fingerprint)fail('Conflicting duplicate response: '+e.responseId);duplicates++;continue;}
      seen.set(e.responseId,fingerprint);
    }
    buckets.get(e.turnId).push(e);
  }
  const rows=[];
  for(const t of turns.values()){
    const es=buckets.get(t.id).sort((a,b)=>time(a.timestamp)-time(b.timestamp)),contexts=es.filter(e=>e.type==='context'),rs=es.filter(e=>e.type==='usage');
    const models=[...new Set(contexts.map(c=>c.model).filter(Boolean))],efforts=[...new Set(contexts.map(c=>c.effort).filter(Boolean))];
    const model=models.length===1&&contexts.every(c=>c.model)?models[0]:null,effort=efforts.length===1&&contexts.every(c=>c.effort)?efforts[0]:null;
    const requested=t.requested??{};
    const configuration=!model||!effort||!requested.model||!requested.effort?'unverified':model===requested.model&&effort===requested.effort?'verified':'mismatch';
    const u=rs.length?sumUsage(rs.map(r=>r.usage)):Object.fromEntries(counters.map(k=>[k,null]));
    const cost=model?price(u,study.rates?.[model]):{credits:null,issue:'missing_or_ambiguous_actual_model'};
    const timers=es.filter(e=>e.type==='timing'),timer=timers.at(-1),start=timer?.startedAt??null,end=timer?.completedAt??null;
    if(start)time(start);if(end)time(end);if(start&&end&&time(end)<time(start))fail('Completion before start');
    if(timer?.activeMs!==undefined&&timer.activeMs!==null&&(!Number.isFinite(timer.activeMs)||timer.activeMs<0))fail('Invalid activeMs');
    const completed=!!end&&time(end)<=cut,activityKind=timer?.activityKind??'unavailable';
    const activeSeconds=completed&&timer?.activeMs!=null?timer.activeMs/1000:null;
    const sourceTotal=rs.at(-1)?.cumulativeUsage;
    const cumulativeMatches=sourceTotal?counters.every(k=>u[k]===usage(sourceTotal)[k]):null;
    rows.push({turnId:t.id,threadId:t.threadId,role:t.role,participant:t.participant??null,case:t.case??null,stage:t.stage??null,requested:pick(requested,['model','effort']),actual:{model,effort},configuration,eligibleForComparison:t.role==='subject'&&configuration==='verified',usage:u,responseCount:rs.length,cumulativeMatches,...cost,startedAt:start,completedAt:completed?end:null,activityKind,activeSeconds,elapsedSeconds:completed&&t.sentAt?(time(end)-time(t.sentAt))/1000:null,dispatchToStartSeconds:start&&t.sentAt?(time(start)-time(t.sentAt))/1000:null,completeAtCutoff:completed});
  }
  const totals=Object.fromEntries(['subject','coordinator'].map(role=>{const xs=rows.filter(r=>r.role===role),missing=xs.filter(r=>r.credits===null).length;const timingGroups=[...new Set(xs.map(r=>r.activityKind))].map(kind=>{const ys=xs.filter(r=>r.activityKind===kind),unknown=ys.filter(r=>r.activeSeconds===null).length,known=ys.reduce((n,r)=>n+(r.activeSeconds??0),0);return {kind,turnCount:ys.length,activeSeconds:unknown?null:known,knownActiveSecondsSubtotal:known,unknownActiveTurns:unknown};});return [role,{turnCount:xs.length,coverage:xs.length?'registered_turns':'no_turns_registered',usage:xs.length?sumUsage(xs.map(r=>r.usage)):Object.fromEntries(counters.map(k=>[k,null])),credits:missing||!xs.length?null:xs.reduce((n,r)=>n+r.credits,0),knownCreditsSubtotal:xs.reduce((n,r)=>n+(r.credits??0),0),unknownCostTurns:missing,verifiedTurns:xs.filter(r=>r.configuration==='verified').length,timingGroups}];}));
  return {schemaVersion:1,round:study.round??null,cutoff,costType:'rate_estimate_not_billed_debit',rateBasis:study.rateBasis??null,tailExcluded:study.tailExcluded===true,trajectoryKind:study.trajectoryKind??'unspecified',sourceProvenance:study.sourceProvenance??[],duplicatesRemoved:duplicates,eventsAfterCutoff:afterCutoff,rows,totals,observations:observations(study.observations),limitations:[...(study.limitations??[]),'Missing values remain unknown; requested configuration never substitutes for actual context.','Invalid/unverified runs still contribute observed spending but are not valid comparison samples.','Reasoning is included in output; nonzero cache-write pricing is intentionally unsupported.','Activity groups with different definitions are not merged. Completed duration after cutoff is not prorated.','Observation channels are preserved; this tool neither grades answers nor rewrites historical scores.']};
}
module.exports={summarize,price,usage,sumUsage,time,observations};
