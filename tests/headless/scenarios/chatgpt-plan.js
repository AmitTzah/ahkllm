// scenarios/chatgpt-plan.js - direct ChatGPT-plan Responses E2E coverage.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const seed = require('../seed');
const { sleep, showChat, sendChatMessage, waitStreamingIdle, openSettings, openSection, saveSettings } = require('./helpers');

const FAKE_CODEX_SCRIPT = path.join(__dirname, '..', 'fake-codex-cli.js');

function planEnv({ endpoint }) {
  return {
    AHKLLM_E2E_PLAN_AUTH: 'fixture',
    AHKLLM_E2E_CHATGPT_RESPONSES_ENDPOINT: String(endpoint).replace('/v1/chat/completions', '/v1/responses'),
    AHKLLM_E2E_CHATGPT_MODELS_ENDPOINT: String(endpoint).replace('/v1/chat/completions', '/v1/models')
  };
}
function installFakeCodex(dataDir) {
  fs.writeFileSync(path.join(dataDir, 'fake-codex.cmd'), [
    '@echo off',
    '"%FAKE_NODE_EXE%" "%FAKE_CODEX_SCRIPT%" %*',
    'exit /b %ERRORLEVEL%',
    ''
  ].join('\r\n'), 'utf8');
  fs.writeFileSync(path.join(dataDir, 'fake-codex-log.jsonl'), '', 'utf8');
}
function imageEnv({ dataDir, endpoint }) {
  return Object.assign(planEnv({ endpoint }), {
    CODEX_CLI_PATH: path.join(dataDir, 'fake-codex.cmd'),
    FAKE_NODE_EXE: process.execPath,
    FAKE_CODEX_SCRIPT: FAKE_CODEX_SCRIPT,
    FAKE_CODEX_LOG: path.join(dataDir, 'fake-codex-log.jsonl')
  });
}
function reqs(log) {
  if (!log || !fs.existsSync(log)) return [];
  return fs.readFileSync(log, 'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse);
}
function responses(log) { return reqs(log).filter((r) => String(r.url || '').includes('/responses')); }
function codexExecs(dataDir) {
  const p = path.join(dataDir, 'fake-codex-log.jsonl');
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse).filter((x) => x.kind === 'exec');
}
function th(id, leaf, title) {
  return { id: id, title: title, active_leaf_id: leaf, model_override: 'chatgpt/gpt-5.6-luna', reasoning_override: 'medium', reasoning_override_set: 1 };
}
function pair(prefix, tid, u, a) {
  return [
    { id: prefix + '-u1', thread_id: tid, role: 'user', content: u || 'seed user' },
    { id: prefix + '-a1', thread_id: tid, role: 'assistant', content: a || 'seed answer', parent_id: prefix + '-u1', model: 'chatgpt/gpt-5.6-luna' }
  ];
}
async function load(cdp, id) {
  await showChat();
  await cdp.eval('window.loadThread(' + JSON.stringify(id) + '); true');
  await cdp.waitFor('window.activeThreadId === ' + JSON.stringify(id), 12000, 100, 'thread loaded');
  if (String(id).startsWith('t-plan'))
    await cdp.waitFor('window._currentSettings && window._currentSettings.model === "chatgpt/gpt-5.6-luna"', 12000, 100, 'ChatGPT-plan model restored');
}
const base = { regression: true, mode: 'sse-success', settings: { threadTitles: { enabled: false } }, launchEnv: planEnv };
const scenarios = [];

scenarios.push(Object.assign({}, base, {
  id: 329,
  name: 'ChatGPT-plan Responses reasoning uses Thought Process and persists',
  mockOpts: { chatGptPlan: true, planDelay: 100, planReasoning: 'Comparing the requested information', planText: 'PLAN REASONING ANSWER' },
  fixtures: { threads: [th('t-plan-329','m-plan-329-a1','Plan Reasoning')], messages: pair('m-plan-329','t-plan-329','prior plan user','prior plan answer') },
  async body({ cdp, dbPath, mockLog }) {
    await load(cdp,'t-plan-329');
    await sendChatMessage(cdp,'basic plan reasoning ui');
    await cdp.waitFor('document.querySelector(".thinking-content") && document.querySelector(".thinking-content").textContent.includes("Comparing the requested information")',10000,100,'reasoning visible');
    await waitStreamingIdle(cdp,20000);
    const row=seed.query(dbPath,"SELECT content,reasoning FROM messages WHERE thread_id='t-plan-329' AND role='assistant' ORDER BY rowid DESC LIMIT 1")[0];
    if(!row||String(row.content).trim()!=='PLAN REASONING ANSWER'||!String(row.reasoning||'').includes('Comparing the requested information')) throw new Error('reasoning persistence failed: '+JSON.stringify(row));
    const r=responses(mockLog)[0]; if(!r) throw new Error('no direct Responses request');
    const body=JSON.stringify(r.body); if(!body.includes('prior plan user')||!body.includes('prior plan answer')||!body.includes('basic plan reasoning ui')) throw new Error('explicit history missing: '+body);
    if(!String(r.authorization||'').startsWith('Bearer ')) throw new Error('authorization scheme missing');
    return 'direct Responses reasoning streamed/persisted with explicit AhkLLM history';
  }
}));

