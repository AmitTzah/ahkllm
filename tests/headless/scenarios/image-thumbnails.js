'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { showChat } = require('./helpers');
const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Z7ZsAAAAASUVORK5CYII=';
const fixtures = {
  threads: [{id:'image-chat',title:'Image chat',active_leaf_id:'image-answer'}, {id:'other-chat',title:'Other chat'}],
  messages: [{id:'image-question',thread_id:'image-chat',role:'user',content:'Saved cover'},
    {id:'image-answer',thread_id:'image-chat',role:'assistant',content:'Saved answer',parent_id:'image-question'}],
  attachments: [{id:'cover',message_id:'image-question',attachment_type:'image',file_path:'attachments/legacy.png',mime_type:'image/png',original_filename:'cover.png',file_size:33554432}]
};
function preLaunch(dataDir) {
  fs.mkdirSync(path.join(dataDir,'attachments'),{recursive:true});
  const image=Buffer.alloc(32*1024*1024);
  Buffer.from(PNG,'base64').copy(image);
  fs.writeFileSync(path.join(dataDir,'attachments','legacy.png'),image);
}
async function load(cdp,dbPath) {
  await showChat();
  await cdp.eval('window.loadThread("image-chat"); true');
  await cdp.waitFor('activeThreadId==="image-chat" && document.querySelector(".image-preview-frame")',10000,50,'image chat metadata');
}
const ready = 'document.querySelector(".image-preview-frame img").naturalWidth>0 && !document.querySelector(".image-preview-frame").classList.contains("is-loading")';
module.exports = [
  {id:361,regression:true,name:'Saved large images show stable loading frames, persist small previews, and enlarge the original',
    mode:'sse-success', fixtures, preLaunch,
    async body({cdp,dbPath,dataDir}) {
      await cdp.send('Fetch.enable',{patterns:[{urlPattern:'*attachment-images*',requestStage:'Request'}]});
      await load(cdp,dbPath);
      const before=await cdp.eval(`(() => {
        const frame=document.querySelector('.image-preview-frame');
        return {loading:frame.classList.contains('is-loading'),status:frame.textContent,width:frame.offsetWidth,height:frame.offsetHeight,
          bytes:JSON.stringify(chatMessages).length,base64:chatMessages.some(m=>(m.attachments||[]).some(a=>a.base64))};
      })()`);
      assert.ok(before.loading && before.status.includes('Loading image'));
      assert.ok(before.bytes<10000 && !before.base64,'large originals must stay out of chat-load IPC');
      await cdp.send('Fetch.disable');
      await cdp.waitFor(ready,15000,50,'original decoded and thumbnail visible');
      const after=await cdp.eval('({width:document.querySelector(".image-preview-frame").offsetWidth,height:document.querySelector(".image-preview-frame").offsetHeight})');
      assert.equal(after.width,before.width); assert.equal(after.height,before.height);
      await cdp.waitFor('document.querySelector(".image-preview-frame img").src.startsWith("blob:")',10000,50,'small preview generated');
      const cacheDir=path.join(dataDir,'image-thumbnails');
      for(let attempt=0;attempt<100;attempt++) {
        if(fs.existsSync(cacheDir) && fs.readdirSync(cacheDir).some(name=>name.endsWith('.ini'))) break;
        await new Promise(resolve=>setTimeout(resolve,50));
      }
      const previews=fs.readdirSync(cacheDir).filter(name=>name.endsWith('.webp'));
      assert.equal(previews.length,1); assert.ok(fs.statSync(path.join(cacheDir,previews[0])).size<512*1024);
      await cdp.eval('AttachmentImages.clearThread("image-chat"); window.loadThread("other-chat"); true');
      await cdp.waitFor('activeThreadId==="other-chat"',10000,50,'other chat');
      await cdp.eval('window.loadThread("image-chat"); true');
      await cdp.waitFor(ready+' && document.querySelector(".image-preview-frame img").src.includes("/thumbnail")',10000,50,'persisted small preview');
      await cdp.click('.image-preview-frame');
      await cdp.waitFor('document.querySelector(".image-overlay img") && document.querySelector(".image-overlay img").naturalWidth>0',15000,50,'original enlarged');
      assert.ok(await cdp.eval('document.querySelector(".image-overlay img").src.includes("/original")'));
      assert.equal(fs.statSync(path.join(dataDir,'attachments','legacy.png')).size,32*1024*1024);
      return '32 MiB original stayed out of IPC; stable spinner, small disk cache, and original enlargement worked';
    }
  },
  {id:362,regression:true,name:'Image routes reject foreign and locked chats and missing originals show an unavailable frame',
    mode:'sse-success', fixtures, preLaunch,
    async body({cdp,dbPath,dataDir}) {
      await load(cdp,dbPath);
      const original=await cdp.eval('chatMessages.find(m=>m.id==="image-question").attachments[0].original_url');
      const response=await cdp.eval('fetch('+JSON.stringify(original)+').then(async r=>({status:r.status,bytes:(await r.arrayBuffer()).byteLength}))');
      assert.equal(response.status,200,JSON.stringify(response));
      await cdp.waitFor(ready,15000,50,'saved image loaded');
      const url=await cdp.eval('chatMessages.find(m=>m.id==="image-question").attachments[0].original_url');
      assert.equal(await cdp.eval('fetch('+JSON.stringify(url.replace('/image-chat/','/other-chat/'))+').then(r=>r.status)'),403);
      await cdp.eval('Ipc.request("setThreadLock",{threadId:"image-chat",mode:"set",salt:"0123456789abcdef0123456789abcdef",passwordHash:"'+ 'a'.repeat(64)+'",iterations:600000})');
      await cdp.eval('Ipc.request("lockChatNow",{threadId:"image-chat"})');
      assert.equal(await cdp.eval('fetch('+JSON.stringify(url)+').then(r=>r.status)'),403);
      await cdp.eval('Ipc.request("unlockThread",{threadId:"image-chat",passwordHash:"'+ 'a'.repeat(64)+'"})');
      await cdp.waitFor(ready,10000,50,'unlocked image');
      await cdp.eval('AttachmentImages.clearThread("image-chat"); window.loadThread("other-chat"); true');
      await cdp.waitFor('activeThreadId==="other-chat"',10000,50,'leave image chat');
      fs.unlinkSync(path.join(dataDir,'attachments','legacy.png'));
      await cdp.eval('window.loadThread("image-chat"); true');
      await cdp.waitFor('document.querySelector(".image-preview-frame.is-error")',10000,50,'missing image unavailable');
      assert.ok(await cdp.eval('document.querySelector(".image-preview-frame").textContent.includes("Image unavailable") && chatMessages.some(m=>m.content==="Saved answer")'));
      return 'foreign/locked URLs denied; unlocking restored access; missing files preserved chat and stopped spinner';
    }
  },
  {id:365,regression:true,name:'Hover image download saves the original bytes without opening the enlargement overlay',
    mode:'sse-success', fixtures, preLaunch,
    async body({cdp,dbPath,dataDir}) {
      const downloadDir=path.join(dataDir,'downloads');
      fs.mkdirSync(downloadDir,{recursive:true});
      await cdp.send('Browser.setDownloadBehavior',{behavior:'allow',downloadPath:downloadDir});
      await load(cdp,dbPath); await cdp.waitFor(ready,15000,50,'original image visible');
      const state=await cdp.eval(`(() => {
        const frame=document.querySelector('.image-preview-frame'), button=frame.querySelector('.image-preview-download');
        return {opacity:getComputedStyle(button).opacity,x:frame.getBoundingClientRect().left+15,y:frame.getBoundingClientRect().top+15};
      })()`);
      assert.equal(state.opacity,'0');
      await cdp.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:state.x,y:state.y});
      await cdp.waitFor('getComputedStyle(document.querySelector(".image-preview-download")).opacity==="1"',5000,50,'hover download button');
      await cdp.click('.image-preview-download');
      await cdp.waitFor('document.querySelector(".image-preview-download").disabled===false',10000,50,'download read completed');
      assert.equal(await cdp.eval('document.querySelector(".image-overlay")!==null'),false);
      const saved=path.join(downloadDir,'cover.png');
      for(let attempt=0;attempt<200;attempt++) {
        if(fs.existsSync(saved)) break;
        await new Promise(resolve=>setTimeout(resolve,50));
      }
      const digest=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
      assert.equal(digest(saved),digest(path.join(dataDir,'attachments','legacy.png')));
      assert.equal(fs.statSync(saved).size,32*1024*1024);
      return 'Hover revealed download action; saved filename and all 32 MiB of original bytes matched; image overlay stayed closed';
    }
  }
];
