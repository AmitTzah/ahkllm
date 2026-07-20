// ======================================================
// chat-attachments.js -- File/image attachment core (state, render, send)
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
    'pdf', 'docx', 'pptx', 'xlsx', 'odt', 'odp', 'ods', 'rtf', 'epub',
    // Text files
    'txt', 'md', 'py', 'js', 'ahk', 'json', 'xml', 'csv',
    'ini', 'cfg', 'yaml', 'yml', 'log', 'html', 'css', 'sql',
    'bat', 'ps1', 'sh', 'java', 'c', 'cpp', 'h', 'rs', 'go',
    'ts', 'tsx', 'jsx', 'toml'
];

var MAX_FILE_SIZE = 50 * 1024 * 1024;     // 50MB file on disk

// Check if file extension is allowed
function isAllowedFile(filename) {
    var ext = filename.split('.').pop().toLowerCase();
    return ALLOWED_EXTENSIONS.indexOf(ext) !== -1;
}

// Get icon for attachment type. Returns SVG path for language-specific icons,
// or Lucide icon name for documents/generic types.
function getAttachmentIcon(mimeType, filename) {
    var ext = (filename || '').split('.').pop().toLowerCase();

    // File-type branded icons (Simple Icons + VS Code Icons) — checked first
    var svgMap = {
        // Languages (Simple Icons)
        'py': 'icons/filetypes/python.svg',
        'js': 'icons/filetypes/javascript.svg',
        'jsx': 'icons/filetypes/javascript.svg',
        'ts': 'icons/filetypes/typescript.svg',
        'tsx': 'icons/filetypes/typescript.svg',
        'go': 'icons/filetypes/go.svg',
        'rs': 'icons/filetypes/rust.svg',
        'c': 'icons/filetypes/c.svg',
        'h': 'icons/filetypes/c.svg',
        'cpp': 'icons/filetypes/cplusplus.svg',
        'java': 'icons/filetypes/java.svg',
        'html': 'icons/filetypes/html5.svg',
        'htm': 'icons/filetypes/html5.svg',
        'css': 'icons/filetypes/css3.svg',
        'ahk': 'icons/filetypes/ahk.svg',
        // Documents (VS Code Icons)
        'pdf': 'icons/filetypes/pdf.svg',
        'docx': 'icons/filetypes/docx.svg',
        'xlsx': 'icons/filetypes/xlsx.svg',
        'pptx': 'icons/filetypes/pptx.svg',
        'epub': 'icons/filetypes/epub.svg',
        'odt': 'icons/filetypes/odt.svg',
        'odp': 'icons/filetypes/odp.svg',
        'ods': 'icons/filetypes/ods.svg',
        'md': 'icons/filetypes/markdown.svg',
        'txt': 'icons/filetypes/txt.svg',
        'log': 'icons/filetypes/txt.svg',
        // Data/Config
        'json': 'icons/filetypes/json.svg',
        'yaml': 'icons/filetypes/yaml.svg',
        'yml': 'icons/filetypes/yaml.svg',
        'xml': 'icons/filetypes/xml.svg',
        'toml': 'icons/filetypes/toml.svg',
        'csv': 'icons/filetypes/csv.svg',
        'ini': 'icons/filetypes/ini.svg',
        'cfg': 'icons/filetypes/cfg.svg',
        'rtf': 'icons/filetypes/rtf.svg',
        'sql': 'icons/filetypes/sqlite.svg',
        // Shell
        'sh': 'icons/filetypes/gnubash.svg',
        'bat': 'icons/filetypes/bat.svg',
        'ps1': 'icons/filetypes/powershell.svg',
        // Images
        'png': 'icons/filetypes/image.svg',
        'jpg': 'icons/filetypes/image.svg',
        'jpeg': 'icons/filetypes/image.svg',
        'gif': 'icons/filetypes/image.svg',
        'webp': 'icons/filetypes/image.svg',
        'bmp': 'icons/filetypes/image.svg',
    };
    if (svgMap.hasOwnProperty(ext)) return svgMap[ext];

    // MIME-based fallbacks (for types detected by MIME, not extension)
    if (mimeType.indexOf('image/') === 0) return 'image';
    if (mimeType.indexOf('wordprocessing') !== -1) return 'file-text';
    if (mimeType.indexOf('presentation') !== -1) return 'presentation';
    if (mimeType.indexOf('spreadsheet') !== -1) return 'file-spreadsheet';

    return 'paperclip';
}

