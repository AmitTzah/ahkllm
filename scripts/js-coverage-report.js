// js-coverage-report.js
//
// Aggregates NODE_V8_COVERAGE dumps (one JSON file per test process) into a
// per-file line/branch coverage report for project files. Project files are
// attributed correctly because tests run with scripts/js-coverage-preload.js.
//
// Usage:
//   $env:NODE_V8_COVERAGE = "$env:TEMP\js-v8cov"
//   node --require scripts/js-coverage-preload.js --test tests/unit/*.test.js
//   node scripts/js-coverage-report.js

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const dumpDir = process.env.NODE_V8_COVERAGE || path.join(os.tmpdir(), 'v8cov');
const projectRoot = process.cwd();
const projectRootLower = projectRoot.toLowerCase();

// ---------------------------------------------------------------------------
// Normalization / collection
// ---------------------------------------------------------------------------

function normalizeUrl(rawUrl) {
    if (!rawUrl) return null;
    let url = String(rawUrl).replace(/^file:\/\//, '');
    if (/^\/[A-Za-z]:/.test(url)) {
        url = url.slice(1); // /C:/... -> C:/...
    }
    if (url.startsWith('node:') || url.startsWith('internal') || url.includes('node_modules')) {
        return null;
    }
    if (!path.isAbsolute(url)) {
        url = path.resolve(projectRoot, url);
    }
    url = path.normalize(url);
    if (!url.toLowerCase().startsWith(projectRootLower)) {
        return null;
    }
    return url;
}

// url -> { source, functions: [{ name, ranges: [{s, e, count}] }] }
const files = new Map();

function entryFor(url) {
    let entry = files.get(url);
    if (!entry) {
        entry = { source: null, functions: [] };
        files.set(url, entry);
    }
    return entry;
}

for (const dumpFile of fs.readdirSync(dumpDir)) {
    if (!dumpFile.endsWith('.json')) continue;
    let dump;
    try {
        dump = JSON.parse(fs.readFileSync(path.join(dumpDir, dumpFile), 'utf-8'));
    } catch {
        continue;
    }
    for (const result of dump.result || []) {
        const url = normalizeUrl(result.url);
        if (!url) continue;
        const entry = entryFor(url);
        if (entry.source === null) {
            try {
                entry.source = fs.readFileSync(url, 'utf-8');
            } catch {
                entry.source = '';
            }
        }
        for (const fn of result.functions || []) {
            const ranges = (fn.ranges || []).map((r) => ({
                s: r.startOffset,
                e: r.endOffset,
                count: r.count,
            }));
            entry.functions.push({ name: fn.functionName || '', ranges });
        }
    }
}

// ---------------------------------------------------------------------------
// Line / branch accounting
// ---------------------------------------------------------------------------

function lineStartOffsets(source) {
    const offsets = [0];
    for (let i = 0; i < source.length; i++) {
        if (source[i] === '\n') offsets.push(i + 1);
    }
    return offsets;
}

function lineCoverageFor(entry) {
    const lineStarts = lineStartOffsets(entry.source);
    const lineCount = lineStarts.length - 1;
    const executable = new Array(lineCount).fill(false);
    const covered = new Array(lineCount).fill(false);

    const applyRange = (range, flagArray) => {
        if (range.e <= range.s) return;
        // Binary search for the first line whose start is within the range.
        let lo = 0;
        let hi = lineStarts.length - 1;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (lineStarts[mid] < range.s) lo = mid + 1;
            else hi = mid;
        }
        let lineIndex = Math.max(0, lo - 1);
        while (lineIndex < lineCount && lineStarts[lineIndex] < range.e) {
            flagArray[lineIndex] = true;
            lineIndex++;
        }
    };

    for (const fn of entry.functions) {
        for (const range of fn.ranges) {
            applyRange(range, executable);
            if (range.count > 0) applyRange(range, covered);
        }
    }

    const uncoveredLines = [];
    let executableLines = 0;
    let coveredLines = 0;
    for (let i = 0; i < lineCount; i++) {
        if (!executable[i]) continue;
        executableLines++;
        if (covered[i]) coveredLines++;
        else uncoveredLines.push(i + 1);
    }
    return { executableLines, coveredLines, uncoveredLines };
}

function branchCoverageFor(entry) {
    let total = 0;
    let covered = 0;
    for (const fn of entry.functions) {
        if (fn.ranges.length <= 1) continue;
        const branches = fn.ranges.slice(1); // first range is the function body
        total += branches.length;
        covered += branches.filter((r) => r.count > 0).length;
    }
    return { total, covered };
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

const rows = [];
for (const [url, entry] of files) {
    if (!entry.source) continue;
    const relative = path.relative(projectRoot, url).replace(/\\/g, '/');
    const line = lineCoverageFor(entry);
    const branch = branchCoverageFor(entry);
    const linePercent = line.executableLines === 0
        ? 100
        : (100 * line.coveredLines) / line.executableLines;
    const branchPercent = branch.total === 0
        ? 100
        : (100 * branch.covered) / branch.total;
    rows.push({
        relative,
        lineCovered: line.coveredLines,
        lineTotal: line.executableLines,
        linePercent,
        branchCovered: branch.covered,
        branchTotal: branch.total,
        branchPercent,
        uncoveredLines: line.uncoveredLines,
    });
}

const projectRows = rows.filter((r) => !r.relative.startsWith('tests/'));
const testRows = rows.filter((r) => r.relative.startsWith('tests/'));

const sorted = [...projectRows].sort((a, b) => a.linePercent - b.linePercent || a.relative.localeCompare(b.relative));

console.log('file | line% | branch% | uncovered lines');
for (const row of sorted) {
    const uncovered = row.uncoveredLines.length
        ? '  lines: ' + row.uncoveredLines.join(',')
        : '';
    console.log(
        `${row.relative} | ${row.linePercent.toFixed(1)}% (${row.lineCovered}/${row.lineTotal}) | ${row.branchPercent.toFixed(1)}% (${row.branchCovered}/${row.branchTotal})${uncovered}`
    );
}

function summarize(rowsOfInterest) {
    const lineTotal = rowsOfInterest.reduce((sum, r) => sum + r.lineTotal, 0);
    const lineCovered = rowsOfInterest.reduce((sum, r) => sum + r.lineCovered, 0);
    const branchTotal = rowsOfInterest.reduce((sum, r) => sum + r.branchTotal, 0);
    const branchCovered = rowsOfInterest.reduce((sum, r) => sum + r.branchCovered, 0);
    return {
        linePercent: lineTotal ? (100 * lineCovered) / lineTotal : 100,
        branchPercent: branchTotal ? (100 * branchCovered) / branchTotal : 100,
        files: rowsOfInterest.length,
        lineCovered,
        lineTotal,
    };
}

const projectSummary = summarize(projectRows);
const testSummary = summarize(testRows);
console.log('');
console.log(`Project source: ${projectSummary.linePercent.toFixed(2)}% lines (${projectSummary.lineCovered}/${projectSummary.lineTotal}), ${projectSummary.branchPercent.toFixed(2)}% branches across ${projectSummary.files} files`);
console.log(`Test files:     ${testSummary.linePercent.toFixed(2)}% lines across ${testSummary.files} files`);

if (process.argv.includes('--uncovered-project-files')) {
    console.log('');
    for (const row of sorted.filter((r) => r.linePercent < 100)) {
        console.log(`${row.relative}: ${row.uncoveredLines.join(',')}`);
    }
}
