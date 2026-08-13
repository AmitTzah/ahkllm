// ======================================================
// chat-attachments-setup.js -- Drop zone, paste, browse event handlers
// ======================================================

// ---- Drop zone setup ----

function setupAttachmentDropZone() {
    var area = document.getElementById('chat-input-area');
    if (!area) return;

    area.addEventListener('dragover', function(e) {
        e.preventDefault();
        e.stopPropagation();
        area.style.outline = '2px dashed var(--accent-primary)';
    });

    area.addEventListener('dragleave', function(e) {
        e.preventDefault();
        e.stopPropagation();
        area.style.outline = '';
    });

    area.addEventListener('drop', function(e) {
        e.preventDefault();
        e.stopPropagation();
        area.style.outline = '';

        var files = e.dataTransfer.files;
        for (var i = 0; i < files.length; i++) {
            if (attachmentState.length >= 10) {
                showErrorBanner('Maximum 10 attachments per message.');
                break;
            }
            addAttachment(files[i]);
        }
    });
}

// ---- Paste handler ----

function setupAttachmentPaste() {
    var input = document.getElementById('chat-input');
    if (!input) return;

    input.addEventListener('paste', function(e) {
        var items = e.clipboardData && e.clipboardData.items;
        if (!items) return;

        for (var i = 0; i < items.length; i++) {
            if (items[i].type.indexOf('image') === 0) {
                e.preventDefault();
                if (attachmentState.length >= 10) {
                    showErrorBanner('Maximum 10 attachments per message.');
                    return;
                }
                var blob = items[i].getAsFile();
                if (blob) {
                    addAttachment(blob);
                }
                return;
            }
        }
        // If no image, let text paste through normally
    });
}

// ---- Browse button ----

function setupAttachmentBrowse() {
    var browseBtn = document.getElementById('attachment-browse-btn');
    var fileInput = document.getElementById('attachment-file-input');
    if (!browseBtn || !fileInput) return;

    browseBtn.addEventListener('click', function() {
        fileInput.click();
    });

    fileInput.addEventListener('change', function() {
        var files = fileInput.files;
        for (var i = 0; i < files.length; i++) {
            if (attachmentState.length >= 10) {
                showErrorBanner('Maximum 10 attachments per message.');
                break;
            }
            addAttachment(files[i]);
        }
        fileInput.value = ''; // Reset so same file can be re-selected
    });
}

// ---- Delegated remove button handler ----
function setupAttachmentRemoveDelegation() {
    var bar = document.getElementById('attachment-bar');
    if (!bar) return;
    bar.addEventListener('click', function(e) {
        var btn = e.target.closest('.attachment-remove');
        if (!btn) return;
        e.stopPropagation();
        var idx = parseInt(btn.getAttribute('data-idx'), 10);
        removeAttachment(idx);
    });
}

// ---- Delegated x handler for message bubble attachments (deferred during edit) ----
function setupMessageAttachmentDeleteDelegation() {
    var chatMessagesEl = document.getElementById('chat-messages');
    if (!chatMessagesEl) return;
    chatMessagesEl.addEventListener('click', function(e) {
        var btn = e.target.closest('.msg-attachment-delete');
        if (!btn) return;
        e.stopPropagation();
        var attId = btn.getAttribute('data-attachment-id');
        if (!attId) return;
        // Bug #217: deletion may only be deferred while editing THE message
        // the attachment belongs to. The old code deferred ANY clicked
        // attachment id into the global _removedAttachmentIds, so clicking
        // the X on another message's attachment while editing made the edit
        // commit hard-delete that OTHER message's attachment row (and its
        // file). An X on a different bubble is a no-op while the editor is
        // open; it is never deferred into this edit.
        var owningBubble = btn.closest('.msg');
        var owningMsgId = owningBubble ? owningBubble.getAttribute('data-msg-id') : null;
        if (typeof _editingMessageId !== 'undefined' && _editingMessageId) {
            if (owningMsgId === _editingMessageId && typeof _removedAttachmentIds !== 'undefined') {
                _removedAttachmentIds.push(attId);
                var wrapper = btn.closest('.msg-attachment-image, .msg-attachment-file');
                if (wrapper) wrapper.style.display = 'none';
            }
            return;
        }
        Ipc.postToHost('deleteAttachment', { id: attId });
    });
}

// ---- Initialize ----
document.addEventListener('DOMContentLoaded', function() {
    setupAttachmentDropZone();
    setupAttachmentPaste();
    setupAttachmentBrowse();
    setupAttachmentRemoveDelegation();
    setupMessageAttachmentDeleteDelegation();
});
