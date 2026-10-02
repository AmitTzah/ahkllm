// Image frames stay in place while local files decode; small previews persist.
(function(root) {
  var memory = new Map();
  var jobs = new Map();
  var generations = new Map();
  var MAX_PREVIEWS = 40;

  function escape(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, function(character) {
      return { '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[character];
    });
  }

  function frameDimensions(attachment) {
    if (attachment.thumbnail_width && attachment.thumbnail_height)
      return { width: attachment.thumbnail_width, height: attachment.thumbnail_height };
    var preview = attachment.previewElement;
    var width = preview && preview.naturalWidth || 300;
    var height = preview && preview.naturalHeight || 300;
    var scale = Math.min(300 / width, 300 / height, 1);
    return { width: Math.max(48, Math.round(width * scale)), height: Math.max(48, Math.round(height * scale)) };
  }

  function renderFrame(attachment, index) {
    var size = frameDimensions(attachment);
    return '<div class="image-preview-frame is-loading" data-image-index="' + index + '" style="width:' + size.width + 'px;height:' + size.height + 'px" role="group" aria-label="Image ' + escape(attachment.original_filename || '') + '" aria-busy="true">' +
      '<button type="button" class="image-preview-open" aria-label="Open image ' + escape(attachment.original_filename || '') + '">' +
      '<img data-preview-index="' + index + '" alt="' + escape(attachment.original_filename || 'image') + '" decoding="async" crossorigin="anonymous">' +
      '<span class="image-preview-status" role="status"><span class="image-preview-spinner"></span><span>Loading image…</span></span></button>' +
      '<button type="button" class="image-preview-download" title="Download original image" aria-label="Download original image"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M12 3v12m-5-5 5 5 5-5M5 16v4h14v-4"/></svg></button></div>';
  }

  function route(originalUrl) {
    var match = /^https:\/\/attachments\.ahk\.localhost\/attachment-images\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_-]+)\/original(?:\?.*)?$/.exec(originalUrl || '');
    return match ? { threadId: match[1], attachmentId: match[2] } : null;
  }

  function remember(key, url) {
    if (memory.has(key)) root.URL.revokeObjectURL(memory.get(key));
    memory.delete(key);
    memory.set(key, url);
    while (memory.size > MAX_PREVIEWS) {
      var first = memory.keys().next().value;
      root.URL.revokeObjectURL(memory.get(first));
      memory.delete(first);
    }
  }

  function makePreview(image, attachment) {
    var identity = route(attachment.original_url);
    if (!identity || !attachment.thumbnail_key) return Promise.resolve(null);
    var key = attachment.original_url;
    if (memory.has(key)) return Promise.resolve(memory.get(key));
    if (jobs.has(key)) return jobs.get(key);
    var width = image.naturalWidth, height = image.naturalHeight;
    var generation = generations.get(identity.threadId) || 0;
    var canvas = root.document.createElement('canvas');
    var scale = Math.min(600 / width, 600 / height, 1);
    canvas.width = Math.max(1, Math.round(width * scale));
    canvas.height = Math.max(1, Math.round(height * scale));
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    var job = new Promise(function(resolve, reject) {
      canvas.toBlob(function(blob) {
        if (!blob || blob.type !== 'image/webp') { reject(new Error('Thumbnail encoding unavailable')); return; }
        if ((generations.get(identity.threadId) || 0) !== generation) { reject(new Error('Chat was locked')); return; }
        var url = root.URL.createObjectURL(blob);
        remember(key, url);
        var reader = new root.FileReader();
        reader.onload = function() {
          var payload = Object.assign({}, identity, { key: attachment.thumbnail_key,
            base64: String(reader.result).split(',')[1], width: width, height: height });
          root.Ipc.request('cacheImageThumbnail', payload).catch(function() { /* Cache failure does not fail the chat. */ });
        };
        reader.readAsDataURL(blob);
        resolve(url);
      }, 'image/webp', 0.86);
    }).finally(function() { if (jobs.get(key) === job) jobs.delete(key); });
    jobs.set(key, job);
    return job;
  }

  function setState(frame, loading, error) {
    frame.classList.toggle('is-loading', loading);
    frame.classList.toggle('is-error', !!error);
    frame.setAttribute('aria-busy', String(loading));
    if (error) frame.querySelector('.image-preview-status').textContent = 'Image unavailable';
  }

  function hydrate(bubble, message) {
    (message.attachments || []).forEach(function(attachment, index) {
      var frame = bubble.querySelector('[data-image-index="' + index + '"]');
      if (!frame) return;
      var image = frame.querySelector('img');
      image.onclick = null;
      frame.onclick = function() { openOriginal(attachment.original_url || image.src, attachment.original_filename); };
      var download = frame.querySelector('.image-preview-download');
      if (download) download.onclick = function(event) { event.stopPropagation(); downloadOriginal(attachment, download); };
      var cached = memory.get(attachment.original_url) || attachment.thumbnail_url;
      var fallback = attachment.original_url || (attachment.base64 ? 'data:' + (attachment.mime_type || 'image/png') + ';base64,' + attachment.base64 : '');
      var source = cached || fallback;
      image.onload = function() {
        setState(frame, false, false);
        if (!cached && image.isConnected) {
          try { makePreview(image, attachment).then(function(url) {
            if (url && image.isConnected) { cached = url; if (image.src !== url) image.src = url; }
          }).catch(function() {}); }
          catch (error) { /* The original remains visible if canvas encoding fails. */ }
        }
      };
      image.onerror = function() {
        if (cached && fallback && image.src !== fallback) { cached = ''; image.src = fallback; return; }
        setState(frame, false, true);
      };
      if (attachment.previewElement) {
        if (image.complete && image.naturalWidth > 0) {
          setState(frame, false, false);
          if (root.requestAnimationFrame) root.requestAnimationFrame(function() { image.onload(); });
        }
      } else if (source) {
        // The loading frame is inserted before starting even a cold file decode.
        var load = function() { image.src = source; };
        if (root.requestAnimationFrame) root.requestAnimationFrame(load); else load();
      } else setState(frame, false, true);
    });
  }

  async function downloadOriginal(attachment, button) {
    if (button.disabled) return;
    var source = attachment.original_url || (attachment.previewElement && attachment.previewElement.src) ||
      (attachment.base64 ? 'data:' + (attachment.mime_type || 'image/png') + ';base64,' + attachment.base64 : '');
    if (!source) return;
    var identity = route(source);
    var generation = identity && (generations.get(identity.threadId) || 0);
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    button.title = 'Downloading original image…';
    try {
      var response = await root.fetch(source);
      if (!response.ok) throw new Error('Image unavailable');
      var blob = await response.blob();
      if (identity && (generations.get(identity.threadId) || 0) !== generation) return;
      var url = root.URL.createObjectURL(blob);
      var anchor = root.document.createElement('a');
      anchor.href = url;
      anchor.download = String(attachment.original_filename || 'image.png').split(/[\\/]/).pop() || 'image.png';
      root.document.body.appendChild(anchor);
      anchor.click(); anchor.remove();
      root.setTimeout(function() { root.URL.revokeObjectURL(url); }, 1000);
      button.title = 'Download original image';
    } catch (error) {
      button.title = 'Image download failed. Click to retry.';
    } finally {
      button.disabled = false;
      button.setAttribute('aria-busy', 'false');
    }
  }

  function openOriginal(source, filename) {
    var existing = root.document.querySelector('.image-overlay');
    if (existing) existing.remove();
    var overlay = root.document.createElement('div');
    overlay.className = 'image-overlay';
    var identity = route(source);
    overlay.dataset.threadId = identity ? identity.threadId : String(root.activeThreadId || '');
    overlay.style.display = 'flex';
    var status = root.document.createElement('div');
    status.className = 'image-preview-status';
    status.innerHTML = '<span class="image-preview-spinner"></span><span>Loading original image…</span>';
    var image = root.document.createElement('img');
    image.alt = filename || 'image';
    image.decoding = 'async';
    image.style.display = 'none';
    image.onload = function() { status.remove(); image.style.display = ''; };
    image.onerror = function() { status.textContent = 'Image unavailable'; };
    overlay.appendChild(status); overlay.appendChild(image);
    overlay.onclick = function() { overlay.remove(); };
    root.document.body.appendChild(overlay);
    image.src = source;
  }

  function clearThread(threadId) {
    generations.set(threadId, (generations.get(threadId) || 0) + 1);
    memory.forEach(function(url, key) {
      var identity = route(key);
      if (identity && identity.threadId === threadId) { root.URL.revokeObjectURL(url); memory.delete(key); }
    });
    jobs.forEach(function(job, key) {
      var identity = route(key);
      if (identity && identity.threadId === threadId) jobs.delete(key);
    });
    var overlay = root.document.querySelector('.image-overlay');
    if (overlay && (overlay.dataset.threadId === threadId || !overlay.dataset.threadId)) overlay.remove();
  }

  root.AttachmentImages = { renderFrame: renderFrame, hydrate: hydrate, openOriginal: openOriginal, downloadOriginal: downloadOriginal, frameDimensions: frameDimensions, clearThread: clearThread };
})(window);
