'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const seed = require('../seed');
const {openPreparedApplication} = require('../application-session');
const {installFakeCodex,fakeCodexEnvironment} = require('../codex-fixture');
const {showChat,sendChatMessage,waitStreamingIdle,openSettings,openSection,saveSettings,sleep} = require('./helpers');

const requests = file => fs.readFileSync(file,'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse);

async function waitForCodexFailureLog(expected) {
  const file=path.join(os.tmpdir(),'LLM_API_Log.json'), deadline=Date.now()+5000;
  while (Date.now()<deadline) {
    try {
      const entry=JSON.parse(fs.readFileSync(file,'utf8')).find(e=>e.status==='error' && String(e.model).startsWith('codex/') && e.response.includes(expected));
      if (entry) return entry;
    } catch {}
    await sleep(50);
  }
  throw new Error('Codex error UI completed but its correlated API log was not retained');
}

function configureXiaomi(dataDir,endpoint) {
  const file = path.join(dataDir,'settings.json'), settings=JSON.parse(fs.readFileSync(file,'utf8'));
  settings.providers.xiaomi={displayName:'Xiaomi MiMo',endpoint,authEnvVar:'MIMO_API_KEY',modelsDevProvider:'xiaomi',toolCallingMode:'native',prefixes:['mimo']};
  fs.writeFileSync(file,JSON.stringify(settings));
}

const scenarios=[380,382].map(id=>({
  id,regression:true,name:id===380?'Xiaomi native thinking tools retain exact reasoning across rounds, reload and follow-up':'Xiaomi non-thinking native application tools explicitly disable thinking',
  mode:'sse-tool-call',preLaunch:configureXiaomi,launchEnv:()=>({MIMO_API_KEY:'mimo-fixture-key'}),
  settings:{threadTitles:{enabled:false},newChatStartsWith:'xiaomi/mimo-v2.6-pro'},
  mockOpts:{xiaomiNative:true,applicationTool:true,toolRounds:2,chatText:'MIMO APPLICATION ANSWER',responseModel:'mimo-v2.6-pro'},
  async body({cdp,dataDir,dbPath,mockLog}) {
    const threadId=await openPreparedApplication(cdp,dataDir,dbPath,id);
    await cdp.eval('Object.assign(window._currentSettings,{reasoning:'+JSON.stringify(id===382?'none':'high')+'}); true');
    await sendChatMessage(cdp,'Use native functions and answer.');await waitStreamingIdle(cdp,25000);
    const first=seed.query(dbPath,'SELECT * FROM messages WHERE thread_id=? AND role=\'assistant\' ORDER BY rowid',[threadId])[0];
    assert.ok(first?.content.includes('MIMO APPLICATION ANSWER'),'MiMo native tools did not complete');
    const node=seed.query(dbPath,'SELECT * FROM application_nodes WHERE message_id=?',[first.id])[0];
    const replay=JSON.parse(node.replay_json);
    assert.equal(replay.filter(i=>i.type==='function_call').length,2);
    assert.deepEqual(replay.filter(i=>i.reasoning_content).map(i=>i.reasoning_content),['MiMo exact round 0 Ω','MiMo exact round 1 Ω','MiMo final reasoning Ω']);
    assert.equal(JSON.parse(node.state_json).checkpoint,1);
    await cdp.eval('window.loadThread('+JSON.stringify(threadId)+'); true');
    await cdp.waitFor('window._currentSettings?.model === "xiaomi/mimo-v2.6-pro"',5000,100,'MiMo model restored');
    await sendChatMessage(cdp,'Continue with the preserved native history.');await waitStreamingIdle(cdp,25000);
    const http=requests(mockLog).filter(r=>r.url.includes('/chat/completions'));
    assert.equal(http.length,6,'Both turns must execute two native tool rounds and a final response');
    assert.ok(http.every(r=>r.body.thinking.type===(id===382?'disabled':'enabled')));
    assert.ok(http.every(r=>r.body.tools.some(t=>t.function?.name==='echo_text')));
    assert.ok(http.at(-1).body.messages.some(m=>m.reasoning_content==='MiMo final reasoning Ω'));
    assert.ok(http.every(r=>!JSON.stringify(r.body.messages).includes('Using echo_text')),'UI tool activity leaked into provider reasoning');
    if (id===380) {
      await cdp.eval('Ipc.postToHost("forkChat",{id:'+JSON.stringify(first.id)+'}); true');
      await cdp.waitFor('window.activeThreadId !== '+JSON.stringify(threadId)+' && window._currentSettings?.model === "xiaomi/mimo-v2.6-pro"',10000,100,'native application fork opened');
      await sendChatMessage(cdp,'Continue the fork with its exact tool reasoning.');await waitStreamingIdle(cdp,25000);
      const forkRequests=requests(mockLog).filter(r=>r.url.includes('/chat/completions')).slice(6);
      assert.equal(forkRequests.length,3);
      assert.ok(forkRequests[0].body.messages.some(m=>m.tool_calls && m.reasoning_content==='MiMo exact round 0 Ω'));
      assert.ok(forkRequests[0].body.messages.some(m=>m.reasoning_content==='MiMo final reasoning Ω'));
    }
    return 'Native MiMo auth, thinking toggle, two tool rounds, immutable exact reasoning and follow-up verified';
  }
}));

for (const [id,prompt,expected] of [[381,'codex structured failure','Mock context exceeded'],[383,'codex banner only failure','No failure detail was returned']]) scenarios.push({
  id,regression:true,name:'Codex failure reports '+(id===381?'structured JSONL detail and valid error JSON':'exit code instead of its stdin banner'),mode:'sse-success',
  preLaunch:dataDir=>{installFakeCodex(dataDir);fs.writeFileSync(path.join(os.tmpdir(),'LLM_API_Log.json'),'[]');},launchEnv:fakeCodexEnvironment,settings:{threadTitles:{enabled:false}},
  fixtures:{threads:[{id:'t-codex-error-'+id,title:'Codex error',active_leaf_id:'u-error-'+id,model_override:'codex/gpt-5.6-luna'}],messages:[{id:'u-error-'+id,thread_id:'t-codex-error-'+id,role:'user',content:'Earlier message'}]},
  async body({cdp}) {
    await showChat();await cdp.eval('window.loadThread('+JSON.stringify('t-codex-error-'+id)+'); true');
    await cdp.waitFor('window._currentSettings?.model === "codex/gpt-5.6-luna"',10000,100,'Codex selected');
    await sendChatMessage(cdp,prompt);await waitStreamingIdle(cdp,20000);
    await cdp.waitFor('document.getElementById("chat-messages").textContent.includes('+JSON.stringify(expected)+')',5000,100,'useful Codex error');
    assert.ok(!await cdp.eval('document.getElementById("chat-messages").textContent.includes("Reading prompt from stdin")'));
    const failure=await waitForCodexFailureLog(expected);
    const detail=JSON.parse(failure.response).error.message;
    assert.ok(detail.includes('code '+(id===381?6:8)) && detail.includes(expected));
    return 'CLI failure detail and exit code survived temp cleanup and are valid retained JSON';
  }
});
scenarios.push({id:384,regression:true,name:'Xiaomi provider preset is addable and saves alongside existing providers',mode:'sse-success',settings:{threadTitles:{enabled:false}},
  async body({cdp,dataDir}) {
    await showChat();await openSettings(cdp);await openSection(cdp,'providers');
    await cdp.click('#addXiaomiProviderBtn');
    await cdp.waitFor('window.SettingsProviders.getCurrentProviders().xiaomi?.endpoint === "https://api.xiaomimimo.com/v1/chat/completions"',5000,100,'Xiaomi preset populated');
    await saveSettings(cdp,dataDir);
    const settings=JSON.parse(fs.readFileSync(path.join(dataDir,'settings.json'),'utf8').replace(/^\uFEFF/,''));
    assert.ok(settings.providers.deepseek && settings.providers.openai,'Adding MiMo removed another provider');
    assert.equal(settings.providers.xiaomi.authEnvVar,'MIMO_API_KEY');
    assert.equal(settings.providers.xiaomi.toolCallingMode,'native');
    assert.equal(settings.providers.xiaomi.modelsDevProvider,'xiaomi');
    return 'Xiaomi preset saved with native tools, catalog and environment auth; existing providers preserved';
  }
});
module.exports=scenarios;
