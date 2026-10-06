'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),assert=require('node:assert/strict');
const seed=require('../seed');
const {openPreparedApplication}=require('../application-session');
const {sendChatMessage,waitStreamingIdle}=require('./helpers');
const lines=file=>fs.readFileSync(file,'utf8').split(/\r?\n/).filter(Boolean).map(JSON.parse);
function configure(dataDir,endpoint) {
  const file=path.join(dataDir,'settings.json'),settings=JSON.parse(fs.readFileSync(file,'utf8'));
  settings.providers.xiaomi={displayName:'Xiaomi MiMo',endpoint,authEnvVar:'MIMO_API_KEY',toolCallingMode:'native'};
  if(settings.newChatStartsWith==='xiaomi/custom-native')settings.models={'xiaomi/custom-native':{provider:'xiaomi',compat:{nativeToolNulls:'native'}}};
  fs.writeFileSync(file,JSON.stringify(settings));
  fs.writeFileSync(path.join(os.tmpdir(),'example-native-raw-rpc.jsonl'),'');
  fs.writeFileSync(path.join(os.tmpdir(),'LLM_API_Log.json'),'[]');
}
module.exports=[391,392,393].map(id=>({id,regression:true,name:'Native reused-index calls '+(id===392?'reject the incomplete call without contaminating its sibling':id===393?'respect the nullable compatibility opt-out':'omit wire nulls and restore the original application contract'),
  mode:'sse-tool-call',preLaunch:configure,
  settings:{threadTitles:{enabled:false},newChatStartsWith:id===393?'xiaomi/custom-native':'xiaomi/mimo-v2.6-pro'},
  launchEnv:()=>({MIMO_API_KEY:'mimo-fixture-key',AHKLLM_E2E_NULLABLE_TOOLS:'1'}),
  mockOpts:{nativeReusedIndex:true,nativeIndexMalformed:id===392,nativeNullOmission:id!==393},
  async body({cdp,dataDir,dbPath,mockLog}) {
    const threadId=await openPreparedApplication(cdp,dataDir,dbPath,id);
    await sendChatMessage(cdp,'Inspect both inputs using native tools.');await waitStreamingIdle(cdp,25000);
    assert.ok(seed.query(dbPath,'SELECT content FROM messages WHERE thread_id=? AND role=\'assistant\'',[threadId])[0]?.content.includes('REUSED INDEX ANSWER'));
    const rpc=lines(path.join(os.tmpdir(),'example-native-raw-rpc.jsonl'));
    const calls=rpc.filter(r=>r.method==='tools.call');
    assert.deepEqual(calls.map(c=>c.params.name),['inspect_optional','inspect_text']);
    assert.equal(calls[0].params.arguments.path,null,'The adapter must receive JSON null, not an empty string or missing property');
    assert.equal(calls[0].params.arguments.depth,4);
    assert.equal(calls[1].params.arguments.text,'SECOND CALL');
    assert.equal(rpc.filter(r=>r.method==='turn.commit').length,1);
    assert.equal(rpc.filter(r=>r.method==='turn.abort').length,0);
    const requests=lines(mockLog).filter(r=>r.url.includes('/chat/completions'));
    assert.equal(requests.length,id===392?3:2);
    const exchange=requests[1].body.messages.find(m=>m.tool_calls).tool_calls;
    assert.equal(exchange.length,2);
    assert.notEqual(exchange[0].id,exchange[1].id);
    assert.equal(JSON.parse(exchange[1].function.arguments).text,'SECOND CALL','The valid sibling was corrupted by a reused index');
    if(id===392) {
      const rejected=requests[1].body.messages.filter(m=>m.role==='tool').map(m=>JSON.parse(m.content));
      assert.equal(rejected.length,2);assert.ok(rejected.every(r=>r.error==='invalid_tool_arguments'));
      assert.ok(rejected[0].message.includes('inspect_optional'));
      assert.ok(rejected[1].message.includes('batch was not executed'));
    } else if(id===391) assert.deepEqual(JSON.parse(exchange[0].function.arguments),{depth:4},'Wire call unexpectedly contained null');
    return 'Independent call IDs, correct index continuations, original null RPC semantics, atomic correction and one committed turn verified';
  }
}));
