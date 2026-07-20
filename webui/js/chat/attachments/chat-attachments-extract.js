// ======================================================
// chat-attachments-extract.js -- PDF and office document text extraction
// ======================================================

// Extract text from PDF: try officeParser first for markdown, fall back to
// pdf.js canvas rendering for scanned PDFs (image conversion).
// officeParser's PDF worker now works because the page loads from https://
// origin (WebView2 virtual host) instead of file://.
function extractPDFText(arrayBuffer, attId) {
    var att = findAttachmentById(attId);
    if (!att) return;

    if (typeof officeParser !== 'undefined') {
        _extractPDFWithOfficeParser(arrayBuffer, attId);
    } else if (typeof pdfjsLib !== 'undefined') {
        _extractPDFScanned(arrayBuffer, attId);
    } else {
        att.loading = false;
        att.extractedText = '__LIBRARY_UNAVAILABLE__';
        renderAttachmentBar();
    }
}

// Try officeParser for PDF markdown extraction. Falls back to pdf.js
// canvas rendering if the output is negligible (scanned PDF).
function _extractPDFWithOfficeParser(arrayBuffer, attId) {
    var att = findAttachmentById(attId);
    if (!att) return;

    var uint8 = new Uint8Array(arrayBuffer);

    // Re-render to ensure spinner is visible during async extraction
    renderAttachmentBar();

    officeParser.parseOffice(uint8)
        .then(function(ast) {
            // Count page nodes in the AST for per-page ratio check
            var pageCount = 0;
            if (ast.content) {
                for (var _ci = 0; _ci < ast.content.length; _ci++) {
                    if (ast.content[_ci].type === 'page') pageCount++;
                }
            }
            if (!pageCount) pageCount = 1;
            var plainText = ast.toText();
            var charsPerPage = Math.round(plainText.length / pageCount);
            var isScanned = _isScannedPDF(plainText, pageCount);
            try {
                window.chrome.webview.postMessage(JSON.stringify({
                    action: 'debugLog',
                    message: '[Extract] officeParser → pages=' + pageCount +
                        ' textLength=' + plainText.length +
                        ' charsPerPage=' + charsPerPage +
                        ' scanned=' + isScanned +
                        (isScanned ? ' → falling back to pdf.js images' : ' → using markdown')
                }));
            } catch(e) { /* ignore if IPC unavailable */ }
            if (isScanned) return null; // signal fallback to pdf.js
            return ast.to('md');
        })
        .then(function(result) {
            att = findAttachmentById(attId);
            if (!att) return;

            if (result === null) {
                // Scanned PDF — fall back to pdf.js image rendering
                _extractPDFScanned(arrayBuffer, attId);
                return;
            }

            var md = (typeof result === 'string') ? result : (result && result.value ? result.value : '');
            att.extractedText = md || '(no text extracted)';
            att.loading = false;
            renderAttachmentBar();
        })
        .catch(function(err) {
            console.error('officeParser PDF error, falling back to pdf.js:', err);
            att = findAttachmentById(attId);
            if (!att) return;

            // If officeParser failed (e.g. PDF worker issue), fall back to pdf.js
            if (typeof pdfjsLib !== 'undefined') {
                _extractPDFScanned(arrayBuffer, attId);
            } else {
                var errMsg = err && err.message ? err.message : String(err);
                att.extractedText = '(extraction failed: ' + errMsg + ')';
                att.loading = false;
                renderAttachmentBar();
            }
        });
}

// Detect scanned PDF using per-page text ratio.
// A real text PDF has hundreds of chars per page. A scanned or
// watermark-only PDF has very little extractable text per page.
// This is robust: it works regardless of page count or text content.
function _isScannedPDF(text, pageCount) {
    if (!text) return true;
    if (!pageCount || pageCount < 1) pageCount = 1;
    return (text.length / pageCount) < 50;
}

// pdf.js: text extraction + scanned PDF image rendering
function _extractPDFScanned(arrayBuffer, attId) {
    var att = findAttachmentById(attId);
    if (!att) return;

    if (typeof pdfjsLib === 'undefined') {
        att.loading = false;
        att.extractedText = '__LIBRARY_UNAVAILABLE__';
        renderAttachmentBar();
        return;
    }

    // Set local worker path -- required when pdf.js loads from file:// protocol
    if (!pdfjsLib.GlobalWorkerOptions.workerSrc) {
        pdfjsLib.GlobalWorkerOptions.workerSrc = './js/vendor/pdf.worker.min.js';
    }

    // Re-render to ensure spinner is visible during async extraction
    renderAttachmentBar();

    try {
        var loadingTask = pdfjsLib.getDocument({ data: arrayBuffer.slice(0) });
        var pdfRef = null;
        loadingTask.promise.then(function(pdf) {
            pdfRef = pdf;
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

            if (_isScannedPDF(fullText, pdfRef.numPages) && pdfRef) {
                var numPages = pdfRef.numPages;
                var remainingSlots = 10 - attachmentState.length + 1;
                var maxRenderPages = Math.min(numPages, 10, Math.max(1, remainingSlots));

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
                    renderAttachmentBar();
                }).catch(function() {
                    att = findAttachmentById(attId);
                    if (!att) return;
                    att.extractedText = '(no extractable text -- scanned PDF)';
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
            att.extractedText = '(extraction failed: ' + (err && err.message ? err.message : String(err)) + ')';
            att.loading = false;
            renderAttachmentBar();
        });
    } catch (e) {
        console.error('PDF sync error:', e);
        att = findAttachmentById(attId);
        if (!att) return;
        att.extractedText = '(extraction failed: ' + (e && e.message ? e.message : String(e)) + ')';
        att.loading = false;
        renderAttachmentBar();
    }
}

// Extract text from office documents using officeparser (docx, pptx, xlsx, odt, odp, ods, rtf, epub)
function extractOfficeText(arrayBuffer, attId) {
    var att = findAttachmentById(attId);
    if (!att) return;

    if (typeof officeParser === 'undefined') {
        att.loading = false;
        att.extractedText = '__LIBRARY_UNAVAILABLE__';
        renderAttachmentBar();
        return;
    }

    // Re-render to ensure spinner is visible during async extraction
    renderAttachmentBar();

    try {
        officeParser.parseOffice(new Uint8Array(arrayBuffer))
            .then(function(ast) { return ast.to('md'); })
            .then(function(result) {
                att = findAttachmentById(attId);
                if (!att) return;
                // v7 returns string directly; v6 returns { value: string }. Handle both.
                var md = (typeof result === 'string') ? result : (result && result.value ? result.value : '');
                att.extractedText = md || '(no text extracted)';
                att.loading = false;
                renderAttachmentBar();
            })
            .catch(function(err) {
                console.error('officeParser error:', err);
                att = findAttachmentById(attId);
                if (!att) return;
                var errMsg = err && err.message ? err.message : String(err);
                att.extractedText = '(extraction failed: ' + errMsg + ')';
                att.loading = false;
                renderAttachmentBar();
            });
    } catch (e) {
        console.error('officeParser sync error:', e);
        att = findAttachmentById(attId);
        if (!att) return;
        att.extractedText = '(extraction failed: ' + (e && e.message ? e.message : String(e)) + ')';
        att.loading = false;
        renderAttachmentBar();
    }
}