// Test if an icon name is an SVG path (starts with 'icons/')
function _isSvgIcon(iconName) {
    return iconName && iconName.indexOf('icons/') === 0;
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
        // Look up by ID -- attachment may have been removed while FileReader was reading
        var att = findAttachmentById(attId);
        if (!att) return;

        var arrayBuffer = e.target.result;

        // Get base64 for sending (chunked approach for performance)
        var bytes = new Uint8Array(arrayBuffer);
        var chunks = [];
        var CHUNK = 8192;
        for (var i = 0; i < bytes.length; i += CHUNK) {
            var end = Math.min(i + CHUNK, bytes.length);
            var chunkStr = '';
            for (var j = i; j < end; j++) { chunkStr += String.fromCharCode(bytes[j]); }
            chunks.push(chunkStr);
        }
        att.base64 = btoa(chunks.join(''));

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
        } else if (att.type === 'docx' || att.type === 'pptx' || att.type === 'xlsx' || att.type === 'odt' || att.type === 'odp' || att.type === 'ods' || att.type === 'rtf' || att.type === 'epub') {
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
    if (mimeType === 'application/epub+zip') return 'epub';
    if (mimeType.indexOf('wordprocessing') !== -1) return 'docx';
    if (mimeType.indexOf('presentation') !== -1) return 'pptx';
    if (mimeType.indexOf('spreadsheet') !== -1) return 'xlsx';
    // Fall back to extension-based detection for formats with generic MIME types
    var ext = (filename || '').split('.').pop().toLowerCase();
    if (ext === 'odt') return 'odt';
    if (ext === 'odp') return 'odp';
    if (ext === 'ods') return 'ods';
    if (ext === 'rtf') return 'rtf';
    if (ext === 'epub') return 'epub';
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
    if (index >= 0 && index < attachmentState.length) {
        attachmentState.splice(index, 1);
        renderAttachmentBar();
    }
}

// Render the attachment bar DOM
function renderAttachmentBar() {
    var bar = document.getElementById('attachment-bar');
    if (!bar) return;

    bar.innerHTML = '';

    if (attachmentState.length === 0) {
        bar.style.display = 'none';
        var sendBtn = document.getElementById('chat-send-btn');
        if (sendBtn && !isLoading) sendBtn.disabled = false;
        return;
    }

    // Check if any attachment is still loading
    var anyLoading = false;
    for (var i = 0; i < attachmentState.length; i++) {
        if (attachmentState[i].loading) { anyLoading = true; break; }
    }
    var sendBtn = document.getElementById('chat-send-btn');
    if (sendBtn) sendBtn.disabled = anyLoading;

    bar.style.display = 'flex';

    for (var i = 0; i < attachmentState.length; i++) {
        _renderAttachmentItem(attachmentState[i], i, bar);
    }

    if (typeof lucide !== 'undefined') lucide.createIcons();
}

// Render a single attachment item in the attachment bar
function _renderAttachmentItem(att, idx, bar) {
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
        var iconName = getAttachmentIcon(att.mimeType, att.filename);
        if (_isSvgIcon(iconName)) {
            var img = document.createElement('img');
            img.src = iconName;
            img.className = 'attachment-icon';
            item.appendChild(img);
        } else {
            var icon = document.createElement('i');
            icon.setAttribute('data-lucide', iconName);
            icon.className = 'attachment-icon';
            item.appendChild(icon);
        }
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
        warnSpan.textContent = '\u26A0\uFE0F Text extraction unavailable';
        item.appendChild(warnSpan);
    }

    // Copy extracted text button
    if (att.extractedText && att.extractedText !== '__SCANNED_PDF__' && att.extractedText !== '__LIBRARY_UNAVAILABLE__') {
        var copyBtn = document.createElement('button');
        copyBtn.className = 'attachment-copy-text';
        copyBtn.title = 'Copy extracted text';
        copyBtn.setAttribute('data-idx', idx);
        copyBtn.innerHTML = '<i data-lucide="copy"></i>';
        copyBtn.onclick = function(e) {
            e.stopPropagation();
            _onCopyAttachmentText(parseInt(this.getAttribute('data-idx'), 10));
        };
        item.appendChild(copyBtn);
    }

    // Remove button
    var removeBtn = document.createElement('button');
    removeBtn.className = 'attachment-remove';
    removeBtn.textContent = '\u00D7';
    removeBtn.title = 'Remove ' + att.filename;
    removeBtn.setAttribute('data-idx', idx);
    item.appendChild(removeBtn);

    bar.appendChild(item);
}

// Copy an attachment's extracted text to clipboard with checkmark feedback
function _onCopyAttachmentText(idx) {
    var text = attachmentState[idx] && attachmentState[idx].extractedText;
    if (!text) return;
    navigator.clipboard.writeText(text).then(function() {
        var bar = document.getElementById('attachment-bar');
        if (!bar) return;
        var btn = bar.querySelectorAll('.attachment-copy-text')[idx];
        if (!btn) return;
        var origHTML = btn.innerHTML;
        btn.innerHTML = '<i data-lucide="check"></i>';
        if (typeof lucide !== 'undefined') lucide.createIcons();
        setTimeout(function() {
            btn.innerHTML = origHTML;
            if (typeof lucide !== 'undefined') lucide.createIcons();
        }, 2000);
    });
}

// Get attachments ready for sending (check base64 size limit)
function getAttachmentsForSend() {
    var result = [];
    for (var i = 0; i < attachmentState.length; i++) {
        var att = attachmentState[i];
        if (!att.base64) continue;

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
    el.innerHTML = '<span>' + escHtml(message) + '</span><button onclick="this.parentElement.remove()" style="background:none;border:none;color:inherit;font-size:1.2rem;cursor:pointer;">&times;</button>';
    container.appendChild(el);
    container.scrollTop = container.scrollHeight;
}
