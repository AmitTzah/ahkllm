'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const seed=require('../seed');
const {openPreparedApplication}=require('../application-session');
const {showChat,sendChatMessage,waitStreamingIdle,sleep}=require('./helpers');
const lines=file=>fs.existsSync(file)?fs.readFileSync(file,'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse):[];
const base={regression:true,mode:'sse-success',settings:{threadTitles:{enabled:false}},preLaunch:()=>fs.writeFileSync(path.join(os.tmpdir(),'LLM_API_Log.json'),'[]'),launchEnv:()=>({AHKLLM_E2E_STREAM_IDLE_SECONDS:'2'})};
async function logWithStatus(status) {
  for(let n=0;n<100;n++){try{const entry=JSON.parse(fs.readFileSync(path.join(os.tmpdir(),'LLM_API_Log.json'),'utf8')).find(e=>e.status===status);if(entry)return entry;}catch{}await sleep(50);}
  throw new Error('Expected retained '+status+' stream log');
}
const scenarios=[{...base,id:394,name:'Active reasoning continues beyond the old 120-second HTTP cutoff and logs total latency',mockOpts:{streamLifecycle:'long',lifecycleDuration:123000},
  async body({cdp,dbPath}) {
    await showChat();const started=Date.now();await sendChatMessage(cdp,'Generate a long active reasoning response.');await waitStreamingIdle(cdp,170000);
    const assistant=seed.query(dbPath,"SELECT * FROM messages WHERE role='assistant'")[0];
    assert.ok(assistant?.content.includes('STREAM COMPLETED ANSWER'));assert.ok(Date.now()-started>=120000);
    const entry=await logWithStatus('success');assert.ok(entry.responseTimeMs>=120000,'Latency reported first token instead of full response duration');
    assert.ok(JSON.parse(entry.response)._ahkllm_stream_diagnostics.raw_response.includes('data: [DONE]'));
    return 'Real HTTP response streamed continuously for more than 120 seconds, completed, persisted usage and retained total elapsed latency';
  }
}];
for(const [id,mode] of [[395,'idle'],[396,'reasoning-drop'],[397,'partial-drop']])scenarios.push({...base,id,name:'HTTP '+mode+' becomes an incomplete-stream error with usable composer and retained raw data',mockOpts:{streamLifecycle:mode},
  async body({cdp,dbPath}) {
    await showChat();await sendChatMessage(cdp,'Exercise incomplete '+mode);await waitStreamingIdle(cdp,15000);
    const entry=await logWithStatus('error'),body=JSON.parse(entry.response);
    assert.ok(body.error.message.includes('before completion'));assert.ok(body._ahkllm_stream_diagnostics);
    if(mode!=='idle'){const partial=seed.query(dbPath,"SELECT * FROM messages WHERE role='assistant'")[0];assert.equal(partial.is_local_copy,1);assert.equal(partial.api_output_tokens,0);}
    await sendChatMessage(cdp,'Recover stream with a final answer.');await waitStreamingIdle(cdp,15000);
    assert.ok(seed.query(dbPath,"SELECT content FROM messages WHERE role='assistant'").some(m=>m.content.includes('STREAM COMPLETED ANSWER')));
    return 'Incomplete stream was not recorded as success; partial output is local only; diagnostics survived and a fresh send completed';
  }
});
for(const [id,mode] of [[398,'reasoning-drop'],[400,'reasoning-complete']])scenarios.push({...base,id,name:'Connected application '+mode+' aborts rather than committing a thought-only turn',mockOpts:{streamLifecycle:mode},
  async body({cdp,dataDir,dbPath}) {
    fs.writeFileSync(path.join(os.tmpdir(),'example-protocol-log.jsonl'),'');const threadId=await openPreparedApplication(cdp,dataDir,dbPath,id);
    await sendChatMessage(cdp,'Exercise reasoning without an answer.');await waitStreamingIdle(cdp,15000);
    const rpc=lines(path.join(os.tmpdir(),'example-protocol-log.jsonl'));assert.equal(rpc.filter(r=>r.method==='turn.abort').length,1);assert.equal(rpc.filter(r=>r.method==='turn.commit').length,0);
    assert.ok((await logWithStatus('error')).response.includes(mode==='reasoning-drop'?'before completion':'reasoning only'));
    await sendChatMessage(cdp,'Recover stream with a final answer.');await waitStreamingIdle(cdp,15000);
    assert.equal(lines(path.join(os.tmpdir(),'example-protocol-log.jsonl')).filter(r=>r.method==='turn.commit').length,1);
    return 'Thought-only application response aborted once, never committed, and the same connected chat recovered';
  }
});
scenarios.push({...base,id:399,name:'ChatGPT Responses uses the same idle safeguard without a total deadline',mockOpts:{streamLifecycle:'long',lifecycleDuration:4500,chatGptPlan:true},
  settings:{threadTitles:{enabled:false},newChatStartsWith:'chatgpt/gpt-5.6-luna'},
  launchEnv:({endpoint})=>({AHKLLM_E2E_STREAM_IDLE_SECONDS:'2',AHKLLM_E2E_PLAN_AUTH:'fixture',AHKLLM_E2E_CHATGPT_RESPONSES_ENDPOINT:endpoint.replace('/v1/chat/completions','/v1/responses'),AHKLLM_E2E_CHATGPT_MODELS_ENDPOINT:endpoint.replace('/v1/chat/completions','/v1/models')}),
  async body({cdp}){await showChat();await sendChatMessage(cdp,'Generate an active Responses stream.');await waitStreamingIdle(cdp,15000);const entry=await logWithStatus('success');assert.ok(entry.responseTimeMs>=4000);assert.ok(entry.response.includes('STREAM COMPLETED ANSWER'));return 'Active Responses transfer exceeded its scaled idle threshold and completed normally';}
});
module.exports=scenarios;
