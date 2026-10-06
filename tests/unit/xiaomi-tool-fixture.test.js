'use strict';
const {it}=require('node:test');
const assert=require('node:assert/strict');
const {validateXiaomiRequest}=require('../headless/xiaomi-tool-fixture');
it('MiMo fixture rejects missing tool reasoning instead of masking incompatibility',()=>{
  const body={thinking:{type:'enabled'},messages:[{role:'assistant',content:'MiMo public round 0',tool_calls:[{id:'call_search_1'}]}]};
  assert.match(validateXiaomiRequest(body,'Bearer mimo-fixture-key'),/reasoning_content/);
  body.messages[0].reasoning_content='MiMo exact round 0 Ω';
  assert.equal(validateXiaomiRequest(body,'Bearer mimo-fixture-key'),'');
  body.thinking.type='disabled';delete body.messages[0].reasoning_content;
  assert.equal(validateXiaomiRequest(body,'Bearer mimo-fixture-key'),'');
});
