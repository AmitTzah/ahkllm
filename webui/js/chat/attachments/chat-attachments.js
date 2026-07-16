// ======================================================
// chat-attachments.js — File/image attachment core (state, render, send)
//
// Drag-drop, paste-from-clipboard, browse button,
// pdf.js PDF extraction, officeparser for all office formats.
// ======================================================

// Attachment state: array of { _id, type, filename, mimeType, base64, size, extractedText }
var attachmentState = [];
var _attachmentIdCounter = 0;

// Constants
var ALLOWED_EXTENSIONS = [
    // Images
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp',
    // Documents
    'pdf', 'docx', 'pptx', 'xlsx', 'odt', 'odp', 'ods', 'rtf',
    // Text files
    'txt', 'md', 'py', 'js', 'ahk', 'json', 'xml', 'csv',
    'ini', 'cfg', 'yaml', 'yml', 'log', 'html', 'css', 'sql',
    'bat', 'ps1', 'sh', 'java', 'c', 'cpp', 'h', 'rs', 'go',
    'ts', 'tsx', 'jsx', 'toml'
];

var MAX_FILE_SIZE = 50 * 1024 * 1024;     // 50MB file on disk
var MAX_BASE64_SIZE = 10 * 1024 * 1024;   // 10MB base64 payload limit

// Check if file extension is allowed
function isAllowedFile(filename) {
    var ext = filename.split('.').pop().toLowerCase();
    return ALLOWED_EXTENSIONS.indexOf(ext) !== -1;
}

// Get icon emoji for attachment type
function getAttachmentIcon(mimeType, filename) {
    if (mimeType.indexOf('image/') === 0) return 'ðŸ–¼ï¸';
    if (mimeType === 'application/pdf') return 'ðŸ“•';
    if (mimeType.indexOf('wordprocessing') !== -1) return 'ðŸ“„';
    if (mimeType.indexOf('presentation') !== -1) return 'ðŸ“Š';
    if (mimeType.indexOf('spreadsheet') !== -1) return 'ðŸ“ˆ';
    var ext = (filename || '').split('.').pop().toLowerCase();
    if (['txt', 'md', 'log', 'rtf'].indexOf(ext) !== -1) return 'ðŸ“';
    if (['py', 'js', 'ahk', 'java', 'c', 'cpp', 'h', 'rs', 'go', 'ts', 'tsx', 'jsx', 'sql', 'bat', 'ps1', 'sh'].indexOf(ext) !== -1) return 'ðŸ’»';
    if (['json', 'xml', 'csv', 'ini', 'cfg', 'yaml', 'yml', 'toml', 'xlsx', 'ods'].indexOf(ext) !== -1) return 'ðŸ“‹';
    if (['html', 'css'].indexOf(ext) !== -1) return 'ðŸŒ';
    if (['odt', 'odp'].indexOf(ext) !== -1 || ['pptx'].indexOf(ext) !== -1) return 'ðŸ“Ž';
    return 'ðŸ“Ž';
}

