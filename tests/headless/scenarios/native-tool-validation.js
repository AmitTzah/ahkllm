'use strict';
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const assert=require('node:assert/strict');
const seed=require('../seed');
const {openPreparedApplication}=require('../application-session');
const {sendChatMessage,waitStreamingIdle}=require('./helpers');
const lines=file=>fs.existsSync(file)?fs.readFileSync(file,'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse):[];
const rpc=()=>lines(path.join(os.tmpdir(),'example-protocol-log.jsonl'));
const api=()=>JSON.parse(fs.readFileSync(path.join(os.tmpdir(),'LLM_API_Log.json'),'utf8').replace(/^\uFEFF/,''));

function configure(dataDir,endpoint) {
  fs.writeFileSync(path.join(os.tmpdir(),'example-protocol-log.jsonl'),'');
  fs.writeFileSync(path.join(os.tmpdir(),'LLM_API_Log.json'),'[]');
  const file=path.join(dataDir,'settings.json'), settings=JSON.parse(fs.readFileSync(file,'utf8'));
  settings.providers.xiaomi={displayName:'Xiaomi MiMo',endpoint,authEnvVar:'MIMO_API_KEY',toolCallingMode:'native'};
  fs.writeFileSync(file,JSON.stringify(settings));
}
const base={regression:true,mode:'sse-tool-call',preLaunch:configure,
  settings:{threadTitles:{enabled:false},newChatStartsWith:'xiaomi/mimo-v2.6-pro'},
  launchEnv:()=>({MIMO_API_KEY:'mimo-fixture-key'})};

const scenarios=['double-encoded','malformed','schema'].map((mode,index)=>({...base,id:385+index,name:'Native MiMo corrects '+mode+' arguments before application execution',
  mockOpts:{xiaomiNative:true,applicationTool:true,toolRounds:2,nativeArgumentCase:mode,chatText:'NATIVE CORRECTED ANSWER'},
  async body({cdp,dataDir,dbPath,mockLog}) {
    const threadId=await openPreparedApplication(cdp,dataDir,dbPath,this.id);
    await cdp.eval('window._currentSettings.reasoning="high"; true');
    await sendChatMessage(cdp,'Use native tools with validation.');await waitStreamingIdle(cdp,25000);
    const assistant=seed.query(dbPath,'SELECT * FROM messages WHERE thread_id=? AND role=\'assistant\'',[threadId])[0];
    assert.ok(assistant?.content.includes('NATIVE CORRECTED ANSWER'));
    assert.equal(rpc().filter(r=>r.method==='tools.call').length,1,'Invalid arguments reached the application');
    assert.equal(rpc().filter(r=>r.method==='turn.commit').length,1);
    assert.equal(rpc().filter(r=>r.method==='turn.abort').length,0);
    const requests=lines(mockLog).filter(r=>r.url.includes('/chat/completions'));
    assert.equal(requests.length,3);
    const feedback=JSON.parse(requests[1].body.messages.find(m=>m.role==='tool').content);
    assert.equal(feedback.error,'invalid_tool_arguments');assert.equal(feedback.ok,false);
    assert.ok(feedback.message.includes('echo_text'));
    assert.ok(assistant.reasoning.includes('Rejected echo_text'));
    const logged=api().filter(e=>e.requestKind==='application tool-call round');
    assert.equal(logged.length,2);
    assert.equal(JSON.parse(logged.at(-1).response).choices[0].message.tool_calls[0].function.arguments,requests[1].body.messages.find(m=>m.tool_calls).tool_calls[0].function.arguments);
    for (const entry of logged) {
      const body=JSON.parse(entry.response), raw=body._ahkllm_stream_diagnostics.raw_response;
      assert.ok(raw.startsWith('data: ') && raw.includes('data: [DONE]'),'Original SSE framing or final marker lost');
      const events=raw.split(/\r?\n/).filter(line=>line.startsWith('data: {')).map(line=>JSON.parse(line.slice(6)));
      const fragments=events.flatMap(e=>(e.choices||[]).flatMap(c=>c.delta?.tool_calls||[]));
      const assembled=fragments.filter(c=>c.index===0).map(c=>c.function?.arguments||'').join('');
      assert.equal(assembled,body.choices[0].message.tool_calls[0].function.arguments,'Raw provider fragments differ from assembled arguments');
      assert.equal(fragments[0].id,body.choices[0].message.tool_calls[0].id);
      assert.ok(events.some(e=>e.choices?.[0]?.finish_reason==='tool_calls'),'Original finish reason not retained');
      assert.equal(events.filter(e=>e.choices?.[0]?.delta?.reasoning_content).length,1,'Raw capture included another round');
    }
    return 'Invalid call rejected locally; exact reasoning and call-ID feedback survived; corrected call executed once and committed';
  }
}));

for (const [id,mode,expected] of [[388,'repeated','3 invalid argument rounds'],[389,'adapter-error',"'str' object has no attribute 'get'"]]) scenarios.push({...base,id,name:'Native application '+mode+' failure aborts, retains diagnostics and permits a fresh send',
  mockOpts:{xiaomiNative:true,applicationTool:true,toolRounds:mode==='repeated'?3:1,nativeArgumentCase:mode,chatText:'NATIVE RECOVERY ANSWER'},
  async body({cdp,dataDir,dbPath}) {
    const threadId=await openPreparedApplication(cdp,dataDir,dbPath,id);
    await cdp.eval('window._currentSettings.reasoning="high"; true');
    await sendChatMessage(cdp,'Exercise native application failure.');await waitStreamingIdle(cdp,25000);
    await cdp.waitFor('document.getElementById("chat-messages").textContent.includes('+JSON.stringify(expected)+')',5000,100,'application error surfaced');
    assert.ok(!await cdp.eval('document.getElementById("chat-messages").textContent.includes("Web search failed")'));
    assert.equal(rpc().filter(r=>r.method==='tools.call').length,mode==='repeated'?0:1);
    assert.equal(rpc().filter(r=>r.method==='turn.abort').length,1);
    assert.equal(rpc().filter(r=>r.method==='turn.commit').length,0);
    const failure=api().find(e=>e.requestKind==='application tool failure');
    assert.ok(failure && failure.status==='error');
    const detail=JSON.parse(failure.response);
    assert.ok(detail._ahkllm_stream_diagnostics.raw_response.includes('data: [DONE]'),'Fatal failure deleted its provider stream before capture');
    assert.equal(detail.application_tool_calls[0].name,'echo_text');
    assert.ok(detail.application_tool_calls[0].arguments.includes(mode==='repeated'?'APPLICATION TOOL RESULT':'NATIVE ADAPTER FAIL'));
    assert.ok(detail.error.message.includes('Application tool failed:'));
    await sendChatMessage(cdp,'Recover native tools using valid arguments.');await waitStreamingIdle(cdp,25000);
    assert.ok(seed.query(dbPath,'SELECT content FROM messages WHERE thread_id=? AND role=\'assistant\'',[threadId]).some(r=>r.content.includes('NATIVE RECOVERY ANSWER')));
    assert.equal(rpc().filter(r=>r.method==='turn.commit').length,1);
    return 'Fatal application failure retained raw call diagnostics, aborted once, released ownership and a fresh send completed';
  }
});

scenarios.push({...base,id:390,name:'Native Responses application arguments use the same correction and validation path',mode:'sse-success',
  settings:{threadTitles:{enabled:false},newChatStartsWith:'chatgpt/gpt-5.6-luna'},
  mockOpts:{chatGptPlan:true,planApplicationTool:true,nativeArgumentCase:'double-encoded',planText:'NATIVE RESPONSES ANSWER',planAfterToolText:'NATIVE RESPONSES ANSWER',planDelay:100},
  launchEnv:({endpoint})=>({AHKLLM_E2E_PLAN_AUTH:'fixture',AHKLLM_E2E_CHATGPT_RESPONSES_ENDPOINT:endpoint.replace('/v1/chat/completions','/v1/responses'),AHKLLM_E2E_CHATGPT_MODELS_ENDPOINT:endpoint.replace('/v1/chat/completions','/v1/models')}),
  async body({cdp,dataDir,dbPath,mockLog}) {
    const threadId=await openPreparedApplication(cdp,dataDir,dbPath,390);
    await sendChatMessage(cdp,'Use native Responses functions.');await waitStreamingIdle(cdp,25000);
    assert.ok(seed.query(dbPath,'SELECT content FROM messages WHERE thread_id=? AND role=\'assistant\'',[threadId])[0]?.content.includes('NATIVE RESPONSES ANSWER'));
    assert.equal(rpc().filter(r=>r.method==='tools.call').length,1);
    const requests=lines(mockLog).filter(r=>r.url.includes('/responses'));
    assert.equal(requests.length,3);
    assert.equal(JSON.parse(requests[1].body.input.find(i=>i.type==='function_call_output').output).error,'invalid_tool_arguments');
    const logs=api().filter(e=>e.status==='success' && e.requestKind==='tool-call round');
    assert.equal(logs.length,2);
    for (const entry of logs) {
      const response=JSON.parse(entry.response);
      assert.ok(response._ahkllm_stream_diagnostics.raw_response.includes('event: response.completed'),'Responses normalization stripped raw diagnostics');
    }
    return 'Responses and MiMo share argument validation, correction feedback and unchanged application authority';
  }
});
module.exports=scenarios;
