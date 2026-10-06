'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const {openPreparedApplication:openApplication} = require('../application-session');
const launcher = require('../launch');
const seed = require('../seed');
const {installFakeCodex, fakeCodexEnvironment, codexRequests} = require('../codex-fixture');
const {showChat, runProbe, sendChatMessage, waitStreamingIdle, sleep} = require('./helpers');

function readLines(file) {
  return fs.existsSync(file) ? fs.readFileSync(file,'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse) : [];
}

function configureTextMode(dataDir, endpoint) {
  installFakeCodex(dataDir);
  fs.writeFileSync(path.join(os.tmpdir(),'example-protocol-log.jsonl'),'');
  const file = path.join(dataDir,'settings.json');
  const settings = JSON.parse(fs.readFileSync(file,'utf8'));
  settings.providers.deepseek.toolCallingMode = 'text-protocol';
  settings.providers.chatgpt = {displayName:'ChatGPT plan',transport:'chatgpt-responses',toolCallingMode:'text-protocol'};
  fs.writeFileSync(file,JSON.stringify(settings));
}

const base = {
  regression:true, mode:'sse-success',preLaunch:configureTextMode,
  settings:{threadTitles:{enabled:false},newChatStartsWith:'codex/gpt-5.6-luna'},
  mockOpts:{applicationTextProtocol:true,chatGptPlan:true,planDelay:150,chunkDelay:450},
  launchEnv: context=>({...fakeCodexEnvironment(context),AHKLLM_E2E_PLAN_AUTH:'fixture',
    AHKLLM_E2E_CHATGPT_RESPONSES_ENDPOINT:context.endpoint.replace('/v1/chat/completions','/v1/responses'),
    AHKLLM_E2E_CHATGPT_MODELS_ENDPOINT:context.endpoint.replace('/v1/chat/completions','/v1/models')})
};

async function successBody({cdp,dataDir,dbPath,mockLog}) {
  const threadId = await openApplication(cdp,dataDir,dbPath,this.id);
  await sendChatMessage(cdp,'Use the text example and answer.');
  await waitStreamingIdle(cdp,25000);
  const first = seed.query(dbPath,'SELECT * FROM messages WHERE thread_id=? AND role=\'assistant\' ORDER BY rowid',[threadId])[0];
  assert.ok(first?.content.includes('APPLICATION TEXT ANSWER Ω'),'Final answer did not arrive');
  assert.ok(!first.content.startsWith('AHKLLM_APPLICATION_V1'),'Protocol envelope leaked into chat');
  assert.ok(first.reasoning.includes('Using echo_text') && first.reasoning.includes('Finished echo_text'),'Tool activity missing');
  const node = seed.query(dbPath,'SELECT * FROM application_nodes WHERE message_id=?',[first.id])[0];
  assert.equal(JSON.parse(node.state_json).checkpoint,1,'Application turn did not commit');
  assert.ok(node.replay_json.includes('function_call_output') && node.replay_json.includes('APPLICATION TEXT TOOL RESULT'),'Tool exchange did not persist');
  assert.equal(readLines(path.join(os.tmpdir(),'example-protocol-log.jsonl')).filter(r=>r.method==='tools.call').length,1);
  await sendChatMessage(cdp,'Continue the text example');
  await waitStreamingIdle(cdp,20000);
  if (this.backend === 'codex') {
    const requests=codexRequests(dataDir);
    assert.equal(requests.length,3,'Expected tool request, continuation, then follow-up');
    assert.ok(requests[0].stdin.includes('EXACT TEXT PREPARED CONTEXT Ω'),'Prepared context missing');
    assert.ok(requests[2].stdin.includes('tool_result') && requests[2].stdin.includes('APPLICATION TEXT TOOL RESULT'),'Replay missing');
    assert.ok(requests.every(r=>r.instructions.includes('Application tool-calling protocol (text-protocol)')));
    assert.equal(first.prompt_tokens,42,'Usage must include both CLI rounds');
    await cdp.eval('Ipc.postToHost("retry",{messageId:'+JSON.stringify(first.id)+'}); true');
    await cdp.waitFor('isThreadRequestInFlight('+JSON.stringify(threadId)+')',5000,50,'retry started');
    await waitStreamingIdle(cdp,20000);
    assert.equal(seed.query(dbPath,'SELECT id FROM messages WHERE thread_id=? AND role=\'assistant\'',[threadId]).length,3,'Retry did not create a retained branch');
  } else {
    const requests=readLines(mockLog).filter(r=>r.url.includes(this.backend==='responses'?'/responses':'/chat/completions'));
    assert.equal(requests.length,3);
    assert.ok(requests.every(r=>!(r.body.tools||[]).some(t=>(t.name||t.function?.name)==='echo_text')),'Text mode sent native schemas');
    assert.ok(JSON.stringify(requests.at(-1).body).includes('tool_result'),'Text-mode replay missing');
    assert.equal(codexRequests(dataDir).length,0,'Generic HTTP text mode invoked CLI');
  }
  assert.ok(!await cdp.eval('document.getElementById("chat-messages").innerText.includes("AHKLLM_APPLICATION_V1")'),'Raw text envelope appeared in UI');
  return 'Generic text functions, Unicode arguments, prepared context, checkpoint commit, activity, and durable replay verified';
}

const scenarios = [
  {...base,id:372,backend:'codex',name:'Connected Codex CLI text protocol executes functions and preserves retries and replay',body:successBody},
  {...base,id:373,backend:'http',name:'Text tool calling is generic and works with an HTTP provider',settings:{...base.settings,newChatStartsWith:'deepseek/deepseek-v4-flash'},body:successBody},
  {...base,id:374,backend:'responses',name:'Text tool calling also works with the ChatGPT Responses transport',settings:{...base.settings,newChatStartsWith:'chatgpt/gpt-5.6-luna'},body:successBody}
];

for(const [id,message] of [[375,'INVALID_TOOL_ARGUMENTS'],[376,'MALFORMED_TOOL_REPLY'],[379,'UNKNOWN_TOOL_REPLY']]) scenarios.push({...base,id,
  name:'Connected text protocol rejects '+message+' without invoking a function or committing',
  async body({cdp,dataDir,dbPath}) {
    const threadId=await openApplication(cdp,dataDir,dbPath,id);
    await sendChatMessage(cdp,message);
    await cdp.waitFor('document.getElementById("chat-messages").textContent.includes("Request failed:")',10000,100,'invalid envelope rejected');
    await waitStreamingIdle(cdp,10000);
    const requests=readLines(path.join(os.tmpdir(),'example-protocol-log.jsonl'));
    assert.equal(requests.filter(r=>r.method==='tools.call'||r.method==='turn.commit').length,0);
    assert.ok(requests.some(r=>r.method==='turn.abort'),'Failed tool request did not abort the application turn');
    assert.equal(seed.query(dbPath,'SELECT id FROM messages WHERE thread_id=? AND role=\'assistant\'',[threadId]).length,0);
    return 'Malformed/unadvertised/invalid calls failed before application execution and released turn ownership';
  }
});

scenarios.push({...base,id:378,name:'Stopping a connected CLI continuation aborts its application turn',
  async body({cdp,dataDir,dbPath}) {
    const threadId=await openApplication(cdp,dataDir,dbPath,378);
    await sendChatMessage(cdp,'CANCEL_AFTER_TOOL');
    const deadline=Date.now()+15000;
    while(codexRequests(dataDir).length<2&&Date.now()<deadline)await sleep(50);
    assert.equal(codexRequests(dataDir).length,2,'No CLI continuation reached the pending tool state');
    await cdp.click('#chat-send-btn');
    await waitStreamingIdle(cdp,10000);
    const requests=readLines(path.join(os.tmpdir(),'example-protocol-log.jsonl'));
    assert.ok(requests.some(r=>r.method==='turn.abort'));
    assert.equal(requests.filter(r=>r.method==='turn.commit').length,0);
    assert.equal(seed.query(dbPath,'SELECT id FROM messages WHERE thread_id=? AND role=\'assistant\'',[threadId]).length,0);
    return 'Stop cancelled the CLI process tree and aborted the pending application transaction';
  }
});

scenarios.push({regression:true,id:377,name:'Usage bar retains previous stats while streaming and reloading the same thread',mode:'sse-slow',settings:{threadTitles:{enabled:false}},
  fixtures:{threads:[{id:'t-usage-377',title:'Usage retention',active_leaf_id:'u-usage-377',model_override:'deepseek/deepseek-v4-flash',cumulative_input_tokens:8000,cumulative_output_tokens:1200,cumulative_cached_tokens:4000,cumulative_cost:0.25}],
    messages:[{id:'u-usage-377',thread_id:'t-usage-377',role:'user',content:'Earlier prompt',token_count:300,active_path_tokens:5000}]},
  async body({cdp}) {
    await showChat();await cdp.eval('window.loadThread("t-usage-377"); true');
    await cdp.waitFor('document.getElementById("tokenBar").textContent.includes("8k")',10000,100,'nonzero previous stats');
    const before=await cdp.eval('document.getElementById("tokenBar").innerHTML');
    await sendChatMessage(cdp,'Please continue with a slow response');
    await cdp.waitFor('streamState.active',10000,50,'response streaming');
    assert.equal(await cdp.eval('document.getElementById("tokenBar").innerHTML'),before,'Stats reset when stream began');
    await cdp.eval('window.loadThread("t-usage-377"); true');
    await cdp.waitFor('window.activeThreadId==="t-usage-377" && streamState.active',10000,50,'stream restored');
    assert.equal(await cdp.eval('document.getElementById("tokenBar").innerHTML'),before,'Stats reset during thread reload');
    await waitStreamingIdle(cdp,20000);
    await cdp.waitFor('document.getElementById("tokenBar").innerHTML!=='+JSON.stringify(before),5000,50,'stats updated after final response');
    return 'All four prior usage values survived streaming/reload and changed only after completion';
  }
});

module.exports=scenarios;
