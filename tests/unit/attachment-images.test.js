const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function loadImages() {
  const frames = [], posts = [], revoked = [], blobs = [], downloads = [], fetches = [], timers = [];
  let created = 0;
  const root = {
    activeThreadId: 'A', requestAnimationFrame(fn) { frames.push(fn); },
    URL: { createObjectURL() { return 'blob:preview-' + (++created); }, revokeObjectURL(url) { revoked.push(url); } },
    Ipc: { request(action, payload) { posts.push({action,payload}); return Promise.resolve(); } },
    fetch(source) { fetches.push(source); return Promise.resolve({ok:true,blob:()=>Promise.resolve({type:'image/png',original:true})}); },
    setTimeout(fn) { timers.push(fn); },
    FileReader: class {
      readAsDataURL() { this.result = 'data:image/webp;base64,fixture'; this.onload(); }
    },
    document: {
      querySelector() { return null; },
      createElement(tag) {
        if (tag === 'canvas') return { getContext() { return { drawImage() {} }; }, toBlob(callback) { blobs.push(callback); } };
        if (tag === 'a') return {click(){downloads.push({href:this.href,filename:this.download});},remove(){}};
        return { dataset:{},style:{},appendChild(){},remove(){} };
      },
      body: { appendChild() {} }
    }
  };
  root.window = root;
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../../webui/js/chat/attachment-images.js'), 'utf8'), root);
  return { root, frames, posts, revoked, blobs, downloads, fetches, timers, images: root.AttachmentImages };
}

function frame() {
  const classes = new Set(['is-loading']);
  const status = {textContent:''};
  const image = {src:'',complete:false,isConnected:true,naturalWidth:4096,naturalHeight:6144};
  const download = {disabled:false,attributes:{},setAttribute(name,value){this.attributes[name]=value;}};
  const wrapper = { image, status, attributes:{},
    classList: { toggle(name,on) { if(on) classes.add(name); else classes.delete(name); } },
    setAttribute(name,value) { this.attributes[name]=value; },
    querySelector(selector) { return selector==='img' ? image : selector==='.image-preview-download' ? download : status; } };
  return { wrapper, image, download, classes, bubble: { querySelector: () => wrapper } };
}

const attachment = {id:'image-1',attachment_type:'image',original_filename:'cover.png',thumbnail_key:'version-1',
  original_url:'https://attachments.ahk.localhost/attachment-images/A/image-1/original?v=version-1',thumbnail_width:200,thumbnail_height:300};

