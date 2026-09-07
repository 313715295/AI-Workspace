#!/usr/bin/env node
'use strict';
const p=require('node:path');
const {summarize}=require('./lib/core.cjs');
const {readJson,writeJson,newDirectory,freeze,verify,snapshot,writeReports}=require('./lib/artifacts.cjs');
const {importR4,adaptCodex}=require('./lib/adapters.cjs');
const {workflow}=require('./lib/workflow.cjs');
const help=`Offline resource evaluation (Node 20+, no dependencies or model calls)
  init --out DIR
  import-r4 --results FILE --measurement FILE [--protocol FILE] [--rates FILE] --out DIR
  adapt-codex --log FILE [--log FILE ...] --map FILE --out DIR
  import --source DIR --kind materials|rubric|submission [--label LABEL] --out NEW_DIR
  freeze --source DIR --kind materials|rubric|submission [--label LABEL] --out NEW_FILE
  verify --source DIR --manifest FILE
  summarize --study FILE --events FILE [--cutoff ISO_TIMESTAMP] --out NEW_DIR
  workflow --config FILE --out WORKSPACE [--at ISO_TIMESTAMP]
Report/import/freeze targets must be new. workflow reuses only its tracked workspace.
Add rounds/cases/configurations by editing a new study copy and supplying exported events.
`;
function options(args){const o={};for(let i=0;i<args.length;i+=2){if(!args[i]?.startsWith('--')||args[i+1]===undefined||args[i+1].startsWith('--'))throw Error('Expected --option VALUE');const key=args[i].slice(2);if(key==='log')o.log=[...(o.log??[]),args[i+1]];else{if(o[key]!==undefined)throw Error('Duplicate option '+key);o[key]=args[i+1];}}return o;}
async function main(args){const [cmd,...tail]=args;if(!cmd||['help','--help','-h'].includes(cmd)){console.log(help);return;}const o=options(tail);const required=k=>{if(!o[k])throw Error('Missing --'+k);return o[k];};const allowed={init:['out'],'import-r4':['results','measurement','protocol','rates','out'],'adapt-codex':['log','map','out'],import:['source','kind','label','out'],freeze:['source','kind','label','out'],verify:['source','manifest'],summarize:['study','events','cutoff','out'],workflow:['config','out','at']}[cmd];if(!allowed)throw Error('Unknown command');for(const key of Object.keys(o))if(!allowed.includes(key))throw Error('Unknown option --'+key);
  if(cmd==='workflow'){console.log(JSON.stringify(workflow(required('config'),required('out'),o.at),null,2));return;}
  if(cmd==='init'){newDirectory(required('out'));writeJson(p.join(o.out,'study.json'),{schemaVersion:1,round:'new-round',cutoff:'REPLACE_WITH_ISO_TIMESTAMP',rates:{},rateBasis:'Set your explicit rate basis',tailExcluded:true,trajectoryKind:'unspecified',turns:[],observations:[],limitations:[]});writeJson(p.join(o.out,'events.json'),[]);return;}
  if(cmd==='summarize'){const r=summarize(readJson(required('study')),readJson(required('events')),o.cutoff);writeReports(required('out'),r);console.log(JSON.stringify({round:r.round,cutoff:r.cutoff,subjectCredits:r.totals.subject.credits,coordinatorCredits:r.totals.coordinator.credits,unverifiedTurns:r.rows.filter(t=>t.configuration!=='verified').length}));return;}
  if(cmd==='import'){console.log(JSON.stringify(snapshot(required('source'),required('out'),required('kind'),o.label)));return;}
  if(cmd==='freeze'){writeJson(required('out'),freeze(required('source'),required('kind'),o.label));return;}
  if(cmd==='verify'){console.log(JSON.stringify(verify(required('source'),readJson(required('manifest')))));return;}
  const data=cmd==='import-r4'?importR4(required('results'),required('measurement'),o.rates,o.protocol):await adaptCodex(required('log'),readJson(required('map')));
  newDirectory(required('out'));writeJson(p.join(o.out,'study.json'),data.study);writeJson(p.join(o.out,'events.json'),data.events);console.log(JSON.stringify({turns:data.study.turns.length,events:data.events.length,exported:'allowlisted metadata only'}));
}
if(require.main===module)main(process.argv.slice(2)).catch(e=>{console.error('ERROR: '+e.message);process.exitCode=1;});
module.exports={main};
