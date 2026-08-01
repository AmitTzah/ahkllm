// js-coverage-preload.js
//
// Makes Node's V8 coverage dumps attribute vm-executed sources to their
// real files. The project's JS unit tests load browser scripts with
// fs.readFileSync + vm.runInContext without a `filename`, so the V8 dump
// would otherwise record them under a generic URL and coverage would show
// zero project files. This preload records read source contents and
// supplies the matching filename to vm calls that don't provide one.
//
// Usage: node --require scripts/js-coverage-preload.js --test tests/unit/*.test.js
// (with NODE_V8_COVERAGE pointing at a dump directory)

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const projectRoot = process.cwd();
const MAX_RECORDED_SOURCES = 256;

// Content -> absolute path for every project file read during the run.
const sourcePathByContent = new Map();

const originalReadFileSync = fs.readFileSync;
fs.readFileSync = function readFileSyncWithSourceTracking(...args) {
    const result = originalReadFileSync.apply(this, args);
    if (typeof result === 'string' && args[0]) {
        let filePath = args[0];
        if (!path.isAbsolute(filePath)) {
            filePath = path.resolve(process.cwd(), filePath);
        }
        filePath = path.normalize(filePath);
        if (filePath.toLowerCase().startsWith(projectRoot.toLowerCase())) {
            if (sourcePathByContent.size >= MAX_RECORDED_SOURCES) {
                sourcePathByContent.clear();
            }
            sourcePathByContent.set(result, filePath);
        }
    }
    return result;
};

function filenameFor(source, options) {
    if (options && options.filename) {
        return options;
    }
    const filePath = sourcePathByContent.get(source);
    if (!filePath) {
        return options;
    }
    return Object.assign({}, options, { filename: filePath });
}

const originalRunInContext = vm.runInContext;
vm.runInContext = function runInContextWithSourceAttribution(source, context, options) {
    return originalRunInContext.call(this, source, context, filenameFor(source, options));
};

const originalRunInNewContext = vm.runInNewContext;
vm.runInNewContext = function runInNewContextWithSourceAttribution(source, context, options) {
    return originalRunInNewContext.call(this, source, context, filenameFor(source, options));
};

const originalRunInThisContext = vm.runInThisContext;
vm.runInThisContext = function runInThisContextWithSourceAttribution(source, options) {
    return originalRunInThisContext.call(this, source, filenameFor(source, options));
};

const originalScript = vm.Script;
vm.Script = function ScriptWithSourceAttribution(source, options) {
    return new originalScript(source, filenameFor(source, options));
};
vm.Script.prototype = originalScript.prototype;
vm.Script.runInContext = originalScript.runInContext;
vm.Script.runInNewContext = originalScript.runInNewContext;
vm.Script.runInThisContext = originalScript.runInThisContext;