describe('Cached image frames', () => {
  it('reserves dimensions and includes a loading indicator without embedding original image bytes', () => {
    const ctx=loadImages();
    const html=ctx.images.renderFrame(attachment,0);
    assert.ok(html.includes('width:200px;height:300px'));
    assert.ok(html.includes('image-preview-spinner') && html.includes('Loading image'));
    assert.ok(html.includes('aria-busy="true"'));
    assert.ok(!html.includes('src='));
  });

  it('paints the loading frame before starting a cold decode, then caches a small preview once', async () => {
    const ctx=loadImages(), view=frame();
    ctx.images.hydrate(view.bubble,{attachments:[attachment]});
    assert.equal(view.image.src,'');
    assert.ok(view.classes.has('is-loading'));
    ctx.frames.shift()();
    assert.equal(view.image.src,attachment.original_url);
    view.image.onload();
    assert.ok(!view.classes.has('is-loading'));
    ctx.blobs.shift()({type:'image/webp'});
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(view.image.src,'blob:preview-1');
    assert.equal(ctx.posts.length,1);
    assert.equal(ctx.posts[0].payload.threadId,'A');
    assert.equal(ctx.posts[0].payload.attachmentId,'image-1');
    assert.equal(ctx.posts[0].payload.width,4096);
    view.image.onload();
    assert.equal(ctx.blobs.length,0,'loading the generated blob must not start another encoding loop');
    const reopened=frame();
    ctx.images.hydrate(reopened.bubble,{attachments:[attachment]});
    ctx.frames.shift()();
    assert.equal(reopened.image.src,'blob:preview-1');
  });

  it('uses persisted thumbnails and falls back to the original if the cache is corrupt', () => {
    const ctx=loadImages(), view=frame();
    const cached=Object.assign({},attachment,{thumbnail_url:'https://attachments.ahk.localhost/attachment-images/A/image-1/thumbnail'});
    ctx.images.hydrate(view.bubble,{attachments:[cached]});
    ctx.frames.shift()();
    assert.equal(view.image.src,cached.thumbnail_url);
    view.image.onerror();
    assert.equal(view.image.src,attachment.original_url);
    view.image.onerror();
    assert.ok(view.classes.has('is-error'));
    assert.equal(view.wrapper.status.textContent,'Image unavailable');
  });

  it('does not retain or persist an in-flight private thumbnail after the chat is locked', async () => {
    const ctx=loadImages(), view=frame();
    ctx.images.hydrate(view.bubble,{attachments:[attachment]});
    ctx.frames.shift()(); view.image.onload();
    ctx.images.clearThread('A');
    ctx.blobs.shift()({type:'image/webp'});
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(ctx.posts.length,0);
    assert.equal(view.image.src,attachment.original_url);
  });

  it('clears cached blobs when locking and avoids background encoding from detached images', async () => {
    const ctx=loadImages(), view=frame();
    ctx.images.hydrate(view.bubble,{attachments:[attachment]});
    ctx.frames.shift()(); view.image.onload(); ctx.blobs.shift()({type:'image/webp'});
    await new Promise(resolve=>setImmediate(resolve));
    ctx.images.clearThread('A');
    assert.deepEqual(ctx.revoked,['blob:preview-1']);
    const detached=frame(); detached.image.isConnected=false;
    ctx.images.hydrate(detached.bubble,{attachments:[attachment]});
    ctx.frames.shift()(); detached.image.onload();
    assert.equal(ctx.blobs.length,0);
  });

  it('downloads the original with its filename, stops preview click propagation, and revokes the download URL', async () => {
    const ctx=loadImages(), view=frame();
    ctx.images.hydrate(view.bubble,{attachments:[Object.assign({},attachment,{thumbnail_url:'https://example.test/tiny.webp'})]});
    let stopped=false;
    view.download.onclick({stopPropagation(){stopped=true;}});
    assert.ok(stopped);
    assert.ok(view.download.disabled);
    await new Promise(resolve=>setImmediate(resolve));
    assert.deepEqual(ctx.fetches,[attachment.original_url]);
    assert.deepEqual(ctx.downloads,[{href:'blob:preview-1',filename:'cover.png'}]);
    assert.equal(view.download.disabled,false);
    assert.equal(view.download.attributes['aria-busy'],'false');
    ctx.timers.shift()();
    assert.deepEqual(ctx.revoked,['blob:preview-1']);
  });

  it('rejects failed original reads without downloading and allows retry', async () => {
    const ctx=loadImages(), view=frame();
    ctx.root.fetch=()=>Promise.resolve({ok:false});
    await ctx.images.downloadOriginal(attachment,view.download);
    assert.equal(ctx.downloads.length,0);
    assert.ok(view.download.title.includes('failed'));
    assert.equal(view.download.disabled,false);
    ctx.root.fetch=()=>Promise.resolve({ok:true,blob:()=>Promise.resolve({})});
    await ctx.images.downloadOriginal(attachment,view.download);
    assert.equal(ctx.downloads.length,1);
  });

  it('does not save an in-flight private image after locking its chat', async () => {
    const ctx=loadImages(), view=frame();
    let finish;
    ctx.root.fetch=()=>Promise.resolve({ok:true,blob:()=>new Promise(resolve=>{finish=resolve;})});
    const downloading=ctx.images.downloadOriginal(attachment,view.download);
    await new Promise(resolve=>setImmediate(resolve));
    ctx.images.clearThread('A');
    finish({}); await downloading;
    assert.equal(ctx.downloads.length,0);
    assert.equal(view.download.disabled,false);
  });
});
