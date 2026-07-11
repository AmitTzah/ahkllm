// ======================================================
// chat-attachments-extract.js — PDF and office document text extraction
// ======================================================

// Extract text from PDF: officeparser for markdown, pdf.js fallback for scanned PDFs
function extractPDFText(arrayBuffer, attId) {
    var att = findAttachmentById(attId);
    if (!att) return;

    // Use pdf.js directly for PDFs â€” simple, reliable, works on file:// protocol.
    // officeParser's PDF worker (.mjs) can't load locally due to CORS restrictions.
    if (typeof pdfjsLib !== 'undefined') {
        _extractPDFScanned(arrayBuffer, attId);
    } else {
        att.loading = false;
        att.extractedText = '__LIBRARY_UNAVAILABLE__';
        renderAttachmentBar();
    }
}

// pdf.js fallback: text extraction + scanned PDF image rendering
function _extractPDFScanned(arrayBuffer, attId) {
    var att = findAttachmentById(attId);
    if (!att) return;

    if (typeof pdfjsLib === 'undefined') {
        att.loading = false;
        att.extractedText = '__LIBRARY_UNAVAILABLE__';
        renderAttachmentBar();
        return;
    }

    // Set local worker path â€” required when pdf.js loads from file:// protocol
    if (!pdfjsLib.GlobalWorkerOptions.workerSrc) {
        pdfjsLib.GlobalWorkerOptions.workerSrc = './js/vendor/pdf.worker.min.js';
    }

    try {
        console.log('[ATTACH-JS] pdf.js extraction starting for: ' + att.filename);
        var loadingTask = pdfjsLib.getDocument({ data: arrayBuffer.slice(0) });
        var pdfRef = null;
        loadingTask.promise.then(function(pdf) {
            pdfRef = pdf;
            console.log('[ATTACH-JS] pdf.js loaded, pages=' + pdf.numPages);
            var maxPages = pdf.numPages;
            var pagePromises = [];
            for (var i = 1; i <= maxPages; i++) {
                pagePromises.push(pdf.getPage(i).then(function(page) {
                    return page.getTextContent().then(function(textContent) {
                        return textContent.items.map(function(item) {
                            return item.str;
                        }).join(' ');
                    });
                }));
            }
            return Promise.all(pagePromises);
        }).then(function(pageTexts) {
            att = findAttachmentById(attId);
            if (!att) return;

            var fullText = pageTexts.join('\n\n').trim();
            att.extractedText = fullText || '';
            console.log('[ATTACH-JS] pdf.js extraction done: textLen=' + (fullText ? fullText.length : 0));

            // If negligible text (<10 chars), this is likely a scanned PDF â€” render pages as images
            if ((!fullText || fullText.length < 10) && pdfRef) {
                var numPages = pdfRef.numPages;
                var remainingSlots = 10 - attachmentState.length + 1;
                var maxRenderPages = Math.min(numPages, 10, Math.max(1, remainingSlots));
                console.log('[ATTACH-JS] Scanned PDF detected â€” rendering ' + maxRenderPages + ' of ' + numPages + ' pages as images (slots=' + remainingSlots + ')');

                var renderPromises = [];
                for (var p = 1; p <= maxRenderPages; p++) {
                    renderPromises.push((function(pageNum) {
                        return pdfRef.getPage(pageNum).then(function(page) {
                            var viewport = page.getViewport({ scale: 1.5 });
                            var canvas = document.createElement('canvas');
                            canvas.width = viewport.width;
                            canvas.height = viewport.height;
                            var ctx = canvas.getContext('2d');
                            return page.render({ canvasContext: ctx, viewport: viewport }).promise.then(function() {
                                return canvas.toDataURL('image/png').split(',')[1];
                            });
                        });
                    })(p));
                }

                return Promise.all(renderPromises).then(function(pageImages) {
                    att = findAttachmentById(attId);
                    if (!att) return;

                    att.base64 = pageImages[0];
                    att.type = 'image';
                    att.mimeType = 'image/png';
                    att.extractedText = '__SCANNED_PDF__';
                    att.filename = att.filename.replace('.pdf', '') + '_p1.png';
                    att.loading = false;

                    for (var pi = 1; pi < pageImages.length; pi++) {
                        if (attachmentState.length >= 10) break;
                        attachmentState.push({
                            _id: ++_attachmentIdCounter,
                            type: 'image',
                            filename: att.filename.replace('_p1.png', '_p' + (pi + 1) + '.png'),
                            mimeType: 'image/png',
                            base64: pageImages[pi],
                            size: 0,
                            extractedText: '__SCANNED_PDF__',
                            loading: false
                        });
                    }
                    console.log('[ATTACH-JS] PDF rendered as ' + pageImages.length + ' images');
                    renderAttachmentBar();
                }).catch(function() {
                    att = findAttachmentById(attId);
                    if (!att) return;
                    att.extractedText = '(no extractable text â€” scanned PDF)';
                    att.loading = false;
                    renderAttachmentBar();
                });
            } else {
                att.loading = false;
                renderAttachmentBar();
            }
        }).catch(function(err) {
            console.error('PDF extraction error:', err);
            att = findAttachmentById(attId);
            if (!att) return;
            att.extractedText = null;
            att.loading = false;
            renderAttachmentBar();
        });
    } catch (e) {
        att = findAttachmentById(attId);
        if (!att) return;
        att.extractedText = null;
        att.loading = false;
        renderAttachmentBar();
    }
}

// Extract text from office documents using officeparser (docx, pptx, xlsx, odt, odp, ods, rtf)
function extractOfficeText(arrayBuffer, attId) {
    var att = findAttachmentById(attId);
    if (!att) return;

    if (typeof officeParser === 'undefined') {
        att.loading = false;
        att.extractedText = '__LIBRARY_UNAVAILABLE__';
        renderAttachmentBar();
        return;
    }

    try {
        console.log('[ATTACH-JS] officeParser extraction starting for: ' + att.filename);
        officeParser.parseOffice(new Uint8Array(arrayBuffer))
            .then(function(ast) { return ast.to('md'); })
            .then(function(result) {
                att = findAttachmentById(attId);
                if (!att) return;
                var md = result ? result.value : '';
                console.log('[ATTACH-JS] officeParser result length=' + md.length);
                // DEBUG: check for double quotes in officeParser output
                var dqCount = (md.match(/""/g) || []).length;
                if (dqCount > 0) {
                    console.log('[ATTACH-JS] DOUBLE-QUOTE DETECTED in officeParser output: ' + dqCount + ' instances');
                    var firstDQ = md.indexOf('""');
                    console.log('[ATTACH-JS] First "" context: ' + md.substring(Math.max(0, firstDQ - 20), firstDQ + 30));
                }
                att.extractedText = md || '(no text extracted)';
                att.loading = false;
                renderAttachmentBar();
            })
            .catch(function(err) {
                console.error('[ATTACH-JS] officeParser error:', err);
                att = findAttachmentById(attId);
                if (!att) return;
                att.extractedText = null;
                att.loading = false;
                renderAttachmentBar();
            });
    } catch (e) {
        att = findAttachmentById(attId);
        if (!att) return;
        att.extractedText = null;
        att.loading = false;
        renderAttachmentBar();
    }
}

