'use strict';
const seed = require('../seed');
const { showChat, waitStreamingIdle } = require('./helpers');
const IMAGE = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z7ZsAAAAASUVORK5CYII=';

async function attachImage(cdp) {
  await cdp.eval(`(() => {
    const binary=atob(${JSON.stringify(IMAGE)});
    const bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));
    addAttachment(new File([bytes], 'cover.png', {type:'image/png'}));
    return true;
  })()`);
  await cdp.waitFor('attachmentState.length===1 && !attachmentState[0].loading && document.querySelector(".attachment-thumb").complete && document.querySelector(".attachment-thumb").naturalWidth>0', 10000, 50, 'decoded attachment preview');
}

function fixtures(prefix, twoThreads = false) {
  const result = { threads: [], messages: [] };
  for (const suffix of twoThreads ? ['a', 'b'] : ['a']) {
    const thread = prefix + '-' + suffix;
    result.threads.push({id:thread,title:thread,active_leaf_id:thread+'-assistant',model_override:'openai/gpt-5-mini'});
    result.messages.push({id:thread+'-user',thread_id:thread,role:'user',content:'Seed '+suffix});
    result.messages.push({id:thread+'-assistant',thread_id:thread,role:'assistant',content:'Prior '+suffix,parent_id:thread+'-user'});
  }
  return result;
}

async function load(cdp, threadId) {
  await showChat();
  await cdp.eval('window.loadThread(' + JSON.stringify(threadId) + '); true');
  await cdp.waitFor('activeThreadId===' + JSON.stringify(threadId) + ' && chatMessages.some(m=>m.id===' + JSON.stringify(threadId+'-assistant') + ')', 10000, 50, 'thread loaded');
}

