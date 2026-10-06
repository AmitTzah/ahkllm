'use strict';

const marker = 'AHKLLM_APPLICATION_V1\n';
const envelope = body => marker + JSON.stringify(body);

function applicationTextReply(instructions, messages) {
  if (!instructions.includes('Application tool-calling protocol (text-protocol)')) return null;
  const users = messages.filter(message => message.role === 'user');
  const last = String(users.at(-1)?.content || '');
  const whole = users.map(message => message.content).join('\n');
  let result;
  try { result = JSON.parse(last); } catch {}
  if (result?.kind === 'tool_result' && whole.includes('CANCEL_AFTER_TOOL')) return {cancel: true};
  if (last.includes('MALFORMED_TOOL_REPLY')) return {text: marker + '{"kind":"tool_calls","calls":['};
  if (last.includes('UNKNOWN_TOOL_REPLY')) return {text: envelope({kind: 'tool_calls', calls: [{name: 'not_advertised', arguments: {text: 'forbidden'}}]})};
  if (last.includes('INVALID_TOOL_ARGUMENTS')) return {text: envelope({kind: 'tool_calls', calls: [{name: 'echo_text', arguments: {text: 42}}]})};
  const hasResult = users.some(message => {
    try { return JSON.parse(message.content).kind === 'tool_result'; } catch { return false; }
  });
  const hasEcho = /"name"\s*:\s*"echo_text"/.test(instructions);
  if (hasEcho && !hasResult) {
    const text = whole.includes('CANCEL_AFTER_TOOL') ? 'CANCEL_AFTER_TOOL' : 'APPLICATION TEXT TOOL RESULT Ω';
    return {text: envelope({kind: 'tool_calls', calls: [{name: 'echo_text', arguments: {text}}]})};
  }
  return {text: envelope({kind: 'final', content: 'APPLICATION TEXT ANSWER Ω\nLiteral example: {"kind":"tool_calls"}'} )};
}

module.exports = {applicationTextReply};
