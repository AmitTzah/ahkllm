'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const assert = require('node:assert/strict');
const {CDP} = require('../cdp');
const launcher = require('../launch');
const {launchApplicationPackage} = require('../application-launcher');
const seed = require('../seed');
const {showChat, runProbe, sleep, sendChatMessage, waitStreamingIdle} = require('./helpers');

const scenario = {
  id: 366,
  name: 'Generic application launcher opens a persisted chat, executes tools, and replays their history on follow-up',
  regression: true,
  mode: 'sse-success',
  settings: {threadTitles: {enabled: true},newChatStartsWith:'chatgpt/gpt-5.6-luna'},
  fixtures: {threads:[{id:'t-background-other',title:'Other chat',active_leaf_id:'u-background-other'}],messages:[{id:'u-background-other',thread_id:'t-background-other',role:'user',content:'Unrelated conversation'}]},
  mockOpts: {chatGptPlan: true, planApplicationTool: true, planDelay: 400, planSkipReasoningDeltas:true, planText: 'APPLICATION ANSWER', planAfterToolText: 'APPLICATION ANSWER'},
  launchEnv: ({endpoint}) => ({
    AHKLLM_E2E_PLAN_AUTH: 'fixture',
    AHKLLM_E2E_CHATGPT_RESPONSES_ENDPOINT: endpoint.replace('/v1/chat/completions', '/v1/responses'),
    AHKLLM_E2E_CHATGPT_MODELS_ENDPOINT: endpoint.replace('/v1/chat/completions', '/v1/models')
  }),
  async body({cdp, dataDir, dbPath, mockLog, port, endpoint}) {
    fs.mkdirSync(path.join(launcher.REPO_ROOT, '.tools'), {recursive: true});
    await showChat();
    const profile = {id: 'example', name: 'Example application', command: [launcher.AHK, path.join(launcher.REPO_ROOT, 'tests/fixtures/external-application.ahk')], timeout_seconds: 5};
    fs.writeFileSync(path.join(dataDir, 'applications.json'), JSON.stringify({example: profile}));
    const packagePath = path.join(dataDir, 'application-package.json');
    fs.writeFileSync(packagePath, JSON.stringify({protocol: 'ahkllm.external-applications', version: 1, request_id: 'example-366', application_id: 'example', title: 'Connected example (author title)', instructions: 'Use the supplied application tools.', message: 'Visible prepared task', initial_input: 'EXACT PRELOADED APPLICATION CONTEXT\n'+ 'canonical text '.repeat(12000), state: {checkpoint: 0}, await_first_message: !!this.composeFirst}));
    const info = runProbe('chat-info');
    const result = await launchApplicationPackage(packagePath,dataDir,info.hwnd);
    if (result.status !== 0) throw new Error('Application launch failed: ' + result.stderr + result.stdout);
    const row = seed.query(dbPath, "SELECT thread_id FROM application_sessions WHERE request_id='example-366'")[0];
    if (!row) throw new Error('Application chat was not persisted');
    await cdp.waitFor('window.activeThreadId === ' + JSON.stringify(row.thread_id), 12000, 100, 'connected thread opened');
    const initialModel = this.http ? 'openai/gpt-5-mini' : 'chatgpt/gpt-5.6-luna';
    await cdp.waitFor('window._currentSettings?.model === '+JSON.stringify(initialModel)+' && window._currentSettings.systemMessage === "Use the supplied application tools."', 5000, 100, 'imported chat honors New Chats Start With and task instructions');
    if (this.http && !await cdp.eval('window._currentSettings.assistantName === "Default application assistant" && window._currentSettings.reasoning === "medium"')) throw new Error('Imported chat lost configured assistant or its reasoning');
    const model = this.http ? 'deepseek/deepseek-v4-flash' : 'chatgpt/gpt-5.6-luna';
    await cdp.eval('Object.assign(window._currentSettings, {model:' + JSON.stringify(model) + ', assistantName:"", systemMessage:"Use the supplied application tools.", systemOverrideSet:true, reasoning:"medium", reasoningOverrideSet:true, temperature:"", webSearch:false, imageGeneration:false}); window._sendAllSettings(true); true');
    await cdp.waitFor('window._currentSettings?.model === '+JSON.stringify(model), 5000, 100, 'selected model synchronized');
    try {
      await cdp.waitFor('document.getElementById("applicationPanel") && (window._applicationState?.awaitingFirstMessage || document.getElementById("applicationPanel").textContent.includes("Run prepared request"))', 15000, 100, 'application actions');
    } catch (error) {
      throw new Error(error.message + ': ' + await cdp.eval('JSON.stringify({state:window._applicationState,panel:document.getElementById("applicationPanel")?.textContent})'));
    }
    if (this.composeFirst) {
      assert.equal(seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='"+row.thread_id+"'").length,0,'Prepared chat fabricated a message');
      const before=fs.existsSync(mockLog)?fs.readFileSync(mockLog,'utf8'):'';
      assert.ok(!before.includes(this.http?'/chat/completions':'/responses'),'Prepared chat started a model request before Send');
      runProbe('kill-chat');
      await showChat();
      await cdp.eval('window.loadThread('+JSON.stringify(row.thread_id)+'); true');
      await cdp.waitFor('window._applicationState?.awaitingFirstMessage && !Array.from(document.querySelectorAll("#applicationPanel button")).some(b=>b.textContent==="Run prepared request")',10000,100,'empty prepared chat resumes');
      const message='Discuss the character motivation.\n\nThen consider the next chapter. \u03a9';
      await sendChatMessage(cdp,message);
      const savedDeadline=Date.now()+10000;
      while (!seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='"+row.thread_id+"' AND role='user'").length && Date.now()<savedDeadline) await sleep(100);
      const saved=seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='"+row.thread_id+"' AND role='user'")[0];
      assert.equal(saved?.content,message,'First visible message differs from the author paragraphs');
    } else {
      await cdp.eval('Array.from(document.querySelectorAll("#applicationPanel button")).find(b => b.textContent === "Run prepared request").click(); true');
    }
    try { await cdp.waitFor('!!window._applicationState?.running', 5000, 100, 'connected turn running'); }
    catch(error) { throw new Error(error.message+': '+await cdp.eval('JSON.stringify({state:window._applicationState,panel:document.getElementById("applicationPanel")?.textContent,chat:document.getElementById("chat-messages")?.innerText})')); }
    await cdp.eval('window.loadThread('+JSON.stringify(row.thread_id)+'); true');
    await cdp.waitFor('!!window._applicationState?.running && !document.getElementById("applicationPanel").querySelector("button")', 5000, 100, 'running turn does not offer recovery');
    runProbe('kill-chat'); // GUI Close invokes Hide, the same operation as Ctrl+W.
    await cdp.eval('window.loadThread("t-background-other"); true');
    await cdp.waitFor('window.activeThreadId === "t-background-other"', 5000, 100, 'switch away from connected turn');
    const deadline=Date.now()+25000;
    while (!seed.query(dbPath, "SELECT id FROM messages WHERE thread_id='"+row.thread_id+"' AND role='assistant'").length && Date.now()<deadline) await sleep(100);
    if (!seed.query(dbPath, "SELECT id FROM messages WHERE thread_id='"+row.thread_id+"' AND role='assistant'").length) throw new Error('Hidden background connected turn did not finish');
    await showChat();
    await cdp.eval('window.loadThread('+JSON.stringify(row.thread_id)+'); true');
    await waitStreamingIdle(cdp, 25000);
    const title=seed.query(dbPath,"SELECT title FROM chat_threads WHERE id='"+row.thread_id+"'")[0].title;
    if (title !== 'Connected example (author title)') throw new Error('Auto-title replaced application title: '+title);
    await cdp.waitFor('document.getElementById("chat-messages").textContent.includes("APPLICATION ANSWER")', 10000, 100, 'application answer');
    const persisted=seed.query(dbPath,"SELECT reasoning FROM messages WHERE thread_id='"+row.thread_id+"' AND role='assistant' ORDER BY rowid LIMIT 1")[0];
    assert.ok(persisted.reasoning.includes('Using echo_text') && persisted.reasoning.includes('Finished echo_text'),'Tool activity disappeared from saved history');
    if (!this.http) assert.ok(persisted.reasoning.includes('Comparing the requested information'),'Final-only public reasoning summary was lost');
    await cdp.waitFor('Array.from(document.querySelectorAll(".thinking-content")).some(node=>node.textContent.includes("Finished echo_text"))',5000,100,'saved tool activity visible after reopening chat');
    await cdp.waitFor('window._applicationState?.threadId === '+JSON.stringify(row.thread_id)+' && window._applicationState.connected && !window._applicationState.running && !document.getElementById("applicationPanel").open', 5000, 100, 'task controls collapse after completion');
    const aligned = await cdp.eval('(() => { const panel=document.getElementById("applicationPanel"); const composer=document.querySelector("#chat-input-area .composer-inner"); const p=panel.getBoundingClientRect(), c=composer.getBoundingClientRect(); return panel.tagName==="DETAILS" && panel.parentElement.id==="chat-input-area" && Math.abs(p.left-c.left)<2 && Math.abs(p.width-c.width)<2; })()');
        if (!aligned) {
      const shot=await cdp.send('Page.captureScreenshot',{format:'png'});
      fs.writeFileSync(path.join(launcher.REPO_ROOT,'.tools','application-task-panel-smoke.png'),Buffer.from(shot.data,'base64'));
      throw new Error('Task controls are not aligned with the composer: '+await cdp.eval('JSON.stringify({panel:document.getElementById("applicationPanel").getBoundingClientRect(),composer:document.querySelector("#chat-input-area .composer-inner").getBoundingClientRect(),parent:document.getElementById("applicationPanel").parentElement.id})'));
    }
    await cdp.click('#applicationPanel summary');
    if (!await cdp.eval('document.getElementById("applicationPanel").open')) throw new Error('Task controls did not expand');
    const panelShot=this.http && await cdp.send('Page.captureScreenshot',{format:'png'});
    if (panelShot) fs.writeFileSync(path.join(launcher.REPO_ROOT,'.tools','application-task-panel-smoke.png'),Buffer.from(panelShot.data,'base64'));
    await cdp.click('#applicationPanel summary');
    await waitStreamingIdle(cdp, 25000);
    await cdp.waitFor('window._currentSettings?.model === '+JSON.stringify(model), 5000, 100, 'selected model restored after background completion');
    await sendChatMessage(cdp, 'Continue the connected example');
    await waitStreamingIdle(cdp, 25000);
    const requests = fs.readFileSync(mockLog, 'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse).filter(entry => String(entry.url).includes(this.http ? '/chat/completions' : '/responses'));
    if (requests.length < 3) throw new Error('No application tool continuation and follow-up were sent');
    const logPath=path.join(os.tmpdir(),'LLM_API_Log.json');
    const destination=this.http?endpoint:endpoint.replace('/v1/chat/completions','/v1/responses');
    const entries=JSON.parse(fs.readFileSync(logPath,'utf8')).filter(entry=>entry.endpoint===destination).reverse();
    assert.equal(entries.length,requests.length,'Each provider request must have its own log entry');
    entries.forEach((entry,index)=>{
      const body=entry.request_archive?fs.readFileSync(path.join(logPath+'.bodies',entry.request_archive),'utf8'):entry.request;
      const actual=typeof requests[index].body==='string'?JSON.parse(requests[index].body):requests[index].body;
      assert.deepEqual(JSON.parse(body),actual,'Logged payload differs from bytes received by the mock provider');
      assert.ok(entry.endpoint.endsWith(requests[index].url),'Logged destination differs from the actual request route');
      assert.ok(entry.request_archive,'Large request was not retained in full');
      if (!this.http) {
        const responseText=entry.response_archive?fs.readFileSync(path.join(logPath+'.bodies',entry.response_archive),'utf8'):entry.response;
        const response=JSON.parse(responseText);
        assert.equal(response.status,'completed');
        assert.ok(response.id && response.usage && Array.isArray(response.output),'Final response metadata is missing');
        assert.ok(!responseText.includes('response.output_text.delta'),'Response log contains token delta events');
        if (index>0) assert.equal(response.output_text,'APPLICATION ANSWER');
      }
    });
    if (this.http) {
      await cdp.eval('window.Ipc.postToHost("showApiLogs",{}); true');
      const target=await launcher.findTarget(port,'api-logs.html',10000);
      if (!target) throw new Error('API log viewer did not initialize');
      const viewer=await CDP.connect(target.webSocketDebuggerUrl);
      try {
        await viewer.waitFor('typeof reloadLogs === "function" && typeof ApiLogPreview !== "undefined"',10000,100,'API log viewer loaded');
        await viewer.eval('reloadLogs(); true');
        await viewer.waitFor('logData.length > 0',10000,100,'API log entries loaded');
        const actualBody=await viewer.eval('ApiLogPreview.fullBody(logData[0],"request")');
        assert.deepEqual(JSON.parse(actualBody),typeof requests.at(-1).body==='string'?JSON.parse(requests.at(-1).body):requests.at(-1).body);
        await viewer.eval('td(0)');
        if (!await viewer.eval('document.getElementById("rq-0").textContent.includes("omitted from preview")')) throw new Error('Large API request preview did not omit its middle');
        await viewer.eval('toggleFull(0,document.querySelector("#det-0 .copy-btn:last-child"))');
        if (!await viewer.eval('document.getElementById("rq-0").textContent.includes("canonical text ".repeat(200))')) throw new Error('Full payload toggle did not restore the retained content');
        await viewer.send('Emulation.setDeviceMetricsOverride',{width:1100,height:700,deviceScaleFactor:1,mobile:false});
        await viewer.eval('toggleFull(0,document.querySelector("#det-0 .copy-btn:last-child"))');
        const shot=await viewer.send('Page.captureScreenshot',{format:'png'});
        fs.writeFileSync(path.join(launcher.REPO_ROOT,'.tools','api-log-payload-smoke.png'),Buffer.from(shot.data,'base64'));
      } finally { await viewer.close(); }
    }
    const first = typeof requests[0].body === 'string' ? JSON.parse(requests[0].body) : requests[0].body;
    const last = typeof requests.at(-1).body === 'string' ? JSON.parse(requests.at(-1).body) : requests.at(-1).body;
    if (!JSON.stringify(this.http ? first.messages : first.input).includes('EXACT PRELOADED APPLICATION CONTEXT')) throw new Error('Initial context was lost');
    const hasToolOutput = this.http ? last.messages.some(item => item.role === 'tool' && item.content.includes('APPLICATION TOOL RESULT')) : last.input.some(item => item.type === 'function_call_output' && item.output.includes('APPLICATION TOOL RESULT'));
    if (!hasToolOutput) throw new Error('Tool history was lost on follow-up');
    const checkpoint = seed.query(dbPath, "SELECT n.state_json FROM application_nodes n JOIN messages m ON m.id=n.message_id WHERE m.thread_id='" + row.thread_id + "' ORDER BY m.rowid DESC LIMIT 1")[0];
    if (!checkpoint || JSON.parse(checkpoint.state_json).checkpoint < 1) throw new Error('Committed application checkpoint was not saved');
    const marker=path.join(os.tmpdir(),'example-context-changed.flag');
    fs.writeFileSync(marker,'changed');
    try {
      const firstReply=seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='"+row.thread_id+"' AND role='assistant' ORDER BY rowid LIMIT 1")[0].id;
      await cdp.eval('window.Ipc.postToHost("retry",{messageId:'+JSON.stringify(firstReply)+'}); true');
      const retryDeadline=Date.now()+25000;
      while (seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='"+row.thread_id+"' AND role='assistant'").length<3 && Date.now()<retryDeadline) await sleep(100);
      assert.equal(seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='"+row.thread_id+"' AND role='assistant'").length,3,'Stale regeneration did not finish automatically');
      await waitStreamingIdle(cdp,25000);
      assert.ok(seed.query(dbPath,"SELECT id FROM messages WHERE id='"+firstReply+"'").length,'Regeneration removed the previous response');
      const retryRequests=fs.readFileSync(mockLog,'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse).filter(entry=>String(entry.url).includes(this.http?'/chat/completions':'/responses'));
      const retryBody=typeof retryRequests.at(-1).body==='string'?JSON.parse(retryRequests.at(-1).body):retryRequests.at(-1).body;
      assert.ok(JSON.stringify(this.http?retryBody.messages:retryBody.input).includes('AUTOMATIC CURRENT CONTEXT'),'Retry did not send automatically reconciled context');
      assert.ok(!(retryBody.tools||[]).some(tool=>(tool.function?.name||tool.name)==='echo_text'),'Retry used stale tool permissions');
      const reconciled=seed.query(dbPath,"SELECT n.state_json,n.replay_json FROM application_nodes n JOIN messages m ON m.id=n.message_id WHERE m.thread_id='"+row.thread_id+"' ORDER BY m.rowid DESC LIMIT 1")[0];
      assert.equal(JSON.parse(reconciled.state_json).checkpoint,11,'Retry committed using the obsolete checkpoint');
      assert.ok(reconciled.replay_json.includes('AUTOMATIC CURRENT CONTEXT'),'Reconciled context was not persisted for subsequent turns');
      await sendChatMessage(cdp,'Continue after automatic reconciliation');
      await waitStreamingIdle(cdp,25000);
      const continued=fs.readFileSync(mockLog,'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse).filter(entry=>String(entry.url).includes(this.http?'/chat/completions':'/responses')).at(-1);
      assert.ok(JSON.stringify(continued.body).includes('AUTOMATIC CURRENT CONTEXT'),'Reconciled context disappeared on follow-up');
    } finally { fs.unlinkSync(marker); }
    return 'Public launcher, generic UTF-8 tools, complete initial context, exact tool replay, and committed checkpoint verified';
  }
};
const httpScenario = Object.assign({}, scenario, {
  id: 367, http: true,
  name: 'Generic application tools and durable replay work with an OpenAI-compatible HTTP provider',
  mode: 'sse-tool-call', mockOpts: {applicationTool:true, chatText:'APPLICATION ANSWER',chunkDelay:400},
  settings:{threadTitles:{enabled:true},newChatStartsWith:'asst:app-default',assistants:[{id:'app-default',name:'Default application assistant',baseModel:'openai/gpt-5-mini',systemMessage:'Assistant prompt must not replace app instructions.',reasoning:'medium',temperature:'',isDefault:true}]},
  launchEnv: null
});
module.exports = [scenario, httpScenario,
  Object.assign({},scenario,{id:369,composeFirst:true,name:'Prepared application chat waits for a multiline first message and resumes with full Responses context'}),
  Object.assign({},httpScenario,{id:370,composeFirst:true,name:'Prepared application chat waits for its first message and preserves context with HTTP tools'})];