scenarios.push(Object.assign({}, base, {
  id: 330,
  name: 'ChatGPT-plan Web Search toggle controls hosted web_search and citations',
  mockOpts: { chatGptPlan:true, planDelay:50, planTextMap:[{match:'search on plan',text:'SEARCH ON PLAN ANSWER'},{match:'search off plan',text:'SEARCH OFF PLAN ANSWER'}] },
  fixtures: { threads:[th('t-plan-330','m-plan-330-a1','Plan Search')], messages:pair('m-plan-330','t-plan-330') },
  async body({cdp,dbPath,mockLog}) {
    await load(cdp,'t-plan-330');
    await cdp.click('#railWebSearchToggle');
    await cdp.waitFor('window._currentSettings.webSearch===true && document.getElementById("railWebSearchToggle").classList.contains("on")',5000,100,'search on');
    await sleep(400);
    await sendChatMessage(cdp,'search on plan'); await waitStreamingIdle(cdp,20000);
    await cdp.click('#railWebSearchToggle');
    await cdp.waitFor('window._currentSettings.webSearch===false && !document.getElementById("railWebSearchToggle").classList.contains("on")',5000,100,'search off');
    await sleep(400);
    await sendChatMessage(cdp,'search off plan'); await waitStreamingIdle(cdp,20000);
    const rs=responses(mockLog); if(rs.length!==2) throw new Error('expected two Responses requests: '+JSON.stringify(rs));
    if(!JSON.stringify(rs[0].body.tools||[]).includes('"web_search"')) throw new Error('search-on omitted web_search');
    if(JSON.stringify(rs[1].body.tools||[]).includes('"web_search"')) throw new Error('search-off retained web_search');
    const rows=seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-330' AND role='assistant' ORDER BY rowid DESC LIMIT 2").reverse();
    if(!String(rows[0].content||'').includes('[source](<https://example.test/source>)')) throw new Error('citation not persisted');
    return 'hosted web_search follows toggle and citations persist';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:331,
  name:'ChatGPT-plan Stop cancels direct Responses and next Send succeeds',
  mockOpts:{chatGptPlan:true,planDelay:80,planAfterReasoningDelay:2500,planReasoning:'Beginning cancellable plan response',planText:'PLAN AFTER CANCEL ANSWER'},
  fixtures:{threads:[th('t-plan-331','m-plan-331-a1','Plan Cancel')],messages:pair('m-plan-331','t-plan-331')},
  async body({cdp,dbPath}) {
    await load(cdp,'t-plan-331'); await sendChatMessage(cdp,'cancel plan request');
    await cdp.waitFor('document.querySelector(".thinking-content") && document.querySelector(".thinking-content").textContent.includes("Beginning cancellable plan response")',10000,100,'reasoning before stop');
    await cdp.click('#chat-send-btn'); await cdp.waitFor('!isThreadRequestInFlight("t-plan-331")',10000,100,'cancel released');
    if(seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-331'").some(r=>String(r.content).includes('PLAN AFTER CANCEL ANSWER'))) throw new Error('cancel persisted final');
    await sendChatMessage(cdp,'after cancellation'); await waitStreamingIdle(cdp,20000);
    if(seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-331'").filter(r=>String(r.content).includes('PLAN AFTER CANCEL ANSWER')).length!==1) throw new Error('next request failed');
    return 'Stop cancelled direct Responses and next request completed';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:332,
  name:'ChatGPT-plan completion stays scoped to originating thread after switch',
  mockOpts:{chatGptPlan:true,planDelay:900,planReasoning:'Working on originating plan thread',planText:'THREAD A PLAN ANSWER'},
  fixtures:{threads:[th('t-plan-a-332','m-plan-a-332-a1','A'),th('t-plan-b-332','m-plan-b-332-a1','B')],messages:[...pair('m-plan-a-332','t-plan-a-332'),...pair('m-plan-b-332','t-plan-b-332')]},
  async body({cdp,dbPath}) {
    await load(cdp,'t-plan-a-332'); await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'plan model restored'); await sendChatMessage(cdp,'slow plan A');
    await cdp.waitFor('isThreadRequestInFlight("t-plan-a-332")',10000,50,'A request in flight');
    await cdp.eval('window.loadThread("t-plan-b-332"); true'); await cdp.waitFor('window.activeThreadId==="t-plan-b-332"',10000,100,'B');
    await cdp.waitFor('!isThreadRequestInFlight("t-plan-a-332")',20000,50,'A request completed in background');
    if(String(await cdp.eval('document.getElementById("chat-messages").textContent')).includes('THREAD A PLAN ANSWER')) throw new Error('A leaked into B UI');
    if(seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-a-332'").filter(r=>String(r.content).includes('THREAD A PLAN ANSWER')).length!==1) throw new Error('A did not persist under A');
    return 'originating thread retained direct Responses persistence';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:333,
  name:'ChatGPT-plan second turn sends explicit prior history and cached usage',
  mockOpts:{chatGptPlan:true,planDelay:30,planTextMap:[{match:'first plan turn',text:'FIRST PLAN ANSWER'},{match:'second plan turn',text:'SECOND PLAN ANSWER'}]},
  fixtures:{threads:[th('t-plan-333','m-plan-333-a1','History')],messages:pair('m-plan-333','t-plan-333')},
  async body({cdp,dbPath,mockLog}) {
    await load(cdp,'t-plan-333'); await sendChatMessage(cdp,'first plan turn'); await waitStreamingIdle(cdp,15000); await sendChatMessage(cdp,'second plan turn'); await waitStreamingIdle(cdp,15000);
    const rs=responses(mockLog); if(rs.length!==2) throw new Error('expected two requests');
    const second=JSON.stringify(rs[1].body.input||[]); if(!second.includes('first plan turn')||!second.includes('FIRST PLAN ANSWER')||!second.includes('second plan turn')) throw new Error('prior history missing: '+second);
    const row=seed.query(dbPath,"SELECT cached_tokens FROM messages WHERE thread_id='t-plan-333' AND role='assistant' ORDER BY rowid DESC LIMIT 1")[0]; if(!row||Number(row.cached_tokens)!==4) throw new Error('cached tokens missing');
    return 'stateless second turn replays history and cached usage persists';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:336,
  name:'Image Generation invokes isolated Codex worker and image returns as visual context',
  mockOpts:{chatGptPlan:true,planDelay:30,planImageTool:true,planImagePrompt:'generate image codex',planAfterToolText:'IMAGE TOOL COMPLETE'},
  fixtures:{threads:[Object.assign(th('t-plan-336','m-plan-336-a1','Image'),{advanced_toggles:'{"imageGeneration":true}'})],messages:pair('m-plan-336','t-plan-336')},
  preLaunch(dataDir){installFakeCodex(dataDir);},
  launchEnv:imageEnv,
  async body({cdp,dbPath,mockLog,dataDir}) {
    await load(cdp,'t-plan-336'); await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna" && window._currentSettings.imageGeneration===true && document.getElementById("railImageGenerationToggle").classList.contains("on")',10000,100,'image generation restored'); await sendChatMessage(cdp,'please generate an image'); await waitStreamingIdle(cdp,25000);
    const imageRs=responses(mockLog);
    if(imageRs.length<2) throw new Error('image tool flow did not produce initial + continuation Responses requests: '+JSON.stringify(imageRs.map(r=>r.body)));
    const firstTools=JSON.stringify(imageRs[0].body&&imageRs[0].body.tools||[]);
    if(!firstTools.includes('"namespace"') || !firstTools.includes('"ahkllm"') || !firstTools.includes('"generate_image"'))
      throw new Error('initial Responses request did not expose ahkllm.generate_image: '+firstTools);
    const continuationInput=JSON.stringify(imageRs[1].body&&imageRs[1].body.input||[]);
    if(!continuationInput.includes('"function_call_output"') || !continuationInput.includes('"call-image-1"'))
      throw new Error('tool continuation did not replay matching function_call_output: '+continuationInput);
    if(codexExecs(dataDir).length!==1)
      throw new Error('expected one Codex image worker exec; responses='+JSON.stringify(imageRs.map(r=>({tools:r.body&&r.body.tools,input:r.body&&r.body.input})))+' codex='+JSON.stringify(codexExecs(dataDir)));
    const atts=seed.query(dbPath,"SELECT a.file_path FROM message_attachments a JOIN messages m ON m.id=a.message_id WHERE m.thread_id='t-plan-336' AND m.role='assistant'"); if(!atts.length) throw new Error('generated image not persisted');
    await cdp.click('#railImageGenerationToggle'); await cdp.waitFor('window._currentSettings.imageGeneration===false',5000,50,'image off');
    await sendChatMessage(cdp,'describe previous image'); await waitStreamingIdle(cdp,15000);
    const rs=responses(mockLog); if(!JSON.stringify(rs[rs.length-1].body.input||[]).includes('"input_image"')) throw new Error('image not sent as next-turn visual context');
    return 'Responses invoked isolated Codex image worker and persisted image returned as visual context';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:339,
  name:'Concurrent ChatGPT-plan requests stay thread-scoped and stopping A leaves B running',
  mockOpts:{chatGptPlan:true,planDelay:1400,planTextMap:[{match:'concurrent A',text:'PLAN A ANSWER'},{match:'concurrent B',text:'PLAN B ANSWER'}]},
  fixtures:{threads:[th('t-plan-a-339','m-plan-a-339-a1','A'),th('t-plan-b-339','m-plan-b-339-a1','B')],messages:[...pair('m-plan-a-339','t-plan-a-339'),...pair('m-plan-b-339','t-plan-b-339')]},
  async body({cdp,dbPath}) {
    await load(cdp,'t-plan-a-339'); await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'plan model A restored'); await sendChatMessage(cdp,'concurrent A');
    await cdp.waitFor('isThreadRequestInFlight("t-plan-a-339")',10000,50,'A busy');
    await cdp.eval('window.loadThread("t-plan-b-339"); true');
    await cdp.waitFor('window.activeThreadId==="t-plan-b-339" && chatMessages.some((m)=>m.id==="m-plan-b-339-a1")',15000,100,'B fully loaded');
    await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'plan model B restored');
    await sleep(250);
    await sendChatMessage(cdp,'concurrent B');
    await cdp.waitFor('isThreadRequestInFlight("t-plan-a-339") && isThreadRequestInFlight("t-plan-b-339")',10000,50,'both plan requests busy');
    await cdp.eval('window.loadThread("t-plan-a-339"); true');
    await cdp.waitFor('window.activeThreadId==="t-plan-a-339" && chatMessages.some((m)=>m.content==="concurrent A")',15000,100,'A fully restored');
    await sleep(250);
    const mode339=await cdp.eval('(() => { const b=document.getElementById("chat-send-btn"); if(!b||!b.onclick)return "none"; if(b.onclick===onStopStreaming)return "stop"; if(b.onclick===onChatSend)return "send"; return "other"; })()');
    if(mode339!=="stop") throw new Error('A did not restore Stop mode before cancellation: '+mode339); await cdp.click('#chat-send-btn');
    await cdp.waitFor('!isThreadRequestInFlight("t-plan-a-339") && isThreadRequestInFlight("t-plan-b-339")',10000,100,'A stopped B busy');
    await cdp.eval('window.loadThread("t-plan-b-339"); true'); await cdp.waitFor('!isThreadRequestInFlight("t-plan-b-339")',20000,50,'B completed');
    const a=seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-a-339'").filter(r=>String(r.content).includes('PLAN A ANSWER'));
    const b=seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-b-339'").filter(r=>String(r.content).includes('PLAN B ANSWER'));
    if(a.length||b.length!==1) throw new Error('concurrency isolation failed');
    return 'stopping A did not cancel B';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:340,
  name:'ChatGPT-plan answer containing SSE-looking data marker persists intact',
  mockOpts:{chatGptPlan:true,planDelay:20,planText:'PLAN DATA MARKER ANSWER\nOrdinary code-like text: data: "embedded scalar text"\nThis remains assistant content.'},
  fixtures:{threads:[th('t-plan-340','m-plan-340-a1','Marker')],messages:pair('m-plan-340','t-plan-340')},
  async body({cdp,dbPath}) {
    await load(cdp,'t-plan-340'); await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'plan model restored'); await sendChatMessage(cdp,'data marker'); await waitStreamingIdle(cdp,15000); await sleep(250);
    const rows=seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-340' AND role='assistant'"); if(!rows.some(r=>String(r.content).includes('data:') && String(r.content).includes('embedded scalar text'))) throw new Error('marker not persisted intact: '+JSON.stringify(rows));
    return 'SSE-looking output text remained ordinary assistant content';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:342,
  name:'ChatGPT-plan usage-limit failure releases ownership and fresh request succeeds',
  mockOpts:{chatGptPlan:true,planDelay:25,planFailFirstRequests:1,planText:'RECOVERED PLAN ANSWER'},
  settings:{threadTitles:{enabled:false},newChatStartsWith:'chatgpt/gpt-5.6-luna'},
  fixtures:{threads:[th('t-plan-342','m-plan-342-a1','Recover')],messages:pair('m-plan-342','t-plan-342')},
  async body({cdp,dbPath}) {
    await load(cdp,'t-plan-342'); await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'plan model restored'); await sendChatMessage(cdp,'trigger plan limit');
    await cdp.waitFor('document.body.textContent.includes("Usage limit reached.")',10000,100,'limit banner'); await cdp.waitFor('!isThreadRequestInFlight("t-plan-342")',10000,100,'failure released');
    const old=await cdp.eval('window.activeThreadId'); await cdp.click('#new-chat-btn'); await cdp.waitFor('window.activeThreadId && window.activeThreadId!=='+JSON.stringify(old),10000,100,'new chat');
    const fresh=await cdp.eval('window.activeThreadId'); await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'new-chat plan model restored'); await sendChatMessage(cdp,'normal after plan limit'); await waitStreamingIdle(cdp,15000);
    const rows=seed.query(dbPath,'SELECT role,content FROM messages WHERE thread_id=?',[fresh]); if(!rows.some(r=>r.role==='assistant'&&String(r.content).includes('RECOVERED PLAN ANSWER'))) throw new Error('fresh request did not recover');
    return 'usage-limit failure released ownership and fresh request succeeded';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:343,
  name:'Sibling switch during direct Responses keeps completion on originating branch',
  mockOpts:{chatGptPlan:true,planDelay:1400,planReasoning:'Working on originating plan branch',planText:'ORIGINATING PLAN BRANCH ANSWER'},
  fixtures:{
    threads:[th('t-plan-343','m-plan-343-a2a','Branch')],
    messages:[
      {id:'m-plan-343-u1',thread_id:'t-plan-343',role:'user',content:'root'},
      {id:'m-plan-343-a1',thread_id:'t-plan-343',role:'assistant',content:'branch A',parent_id:'m-plan-343-u1',sibling_group:'sg-plan-343',sibling_index:0,model:'chatgpt/gpt-5.6-luna'},
      {id:'m-plan-343-a1b',thread_id:'t-plan-343',role:'assistant',content:'branch B',parent_id:'m-plan-343-u1',sibling_group:'sg-plan-343',sibling_index:1,model:'chatgpt/gpt-5.6-luna'},
      {id:'m-plan-343-u2a',thread_id:'t-plan-343',role:'user',content:'follow A',parent_id:'m-plan-343-a1'},
      {id:'m-plan-343-a2a',thread_id:'t-plan-343',role:'assistant',content:'A leaf',parent_id:'m-plan-343-u2a',model:'chatgpt/gpt-5.6-luna'},
      {id:'m-plan-343-u2b',thread_id:'t-plan-343',role:'user',content:'follow B',parent_id:'m-plan-343-a1b'},
      {id:'m-plan-343-a2b',thread_id:'t-plan-343',role:'assistant',content:'B leaf',parent_id:'m-plan-343-u2b',model:'chatgpt/gpt-5.6-luna'}
    ]
  },
  async body({cdp,dbPath}) {
    await load(cdp,'t-plan-343'); await cdp.waitFor('chatMessages[chatMessages.length-1].id==="m-plan-343-a2a"',10000,100,'A leaf'); await sendChatMessage(cdp,'slow branch plan');
    await cdp.waitFor('isThreadRequestInFlight("t-plan-343")',10000,50,'branch request in flight');
    let sent=null; const sentDeadline=Date.now()+5000;
    while(Date.now()<sentDeadline){ sent=seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='t-plan-343' AND role='user' AND content='slow branch plan' ORDER BY rowid DESC LIMIT 1")[0]||null; if(sent) break; await sleep(50); }
    if(!sent) throw new Error('originating user message was not durably visible before branch switch');
    await cdp.click('#chat-messages .msg:nth-child(2) .msg-action-btn[title="Next branch"]'); await cdp.waitFor('chatMessages[chatMessages.length-1].id==="m-plan-343-a2b"',10000,100,'B leaf');
    await sleep(250);
    if(!await cdp.eval('isThreadRequestInFlight("t-plan-343")')) throw new Error('branch request completed before off-path ownership could be verified');
    const siblingText343=String(await cdp.eval('document.getElementById("chat-messages").textContent'));
    if(siblingText343.includes('Working on originating plan branch')) throw new Error('originating branch activity leaked into sibling branch');
    await cdp.waitFor('!isThreadRequestInFlight("t-plan-343")',20000,50,'originating branch request completed');
    const rows=seed.query(dbPath,"SELECT parent_id,content FROM messages WHERE thread_id='t-plan-343' AND role='assistant'").filter(r=>String(r.content).includes('ORIGINATING PLAN BRANCH ANSWER'));
    if(rows.length!==1||!sent||rows[0].parent_id!==sent.id) {
      const assistants=seed.query(dbPath,"SELECT id,parent_id,content FROM messages WHERE thread_id='t-plan-343' AND role='assistant' ORDER BY rowid");
      const leaf=seed.query(dbPath,"SELECT active_leaf_id FROM chat_threads WHERE id='t-plan-343'")[0];
      throw new Error('originating branch ownership failed: '+JSON.stringify({sent,rows,assistants,leaf}));
    }
    if(seed.query(dbPath,"SELECT active_leaf_id FROM chat_threads WHERE id='t-plan-343'")[0].active_leaf_id!=='m-plan-343-a2b') throw new Error('background completion yanked sibling branch');
    return 'completion persisted under branch A without changing visible branch B';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:347,
  name:'ChatGPT-plan title model stays isolated from HTTP chat transport',
  mockOpts:{chatGptPlan:true,planDelay:20,planTextMap:[{match:'HTTP first exchange 347',text:'Mock Plan Title'}]},
  settings:{threadTitles:{enabled:true,model:'chatgpt/gpt-5.6-luna',prompt:'TITLE_PROMPT_347: Return only a short title.',maxTokens:50}},
  fixtures:{threads:[{id:'t-title-http-347',title:'New Chat',active_leaf_id:null,model_override:'openai/gpt-5-mini'}]},
  async body({cdp,dbPath,mockLog}) {
    await load(cdp,'t-title-http-347'); await cdp.waitFor('window._currentSettings && window._currentSettings.model==="openai/gpt-5-mini"',10000,100,'HTTP model restored'); await sendChatMessage(cdp,'HTTP first exchange 347'); await waitStreamingIdle(cdp,20000);
    const deadline=Date.now()+12000; let title='New Chat';
    while(Date.now()<deadline){const row=seed.query(dbPath,"SELECT title FROM chat_threads WHERE id='t-title-http-347'")[0]; title=row&&row.title; if(title!=='New Chat') break; await sleep(100);}
    if(title!=='Mock Plan Title') throw new Error('plan title not persisted: '+title);
    const all=reqs(mockLog); const chats=all.filter(r=>String(r.url).includes('/chat/completions')); const plans=all.filter(r=>String(r.url).includes('/responses'));
    const mainHttp=chats.find(r=>String(r.body&&r.body.model)==='gpt-5-mini');
    const titlePlan=plans.find(r=>String(r.body&&r.body.model)==='gpt-5.6-luna');
    if(!mainHttp||!titlePlan) throw new Error('main/title transports were not isolated: '+JSON.stringify({chats:chats.map(r=>r.body&&r.body.model),plans:plans.map(r=>r.body&&r.body.model)}));
    return 'HTTP main chat stayed isolated while title generation used direct Responses';
  }
}));


scenarios.push(Object.assign({}, base, {
  id:349,
  name:'ChatGPT-plan authorization indicator follows the effective model and exposes Manage usage',
  mockOpts:{chatGptPlan:true},
  fixtures:{
    threads:[
      th('t-plan-ui-349','m-plan-ui-349-a1','Plan UI'),
      {id:'t-http-ui-349',title:'HTTP UI',active_leaf_id:'m-http-ui-349-a1',model_override:'openai/gpt-5-mini'}
    ],
    messages:[
      ...pair('m-plan-ui-349','t-plan-ui-349'),
      {id:'m-http-ui-349-u1',thread_id:'t-http-ui-349',role:'user',content:'http seed'},
      {id:'m-http-ui-349-a1',thread_id:'t-http-ui-349',role:'assistant',content:'http answer',parent_id:'m-http-ui-349-u1',model:'openai/gpt-5-mini'}
    ]
  },
  async body({cdp}) {
    await load(cdp,'t-plan-ui-349');
    await cdp.waitFor("(() => { const el=document.getElementById('chatGptPlanInline'); return el && el.style.display === 'flex' && el.textContent.includes('Using ChatGPT plan'); })()",10000,100,'plan usage indicator');
    const manage=await cdp.eval("(() => { const b=document.getElementById('chatGptPlanManageUsage'); return !!b && b.textContent.includes('Manage usage'); })()");
    if(!manage) throw new Error('ChatGPT-plan Manage usage control is missing');

    await cdp.eval('window.loadThread("t-http-ui-349"); true');
    await cdp.waitFor('window.activeThreadId==="t-http-ui-349" && chatMessages.some((m)=>m.id==="m-http-ui-349-a1")',10000,100,'HTTP thread loaded');
    await cdp.waitFor("(() => { const el=document.getElementById('chatGptPlanInline'); return el && el.style.display === 'none'; })()",10000,100,'plan indicator hidden on non-plan model');
    return 'plan usage indicator and Manage usage are visible only for the authenticated ChatGPT-plan model';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:350,
  name:'Image Generation OFF omits the AhkLLM image tool and never launches Codex CLI',
  mockOpts:{chatGptPlan:true,planDelay:30,planImageTool:true,planText:'TEXT ONLY WITH IMAGE TOOL DISABLED'},
  fixtures:{
    threads:[Object.assign(th('t-plan-image-off-350','m-plan-image-off-350-a1','Image Off'),{advanced_toggles:'{"imageGeneration":false}'})],
    messages:pair('m-plan-image-off-350','t-plan-image-off-350')
  },
  preLaunch(dataDir){installFakeCodex(dataDir);},
  launchEnv:imageEnv,
  async body({cdp,dbPath,mockLog,dataDir}) {
    await load(cdp,'t-plan-image-off-350');
    const enabled=await cdp.eval('!!(window._currentSettings && window._currentSettings.imageGeneration)');
    if(enabled) throw new Error('image generation fixture unexpectedly loaded enabled');

    await sendChatMessage(cdp,'please generate an image while disabled');
    await waitStreamingIdle(cdp,15000);
    const rs=responses(mockLog);
    if(rs.length!==1) throw new Error('expected exactly one direct Responses request: '+JSON.stringify(rs));
    const tools=JSON.stringify(rs[0].body.tools||[]);
    if(tools.includes('"namespace"') && tools.includes('"ahkllm"'))
      throw new Error('Image Generation OFF still exposed the AhkLLM image namespace: '+tools);
    if(codexExecs(dataDir).length!==0)
      throw new Error('Image Generation OFF launched Codex CLI: '+JSON.stringify(codexExecs(dataDir)));
    const rows=seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-image-off-350' AND role='assistant' ORDER BY rowid DESC LIMIT 1");
    if(!rows.length || !String(rows[0].content).includes('TEXT ONLY WITH IMAGE TOOL DISABLED'))
      throw new Error('normal text response did not persist with Image Generation OFF: '+JSON.stringify(rows));
    return 'toggle-off request stayed entirely on direct Responses: no client image tool and no Codex process';
  }
}));


scenarios.push({
  id:351,
  name:'ChatGPT-plan model without OAuth permission is rejected before any Responses network call',
  regression:true,
  mode:'sse-success',
  mockOpts:{chatGptPlan:true,planDelay:20,planText:'SHOULD NOT REACH NETWORK'},
  settings:{threadTitles:{enabled:false}},
  fixtures:{threads:[th('t-plan-auth-off-351','m-plan-auth-off-351-a1','Auth Off')],messages:pair('m-plan-auth-off-351','t-plan-auth-off-351')},
  launchEnv:{},
  async body({cdp,mockLog}) {
    await load(cdp,'t-plan-auth-off-351');
    await sendChatMessage(cdp,'unauthenticated plan request');
    await cdp.waitFor('document.body.textContent.includes("Sign in with ChatGPT in Settings")',10000,100,'friendly ChatGPT sign-in error');
    await cdp.waitFor('!isThreadRequestInFlight("t-plan-auth-off-351")',10000,100,'unauthenticated request released');
    const rs=responses(mockLog);
    if(rs.length!==0) throw new Error('unauthenticated ChatGPT-plan request reached the network: '+JSON.stringify(rs));
    return 'unauthenticated plan use was rejected locally with a friendly sign-in error and zero Responses calls';
  }
});



scenarios.push(Object.assign({}, base, {
  id:352,
  name:'ChatGPT-plan direct Responses accepts accumulated AhkLLM history beyond the former 1,048,576-character Codex ceiling',
  mockOpts:{chatGptPlan:true,planDelay:20,planText:'LARGE HISTORY PLAN ANSWER'},
  fixtures:(() => {
    const block='x'.repeat(540000);
    return {
      threads:[th('t-plan-large-352','m-plan-large-352-a1','Large Plan History')],
      messages:[
        {id:'m-plan-large-352-u1',thread_id:'t-plan-large-352',role:'user',content:block},
        {id:'m-plan-large-352-a1',thread_id:'t-plan-large-352',role:'assistant',content:block,parent_id:'m-plan-large-352-u1',model:'chatgpt/gpt-5.6-luna'}
      ]
    };
  })(),
  async body({cdp,dbPath,mockLog,dataDir}) {
    await load(cdp,'t-plan-large-352');
    await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'large-history plan model restored');
    await sendChatMessage(cdp,'continue after the former Codex character ceiling');
    await waitStreamingIdle(cdp,30000);

    const rs=responses(mockLog);
    if(rs.length!==1) throw new Error('expected exactly one direct Responses request: '+JSON.stringify(rs.map(r=>r.url)));
    const serialized=JSON.stringify(rs[0].body && rs[0].body.input || []);
    if(serialized.length<=1048576)
      throw new Error('fixture did not exceed former Codex 1,048,576-character ceiling: '+serialized.length);
    if(!serialized.includes('continue after the former Codex character ceiling'))
      throw new Error('latest user turn missing from large direct Responses input');

    const rows=seed.query(dbPath,"SELECT content FROM messages WHERE thread_id='t-plan-large-352' AND role='assistant' ORDER BY rowid DESC LIMIT 1");
    if(!rows.length || !String(rows[0].content).includes('LARGE HISTORY PLAN ANSWER'))
      throw new Error('large-history continuation did not persist: '+JSON.stringify(rows));

    if(codexExecs(dataDir).length!==0)
      throw new Error('normal large-history ChatGPT-plan chat unexpectedly invoked Codex CLI');
    return 'explicit Responses input exceeded 1,048,576 characters and completed without the former Codex turn/start limit';
  }
}));


scenarios.push(Object.assign({}, base, {
  id:353,
  name:'Legacy codex/... chat model id resolves through canonical ChatGPT-plan provider without rewriting history on load',
  mockOpts:{chatGptPlan:true,planDelay:20,planText:'LEGACY ALIAS PLAN ANSWER'},
  fixtures:{
    threads:[{id:'t-plan-legacy-353',title:'Legacy Plan Alias',active_leaf_id:'m-plan-legacy-353-a1',model_override:'codex/gpt-5.6-luna',reasoning_override:'medium',reasoning_override_set:1}],
    messages:[
      {id:'m-plan-legacy-353-u1',thread_id:'t-plan-legacy-353',role:'user',content:'legacy user'},
      {id:'m-plan-legacy-353-a1',thread_id:'t-plan-legacy-353',role:'assistant',content:'legacy assistant',parent_id:'m-plan-legacy-353-u1',model:'codex/gpt-5.6-luna'}
    ]
  },
  async body({cdp,dbPath,mockLog,dataDir}) {
    await load(cdp,'t-plan-legacy-353');
    await cdp.waitFor('window._currentSettings && window._currentSettings.model==="chatgpt/gpt-5.6-luna"',10000,100,'legacy model canonicalized in UI');
    const before=seed.query(dbPath,"SELECT model_override FROM chat_threads WHERE id='t-plan-legacy-353'")[0];
    if(!before || before.model_override!=='codex/gpt-5.6-luna')
      throw new Error('loading legacy chat unexpectedly rewrote historical model_override: '+JSON.stringify(before));

    await sendChatMessage(cdp,'continue legacy alias chat');
    await waitStreamingIdle(cdp,15000);

    const rs=responses(mockLog);
    if(rs.length!==1) throw new Error('legacy alias did not route through one direct Responses request: '+JSON.stringify(rs.map(r=>r.url)));
    if(String(rs[0].body&&rs[0].body.model)!=='gpt-5.6-luna')
      throw new Error('legacy alias sent wrong API model slug: '+JSON.stringify(rs[0].body));
    if(codexExecs(dataDir).length!==0)
      throw new Error('legacy normal chat unexpectedly invoked Codex CLI');
    const rows=seed.query(dbPath,"SELECT content,provider,model FROM messages WHERE thread_id='t-plan-legacy-353' AND role='assistant' ORDER BY rowid DESC LIMIT 1");
    if(!rows.length || !String(rows[0].content).includes('LEGACY ALIAS PLAN ANSWER'))
      throw new Error('legacy alias continuation did not persist: '+JSON.stringify(rows));
    if(rows[0].provider!=='chatgpt')
      throw new Error('new response from legacy chat was not attributed to canonical chatgpt provider: '+JSON.stringify(rows[0]));
    const after=seed.query(dbPath,"SELECT model_override FROM chat_threads WHERE id='t-plan-legacy-353'")[0];
    if(!after || after.model_override!=='codex/gpt-5.6-luna')
      throw new Error('continuing legacy chat unexpectedly rewrote historical thread model id: '+JSON.stringify(after));
    return 'old codex/... DB id displayed canonically as chatgpt/..., new usage was attributed to chatgpt, and direct Responses continued without rewriting historical state or invoking Codex CLI';
  }
}));

function catalogEnv({ endpoint }) {
  return Object.assign(planEnv({ endpoint }), {
    AHKLLM_E2E_CHATGPT_MODELS_ENDPOINT: String(endpoint).replace('/v1/chat/completions', '/v1/models')
  });
}

function savedCatalog(dataDir) {
  return JSON.parse(fs.readFileSync(path.join(dataDir, 'settings.json'), 'utf8').replace(/^\uFEFF/, ''));
}

scenarios.push(Object.assign({}, base, {
  id: 354,
  name: 'ChatGPT model refresh persists, prunes stale rows, joins Fetch Latest Models, and preserves catalog on failure',
  launchEnv: catalogEnv,
  settings: {
    threadTitles: { enabled: false },
    providers: { chatgpt: { displayName: 'ChatGPT plan', transport: 'chatgpt-responses' } },
    models: {
      'chatgpt/stale': { provider: 'chatgpt', api: 'chatgpt-responses' },
      'chatgpt/gpt-5.6-luna': { provider: 'chatgpt', api: 'chatgpt-responses' }
    }
  },
  mockOpts: {
    chatGptPlan: true,
    planModelCatalogs: [
      { models: [
        { slug: 'gpt-5.6-luna', display_name: 'Luna account name', visibility: 'list' },
        { slug: 'discovered', display_name: 'Discovered account model', visibility: 'list' },
        { slug: 'hidden', display_name: 'Hidden', visibility: 'hidden' },
        { slug: 'missing-visibility', display_name: 'Not displayable' }
      ] },
      { models: [
        { slug: 'gpt-5.6-luna', display_name: 'Luna account name', visibility: 'list' },
        { slug: 'discovered', display_name: 'Discovered account model', visibility: 'list' }
      ] },
      { models: [{ slug: 'discovered', display_name: 'Updated account name', visibility: 'list' }] },
      { status: 500, body: { error: 'Catalog unavailable' } },
      { models: [] }
    ]
  },
  async body({ cdp, dataDir, mockLog }) {
    await openSettings(cdp);
    await cdp.waitFor('window.SettingsModels.collectCurrentModels().some(m=>m.id==="chatgpt/discovered")', 10000, 100, 'startup catalog discovery');
    await openSection(cdp, 'providers');
    await cdp.eval('(() => { const name=document.querySelector("[data-field=displayName]"); name.value="Unsaved plan label"; name.dispatchEvent(new Event("input", {bubbles:true})); return true; })()');
    await cdp.click('.chatgpt-refresh-models');
    await cdp.waitFor('window.SettingsModels.collectCurrentModels().filter(m=>m.provider==="chatgpt").map(m=>m.id).sort().join(",")==="chatgpt/discovered,chatgpt/gpt-5.6-luna" && !document.querySelector(".chatgpt-refresh-models").disabled', 10000, 100, 'provider refresh updates Models table');
    const first = savedCatalog(dataDir);
    if (first.providers.chatgpt.modelCatalogSource !== 'account' || Object.keys(first.models).length !== 2)
      throw new Error('discovery did not persist an authoritative account catalog');
    if (await cdp.eval('document.querySelector("[data-field=displayName]").value') !== 'Unsaved plan label')
      throw new Error('catalog refresh erased an unsaved provider edit');
    if (!(await cdp.eval('window.SettingsPanel.isDirty()')))
      throw new Error('catalog refresh cleared unrelated dirty state');
    const names = await cdp.eval('window.SettingsModels.collectCurrentModels().map(m=>m.displayName)');
    if (!names.includes('Discovered account model')) throw new Error('display names did not reach Models settings');

    await openSection(cdp, 'models');
    await cdp.click('#refreshPricingBtn');
    await cdp.waitFor('window.SettingsModels.rightPanelIds().join(",")==="chatgpt/discovered" && document.getElementById("refreshModelStatus").textContent.includes("ChatGPT")', 10000, 100, 'unified refresh reconciles modal');
    if (!String(await cdp.eval('document.getElementById("refreshLeftTbody").textContent')).includes('discovered'))
      throw new Error('Fetch Latest Models did not display the account catalog');
    if (savedCatalog(dataDir).models['chatgpt/gpt-5.6-luna']) throw new Error('stale model was not pruned from disk');
    await cdp.click('#refreshSaveBtn');
    await saveSettings(cdp, dataDir);
    const saved = savedCatalog(dataDir);
    if (saved.providers.chatgpt.modelCatalogSource !== 'account' || Object.keys(saved.models).join(',') !== 'chatgpt/discovered')
      throw new Error('Settings save reintroduced fallback models or dropped catalog authority');
    await cdp.eval('Ipc.request("requestAllSettings").then(() => Ipc.request("requestChatGptPlanStatus"))');
    await cdp.waitFor('window.SettingsModels.collectCurrentModels().map(m=>m.id).join(",")==="chatgpt/discovered"', 10000, 100, 'reloaded settings preserve discovered membership');

    await openSection(cdp, 'providers');
    const beforeFailure = fs.readFileSync(path.join(dataDir, 'settings.json'), 'utf8');
    await cdp.click('.chatgpt-refresh-models');
    try {
      await cdp.waitFor('document.querySelector(".chatgpt-plan-status").textContent.includes("refresh failed") && !document.querySelector(".chatgpt-refresh-models").disabled', 10000, 100, 'failed refresh re-enables controls');
    } catch (error) {
      throw new Error(error.message + ': ' + await cdp.eval('JSON.stringify({status:document.querySelector(".chatgpt-plan-status").textContent,disabled:document.querySelector(".chatgpt-refresh-models").disabled})'));
    }
    if (fs.readFileSync(path.join(dataDir, 'settings.json'), 'utf8') !== beforeFailure)
      throw new Error('failed discovery changed the saved catalog');
    await cdp.click('.chatgpt-refresh-models');
    await cdp.waitFor('window.SettingsModels.collectCurrentModels().filter(m=>m.provider==="chatgpt").length===0 && !document.querySelector(".chatgpt-refresh-models").disabled', 10000, 100, 'empty catalog prunes all plan rows');
    if (Object.keys(savedCatalog(dataDir).models).length !== 0) throw new Error('empty catalog did not persist');
    const requests = reqs(mockLog).filter(r => r.url === '/v1/models');
    if (requests.length !== 5 || requests.some(r => !String(r.authorization).startsWith('Bearer ')))
      throw new Error('expected startup plus four authenticated account catalog requests');
    return 'provider and unified refresh persist account membership; table/modal stay synchronized, unsaved edits survive, failures preserve disk, and empty catalogs remain empty';
  }
}));

scenarios.push(Object.assign({}, base, {
  id: 355,
  name: 'ChatGPT catalog refresh preserves unsaved API-model edits and other saved provider models',
  launchEnv: catalogEnv,
  settings: { threadTitles: { enabled: false }, models: {
    'openai/gpt-5-mini': { provider: 'openai', input: 1, output: 2 },
    'chatgpt/stale': { provider: 'chatgpt', api: 'chatgpt-responses' }
  } },
  mockOpts: { chatGptPlan: true },
  async body({ cdp, dataDir }) {
    await openSettings(cdp);
    await openSection(cdp, 'models');
    await cdp.eval('(() => { const row=Array.from(document.querySelectorAll("#modelsTableBody tr")).find(r=>r.querySelector("[data-field=provider]").value==="openai"); const input=row.querySelector("[data-field=id]"); input.value="unsaved-http"; input.dispatchEvent(new Event("input",{bubbles:true})); return true; })()');
    await openSection(cdp, 'providers');
    await cdp.click('.chatgpt-refresh-models');
    await cdp.waitFor('window.SettingsModels.collectCurrentModels().some(m=>m.id==="chatgpt/gpt-5.6-luna") && !window.SettingsModels.collectCurrentModels().some(m=>m.id==="chatgpt/stale")', 10000, 100, 'account catalog replaced');
    if (!(await cdp.eval('window.SettingsModels.collectCurrentModels().some(m=>m.id==="openai/unsaved-http") && window.SettingsPanel.isDirty()')))
      throw new Error('catalog update erased an unrelated unsaved API-model edit');
    const saved = savedCatalog(dataDir);
    if (!saved.models['openai/gpt-5-mini'] || saved.models['openai/unsaved-http'])
      throw new Error('catalog refresh changed unrelated saved model data');
    return 'ChatGPT refresh changed only plan rows and preserved both unsaved API-model edits and saved API metadata';
  }
}));

scenarios.push(Object.assign({}, base, {
  id: 356,
  name: 'Interrupted ChatGPT Responses stream preserves its real failure instead of suggesting an API key',
  mockOpts: { chatGptPlan: true, planDelay: 20, planTruncateAfterCreated: true },
  fixtures: { threads: [th('t-plan-truncated-356', 'm-plan-truncated-356-a1', 'Interrupted response')],
    messages: pair('m-plan-truncated-356', 't-plan-truncated-356') },
  async body({ cdp }) {
    await load(cdp, 't-plan-truncated-356');
    await sendChatMessage(cdp, 'interrupted response');
    await cdp.waitFor('document.body.textContent.includes("stream ended without response.completed")', 10000, 100, 'terminal failure displayed');
    await cdp.waitFor('!isThreadRequestInFlight("t-plan-truncated-356")', 10000, 100, 'failed request released');
    if (String(await cdp.eval('document.body.textContent')).includes('Check your API key'))
      throw new Error('ChatGPT stream failure misleadingly suggested an API key');
    return 'interrupted Responses stream reports its terminal failure and releases request ownership';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:363,
  name:'Large slash-containing image survives ChatGPT serialization and image-tool continuation',
  mockOpts:{chatGptPlan:true,planDelay:30,planImageTool:true,planImagePrompt:'generate image codex',planAfterToolText:'LARGE IMAGE COMPLETE'},
  fixtures:{threads:[Object.assign(th('t-plan-large-363','m-plan-large-363-a1','Large image'),{advanced_toggles:'{"imageGeneration":true}'})],
    messages:pair('m-plan-large-363','t-plan-large-363'),
    attachments:[{id:'large-cover-363',message_id:'m-plan-large-363-u1',attachment_type:'image',file_path:'attachments/large-cover.png',mime_type:'image/png',original_filename:'large-cover.png',file_size:33554432}]},
  preLaunch(dataDir) {
    installFakeCodex(dataDir);
    fs.mkdirSync(path.join(dataDir,'attachments'),{recursive:true});
    const bytes=Buffer.alloc(32*1024*1024,255);
    Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z7ZsAAAAASUVORK5CYII=','base64').copy(bytes);
    fs.writeFileSync(path.join(dataDir,'attachments','large-cover.png'),bytes);
  },
  launchEnv:imageEnv,
  async body({cdp,dbPath,mockLog,dataDir}) {
    await load(cdp,'t-plan-large-363');
    await cdp.waitFor('window._currentSettings.imageGeneration===true',10000,50,'image generation enabled');
    await cdp.eval(`window.largeImageTerminals=[]; chrome.webview.addEventListener('message',event=>{const message=typeof event.data==='string'?JSON.parse(event.data):event.data; if(['streamDone','setChatButtonsEnabled','chatMessageSaved','appendChatMessage'].includes(message.target)) largeImageTerminals.push({target:message.target,data:message.data,messages:chatMessages.map(m=>({id:m.id,role:m.role,pending:m.pending}))});}); true`);
    await sendChatMessage(cdp,'Generate an alternative cover');
    try { await waitStreamingIdle(cdp,45000); }
    catch(error) {
      const diagnostic=await cdp.eval('({thread:activeThreadId,active:streamState.active,streamThread:streamState.threadId,loading:isLoading,requests:_threadRequestState,messages:chatMessages.map(m=>({id:m.id,role:m.role,content:m.content})),terminals:largeImageTerminals})');
      throw new Error(error.message+' '+JSON.stringify(diagnostic));
    }
    const state=await cdp.eval('({thread:activeThreadId,messages:chatMessages.map(m=>({id:m.id,role:m.role,content:m.content})),text:document.getElementById("chat-messages").textContent})');
    if(!state.messages.some(m=>m.role==='assistant' && m.content.includes('LARGE IMAGE COMPLETE')) || !state.text.includes('LARGE IMAGE COMPLETE'))
      throw new Error('Large-image response missing from visible chat: '+JSON.stringify(state));
    const requests=responses(mockLog);
    if(requests.length!==2) throw new Error('Expected image request and tool continuation');
    const original=fs.readFileSync(path.join(dataDir,'attachments','large-cover.png')).toString('base64');
    for(const request of requests) {
      const images=request.body.input.flatMap(item=>Array.isArray(item.content)?item.content:[]).filter(part=>part.type==='input_image');
      if(!images.some(part=>part.image_url==='data:image/png;base64,'+original)) throw new Error('Original image bytes changed during request serialization');
      if(request.body.stream!==true || request.body.store!==false) throw new Error('Responses boolean fields were not serialized correctly');
    }
    if(codexExecs(dataDir).length!==1) throw new Error('Expected one image worker');
    if(!seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='t-plan-large-363' AND content='LARGE IMAGE COMPLETE'").length) throw new Error('Final response was not persisted');
    return '32 MiB slash-rich image preserved exactly in initial request and tool continuation; real boolean fields and final answer persisted';
  }
}));

scenarios.push(Object.assign({}, base, {
  id:364,
  name:'ChatGPT image call from item-done survives a completed response with empty output',
  mockOpts:{chatGptPlan:true,planDelay:30,planImageTool:true,planEmptyTerminalOutput:true,planImagePrompt:'generate image codex',planAfterToolText:'ITEM DONE IMAGE COMPLETE'},
  fixtures:{threads:[Object.assign(th('t-plan-item-364','m-plan-item-364-a1','Item-done image'),{advanced_toggles:'{"imageGeneration":true}'})],messages:pair('m-plan-item-364','t-plan-item-364')},
  preLaunch:installFakeCodex, launchEnv:imageEnv,
  async body({cdp,dbPath,mockLog,dataDir}) {
    await load(cdp,'t-plan-item-364');
    await cdp.waitFor('window._currentSettings.imageGeneration===true',10000,50,'image generation enabled');
    await sendChatMessage(cdp,'Generate an alternative cover'); await waitStreamingIdle(cdp,25000);
    const requests=responses(mockLog);
    if(requests.length!==2 || codexExecs(dataDir).length!==1) throw new Error('Completed streamed call must invoke exactly one image worker and continuation');
    const input=requests[1].body.input;
    if(input.filter(item=>item.type==='function_call' && item.call_id==='call-image-1').length!==1 || input.filter(item=>item.type==='function_call_output' && item.call_id==='call-image-1').length!==1)
      throw new Error('Continuation lost or duplicated the original namespaced call and its matching output');
    if(!await cdp.eval('document.getElementById("chat-messages").textContent.includes("ITEM DONE IMAGE COMPLETE") && document.querySelector(".image-preview-frame")!==null'))
      throw new Error('Completed response and generated image must appear immediately');
    if(!seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='t-plan-item-364' AND content='ITEM DONE IMAGE COMPLETE'").length)
      throw new Error('Image continuation answer was not persisted');
    return 'Real item-done/arguments-done/empty-output sequence invoked one image worker, preserved call IDs, and displayed/persisted the result';
  }
}));

module.exports = scenarios;