const common = { regression: true, mode: 'sse-success', settings: {threadTitles:{enabled:false}}, mockOpts: {chunkDelay:250} };
module.exports = [
  Object.assign({}, common, {
    id:357, name:'Sending an image paints its preview immediately and replaces the pending bubble with one saved message',
    fixtures:fixtures('pending-357'),
    async body({cdp,dbPath}) {
      await load(cdp,'pending-357-a');
      await attachImage(cdp);
      await cdp.type('#chat-input','Immediate image preview');
      const immediate=await cdp.eval(`(() => {
        const request=Ipc.request;
        window.pendingHostPosts=0;
        Ipc.request=function(action,payload,timeout) {
          if(action!=='chatSend') return request.call(Ipc,action,payload,timeout);
          window.pendingHostPosts++;
          return new Promise((resolve,reject)=>setTimeout(()=>request.call(Ipc,action,payload,timeout).then(resolve,reject),750));
        };
        onChatSend();
        const pending=chatMessages.find(message=>message.pending && message.content==='Immediate image preview');
        const bubble=pending && document.querySelector('[data-msg-id="'+pending.id+'"]');
        const image=bubble && bubble.querySelector('.msg-attachment-image img');
        return {text:bubble&&bubble.textContent,src:image&&image.src,posts:pendingHostPosts,actions:bubble&&bubble.querySelectorAll('.msg-actions button').length};
      })()`);
      if(!immediate.text.includes('Immediate image preview') || !String(immediate.src).startsWith('data:image/png;base64,') || immediate.posts!==0 || immediate.actions!==0)
        throw new Error('message preview did not render before host send: '+JSON.stringify(immediate));
      await cdp.waitFor('chatMessages.some(m=>m.content==="Immediate image preview" && !m.pending)',10000,50,'pending bubble reconciled');
      await waitStreamingIdle(cdp,15000);
      const visible=await cdp.eval('chatMessages.filter(m=>m.role==="user" && m.content==="Immediate image preview").map(m=>({id:m.id,pending:!!m.pending,attachments:m.attachments.length}))');
      if(visible.length!==1 || visible[0].pending || visible[0].attachments!==1) throw new Error('preview duplicated or lost its saved attachment');
      const saved=seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='pending-357-a' AND role='user' AND content='Immediate image preview'");
      if(saved.length!==1 || saved[0].id!==visible[0].id) throw new Error('visible and persisted IDs did not reconcile');
      return 'cached image/text painted synchronously before delayed IPC; exactly one durable bubble and attachment remained';
    }
  }),
  Object.assign({}, common, {
    id:358, name:'Failed image persistence restores the draft and a retry leaves one successful message',
    fixtures:fixtures('pending-358'),
    async body({cdp,dbPath}) {
      await load(cdp,'pending-358-a'); await attachImage(cdp);
      await cdp.type('#chat-input','Recover this image');
      await cdp.eval(`(() => { const getter=getAttachmentsForSend; let first=true; window.getAttachmentsForSend=function(){const result=getter();if(first){first=false;result[0].base64='';}return result;}; onChatSend();return true;})()`);
      await cdp.waitFor('chatMessages.some(m=>m.pending && m.sendState==="failed") && document.getElementById("chat-input").value==="Recover this image" && attachmentState.length===1 && !isThreadRequestInFlight("pending-358-a")',10000,50,'failed save and recovered draft');
      if(seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='pending-358-a' AND content='Recover this image'").length) throw new Error('failed send was persisted despite rollback');
      await cdp.click('#chat-send-btn');
      await cdp.waitFor('chatMessages.some(m=>m.content==="Recover this image" && !m.pending)',10000,50,'retry saved');
      await waitStreamingIdle(cdp,15000);
      const count=await cdp.eval('chatMessages.filter(m=>m.content==="Recover this image").length');
      if(count!==1 || seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='pending-358-a' AND content='Recover this image'").length!==1)
        throw new Error('retry duplicated the failed preview or persisted message');
      return 'attachment failure rolled back, restored the draft, and retry replaced the failed preview with one saved message';
    }
  }),
  Object.assign({}, common, {
    id:359, name:'A delayed user-message confirmation stays in its originating chat after switching threads',
    fixtures:fixtures('pending-359',true), mockOpts:{chunkDelay:800},
    async body({cdp,dbPath}) {
      await load(cdp,'pending-359-a'); await attachImage(cdp);
      await cdp.type('#chat-input','Image belongs to A');
      await cdp.eval(`(() => {
        const handle=WebMessageRouter.handle;
        window.heldSaveMessages=[];
        const hold=function(event){let message;try{message=typeof event.data==='string'?JSON.parse(event.data):event.data;}catch{}
          if(message && (message.target==='chatMessageSaved' || (message.target==='appendChatMessage' && message.data.clientMessageId))){heldSaveMessages.push(event);return;}
          return handle.call(WebMessageRouter,event);};
        chrome.webview.removeEventListener('message',handle);
        chrome.webview.addEventListener('message',hold);
        window.releaseSaveMessages=()=>{
          chrome.webview.removeEventListener('message',hold);
          chrome.webview.addEventListener('message',handle);
          heldSaveMessages.splice(0).forEach(event=>handle.call(WebMessageRouter,event));
        };
        onChatSend();return true;
      })()`);
      await cdp.waitFor('heldSaveMessages.length>=2',10000,50,'save confirmations held');
      await cdp.eval('window.loadThread("pending-359-b"); true');
      await cdp.waitFor('activeThreadId==="pending-359-b" && chatMessages.some(m=>m.id==="pending-359-b-assistant")',10000,50,'B loaded');
      await cdp.eval('releaseSaveMessages(); true');
      if(await cdp.eval('chatMessages.some(m=>m.content==="Image belongs to A") || activeThreadId!=="pending-359-b"')) throw new Error('A confirmation leaked into B');
      if(seed.query(dbPath,"SELECT id FROM messages WHERE thread_id='pending-359-a' AND content='Image belongs to A'").length!==1) throw new Error('A message was not saved under A');
      return 'late save/attachment echo reconciled only its originating chat; B remained unchanged';
    }
  }),
  Object.assign({}, common, {
    id:360, name:'The first image send in a threadless chat binds its immediate preview to the newly created thread',
    async body({cdp,dbPath}) {
      await showChat();
      await cdp.eval('Ipc.postToHost("updateModelSettings",{model:"openai/gpt-5-mini",systemMessage:"",reasoning:"",temperature:""}); true');
      await cdp.waitFor('window._currentSettings && window._currentSettings.model==="openai/gpt-5-mini"',10000,50,'vision model selected');
      if(await cdp.eval('activeThreadId')!=='') throw new Error('fixture must start with a threadless chat');
      await attachImage(cdp); await cdp.type('#chat-input','First image send');
      const preview=await cdp.eval('onChatSend(); chatMessages.some(m=>m.pending && m.content==="First image send")');
      if(!preview) throw new Error('first image send did not appear synchronously');
      await cdp.waitFor('activeThreadId!=="" && chatMessages.some(m=>m.content==="First image send" && !m.pending)',10000,50,'first send saved and bound');
      await waitStreamingIdle(cdp,15000);
      const state=await cdp.eval('({thread:activeThreadId,users:chatMessages.filter(m=>m.role==="user" && m.content==="First image send").map(m=>m.id),newChatBusy:isThreadRequestInFlight("")})');
      if(state.users.length!==1 || state.newChatBusy) throw new Error('fresh-chat pending state did not reconcile');
      const saved=seed.query(dbPath,"SELECT id,thread_id FROM messages WHERE role='user' AND content='First image send'");
      if(saved.length!==1 || saved[0].id!==state.users[0] || saved[0].thread_id!==state.thread) throw new Error('fresh-chat IDs diverged between preview and DB');
      return 'threadless image preview appeared synchronously, adopted its durable thread/message IDs, and retired provisional request state';
    }
  })
];
