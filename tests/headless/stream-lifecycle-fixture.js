'use strict';
async function lifecycleResponse(body,opts,req,res) {
  const responses=req.url.includes('/responses');
  const lastUser=body.messages?.filter(m=>m.role==='user').at(-1)?.content||JSON.stringify(body.input||[]);
  const mode=String(lastUser).includes('Recover stream')?'complete':opts.streamLifecycle;
  res.writeHead(200,{'Content-Type':'text/event-stream'});
  const http=(delta,finish=null,usage)=>res.write('data: '+JSON.stringify({choices:[{delta,finish_reason:finish}],model:body.model,...(usage?{usage}:{})})+'\n\n');
  const event=(name,value)=>res.write('event: '+name+'\ndata: '+JSON.stringify({type:name,...value})+'\n\n');
  if(mode==='idle'){res.write(': keepalive\n\n');return;}
  if(responses)event('response.created',{response:{id:'lifecycle',status:'in_progress',model:body.model}});
  const started=Date.now(),duration=mode==='long'?(opts.lifecycleDuration||125000):300;
  do {
    if(responses)event('response.reasoning_summary_text.delta',{delta:'Still reasoning. '});
    else http({reasoning_content:'Still reasoning. '});
    await new Promise(resolve=>setTimeout(resolve,mode==='long'?500:100));
    if(res.destroyed||res.writableEnded)return;
  }while(Date.now()-started<duration);
  if(mode==='reasoning-drop'){res.end();return;}
  if(mode==='partial-drop'){http({content:'PARTIAL UNFINISHED ANSWER'});res.end();return;}
  if(mode==='reasoning-complete'){http({},'stop',{prompt_tokens:20,completion_tokens:9,total_tokens:29});res.end('data: [DONE]\n\n');return;}
  const text='STREAM COMPLETED ANSWER';
  if(responses){
    event('response.output_text.delta',{delta:text});
    event('response.completed',{response:{id:'lifecycle',status:'completed',model:body.model,output:[{type:'message',role:'assistant',content:[{type:'output_text',text}]}],usage:{input_tokens:20,output_tokens:9,total_tokens:29}}});
  }else{http({content:text});http({},'stop',{prompt_tokens:20,completion_tokens:9,total_tokens:29});}
  res.end('data: [DONE]\n\n');
}
module.exports={lifecycleResponse};
