'use strict';
function reusedIndexResponse(body,opts,res) {
  const optional=body.tools.find(t=>t.function?.name==='inspect_optional').function;
  const omit=opts.nativeNullOmission!==false;
  const wire=optional.parameters;
  const valid=omit ? wire.properties.path.type==='string'&&!wire.required.includes('path')&&optional.strict===false : Array.isArray(wire.properties.path.type)&&wire.required.includes('path');
  if(!valid){res.writeHead(400,{'Content-Type':'application/json'});res.end(JSON.stringify({error:{message:'Nullable wire schema does not match the selected compatibility policy'}}));return;}
  const outputs=body.messages.filter(m=>m.role==='tool');
  const correction=outputs.length>0 && JSON.parse(outputs.at(-1).content).error==='invalid_tool_arguments';
  res.writeHead(200,{'Content-Type':'text/event-stream'});
  const emit=delta=>res.write('data: '+JSON.stringify({choices:[{delta}]})+'\n\n');
  if(outputs.length&&!correction){emit({content:'REUSED INDEX ANSWER'});res.write('data: '+JSON.stringify({choices:[{delta:{},finish_reason:'stop'}],model:body.model,usage:{prompt_tokens:20,completion_tokens:9,total_tokens:29}})+'\n\n');res.end('data: [DONE]\n\n');return;}
  const prefix=correction?'corrected':'initial';
  emit({tool_calls:[{index:0,id:prefix+'-optional',type:'function',function:{name:'inspect_optional',arguments:''}}]});
  emit({tool_calls:[{index:0,id:null,function:{name:null,arguments:opts.nativeIndexMalformed&&!correction?'{"path": ':JSON.stringify(omit?{depth:4}:{path:null,depth:4})}}]});
  emit({tool_calls:[{index:0,id:prefix+'-text',type:'function',function:{name:'inspect_text',arguments:''}}]});
  emit({tool_calls:[{index:0,id:null,function:{name:null,arguments:'{"text":"SECOND '}}]});
  emit({tool_calls:[{index:0,id:null,function:{name:null,arguments:'CALL"}'}}]});
  res.write('data: '+JSON.stringify({choices:[{delta:{},finish_reason:'tool_calls'}],model:body.model,usage:{prompt_tokens:20,completion_tokens:9,total_tokens:29}})+'\n\n');
  res.end('data: [DONE]\n\n');
}
module.exports={reusedIndexResponse};
