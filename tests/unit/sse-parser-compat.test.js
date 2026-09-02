const { describe, it } = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

describe('SSEParser OpenAI-compatible null guards', () => {
  const src = fs.readFileSync(path.resolve(__dirname, '..', '..', 'api', 'SSEParser.ahk'), 'utf8');
  const normalizedSrc = src.replace(/\r\n/g, '\n');

  it('guards tool_calls before enumeration', () => {
    assert.ok(src.includes('delta.Has("tool_calls") && IsObject(delta["tool_calls"]) && Type(delta["tool_calls"]) = "Array"'),
      'tool_calls must be a real Array before iteration');
    assert.ok(src.includes('for tcf in delta["tool_calls"]'),
      'real tool-call arrays must still be iterated');
  });

  it('guards choices and null/scalar deltas', () => {
    assert.ok(normalizedSrc.includes('!IsObject(choices) || Type(choices) != "Array"'),
      'choices must be an Array before Length/iteration');
    assert.ok(normalizedSrc.includes('if !IsObject(delta)\n                continue'),
      'null/scalar deltas must be ignored safely');
  });

  it('does not dereference a null choice while reading finish reasons', () => {
    assert.ok(normalizedSrc.includes('if IsObject(choice) && choice.Has("finish_reason")'),
      'finish metadata must be read only from object choices');
    assert.ok(!normalizedSrc.includes('finish := choices[1].Has("finish_reason")'),
      'finish parsing must not assume choices[1] is an object');
  });
});
