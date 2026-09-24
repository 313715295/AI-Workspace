'use strict';
const counters=['input_tokens','cached_input_tokens','cache_write_input_tokens','output_tokens','reasoning_output_tokens','total_tokens'];
const kinds=['preregistered','checker_false_negative','post_hoc_unscored'];
const CALCULATION_VERSION='resource-evaluation-2';
const fail=m=>{throw Error(m);};
function time(s){if(typeof s!=='string'||!/(Z|[+-]\d\d:\d\d)$/.test(s)||!Number.isFinite(Date.parse(s)))fail('Expected timestamp with timezone');return Date.parse(s);}
function count(v,k){if(v!==undefined&&v!==null&&(!Number.isSafeInteger(v)||v<0))fail('Invalid token counter: '+k);return v??null;}
function usage(v={}){const u=Object.fromEntries(counters.map(k=>[k,count(v[k],k)]));if(u.cached_input_tokens!==null&&u.input_tokens!==null&&u.cached_input_tokens>u.input_tokens)fail('Cached input exceeds input');if(u.reasoning_output_tokens!==null&&u.output_tokens!==null&&u.reasoning_output_tokens>u.output_tokens)fail('Reasoning exceeds output');return u;}
function sumUsage(rows){return Object.fromEntries(counters.map(k=>[k,rows.some(r=>r[k]===null)?null:rows.reduce((n,r)=>n+r[k],0)]));}
function price(u,rate,unit='codex_credits'){
  if(!['codex_credits','api_usd'].includes(unit))fail('Unknown cost unit');
  if(!rate)return {cost:null,credits:null,usd:null,issue:'missing_rate'};
  const unknown=issue=>({cost:null,credits:null,usd:null,issue});
  for(const k of ['input','cachedInput','output'])if(typeof rate[k]!=='number'||!Number.isFinite(rate[k])||rate[k]<0)return unknown('invalid_rate');
  if(['input_tokens','cached_input_tokens','output_tokens'].some(k=>u[k]===null))return unknown('missing_billable_counter');
  let write=0;
  if(unit==='api_usd'){
    if(u.cache_write_input_tokens===null)return unknown('missing_cache_write_counter');
    write=u.cache_write_input_tokens;
    if(write>0&&(typeof rate.cacheWrite!=='number'||!Number.isFinite(rate.cacheWrite)||rate.cacheWrite<0))return unknown('missing_cache_write_rate');
    if(write>u.input_tokens-u.cached_input_tokens)return unknown('cache_write_exceeds_uncached_input');
  }
  const cost=((u.input_tokens-u.cached_input_tokens-write)*rate.input+u.cached_input_tokens*rate.cachedInput+write*(rate.cacheWrite??0)+u.output_tokens*rate.output)/1e6;
  return {cost,credits:unit==='codex_credits'?cost:null,usd:unit==='api_usd'?cost:null,issue:null};
}
const pick=(v,keys)=>Object.fromEntries(keys.filter(k=>v[k]!==undefined).map(k=>[k,v[k]]));
function observations(xs=[]){return xs.map(x=>{if(!kinds.includes(x.kind))fail('Unknown observation kind');return pick(x,['kind','basis','case','participant','stage','rawPass','resolvedPass','score','expected','actual','noWrites','count','label','sourceRef']);});}
function summarize(study,events,overrideCutoff){
  if(study.schemaVersion!==1||!Array.isArray(study.turns)||!Array.isArray(events))fail('Expected schemaVersion 1 study and events array');
  const costUnit=study.costUnit??'codex_credits';if(!['codex_credits','api_usd'].includes(costUnit))fail('Unknown cost unit');
  const comparisonScope=study.comparisonScope??null;if(comparisonScope!==null&&!['turn','stage','task'].includes(comparisonScope))fail('Unknown comparison scope');
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
    const priced=rs.map(r=>model?price(r.usage,study.rates?.[model],costUnit):{cost:null,credits:null,usd:null,issue:'missing_or_ambiguous_actual_model'});
    const unknownCostResponses=priced.filter(x=>x.cost===null).length,knownCostSubtotal=priced.reduce((n,x)=>n+(x.cost??0),0);
    const cost=unknownCostResponses||!rs.length?null:knownCostSubtotal;
    const issue=!rs.length?'missing_usage':priced.find(x=>x.issue)?.issue??null;
    const timers=es.filter(e=>e.type==='timing'),timer=timers.at(-1),start=timer?.startedAt??null,end=timer?.completedAt??null;
    if(start)time(start);if(end)time(end);if(start&&end&&time(end)<time(start))fail('Completion before start');
    if(timer?.activeMs!==undefined&&timer.activeMs!==null&&(!Number.isFinite(timer.activeMs)||timer.activeMs<0))fail('Invalid activeMs');
    const completed=!!end&&time(end)<=cut,activityKind=timer?.activityKind??'unavailable';
    const activeSeconds=completed&&timer?.activeMs!=null?timer.activeMs/1000:null;
    const sourceTotal=rs.at(-1)?.cumulativeUsage;
    const cumulativeMatches=sourceTotal?counters.every(k=>u[k]===usage(sourceTotal)[k]):null;
    const missingMeasuredCounter=rs.some(r=>['input_tokens','cached_input_tokens','output_tokens',...(costUnit==='api_usd'?['cache_write_input_tokens']:[])].some(k=>r.usage[k]===null));
    const measurementIssues=[...(!rs.length?['no_observed_usage']:[]),...(!completed?['incomplete_at_cutoff']:[]),...(cumulativeMatches!==true?['cumulative_usage_unverified']:[]),...(missingMeasuredCounter?['missing_usage_counter']:[])];
    const measurementComplete=measurementIssues.length===0,costScope=t.costScope??null;
    if(costScope!==null&&!['turn','stage','task'].includes(costScope))fail('Unknown turn cost scope');
    const costComplete=cost!==null,eligibleForComparison=t.role==='subject'&&configuration==='verified'&&measurementComplete&&costComplete&&comparisonScope!==null&&costScope===comparisonScope;
    rows.push({turnId:t.id,threadId:t.threadId,role:t.role,participant:t.participant??null,case:t.case??null,stage:t.stage??null,costScope,comparisonScope,requested:pick(requested,['model','effort']),actual:{model,effort},configuration,measurementComplete,measurementIssues,costComplete,eligibleForComparison,usage:u,responseCount:rs.length,responseCountBasis:'deduplicated_observed_usage_records',responseCoverage:'supplier_request_total_unverified',cumulativeMatches,costUnit,cost,credits:costUnit==='codex_credits'?cost:null,usd:costUnit==='api_usd'?cost:null,knownCostSubtotal,knownCreditsSubtotal:costUnit==='codex_credits'?knownCostSubtotal:null,unknownCostResponses,issue,startedAt:start,completedAt:completed?end:null,activityKind,activeSeconds,observedOutputTokensPerActiveSecond:activeSeconds>0&&u.output_tokens!==null?u.output_tokens/activeSeconds:null,elapsedSeconds:completed&&t.sentAt?(time(end)-time(t.sentAt))/1000:null,dispatchToStartSeconds:start&&t.sentAt?(time(start)-time(t.sentAt))/1000:null,completeAtCutoff:completed});
  }
  const totals=Object.fromEntries(['subject','coordinator'].map(role=>{const xs=rows.filter(r=>r.role===role),missing=xs.filter(r=>r.cost===null).length;const timingGroups=[...new Set(xs.map(r=>r.activityKind))].map(kind=>{const ys=xs.filter(r=>r.activityKind===kind),unknown=ys.filter(r=>r.activeSeconds===null).length,known=ys.reduce((n,r)=>n+(r.activeSeconds??0),0);return {kind,turnCount:ys.length,activeSeconds:unknown?null:known,knownActiveSecondsSubtotal:known,unknownActiveTurns:unknown};});const knownCostSubtotal=xs.reduce((n,r)=>n+r.knownCostSubtotal,0),cost=missing||!xs.length?null:knownCostSubtotal;return [role,{turnCount:xs.length,responseCount:xs.reduce((n,r)=>n+r.responseCount,0),responseCountBasis:'deduplicated_observed_usage_records',responseCoverage:'supplier_request_total_unverified',coverage:xs.length?'registered_turns':'no_turns_registered',usage:xs.length?sumUsage(xs.map(r=>r.usage)):Object.fromEntries(counters.map(k=>[k,null])),costUnit,cost,credits:costUnit==='codex_credits'?cost:null,usd:costUnit==='api_usd'?cost:null,knownCostSubtotal,knownCreditsSubtotal:costUnit==='codex_credits'?knownCostSubtotal:null,unknownCostTurns:missing,unknownCostResponses:xs.reduce((n,r)=>n+r.unknownCostResponses,0),verifiedTurns:xs.filter(r=>r.configuration==='verified').length,measurementCompleteTurns:xs.filter(r=>r.measurementComplete).length,comparableTurns:xs.filter(r=>r.eligibleForComparison).length,timingGroups}];}));
  return {schemaVersion:1,calculationVersion:CALCULATION_VERSION,round:study.round??null,cutoff,costType:'rate_estimate_not_billed_debit',costUnit,comparisonScope,rateBasis:study.rateBasis??null,rateDate:study.rateDate??null,tailExcluded:study.tailExcluded===true,trajectoryKind:study.trajectoryKind??'unspecified',sourceProvenance:study.sourceProvenance??[],duplicatesRemoved:duplicates,eventsAfterCutoff:afterCutoff,rows,totals,observations:observations(study.observations),limitations:[...(study.limitations??[]),'Observed response counts are deduplicated usage records, not proven supplier request totals.','Missing values remain unknown; requested configuration never substitutes for actual context.','Comparison needs verified configuration, complete measurement, known cost and the declared cost scope; incomplete attempts still retain observed spending.','Reasoning is included in output; Codex credits and API USD are separate estimates.','Output tokens per active second uses the stated activity definition and is not pure model generation speed.','Activity groups with different definitions are not merged. Completed duration after cutoff is not prorated.','Observation channels are preserved; this tool neither grades answers nor rewrites historical scores.']};
}
module.exports={summarize,price,usage,sumUsage,time,observations,CALCULATION_VERSION};
