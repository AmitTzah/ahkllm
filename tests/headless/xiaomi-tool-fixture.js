'use strict';

function validateXiaomiRequest(body, authorization) {
  if (authorization !== 'Bearer mimo-fixture-key') return 'Expected Xiaomi Bearer authentication';
  if (body.thinking?.type !== 'enabled' && body.thinking?.type !== 'disabled') return 'Missing Xiaomi thinking toggle';
  if (body.reasoning_effort !== undefined) return 'MiMo does not use reasoning_effort';
  for (const message of body.messages || []) {
    for (const call of message.tool_calls || []) {
      const round = Number(call.id.replace('call_search_', '')) - 1;
      if (body.thinking.type === 'enabled' && message.reasoning_content !== `MiMo exact round ${round} Ω`) return 'Missing or altered reasoning_content on native tool replay';
      if (message.content !== `MiMo public round ${round}`) return 'Assistant tool-round content was lost';
    }
  }
  return '';
}

module.exports = {validateXiaomiRequest};