// Add a file to the attachment state
function addAttachment(file) {
    // Check file size
    if (file.size > MAX_FILE_SIZE) {
        showErrorBanner('File "' + file.name + '" exceeds 50MB limit.');
        return;
    }

    // Check extension
    if (!isAllowedFile(file.name)) {
        var ext = file.name.split('.').pop().toLowerCase();
        showErrorBanner('File type .' + ext + ' is not supported.');
        return;
    }

    var mimeType = file.type || 'application/octet-stream';
    var attId = ++_attachmentIdCounter;
    var attachment = {
        _id: attId,
        type: getAttachmentTypeFromMime(mimeType, file.name),
        filename: file.name,
        mimeType: mimeType,
        base64: null,
        size: file.size,
        extractedText: null,
        loading: true   // all files start loading until FileReader + extraction completes
    };

    attachmentState.push(attachment);
    renderAttachmentBar();

    var reader = new FileReader();
    reader.onload = function(e) {
        // Look up by ID â€” attachment may have been removed while FileReader was reading
        var att = findAttachmentById(attId);
        if (!att) return;

        var arrayBuffer = e.target.result;

        // Get base64 for sending
        var bytes = new Uint8Array(arrayBuffer);
        var binary = '';
        for (var i = 0; i < bytes.byteLength; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        att.base64 = btoa(binary);

        // Compute SHA-256 hash for content-addressable storage
        crypto.subtle.digest('SHA-256', arrayBuffer).then(function(hashBuffer) {
            var hashArray = Array.from(new Uint8Array(hashBuffer));
            att.contentHash = hashArray.map(function(b) { return b.toString(16).padStart(2, '0'); }).join('');
        }).catch(function() {
            att.contentHash = null;
        });

        // Re-render to show thumbnail for images
        if (att.type === 'image') {
            att.loading = false;
            renderAttachmentBar();
        }

        // Extract text for PDF/office/text files
        if (att.type === 'pdf') {
            extractPDFText(arrayBuffer, attId);
        } else if (att.type === 'docx' || att.type === 'pptx' || att.type === 'xlsx' || att.type === 'odt' || att.type === 'odp' || att.type === 'ods' || att.type === 'rtf') {
            extractOfficeText(arrayBuffer, attId);
        } else if (att.type === 'text_file') {
            try {
                att.extractedText = new TextDecoder('utf-8').decode(new Uint8Array(arrayBuffer));
            } catch (e) {
                att.extractedText = '(could not decode text)';
            }
            att.loading = false;
            renderAttachmentBar();
        }
    };
    reader.readAsArrayBuffer(file);
}

// Get attachment_type from mime
function getAttachmentTypeFromMime(mimeType, filename) {
    if (mimeType.indexOf('image/') === 0) return 'image';
    if (mimeType === 'application/pdf') return 'pdf';
    if (mimeType.indexOf('wordprocessing') !== -1) return 'docx';
    if (mimeType.indexOf('presentation') !== -1) return 'pptx';
    if (mimeType.indexOf('spreadsheet') !== -1) return 'xlsx';
    // Fall back to extension-based detection for formats with generic MIME types
    var ext = (filename || '').split('.').pop().toLowerCase();
    if (ext === 'odt') return 'odt';
    if (ext === 'odp') return 'odp';
    if (ext === 'ods') return 'ods';
    if (ext === 'rtf') return 'rtf';
    return 'text_file';
}

// Look up attachment by unique ID (safe across async callbacks after removals)
function findAttachmentById(id) {
    for (var i = 0; i < attachmentState.length; i++) {
        if (attachmentState[i]._id === id) return attachmentState[i];
    }
    return null;
}

// Remove an attachment from state
function removeAttachment(index) {
    console.log('[ATTACH-JS] removeAttachment called: index=' + index + ' stateLen=' + attachmentState.length);
    if (index >= 0 && index < attachmentState.length) {
        attachmentState.splice(index, 1);
        console.log('[ATTACH-JS] attachment removed, new stateLen=' + attachmentState.length);
        renderAttachmentBar();
    } else {
        console.log('[ATTACH-JS] removeAttachment: invalid index ' + index);
    }
}

// Render the attachment bar DOM
function renderAttachmentBar() {
    var bar = document.getElementById('attachment-bar');
    if (!bar) return;

    bar.innerHTML = '';

    if (attachmentState.length === 0) {
        bar.style.display = 'none';
        // Re-enable send button when no attachments
        var sendBtn = document.getElementById('chat-send-btn');
        if (sendBtn && !isLoading) sendBtn.disabled = false;
        return;
    }

    // Check if any attachment is still loading
    var anyLoading = false;
    for (var i = 0; i < attachmentState.length; i++) {
        if (attachmentState[i].loading) { anyLoading = true; break; }
    }
    // Gray out send button while attachments are processing
    var sendBtn = document.getElementById('chat-send-btn');
    if (sendBtn) sendBtn.disabled = anyLoading;

    bar.style.display = 'flex';
    console.log('[ATTACH-JS] bar shown, innerHTML children=' + bar.children.length);

    for (var i = 0; i < attachmentState.length; i++) {
        var att = attachmentState[i];
        var item = document.createElement('div');
        item.className = 'attachment-item';

        // Icon or thumbnail
        if (att.type === 'image' && att.base64) {
            var thumb = document.createElement('img');
            thumb.className = 'attachment-thumb';
            thumb.src = 'data:' + att.mimeType + ';base64,' + att.base64;
            item.appendChild(thumb);
        } else if (att.loading) {
            var spinner = document.createElement('div');
            spinner.className = 'attachment-spinner';
            item.appendChild(spinner);
        } else {
            var icon = document.createElement('span');
            icon.className = 'attachment-icon';
            icon.textContent = getAttachmentIcon(att.mimeType, att.filename);
            item.appendChild(icon);
        }

        // Filename
        var nameSpan = document.createElement('span');
        nameSpan.className = 'attachment-name';
        nameSpan.textContent = att.filename;
        nameSpan.title = att.filename;
        item.appendChild(nameSpan);

        // Scanned PDF warning
        if (att.extractedText === '__SCANNED_PDF__') {
            var scanWarn = document.createElement('span');
            scanWarn.style.cssText = 'font-size:0.6rem;color:var(--warning);flex-shrink:0;';
            scanWarn.textContent = '\u26A0\uFE0F Scanned';
            item.appendChild(scanWarn);
        }

        // CDN unavailable warning
        if (att.extractedText === '__LIBRARY_UNAVAILABLE__') {
            var warnSpan = document.createElement('span');
            warnSpan.style.cssText = 'font-size:0.65rem;color:var(--warning);flex-shrink:0;';
            warnSpan.textContent = 'âš ï¸ Text extraction unavailable';
            item.appendChild(warnSpan);
        }

        // Remove button â€” use data attribute for delegation
        var removeBtn = document.createElement('button');
        removeBtn.className = 'attachment-remove';
        removeBtn.textContent = '\u00D7';
        removeBtn.title = 'Remove ' + att.filename;
        removeBtn.setAttribute('data-idx', i);
        item.appendChild(removeBtn);

        bar.appendChild(item);
    }
}

// Get attachments ready for sending (check base64 size limit)
function getAttachmentsForSend() {
    var result = [];
    for (var i = 0; i < attachmentState.length; i++) {
        var att = attachmentState[i];
        if (!att.base64) continue;

        // Check 10MB base64 limit
        if (att.base64.length > MAX_BASE64_SIZE) {
            showErrorBanner('File "' + att.filename + '" is too large to send (max ~7.5MB for images).');
            continue;
        }

        result.push({
            type: att.type,
            filename: att.filename,
            mimeType: att.mimeType,
            base64: att.base64,
            size: att.size,
            extractedText: att.extractedText || '',
            contentHash: att.contentHash || ''
        });
    }
    return result;
}

// Clear all attachments
function clearAttachments() {
    attachmentState = [];
    renderAttachmentBar();
}

// Error banner in chat
function showErrorBanner(message) {
    var container = document.getElementById('chat-messages');
    if (!container) return;
    var el = document.createElement('div');
    el.className = 'error-banner';
    el.style.cssText = 'background:var(--danger);color:var(--bg-panel);padding:8px 16px;margin:8px;border-radius:6px;font-size:0.85rem;display:flex;justify-content:space-between;align-items:center;';
    el.innerHTML = '<span>' + message.replace(/</g, '<').replace(/>/g, '>') + '</span><button onclick="this.parentElement.remove()" style="background:none;border:none;color:inherit;font-size:1.2rem;cursor:pointer;">&times;</button>';
    container.appendChild(el);
    container.scrollTop = container.scrollHeight;
}

