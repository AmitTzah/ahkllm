'use strict';
function nativeToolArguments(opts,round,messages) {
  const lastUser=(messages||[]).filter(m=>m.role==='user').at(-1)?.content||'';
  if (String(lastUser).includes('Recover native tools')) return JSON.stringify({text:'APPLICATION TOOL RESULT'});
  const mode=opts.nativeArgumentCase;
  if (mode==='adapter-error') return JSON.stringify({text:'NATIVE ADAPTER FAIL'});
  if (mode==='repeated' || round===0) {
    if (mode==='double-encoded' || mode==='repeated') return JSON.stringify(JSON.stringify({text:'APPLICATION TOOL RESULT'}));
    if (mode==='malformed') return '{"text":';
    if (mode==='schema') return JSON.stringify({text:17});
  }
  return JSON.stringify({text:'APPLICATION TOOL RESULT'});
}
module.exports={nativeToolArguments};
